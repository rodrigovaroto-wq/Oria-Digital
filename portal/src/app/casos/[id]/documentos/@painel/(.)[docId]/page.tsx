import { DocumentoDetalhe } from "@/components/documento-detalhe";
import { PainelDocumento } from "@/components/painel-documento";

// O mesmo `DocumentoDetalhe` da página inteira, dentro do painel lateral. As server actions do
// detalhe (aceitar, classe contábil, transcrição) revalidam `/casos/[id]/documentos/[docId]` —
// o caminho da URL atual do painel —, então o painel se refaz com o resultado.
export default async function PainelDoDocumento({
  params,
}: Readonly<{ params: Promise<{ id: string; docId: string }> }>) {
  const { id, docId } = await params;
  return (
    <PainelDocumento casoId={id} docId={docId}>
      <DocumentoDetalhe id={id} docId={docId} />
    </PainelDocumento>
  );
}
