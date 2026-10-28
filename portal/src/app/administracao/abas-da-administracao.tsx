"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// As duas abas da Administração. Mesmo desenho das abas do mandato
// (`casos/[id]/abas-do-mandato.tsx`); aqui são duas fixas, sem contagem — um número
// numa aba de custo seria o primeiro "zero" que a tela poderia afirmar sem medir.
const ABAS = [
  { rotulo: "Qualidade da automação", href: "/administracao" },
  { rotulo: "Custos", href: "/administracao/custos" },
] as const;

export function AbasDaAdministracao() {
  let caminho = usePathname();
  while (caminho.length > 1 && caminho.endsWith("/")) caminho = caminho.slice(0, -1);
  return (
    <nav aria-label="Seções da administração" className="overflow-x-auto">
      <ul className="flex min-w-max gap-1 border-b border-tinta-200">
        {ABAS.map((a) => {
          const atual = caminho === a.href;
          return (
            <li key={a.href}>
              <Link
                href={a.href}
                aria-current={atual ? "page" : undefined}
                className={`-mb-px flex items-center whitespace-nowrap border-b-2 px-3 py-2 text-sm transition-colors ${
                  atual
                    ? "border-acento-600 font-semibold text-tinta-900"
                    : "border-transparent text-tinta-500 hover:border-tinta-300 hover:text-tinta-900"
                }`}
              >
                {a.rotulo}
              </Link>
            </li>
          );
        })}
      </ul>
    </nav>
  );
}
