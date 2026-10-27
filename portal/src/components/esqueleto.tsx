// ESQUELETO DE CARREGAMENTO. Blocos tinta-100 sobre o papel; o pulso só roda com
// `motion-safe:` (quem marcou prefers-reduced-motion vê o bloco parado, que é o
// mesmo recado sem movimento). `role="status"` + "Carregando…" para leitor de
// tela, porque a forma cinza não diz nada a quem não a vê.
export function Bloco({ className = "" }: { className?: string }) {
  return <div className={`rounded bg-tinta-100 motion-safe:animate-pulse ${className}`} />;
}

export function Esqueleto({ children }: { children: React.ReactNode }) {
  return (
    <div role="status" aria-live="polite" className="space-y-4">
      <span className="sr-only">Carregando…</span>
      {children}
    </div>
  );
}

// Tabela genérica: cabeçalho + N linhas. Medido nas telas: lista de mandatos e
// documentos são tabelas de 5 a 8 colunas — o esqueleto imita a massa, não o detalhe.
export function EsqueletoTabela({ linhas = 6 }: { linhas?: number }) {
  return (
    <div className="overflow-hidden rounded-md border border-tinta-200 bg-folha">
      <div className="border-b border-tinta-200 bg-tinta-50 p-3"><Bloco className="h-3 w-1/3" /></div>
      {Array.from({ length: linhas }, (_, i) => (
        <div key={i} className="flex items-center gap-4 border-b border-tinta-100 p-3 last:border-b-0">
          <Bloco className="h-4 w-1/4" /><Bloco className="h-4 w-1/6" /><Bloco className="h-4 flex-1" />
        </div>
      ))}
    </div>
  );
}
