"use client";

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

// A visão geral é dona também das sub-páginas que ainda não têm aba própria
// (documento e adicionar): quem está lendo um documento está "no mandato", e
// sem isso nenhuma aba ficaria marcada.
function ativa(caminho: string, base: string, sufixo: string): boolean {
  const limpo = caminho.replace(/\/+$/, "");
  if (sufixo === "") {
    return limpo === base || limpo.startsWith(`${base}/documentos`) || limpo === `${base}/adicionar`;
  }
  const alvo = `${base}${sufixo}`;
  return limpo === alvo || limpo.startsWith(`${alvo}/`);
}

export function AbasDoMandato({ casoId, abas }: { casoId: string; abas: AbaDoMandato[] }) {
  const caminho = usePathname();
  const base = `/casos/${casoId}`;
  return (
    <nav aria-label="Seções do mandato" className="-mx-6 overflow-x-auto px-6 sm:mx-0 sm:px-0">
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
