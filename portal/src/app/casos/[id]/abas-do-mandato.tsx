"use client";

import { useEffect, useRef } from "react";
import Link from "next/link";
import { usePathname } from "next/navigation";

// AS ABAS FIXAS DO MANDATO. Antes, cada tela do mandato tinha o seu próprio
// "← Voltar" (cinco variantes) e a navegação entre Revisão, Perguntas,
// Perímetro e Modelagem era uma fileira de botões que só existia na visão geral.
// Agora a faixa é a mesma em toda tela de /casos/[id].
//
// `contagens` chega pronta do servidor: `null` = não se sabe (consulta falhou ou
// migration não aplicada) e a aba sai SEM número — "0" diria "não há nada", e
// isso seria afirmar o que não se mediu.

export interface AbaDoMandato {
  rotulo: string;
  /** Caminho depois de /casos/{id}; "" é a visão geral. */
  sufixo: string;
  contagem: number | null;
}

// A Visão geral só é ativa na raiz e em /adicionar (sub-página sem aba própria: quem
// está adicionando arquivos está "no mandato", e sem isso nenhuma aba ficaria marcada).
// Documentos é ativa em /documentos e em /documentos/{docId}: o detalhe de um documento
// pertence à aba da lista de onde se chegou nele.
function ativa(caminho: string, base: string, sufixo: string): boolean {
  // Barra final tirada em laço: a regex `/\/+$/` é retrocesso super-linear
  // para o Sonar (S8786), e o caminho vem da URL.
  let limpo = caminho;
  while (limpo.endsWith("/")) limpo = limpo.slice(0, -1);
  if (sufixo === "") {
    return limpo === base || limpo === `${base}/adicionar`;
  }
  const alvo = `${base}${sufixo}`;
  return limpo === alvo || limpo.startsWith(`${alvo}/`);
}

export function AbasDoMandato({ casoId, abas }: Readonly<{ casoId: string; abas: AbaDoMandato[] }>) {
  const caminho = usePathname();
  const base = `/casos/${casoId}`;
  // NO CELULAR as sete abas passam da largura (a faixa rola na horizontal) e a ativa pode estar
  // fora da vista — por exemplo "Entregáveis", a última, ao chegar por um link. Centraliza a ativa
  // dentro da PRÓPRIA faixa (`scrollTo` no contêiner, não `scrollIntoView`, que também rolaria a
  // página). Em tela larga nada rola e a conta dá 0.
  const faixa = useRef<HTMLElement>(null);
  useEffect(() => {
    const nav = faixa.current;
    const atual = nav?.querySelector<HTMLElement>('[aria-current="page"]');
    if (!nav || !atual) return;
    nav.scrollTo({ left: atual.offsetLeft - (nav.clientWidth - atual.offsetWidth) / 2 });
  }, [caminho]);
  return (
    <nav ref={faixa} aria-label="Seções do mandato" className="relative -mx-6 overflow-x-auto px-6 sm:mx-0 sm:px-0">
      <ul className="flex min-w-max gap-1 border-b border-tinta-200">
        {abas.map((a) => {
          const atual = ativa(caminho, base, a.sufixo);
          return (
            <li key={a.sufixo}>
              <Link
                href={`${base}${a.sufixo}`}
                aria-current={atual ? "page" : undefined}
                className={`-mb-px flex items-center gap-1.5 whitespace-nowrap border-b-2 px-3 py-2 text-sm transition-colors ${
                  atual
                    ? "border-acento-600 font-semibold text-tinta-900"
                    : "border-transparent text-tinta-500 hover:border-tinta-300 hover:text-tinta-900"
                }`}
              >
                {a.rotulo}
                {a.contagem !== null && a.contagem > 0 && (
                  <span className="chip bg-tinta-100 text-tinta-600">{a.contagem}</span>
                )}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
