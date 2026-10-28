import { notFound } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { FALTA_EMAIL, idCurto, origemDoMembro, type MembroLinha } from "@/lib/membros";
import { adicionarMembro, removerMembro } from "./actions";
import { FormMembro } from "./FormMembro";

export const dynamic = "force-dynamic";

// A TELA DE MEMBROS — só para administrador (0215). Quem não é administrador recebe 404, não uma tela
// vazia: "lista de membros vazia" seria afirmar que o mandato não tem ninguém, e ele não sabe.
// O `authenticated` não lê `auth.users`, então a lista mostra o id curto e a tela DIZ o que falta
// (`FALTA_EMAIL`) — pendência de banco, não resolvida aqui por invenção.
export default async function MembrosPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();

  const { data: ehAdmin } = await supabase.rpc("fn_eh_admin");
  if (ehAdmin !== true) notFound();

  const [casoRes, membrosRes] = await Promise.all([
    supabase.from("caso").select("id, nome").eq("id", id).maybeSingle(),
    supabase.from("caso_membro").select("usuario_id, desde, por").eq("caso_id", id)
      .order("desde", { ascending: true }).order("usuario_id", { ascending: true }),
  ]);
  if (!casoRes.data) notFound();

  const membros = (membrosRes.data as MembroLinha[] | null) ?? [];
  const adicionar = adicionarMembro.bind(null, id);
  const remover = removerMembro.bind(null, id);

  return (
    <div className="max-w-3xl space-y-6">
      <div>
        <h1 className="text-xl font-semibold text-tinta-900">Membros — {casoRes.data.nome}</h1>
        <p className="mt-1 text-sm text-tinta-500">
          Quem trabalha neste mandato. Só os membros e os administradores o enxergam.
        </p>
      </div>

      <p className="rounded-lg border border-alerta-200 bg-alerta-50 p-3 text-sm text-alerta-900">
        {FALTA_EMAIL}
      </p>

      {membrosRes.error ? (
        <p className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          Não foi possível ler os membros: {membrosRes.error.message}. A lista não foi conferida — não é um mandato sem membro.
        </p>
      ) : membros.length === 0 ? (
        <p className="rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">
          <strong className="font-semibold">Mandato sem membro.</strong> Só os administradores o enxergam.
          Adicione quem vai trabalhar nele.
        </p>
      ) : (
        <ul className="carta divide-y divide-tinta-100">
          {membros.map((m) => (
            <li key={m.usuario_id} className="flex flex-wrap items-center justify-between gap-3 px-4 py-3">
              <div className="min-w-0">
                <p className="font-mono text-sm text-tinta-900" title={m.usuario_id}>{idCurto(m.usuario_id)}…</p>
                <p className="text-xs text-tinta-500">
                  {origemDoMembro(m.por)}
                  {m.desde ? ` · desde ${new Date(m.desde).toLocaleDateString("pt-BR")}` : ""}
                </p>
              </div>
              <FormMembro acao={remover} botao="Remover" className="flex flex-wrap items-center gap-2">
                <input type="hidden" name="usuario" value={m.usuario_id} />
              </FormMembro>
            </li>
          ))}
        </ul>
      )}

      <section>
        <h2 className="titulo-secao">Adicionar membro</h2>
        <FormMembro acao={adicionar} botao="Adicionar" className="mt-2 flex flex-wrap items-end gap-2">
          <label className="text-sm text-tinta-700">
            Identificador do usuário (uuid)
            <input name="usuario" required placeholder="00000000-0000-0000-0000-000000000000"
                   className="mt-1 block w-96 max-w-full rounded border border-tinta-200 bg-folha px-2 py-1 font-mono text-sm" />
          </label>
        </FormMembro>
      </section>
    </div>
  );
}
