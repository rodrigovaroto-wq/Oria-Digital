"use client";

import Link from "next/link";
import { useState } from "react";
import {
  CATEGORIAS_DO_HISTORICO, agruparPorDia, categoriaDoTipo, horaDoEvento, rotuloDoTipo, textoDoAutor,
  type CategoriaDoHistorico, type EventoDoHistorico,
} from "@/lib/historico-do-mandato";

// A LINHA DO TEMPO + O FILTRO. O filtro é do CLIENTE e só enxerga a página carregada — a tela diz
// isso ao lado dele, porque "nenhum evento de Perguntas" numa página de 100 não quer dizer que o
// mandato não tem perguntas mais atrás.
export function LinhaDoTempo({ casoId, eventos }: Readonly<{ casoId: string; eventos: EventoDoHistorico[] }>) {
  const [categoria, setCategoria] = useState<CategoriaDoHistorico | "todas">("todas");
  const presentes = new Set(eventos.map((e) => categoriaDoTipo(e.tipo)));
  // "Outros" só aparece se há tipo desconhecido na página: um filtro que nunca acha nada confunde.
  const opcoes = CATEGORIAS_DO_HISTORICO.filter((c) => c.id !== "outros" || presentes.has("outros"));
  const visiveis = categoria === "todas" ? eventos : eventos.filter((e) => categoriaDoTipo(e.tipo) === categoria);
  const dias = agruparPorDia(visiveis);

  return (
    <div>
      <div className="flex flex-wrap items-center gap-2" role="group" aria-label="Filtrar por categoria">
        <button type="button" aria-pressed={categoria === "todas"} onClick={() => setCategoria("todas")}
          className={categoria === "todas" ? "btn-primario" : "btn-secundario"}>
          Todos
        </button>
        {opcoes.map((c) => (
          <button key={c.id} type="button" aria-pressed={categoria === c.id} onClick={() => setCategoria(c.id)}
            className={categoria === c.id ? "btn-primario" : "btn-secundario"}>
            {c.rotulo} ({eventos.filter((e) => categoriaDoTipo(e.tipo) === c.id).length})
          </button>
        ))}
      </div>
      <p className="mt-2 text-xs text-tinta-600">
        O filtro vale só para os {eventos.length} eventos carregados nesta página, não para o histórico inteiro.
      </p>

      {dias.length === 0 ? (
        <p className="mt-6 text-sm text-tinta-700">
          Nenhum evento desta categoria entre os carregados. Isso não diz que não houve nenhum antes deles.
        </p>
      ) : (
        <div className="mt-6 space-y-8">
          {dias.map((dia) => (
            <section key={dia.chave} aria-label={dia.rotulo}>
              <h2 className="font-titulo text-base font-medium capitalize text-tinta-900">{dia.rotulo}</h2>
              <ol className="mt-3 divide-y divide-tinta-200 rounded-md border border-tinta-200 bg-folha">
                {dia.eventos.map((e) => (
                  <li key={e.chave} className="flex gap-4 p-3 text-sm">
                    <time dateTime={e.em} className="w-12 shrink-0 tabular-nums text-tinta-600">{horaDoEvento(e.em)}</time>
                    <div className="min-w-0 flex-1">
                      <p className="font-medium text-tinta-900">{rotuloDoTipo(e.tipo)}</p>
                      <p className="mt-0.5 break-words text-tinta-800">{e.resumo}</p>
                      <p className="mt-1 text-xs text-tinta-600">
                        {textoDoAutor(e.tipo, e.autor, e.referencia)}
                        {e.documento_id && (
                          <>
                            {" · "}
                            <Link href={`/casos/${casoId}/documentos/${e.documento_id}`} className="underline hover:text-tinta-900">
                              Abrir documento
                            </Link>
                          </>
                        )}
                      </p>
                    </div>
                  </li>
                ))}
              </ol>
            </section>
          ))}
        </div>
      )}
    </div>
  );
}
