import { Bloco, Esqueleto, EsqueletoTabela } from "@/components/esqueleto";

// Dentro de `[id]/layout.tsx`. Forma: título, a grade do Kit Básico e a tabela de documentos.
export default function CarregandoDocumentos() {
  return (
    <Esqueleto>
      <Bloco className="h-5 w-40" />
      <div className="grid grid-cols-1 gap-2 sm:grid-cols-2">
        {Array.from({ length: 6 }, (_, i) => <Bloco key={i} className="h-11 w-full" />)}
      </div>
      <EsqueletoTabela linhas={6} />
    </Esqueleto>
  );
}
