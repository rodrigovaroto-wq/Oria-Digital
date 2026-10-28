"use client";

import { useActionState } from "react";
import { ativarPremissa, type Resultado } from "./actions";
import { valorParaGravar, type PremissaSugerida } from "@/lib/premissas-do-realizado";

// O QUE ESTE BLOCO ENTREGA, e por que ele fica ACIMA da lista de premissas.
//
// Oito das premissas que a lista abaixo pede em campo vazio já estão respondidas
// pelo próprio caso: o balanço diz em quantos dias a empresa recebe, estoca e
// paga; a DRE diz quanto o custo e o SG&A consomem da receita, e a que alíquota o
// lucro foi tributado. Digitar de cabeça o que o documento afirma é a forma mais
// barata de o modelo deixar de reproduzir o balanço de onde saiu.
//
// O NÚMERO VEM COM A CONTA À VISTA. Cada sugestão mostra o numerador, o
// denominador e a divisão que os une — é o que permite discordar dela. Sugestão
// que aparece só como número pronto convida a aceitar sem olhar, e esta é uma
// tela onde aceitar sem olhar dirige a projeção inteira.
//
// APLICA O MESMO NÚMERO EM TODOS OS ANOS, e isso é ponto de partida, não
// projeção: o realizado se repetindo é a hipótese mais simples possível, e a
// única que não inventa tendência. Mudar ano a ano é o trabalho do analista na
// lista abaixo, com o número já lá.

function Sugestao({
  casoId, anos, p, jaAtiva,
}: {
  casoId: string;
  anos: number[];
  p: PremissaSugerida;
  jaAtiva: boolean;
}) {
  const [r, act, salvando] = useActionState(
    async (prev: Resultado, fd: FormData) => ativarPremissa(casoId, prev, fd),
    null as Resultado,
  );

  const mostrado = p.valor === null
    ? "—"
    : p.unidade === "dias"
      ? `${p.valor.toLocaleString("pt-BR", { maximumFractionDigits: 1 })} dias`
      : `${(p.valor * 100).toLocaleString("pt-BR", { maximumFractionDigits: 1 })}%`;

  const num = (v: number) => v.toLocaleString("pt-BR", { maximumFractionDigits: 0 });

  return (
    <form
      action={act}
      className={`flex flex-wrap items-center gap-x-3 gap-y-1 rounded border px-2 py-1.5 text-xs ${
        p.valor === null ? "border-tinta-200 bg-tinta-50" : "border-info-200 bg-info-50"
      }`}
    >
      <input type="hidden" name="codigo" value={p.codigo} />
      <input type="hidden" name="origem" value="historico" />
      {p.valor !== null && anos.map((ano) => (
        <input key={ano} type="hidden" name={`valor_${ano}`} value={String(valorParaGravar(p))} />
      ))}

      <span className="min-w-48 flex-1 font-medium text-tinta-800">{p.nome}</span>

      <span className="valor-sensivel w-24 text-right font-semibold tabular-nums text-tinta-900">{mostrado}</span>

      {/* A CONTA, sempre. Sem ela o número é palpite com cara de medição. */}
      <span className="min-w-64 flex-1 text-tinta-500">
        {p.valor === null ? (
          /* o motivo cita os valores medidos (ex.: dívida e ativo) */
          <em className="valor-sensivel">{p.porQueNao}</em>
        ) : (
          <>
            {p.conta}
            {p.numerador && p.denominador && (
              <span className="valor-sensivel ml-1 tabular-nums text-tinta-400">
                ({num(p.numerador.valor)} ÷ {num(p.denominador.valor)})
              </span>
            )}
          </>
        )}
      </span>

      {p.valor !== null && (
        <button type="submit" disabled={salvando} className="btn-discreto shrink-0">
          {salvando ? "…" : jaAtiva ? "Substituir" : "Usar"}
        </button>
      )}

      {r && (
        <span className={`w-full ${r.tom === "ok" ? "text-ok-700" : "text-risco-700"}`}>
          {r.texto}
        </span>
      )}
    </form>
  );
}

export function SugestoesDoRealizado({
  casoId, anos, sugestoes, ativas,
}: {
  casoId: string;
  anos: number[];
  sugestoes: PremissaSugerida[];
  ativas: Set<string>;
}) {
  const comValor = sugestoes.filter((s) => s.valor !== null).length;

  return (
    <div className="mb-4 rounded border border-info-200 bg-folha p-2">
      <p className="text-xs font-medium text-tinta-700">
        Sugerido pelo realizado — {comValor} de {sugestoes.length}
      </p>
      <p className="mb-2 mt-0.5 text-xs text-tinta-500">
        Lidas do balanço e da DRE deste caso, no último exercício realizado. Cada uma mostra a
        divisão que a produziu. Aceitar aplica o mesmo número em todos os {anos.length} anos do
        horizonte: é ponto de partida, e a lista abaixo continua editável ano a ano.
      </p>
      <div className="space-y-1">
        {sugestoes.map((s) => (
          <Sugestao key={s.codigo} casoId={casoId} anos={anos} p={s} jaAtiva={ativas.has(s.codigo)} />
        ))}
      </div>
    </div>
  );
}
