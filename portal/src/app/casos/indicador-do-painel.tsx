import Link from "next/link";
import { SeloDeOrigem } from "../../components/selo-de-origem";
import { IconeSetaCanto } from "../../components/icones";
import type { OrigemDoNumero } from "../../lib/origem-do-numero";

const COR_DO_DETALHE = { alerta: "text-risco-700", bom: "text-ok-700", neutro: "text-tinta-500" } as const;
// O ponto repete em cor o que o texto do detalhe diz (trava = risco, pronto = ok). Neutro não tem ponto.
const PONTO_DO_DETALHE = { alerta: "bg-risco-500", bom: "bg-ok-500", neutro: "" } as const;

const BOTAO_NO_DESTAQUE = "border-white/40 bg-vidro-texto text-vidro-acao hover:opacity-90";
const BOTAO_NO_VIDRO = "border-[var(--cartao-borda)] bg-tinta-100 text-tinta-700 hover:bg-tinta-200";

function corDaBarra(barra: number): string {
  if (barra >= 0.9) return "stroke-ok-500";
  if (barra >= 0.6) return "stroke-alerta-500";
  return "stroke-risco-500";
}

// O ANEL: raio 36 em viewBox 84 (traço de 8). A fração vira `stroke-dasharray` (comprimento do arco, resto);
// o arco começa às 12h (rotação de -90°). É o número, desenhado: o texto no centro diz o mesmo em palavras.
const R_ANEL = 36;
const C_ANEL = 2 * Math.PI * R_ANEL;

function Anel({ fracao, children }: Readonly<{ fracao: number; children: React.ReactNode }>) {
  const f = Math.min(1, Math.max(0, fracao));
  return (
    <div className="relative h-[84px] w-[84px] shrink-0">
      <svg viewBox="0 0 84 84" className="h-full w-full -rotate-90" aria-hidden focusable="false">
        <circle cx="42" cy="42" r={R_ANEL} fill="none" strokeWidth="8" className="stroke-tinta-200" />
        {/* O mínimo visível (2%) evita um anel sem arco quando a fração é quase zero; o texto continua exato. */}
        <circle
          cx="42" cy="42" r={R_ANEL} fill="none" strokeWidth="8" strokeLinecap="round"
          strokeDasharray={`${Math.max(0.02, f) * C_ANEL} ${C_ANEL}`}
          className={corDaBarra(f)}
        />
      </svg>
      <div className="absolute inset-0 flex items-center justify-center">{children}</div>
    </div>
  );
}

/**
 * Um número do topo, no cartão de vidro: o rótulo em cima (com o botão ↗ quando há para onde ir), o número
 * grande embaixo e a nota pequena logo abaixo. `valor` é string de propósito: metade destes indicadores
 * é dinheiro ou duração, e formatar aqui dentro obrigaria o componente a saber
 * de moeda e de fuso. Nulo vira traço, que é informação e não buraco.
 */
export function Indicador({
  valor, rotulo, detalhe, tom, nota, barra, origem, destaque, href,
}: Readonly<{
  valor: string | null;
  rotulo: string;
  detalhe?: string | null;
  tom?: "neutro" | "alerta" | "bom";
  /** por que não há número; só aparece quando `valor` é nulo */
  nota?: string;
  /** 0..1, desenha o ANEL ao lado do número. Só onde a fração É o número. */
  barra?: number | null;
  /** de onde o número vem; só entra onde a origem muda a leitura (ver `lib/origem-do-numero.ts`) */
  origem?: Exclude<OrigemDoNumero, "conferido">;
  /** o cartão em cobalto: o número que o dia pede para olhar primeiro. É ênfase, não estado. */
  destaque?: boolean;
  /** para onde o ↗ leva. Sem destino real, sem botão: ele nunca é enfeite. */
  href?: string;
}>) {
  const tomEfetivo = tom ?? "neutro";
  const corDetalhe = destaque ? "text-white" : COR_DO_DETALHE[tomEfetivo];
  const pontoDoDetalhe = destaque ? "bg-vidro-texto" : PONTO_DO_DETALHE[tomEfetivo];
  // O ↗ no cartão de cobalto é o botão claro do casco (`vidro-texto` com `vidro-acao`, que não invertem com o tema);
  // no cartão de vidro é um círculo de `tinta-100`. Em constantes à parte: a varredura de "fundo que inverte com
  // texto do casco no mesmo className" lê cada literal, e aqui as duas famílias nunca se misturam.
  const botao = destaque ? BOTAO_NO_DESTAQUE : BOTAO_NO_VIDRO;
  const comAnel = typeof barra === "number" && valor !== null;
  const textoValor = "font-dado text-[40px] leading-none font-medium tabular-nums tracking-[-0.03em]";
  const numero = valor === null ? (
    <p className={`${textoValor} ${destaque ? "text-white" : "text-tinta-400"}`} title={nota}>
      —
    </p>
  ) : (
    <p className={`${comAnel ? "font-dado text-[22px] leading-none font-medium tabular-nums tracking-[-0.02em]" : textoValor} ${destaque ? "text-white" : "text-tinta-900"}`}>{valor}</p>
  );
  return (
    <div className={`${destaque ? "cartao-destaque" : "carta"} flex min-h-[168px] flex-col justify-between gap-5 p-[18px]`}>
      <div className="flex items-start justify-between gap-3">
        <div className="min-w-0">
          <p className={`text-sm font-medium ${destaque ? "text-white" : "text-tinta-900"}`}>{rotulo}</p>
          {origem && <p className="mt-1"><SeloDeOrigem origem={origem} /></p>}
        </div>
        {href && (
          <Link
            href={href}
            aria-label={`Ver: ${rotulo}`}
            className={`flex h-8 w-8 shrink-0 items-center justify-center rounded-full border transition-colors duration-150 ${botao}`}
          >
            <IconeSetaCanto tamanho={16} />
          </Link>
        )}
      </div>
      <div className={comAnel ? "flex items-center gap-4" : "flex flex-col gap-2"}>
        {comAnel ? <Anel fracao={barra}>{numero}</Anel> : numero}
        {/* Nada aqui leva `valor-sensivel`: são contagens do painel (mandatos, pendências, cobertura),
            que a política do globals.css não lista como sensíveis, e o detalhe pode ser a nota de
            ausência "travados: não conferido agora", que é o motivo do traço e nunca se borra (regra 1:
            com a leitura falha e o modo discrição ligado, ela seria a única frase que diz "não sei"). */}
        <p className={`flex min-h-4 min-w-0 flex-1 items-center gap-1.5 text-xs font-medium [overflow-wrap:anywhere] ${valor === null ? (destaque ? "text-white" : "text-tinta-500") : corDetalhe}`}>
          {valor !== null && detalhe && pontoDoDetalhe && (
            <span aria-hidden className={`h-1.5 w-1.5 shrink-0 rounded-full ${pontoDoDetalhe}`} />
          )}
          {valor === null ? (nota ?? "") : (detalhe ?? "")}
        </p>
      </div>
    </div>
  );
}
