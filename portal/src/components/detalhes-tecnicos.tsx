// O RECOLHIDO ÚNICO DO QUE É DE ENGENHARIA. Número de migration, caminho de
// arquivo, nome de função, SQL e mensagem crua do banco não somem da tela — o
// dono os usa para diagnosticar —, mas deixam o corpo, onde o analista precisa de
// uma frase de negócio e do que fazer. Mesmo padrão visual do `PainelDeErro`
// (<details> fechado, "Detalhes técnicos"), em tom neutro para servir também a
// avisos que não são erro. Sem estado: serve a server e a client component.
export function DetalhesTecnicos({
  children, className = "mt-2", prosa = false,
}: {
  children: React.ReactNode;
  className?: string;
  // `prosa`: o recolhido guarda parágrafo explicativo (não SQL nem mensagem de banco),
  // e monoespaçado ele fica ilegível.
  prosa?: boolean;
}) {
  return (
    <details className={`${className} text-xs`}>
      <summary className="cursor-pointer opacity-80">Detalhes técnicos</summary>
      <div className={`mt-2 space-y-1 rounded bg-folha p-3 ${prosa ? "" : "font-mono"} break-words text-tinta-700`}>
        {children}
      </div>
    </details>
  );
}
