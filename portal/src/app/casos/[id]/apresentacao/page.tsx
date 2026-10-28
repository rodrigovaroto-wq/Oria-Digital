import { redirect } from "next/navigation";

// A aba "Apresentação" virou "Entregáveis" (fase 2, item 20): os campos moram na seção
// `#campos` de lá. Fica o redirect porque link antigo e favorito apontam para esta rota.
export default async function ApresentacaoPage({ params }: Readonly<{ params: Promise<{ id: string }> }>) {
  const { id } = await params;
  redirect(`/casos/${id}/entregaveis#campos`);
}
