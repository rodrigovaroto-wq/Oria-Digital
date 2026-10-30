"use client";

import { useRouter } from "next/navigation";

// A LINHA INTEIRA DA TABELA ABRE O PAINEL, não só o link "abrir". Os links dentro da linha
// continuam sendo o caminho do teclado e do leitor de tela; o clique na linha é conveniência de
// mouse — por isso ignora cliques em link/botão e seleção de texto (quem seleciona o nome do
// arquivo para copiar não quer abrir nada). `data-doc-row` é como o painel devolve o foco à linha.
export function LinhaDeDocumento({
  docId, href, children,
}: Readonly<{ docId: string; href: string; children: React.ReactNode }>) {
  const router = useRouter();
  return (
    <tr
      data-doc-row={docId}
      tabIndex={-1}
      className="cursor-pointer align-top transition-colors hover:bg-tinta-50 focus:outline-none focus-visible:bg-tinta-50"
      onClick={(e) => {
        if ((e.target as HTMLElement).closest("a, button, input, select, textarea")) return;
        if (globalThis.getSelection()?.toString()) return;
        router.push(href, { scroll: false });
      }}
    >
      {children}
    </tr>
  );
}
