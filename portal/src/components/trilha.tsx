"use client";

import Link from "next/link";
import { usePathname } from "next/navigation";

// A TRILHA (breadcrumb), agora sobre o casco de vidro escuro da barra de topo:
// o passo corrente em #ece8df e os anteriores em #a39d92 (medidos em DESIGN.md).
//
// A TRILHA (breadcrumb) diz ONDE a pessoa está, que o cabeçalho antigo nunca
// disse: dentro de um mandato, a única pista era o título da página. O nome vem
// da lista que o layout JÁ busca para a barra lateral — zero consulta nova. O
// teto dessa lista são os mandatos ativos; um mandato fechado ou fora dela cai
// em "Mandato" em vez de mostrar o UUID, que não diz nada a ninguém.

interface Passo {
  rotulo: string;
  href?: string;
}

export function passosDaTrilha(caminho: string, nomes: Record<string, string>): Passo[] {
  // Barra final removida em laço, não com `/\/+$/`: o Sonar (S8786) mede essa
  // regex como retrocesso super-linear, e o caminho vem da URL do usuário.
  let limpo = caminho;
  while (limpo.length > 1 && limpo.endsWith("/")) limpo = limpo.slice(0, -1);
  if (limpo === "/casos") return [{ rotulo: "Início" }];
  if (limpo === "/casos/todos") return [{ rotulo: "Mandatos" }];
  if (limpo === "/casos/novo") return [{ rotulo: "Mandatos", href: "/casos/todos" }, { rotulo: "Novo mandato" }];
  if (limpo === "/administracao") return [{ rotulo: "Administração" }, { rotulo: "Qualidade da automação" }];
  if (limpo === "/administracao/custos") return [{ rotulo: "Administração" }, { rotulo: "Custos" }];
  const m = /^\/casos\/([^/]+)/.exec(limpo);
  if (m) return [{ rotulo: "Mandatos", href: "/casos/todos" }, { rotulo: nomes[m[1]] ?? "Mandato" }];
  return [];
}

export function Trilha({ nomes }: Readonly<{ nomes: Record<string, string> }>) {
  const passos = passosDaTrilha(usePathname(), nomes);
  if (passos.length === 0) return null;
  return (
    <nav aria-label="Você está em" className="min-w-0 flex-1">
      <ol className="flex min-w-0 items-center gap-1.5 text-sm text-vidro-suave">
        {passos.map((p, i) => {
          const ultimo = i === passos.length - 1;
          return (
            <li key={p.href ?? p.rotulo} className={`flex items-center gap-1.5 ${ultimo ? "min-w-0" : "shrink-0"}`}>
              {i > 0 && <span aria-hidden>›</span>}
              {p.href && !ultimo ? (
                <Link href={p.href} className="rounded px-1 hover:text-vidro-texto hover:underline">
                  {p.rotulo}
                </Link>
              ) : (
                <span
                  aria-current={ultimo ? "page" : undefined}
                  className={ultimo ? "truncate font-medium text-vidro-texto" : ""}
                >
                  {p.rotulo}
                </span>
              )}
            </li>
          );
        })}
      </ol>
    </nav>
  );
}
