// Um número do topo do Início. Mora fora de `painel-blocos.tsx` (que lê o banco) para a suíte poder
// RENDERIZÁ-LO: o que ele borra e o que não borra no modo discrição é comportamento, não texto.

import { SeloDeOrigem } from "../../components/selo-de-origem";
import type { OrigemDoNumero } from "../../lib/origem-do-numero";

const COR_DO_DETALHE = { alerta: "text-risco-700", bom: "text-ok-700", neutro: "text-tinta-500" } as const;
// O ponto repete em cor o que o texto do detalhe diz (trava = risco, pronto = ok). Neutro não tem ponto.
const PONTO_DO_DETALHE = { alerta: "bg-risco-500", bom: "bg-ok-500", neutro: "" } as const;

function corDaBarra(barra: number): string {
  if (barra >= 0.9) return "bg-ok-500";
  if (barra >= 0.6) return "bg-alerta-500";
  return "bg-risco-500";
}

/**
 * Um número do topo. `valor` é string de propósito: metade destes indicadores
 * é dinheiro ou duração, e formatar aqui dentro obrigaria o componente a saber
 * de moeda e de fuso. Nulo vira traço, que é informação e não buraco.
 */
export function Indicador({
  valor, rotulo, detalhe, tom, nota, barra, origem,
}: Readonly<{
  valor: string | null;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  /** por que não há número; só aparece quando `valor` é nulo */
  nota?: string;
  /** 0..1, desenha a fração embaixo do número. Só onde a fração É o número. */
  barra?: number | null;
  /** de onde o número vem; só entra onde a origem muda a leitura (ver `lib/origem-do-numero.ts`) */
  origem?: Exclude<OrigemDoNumero, "conferido">;
}>) {
  const corDetalhe = COR_DO_DETALHE[tom ?? "neutro"];
  return (
    <div className="carta px-[18px] py-4">
      {valor === null ? (
        <p className="font-dado text-[28px] leading-9 font-medium text-tinta-400" title={nota}>
          —
        </p>
      ) : (
        <p className="indicador-valor">{valor}</p>
      )}
      <p className="indicador-rotulo">{rotulo}</p>
      {origem && <p className="mt-0.5"><SeloDeOrigem origem={origem} /></p>}
      {/* A barra só existe onde a fração É o número, hoje a cobertura. Ao lado
          de um total ela sugeriria um limite que não existe. */}
      {typeof barra === "number" && (
        <div className="mt-2 h-1 w-full overflow-hidden rounded-full bg-tinta-50">
          <div
            className={`h-full rounded-full ${corDaBarra(barra)}`}
            style={{ width: `${Math.min(100, Math.max(2, barra * 100))}%` }}
          />
        </div>
      )}
      {/* Nada aqui leva `valor-sensivel`: são contagens do painel (mandatos, pendências, cobertura),
          que a política do globals.css não lista como sensíveis, e o detalhe pode ser a nota de
          ausência "travados: não conferido agora", que é o motivo do traço e nunca se borra (regra 1:
          com a leitura falha e o modo discrição ligado, ela seria a única frase que diz "não sei"). */}
      <p className={`mt-1 flex min-h-4 items-center gap-1.5 text-xs font-medium ${valor === null ? "text-tinta-500" : corDetalhe}`}>
        {valor !== null && detalhe && PONTO_DO_DETALHE[tom ?? "neutro"] && (
          <span aria-hidden className={`h-1.5 w-1.5 shrink-0 rounded-full ${PONTO_DO_DETALHE[tom ?? "neutro"]}`} />
        )}
        {valor === null ? (nota ?? "") : (detalhe ?? "")}
      </p>
    </div>
  );
}
