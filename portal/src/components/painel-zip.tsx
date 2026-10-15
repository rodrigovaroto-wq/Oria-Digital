"use client";

import {
  contarEntradasDoZip, rotuloDaEntrada, type EntradaDoZip, type ProgressoDoZip, type ResultadoOficial,
} from "@/lib/envio-oficial";
import { formatarBytes } from "@/lib/limite-de-envio";

// O QUE O ANALISTA VÊ DE UM PACOTE COMPACTADO (zip).
//
// O pacote leva minutos (um SPED de 10 milhões de linhas leva ~40 s sozinho), então a
// tela mostra ONDE ele está, entrada a entrada. E mostra TODA entrada que não foi lida
// como arquivo oficial: a que foi ao processamento fica numa lista recolhida (é a
// regra, não a exceção), mas a recusada, a não enviada, a ignorada e a retida ficam
// abertas, cada uma com o motivo e o efeito. Um arquivo que ficou de fora e não aparece
// aqui é um arquivo que ninguém sabe que está faltando no mandato (regra 7).
// As entradas oficiais aparecem no painel dos arquivos lidos no computador, com o nome
// "pacote › arquivo".

const COR = {
  ok: "border-ok-300 bg-ok-50 text-ok-900",
  alerta: "border-alerta-300 bg-alerta-50 text-alerta-900",
  erro: "border-risco-300 bg-risco-50 text-risco-900",
} as const;

export default function PainelZip({
  progresso, entradas, oficiais,
}: {
  progresso: ProgressoDoZip | null;
  entradas: readonly EntradaDoZip[];
  oficiais: readonly ResultadoOficial[];
}) {
  if (!progresso && entradas.length === 0) return null;
  const oficiaisDoZip = progresso ? oficiais.filter((o) => o.nome.startsWith(`${progresso.zip} › `)) : [];
  const n = contarEntradasDoZip(entradas, oficiaisDoZip);
  const enviadas = entradas.filter((e) => e.situacao === "ao_n8n");
  const outras = entradas.filter((e) => e.situacao !== "ao_n8n");
  return (
    <section className="rounded border border-tinta-200 bg-folha p-3 text-sm" aria-label="Pacote compactado">
      <p className="text-xs font-semibold uppercase tracking-wide text-tinta-500">
        Pacote compactado{progresso ? ` — ${progresso.zip}` : ""}
      </p>
      {progresso && (progresso.fase === "abrindo" || progresso.fase === "lendo") && (
        <p className="mt-1 text-xs text-tinta-600" aria-live="polite">
          {progresso.fase === "abrindo"
            ? "Abrindo o pacote no seu computador…"
            : `Entrada ${progresso.indice.toLocaleString("pt-BR")} de ${progresso.total.toLocaleString("pt-BR")}: ${progresso.nome}. `}
          O pacote pode levar vários minutos — mantenha esta aba aberta.
        </p>
      )}
      {progresso?.fase === "falhou" && (
        <p className={`mt-1 rounded border p-2 text-xs ${COR.erro}`}>
          O pacote não pôde ser aberto ou a leitura parou: {progresso.erro}. O que já foi gravado está acima;
          o restante NÃO foi processado e nenhum arquivo comum do pacote foi enviado. Pode reenviar o pacote:
          os arquivos oficiais já gravados são reconhecidos como reenvio.
        </p>
      )}
      {progresso?.fase === "fim" && (
        <p className="mt-1 text-xs text-tinta-700">
          Pacote concluído: {n.oficiais} arquivo(s) de leiaute oficial lido(s) aqui ({n.oficiaisComResposta} com resposta do banco),
          {" "}{n.aoN8n} enviado(s) ao processamento, {n.naoEnviadas} não enviado(s), {n.recusadas} recusado(s),
          {" "}{n.ignoradas} ignorado(s){n.retidas > 0 ? `, ${n.retidas} retido(s)` : ""}.
        </p>
      )}
      {outras.length > 0 && (
        <ul className="mt-2 space-y-1">
          {outras.map((e) => (
            <li key={e.chave} className={`rounded border p-2 text-xs ${e.situacao === "ignorada" ? "border-tinta-200 bg-tinta-50 text-tinta-700" : e.situacao === "recusada" ? COR.erro : COR.alerta}`}>
              <span className="font-medium">{e.nome}</span>
              {e.bytes !== null && <span className="text-tinta-500"> ({formatarBytes(e.bytes)})</span>}
              {" — "}{rotuloDaEntrada(e)}
            </li>
          ))}
        </ul>
      )}
      {enviadas.length > 0 && (
        <details className="mt-2 text-xs text-tinta-600">
          <summary className="cursor-pointer">{enviadas.length} arquivo(s) enviado(s) ao processamento</summary>
          <ul className="mt-1 max-h-60 space-y-0.5 overflow-auto">
            {enviadas.map((e) => (
              <li key={e.chave}>{e.nome} <span className="text-tinta-400">({formatarBytes(e.bytes ?? 0)})</span></li>
            ))}
          </ul>
        </details>
      )}
    </section>
  );
}
