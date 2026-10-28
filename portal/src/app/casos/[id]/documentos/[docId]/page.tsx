import { DocumentoDetalhe } from "@/components/documento-detalhe";

// A PÁGINA INTEIRA do documento (link direto, F5, "Abrir em página inteira"). Leitura e desenho
// moram em `DocumentoDetalhe`, compartilhado com o painel lateral da lista.
export default async function PlanilhaDocumentoPage({
  params,
}: Readonly<{ params: Promise<{ id: string; docId: string }> }>) {
  const { id, docId } = await params;
  return <DocumentoDetalhe id={id} docId={docId} />;
}
