import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Caso } from "@/lib/types";
import UploadForm from "@/components/upload-form";

export default async function AdicionarArquivosPage({
  params,
}: {
  params: Promise<{ id: string }>;
}) {
  const { id } = await params;
  const supabase = await createClient();
  const { data, error } = await supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single();

  if (error || !data) notFound();
  const caso = data as Caso;

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        <h1 className="text-lg font-semibold text-tinta-900">Adicionar arquivos</h1>
        <p className="text-sm text-tinta-500">
          Os novos arquivos entram neste mesmo mandato e somam ao checklist, à exportação para Excel e
          à checagem de dados já existentes.
        </p>
      </div>
      <UploadForm mandatoInicial={caso.nome} travarMandato casoId={caso.id} />
    </div>
  );
}
