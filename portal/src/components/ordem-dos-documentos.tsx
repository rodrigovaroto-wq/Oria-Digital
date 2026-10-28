"use client";

import { useEffect, useSyncExternalStore } from "react";

// A ORDEM QUE A LISTA MOSTRA, entregue ao painel. A lista (slot `children`) e o painel (slot
// `@painel`) são renderizados separadamente pelo servidor: o painel não enxerga o `?filtro=` da
// lista. Em vez de reconsultar o banco para refazer o filtro (egress), a lista registra aqui os
// ids que já tem, na ordem, e o painel os lê no navegador. Não há persistência: F5 abre a página
// inteira (sem painel), e a ordem some junto — por isso o painel trata "sem ordem" como ausência
// declarada, não como "primeiro da lista".
let ordem: readonly string[] | null = null;
const ouvintes = new Set<() => void>();

function definir(ids: readonly string[] | null) {
  ordem = ids;
  ouvintes.forEach((f) => f());
}

export function useOrdemDosDocumentos(): readonly string[] | null {
  return useSyncExternalStore(
    (f) => { ouvintes.add(f); return () => { ouvintes.delete(f); }; },
    () => ordem,
    () => null,
  );
}

export function OrdemDosDocumentos({ ids }: Readonly<{ ids: readonly string[] }>) {
  // A chave de conteúdo evita regravar (e re-renderizar o painel) quando a lista é refeita com
  // os mesmos ids, p.ex. depois de uma ação que revalida.
  const chave = ids.join(",");
  useEffect(() => {
    definir(chave ? chave.split(",") : []);
    return () => definir(null);
  }, [chave]);
  return null;
}
