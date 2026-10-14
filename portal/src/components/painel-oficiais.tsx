"use client";

import {
  achadosDaConferencia, descreverContagem, descreverDesfecho, rotuloDaFamilia, rotuloDoStatus,
  type ResultadoOficial,
} from "@/lib/envio-oficial";
import { formatarBytes } from "@/lib/limite-de-envio";

// O QUE O ANALISTA VÊ DE CADA ARQUIVO LIDO NO PRÓPRIO COMPUTADOR.
//
// Três camadas que a tela NÃO mistura, porque cada uma pode falhar sem a
// outra: (1) o que o LEITOR disse do arquivo (status do envelope e a contagem
// lida × declarada), (2) o que o resumo MEDIU (lançamentos desbalanceados,
// valores inválidos) e (3) o que o BANCO respondeu (completo, recusado,
// ausente, reenvio). "Lido por inteiro" não é "gravado", e nenhum arquivo é
// chamado de concluído sem a resposta `completo` do banco — a falha de rede no
// meio deixa o arquivo em carga, e a tela diz isso em vez de "enviado".
// Ausência nunca aparece como zero: campo que o banco ou o leitor não deu
// simplesmente não é mostrado como número.

const COR = {
  ok: "border-ok-300 bg-ok-50 text-ok-900",
  alerta: "border-alerta-300 bg-alerta-50 text-alerta-900",
  erro: "border-risco-300 bg-risco-50 text-risco-900",
} as const;

function Barra({ fracao }: { fracao: number }) {
  return (
    <div className="mt-1 h-1.5 w-full overflow-hidden rounded bg-tinta-100">
      <div className="h-full bg-tinta-600 transition-all" style={{ width: `${Math.round(Math.min(1, Math.max(0, fracao)) * 100)}%` }} />
    </div>
  );
}

export default function PainelOficiais({ resultados }: { resultados: readonly ResultadoOficial[] }) {
  if (resultados.length === 0) return null;
  return (
    <section className="rounded border border-tinta-200 bg-folha p-3 text-sm" aria-label="Arquivos lidos no seu computador">
      <p className="text-xs font-semibold uppercase tracking-wide text-tinta-500">
        Arquivos lidos no seu computador — só o resumo é enviado
      </p>
      <ul className="mt-2 space-y-3">
        {resultados.map((r) => {
          const achados = achadosDaConferencia(r.resumo);
          const desfecho = r.desfecho ? descreverDesfecho(r.desfecho) : null;
          return (
            <li key={r.chave} className="rounded border border-tinta-100 p-2">
              <p className="font-medium text-tinta-800">
                {r.nome} <span className="font-normal text-tinta-400">({formatarBytes(r.bytes)})</span>
              </p>
              <p className="text-xs text-tinta-500">{rotuloDaFamilia(r.familia, r.subtipo)}</p>

              {r.fase === "na_fila" && <p className="mt-1 text-xs text-tinta-500">Na fila para leitura.</p>}
              {r.fase === "lendo" && (
                <div className="mt-1 text-xs text-tinta-600">
                  Lendo no seu computador: {formatarBytes(r.lidosBytes)} de {formatarBytes(r.bytes)}.
                  Pode levar alguns minutos num arquivo grande — mantenha esta aba aberta.
                  <Barra fracao={r.bytes > 0 ? r.lidosBytes / r.bytes : 0} />
                </div>
              )}
              {r.fase === "gravando" && (
                <div className="mt-1 text-xs text-tinta-600">
                  {r.gravacao?.etapa === "anexar" && r.gravacao.total > 0
                    ? `Enviando o resumo: parte ${Math.min(r.gravacao.feitas + 1, r.gravacao.total)} de ${r.gravacao.total}. Ainda não concluído.`
                    : "Registrando o arquivo no banco. Ainda não concluído."}
                  {r.gravacao?.etapa === "anexar" && r.gravacao.total > 0 && <Barra fracao={r.gravacao.feitas / r.gravacao.total} />}
                </div>
              )}

              {r.erroDeLeitura && (
                <p className={`mt-2 rounded border p-2 text-xs ${COR.erro}`}>
                  O arquivo não pôde ser lido neste computador: {r.erroDeLeitura}. Nada foi enviado.
                  Tente de novo; se repetir, avise quem cuida do sistema.
                </p>
              )}
              {r.envelope && (
                <div className="mt-1 text-xs text-tinta-700">
                  <p>{rotuloDoStatus(r.envelope)}</p>
                  <p>{descreverContagem(r.envelope)}</p>
                </div>
              )}
              {achados.map((a) => (
                <p key={a} className={`mt-1 rounded border p-2 text-xs ${COR.alerta}`}>{a}</p>
              ))}
              {desfecho && <p className={`mt-1 rounded border p-2 text-xs ${COR[desfecho.tom]}`}>{desfecho.texto}</p>}
            </li>
          );
        })}
      </ul>
    </section>
  );
}
