"use server";

import { redirect } from "next/navigation";
import { createClient } from "@/lib/supabase/server";
import { hrefDoPasso2, validarNomeDoMandato } from "@/lib/passo-do-mandato";

// PASSO 1 DO NOVO MANDATO: cria o caso e leva ao passo 2. A criação é a MESMA
// chamada do upload (`obterCasoId` -> `fn_upsert_caso`, com o ator da tela): por
// ela o nome é reaproveitado se já existe, e é por isso que o aviso de "já existia"
// é lido ANTES — sem ele o analista que repete um nome acha que abriu um mandato
// novo e na verdade está somando ao antigo.
export type ResultadoDoPasso1 = { erro: { titulo: string; explicacao: string; tecnico?: string }; nome: string } | null;

export async function criarMandato(_anterior: ResultadoDoPasso1, form: FormData): Promise<ResultadoDoPasso1> {
  const bruto = String(form.get("mandato") ?? "");
  const v = validarNomeDoMandato(bruto);
  if (!v.ok) return { nome: bruto, erro: { titulo: "O mandato não foi criado.", explicacao: v.motivo } };

  const supabase = await createClient();
  const { data: existente } = await supabase.from("caso").select("id").eq("nome", v.nome).limit(1);
  const jaExistia = (existente?.length ?? 0) > 0;

  const { data, error } = await supabase.rpc("fn_upsert_caso", { p_nome: v.nome, p_ator: "portal:navegador" });
  if (error || typeof data !== "string") {
    return {
      nome: bruto,
      erro: {
        titulo: "O mandato não foi criado.",
        explicacao:
          "O sistema não conseguiu registrar o mandato, então nada foi criado e nenhum arquivo foi enviado. "
          + "Tente de novo; se repetir, avise quem cuida do sistema com o nome do mandato e a hora.",
        tecnico: error?.message ?? "o banco não devolveu o id do mandato",
      },
    };
  }
  redirect(hrefDoPasso2(data, jaExistia));
}
