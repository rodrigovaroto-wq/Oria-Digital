import Link from "next/link";
import { createClient } from "@/lib/supabase/server";
import { CAPITULOS_APRESENTACAO } from "@/lib/apresentacao/campos";
import { FormCapitulo } from "./FormCapitulo";

// A TELA DOS CAMPOS "[a preencher]" DA APRESENTAÇÃO DE CRÉDITO.
//
// Os números do deck vêm do realizado (Modelagem); aqui fica o que só o analista ou a pesquisa
// sabem — títulos dos slides de pesquisa, tendências, sócios, concorrentes, notas do scorecard,
// contatos. Campo em branco continua "[a preencher]" no deck: nada é inventado no lugar.
export default async function ApresentacaoPage({ params }: { params: Promise<{ id: string }> }) {
  const { id } = await params;
  const supabase = await createClient();
  const [casoRes, camposRes] = await Promise.all([
    supabase.from("caso").select("nome").eq("id", id).single(),
    supabase.from("caso_apresentacao_campo").select("chave, valor").eq("caso_id", id),
  ]);
  const valores = Object.fromEntries(((camposRes.data ?? []) as Array<{ chave: string; valor: string }>).map((c) => [c.chave, c.valor]));
  const preenchidos = Object.keys(valores).length;
  const total = CAPITULOS_APRESENTACAO.reduce((t, c) => t + c.campos.length, 0);
  return (
    <div className="space-y-6">
      <div className="flex flex-wrap items-start justify-between gap-4">
        <div>
          <h1 className="font-titulo text-2xl font-medium tracking-tight text-tinta-900">
            Apresentação de crédito{casoRes.data?.nome ? ` — ${casoRes.data.nome}` : ""}
          </h1>
          <p className="mt-0.5 text-sm text-tinta-500">
            {preenchidos} de {total} campos preenchidos. Os números vêm da Modelagem; em branco, o slide sai “[a preencher]”.
          </p>
        </div>
        <div className="flex gap-2">
          <Link href={`/casos/${id}/modelagem`} className="btn-secundario">Voltar à modelagem</Link>
          <a href={`/casos/${id}/export?modo=apresentacao`} className="btn-primario">Gerar apresentação</a>
        </div>
      </div>
      {camposRes.error && (
        <p role="status" className="carta p-4 text-sm text-alerta-900">
          Não foi possível ler os campos ({camposRes.error.message}). Se a tabela não existe, a migration 0199 ainda não foi
          aplicada: o deck sai com todas as lacunas “[a preencher]”.
        </p>
      )}
      {CAPITULOS_APRESENTACAO.map((cap) => <FormCapitulo key={cap.titulo} casoId={id} capitulo={cap} valores={valores} />)}
    </div>
  );
}
