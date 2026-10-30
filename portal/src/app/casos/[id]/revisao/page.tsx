import { redirect } from "next/navigation";

// A ABA "REVISÃO" VIROU O FILTRO "CONFIRMAR DOCUMENTO" DE PENDÊNCIAS (fase 2). A rota
// fica só para os links antigos — e-mails, favoritos, a fila do Início de antes — não
// caírem num 404.
export default async function RevisaoAntiga({ params }: Readonly<{ params: Promise<{ id: string }> }>) {
  const { id } = await params;
  redirect(`/casos/${id}/pendencias?filtro=confirmar`);
}
