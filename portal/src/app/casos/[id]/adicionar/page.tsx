import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import type { Caso } from "@/lib/types";
import Link from "next/link";
import UploadForm from "@/components/upload-form";
import { cabecalhoDoPasso, textoDoPasso } from "@/lib/passo-do-mandato";

export default async function AdicionarArquivosPage({
  params,
  searchParams,
}: {
  params: Promise<{ id: string }>;
  searchParams: Promise<{ passo?: string | string[]; existente?: string | string[] }>;
}) {
  const { id } = await params;
  const passo = cabecalhoDoPasso(await searchParams);
  const supabase = await createClient();
  const { data, error } = await supabase.from("caso").select("id, nome, produto, status, criado_em").eq("id", id).single();

  if (error || !data) notFound();
  const caso = data as Caso;

  return (
    <div className="max-w-2xl space-y-6">
      <div>
        {passo && (
          <p className="mb-1 text-xs font-semibold uppercase tracking-wide text-acento-700">
            {textoDoPasso(passo)} · {passo.rotulo}
          </p>
        )}
        <h1 className="text-lg font-semibold text-tinta-900">{passo ? `Documentos de ${caso.nome}` : "Adicionar arquivos"}</h1>
        <p className="text-sm text-tinta-500">
          Os novos arquivos entram neste mesmo mandato e somam ao checklist, à exportação para Excel e
          à checagem de dados já existentes.
        </p>
        {passo?.jaExistia && (
          <p role="status" className="mt-2 rounded-md bg-alerta-50 px-3 py-2 text-xs text-alerta-900">
            Já existia um mandato com este nome: os arquivos entram nele, somando ao que já há — não foi criado um mandato novo.
          </p>
        )}
      </div>
      <UploadForm mandatoInicial={caso.nome} travarMandato casoId={caso.id} />
      {passo && (
        <p className="text-sm">
          <Link href={`/casos/${caso.id}`} className="text-tinta-500 underline hover:text-tinta-900">
            Adicionar depois
          </Link>{" "}
          <span className="text-tinta-500">— o mandato fica criado, sem documentos, e você vai para a Visão geral.</span>
        </p>
      )}
    </div>
  );
}
