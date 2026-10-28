"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";
import { etapasDoMandato } from "@/lib/etapas";

// A BARRA DE ETAPAS (layout de `/casos/[id]`). Quem decide QUAIS etapas existem e QUAL está ativa é
// `lib/etapas.ts` (testado em `verificar-navegacao.mts`); aqui só se desenha. Fica fixa abaixo do
// cabeçalho (57px) para a troca de etapa estar a um clique em qualquer ponto de uma tela longa.
export function EtapasDoMandato({ id, ehAdmin }: { id: string; ehAdmin: boolean }) {
  const caminho = usePathname();
  const etapas = etapasDoMandato(id, caminho, ehAdmin);
  return (
    <nav
      aria-label="Etapas do mandato"
      className="sticky top-[57px] z-[5] -mx-6 mb-6 overflow-x-auto border-b border-tinta-200 bg-folha/95 px-6 backdrop-blur"
    >
      <ul className="flex min-w-max gap-1">
        {etapas.map((e) => (
          <li key={e.chave}>
            {e.href ? (
              <Link
                href={e.href}
                aria-current={e.ativa ? "page" : undefined}
                className={`-mb-px block border-b-2 px-3 py-2.5 text-sm transition-colors ${
                  e.ativa
                    ? "border-acento-600 font-medium text-acento-700"
                    : "border-transparent text-tinta-600 hover:text-tinta-900"
                }`}
              >
                {e.rotulo}
              </Link>
            ) : (
              <span
                aria-disabled="true"
                title="Em construção: esta etapa ainda não existe, então nada foi consultado."
                className="-mb-px block cursor-not-allowed border-b-2 border-transparent px-3 py-2.5 text-sm text-tinta-400"
              >
                {e.rotulo} <span className="text-[10px] uppercase tracking-wide">em construção</span>
              </span>
            )}
          </li>
        ))}
      </ul>
    </nav>
  );
}
