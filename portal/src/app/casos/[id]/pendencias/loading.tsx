import { Bloco, Esqueleto } from "@/components/esqueleto";

// Dentro de `[id]/layout.tsx`: cabeçalho e abas ficam, só o conteúdo é esqueleto. Forma:
// título, a fileira de filtros e a lista de cartões.
export default function CarregandoPendencias() {
  return (
    <Esqueleto>
      <Bloco className="h-5 w-32" />
      <div className="flex flex-wrap gap-2">
        {Array.from({ length: 5 }, (_, i) => <Bloco key={i} className="h-7 w-32 rounded-full" />)}
      </div>
      <Bloco className="h-28 w-full" />
      <Bloco className="h-28 w-full" />
      <Bloco className="h-28 w-full" />
    </Esqueleto>
  );
}
