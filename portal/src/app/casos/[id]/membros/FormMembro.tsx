"use client";

import { useActionState, type ReactNode } from "react";
import type { ResultadoMembro } from "@/lib/membros";

/** Formulário pequeno com o resultado ao lado. `acao` vem JÁ amarrada ao caso pela página (servidor). */
export function FormMembro({ acao: salvar, botao, children, className }: Readonly<{
  acao: (anterior: ResultadoMembro, form: FormData) => Promise<ResultadoMembro>;
  botao: string; children: ReactNode; className?: string;
}>) {
  const [resultado, acao, pendente] = useActionState<ResultadoMembro, FormData>(salvar, null);
  return (
    <form action={acao} className={className ?? "flex flex-wrap items-end gap-2"}>
      {children}
      <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Gravando…" : botao}</button>
      {resultado && (
        <output className={`basis-full text-sm ${resultado.tom === "ok" ? "text-ok-800" : "text-risco-800"}`}>{resultado.texto}</output>
      )}
    </form>
  );
}
