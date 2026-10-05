"use client";

import { useActionState } from "react";
import type { ResultadoCampos } from "./actions";
import type { CapituloApresentacao } from "@/lib/apresentacao/campos";

/** Um capítulo do catálogo: cada campo com o valor gravado (ou vazio = "[a preencher]" no deck). */
/** `acao` vem JÁ amarrada ao caso pela página (servidor): o argumento ligado lá vai cifrado. */
export function FormCapitulo({ acao: salvar, capitulo, valores }: Readonly<{
  acao: (anterior: ResultadoCampos, form: FormData) => Promise<ResultadoCampos>;
  capitulo: CapituloApresentacao; valores: Record<string, string>;
}>) {
  const [resultado, acao, pendente] = useActionState<ResultadoCampos, FormData>(salvar, null);
  return (
    <form action={acao} className="carta space-y-3 p-5">
      <h2 className="font-titulo text-lg font-medium text-tinta-900">{capitulo.titulo}</h2>
      {capitulo.campos.map((c) => (
        <label key={c.chave} className="block text-sm">
          <span className="text-tinta-600">{c.rotulo}</span>
          {c.longo ? (
            <textarea name={`campo:${c.chave}`} defaultValue={valores[c.chave] ?? ""} rows={3}
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1" />
          ) : (
            <input name={`campo:${c.chave}`} defaultValue={valores[c.chave] ?? ""}
              className="mt-1 w-full rounded border border-tinta-200 px-2 py-1" />
          )}
        </label>
      ))}
      <div className="flex items-center gap-3">
        <button type="submit" className="btn-primario" disabled={pendente}>{pendente ? "Salvando…" : "Salvar capítulo"}</button>
        {resultado && (
          <output className={resultado.tom === "ok" ? "text-sm text-tinta-600" : "text-sm text-alerta-900"}>{resultado.texto}</output>
        )}
      </div>
    </form>
  );
}
