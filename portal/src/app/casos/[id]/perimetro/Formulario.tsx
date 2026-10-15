"use client";

import { useActionState, type ReactNode } from "react";
import type { ResultadoPerimetro } from "./actions";

/** Um formulário pequeno com o resultado ao lado. `acao` vem JÁ amarrada ao caso pela página (servidor). */
export function Formulario({ acao: salvar, entidadeId, botao, children, className }: Readonly<{
  acao: (anterior: ResultadoPerimetro, form: FormData) => Promise<ResultadoPerimetro>;
  entidadeId: string; botao: string; children: ReactNode; className?: string;
}>) {
  const [resultado, acao, pendente] = useActionState<ResultadoPerimetro, FormData>(salvar, null);
  return (
    <form action={acao} className={className ?? "flex flex-wrap items-end gap-2"}>
      <input type="hidden" name="entidade_id" value={entidadeId} />
      {children}
      <button type="submit" className="btn-secundario" disabled={pendente}>{pendente ? "Gravando…" : botao}</button>
      {resultado && (
        <output className={`basis-full text-sm ${resultado.tom === "ok" ? "text-ok-800" : "text-risco-800"}`}>{resultado.texto}</output>
      )}
    </form>
  );
}

export const CAMPO = "mt-1 rounded border border-tinta-200 bg-folha px-2 py-1 text-sm";
