import { ORIGENS, type OrigemDoNumero } from "../lib/origem-do-numero";

/** O selo ao lado de um número: ponto na cor da origem MAIS o nome dela (cor sozinha não conta). */
export function SeloDeOrigem({ origem }: Readonly<{ origem: Exclude<OrigemDoNumero, "conferido"> }>) {
  const o = ORIGENS[origem];
  return (
    <span className={`inline-flex items-center gap-1 text-[11px] font-medium ${o.texto}`}>
      <span aria-hidden className={`h-1.5 w-1.5 rounded-full ${o.ponto}`} />
      {o.rotulo}
    </span>
  );
}

/** A legenda das três origens. A que não tem dado diz que não foi medida, em vez de sumir. */
export function LegendaDeOrigem() {
  return (
    <p className="flex flex-wrap items-center gap-x-4 gap-y-1 text-[11px] texto-fundo">
      <span>Origem do número:</span>
      {(Object.keys(ORIGENS) as OrigemDoNumero[]).map((k) => {
        const o = ORIGENS[k];
        return (
          <span key={k} className="inline-flex items-center gap-1">
            <span aria-hidden className={`h-1.5 w-1.5 rounded-full ${o.disponivel ? o.ponto : "border border-tinta-400"}`} />
            {o.rotulo}
            {!o.disponivel && <span> ({o.semDado})</span>}
          </span>
        );
      })}
    </p>
  );
}
