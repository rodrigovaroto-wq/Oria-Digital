"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ZonaDeEscrita } from "@/components/acesso-na-tela";
import { INTERVALO_ACOMPANHAMENTO_MS, janelaPara } from "@/lib/espera-do-lote";
import { fraseDoBloqueio, type ItemDaFila, type Recusado, type VeredictoDoReprocesso } from "@/lib/fila-de-reprocesso";

type Sucesso = { ids: string[]; desde: string; recusados: Recusado[] };

// A FILA DE REPROCESSO na aba Documentos: o documento cuja leitura falhou, com o botão que reenvia o
// ORIGINAL guardado (POST /api/casos/[id]/reprocessar). Quem decide o que é reprocessável é o banco; a
// tela só mostra o motivo do que não é. Depois do envio acompanha `api/intake/status` — o mesmo da tela
// de envio — e atualiza a página quando a leitura termina (ou diz que parou de acompanhar).
export function FilaDeReprocesso({
  casoId, itens, pode, motivoSemPermissao,
}: Readonly<{ casoId: string; itens: ItemDaFila[]; pode: boolean; motivoSemPermissao: string | null }>) {
  const router = useRouter();
  const [enviando, setEnviando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);
  const [sucesso, setSucesso] = useState<Sucesso | null>(null);
  const [terminou, setTerminou] = useState<"pronto" | "recusado" | "tempo" | null>(null);
  const [veredito, setVeredito] = useState<VeredictoDoReprocesso | null>(null);
  const reprocessaveis = itens.filter((i) => i.reprocessavel);

  async function reprocessar(ids: string[]) {
    setEnviando(true); setErro(null); setSucesso(null); setTerminou(null); setVeredito(null);
    try {
      const resp = await fetch(`/api/casos/${casoId}/reprocessar`, {
        method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ documentoIds: ids }),
      });
      const json = await resp.json().catch(() => ({}));
      if (!resp.ok || !json.ok) {
        const recusados = (json.recusados as Recusado[] | undefined) ?? [];
        setErro([json.error ?? `Falha no reprocesso (HTTP ${resp.status}).`, ...recusados.map((r) => `${nomeDe(r.documentoId)}: ${r.motivo}`)].join(" "));
        return;
      }
      setSucesso({ ids: json.enviados.map((e: { documentoId: string }) => e.documentoId), desde: json.desde, recusados: json.recusados ?? [] });
    } catch (e) {
      setErro(`Não foi possível enviar o pedido: ${(e as Error).message}`);
    } finally {
      setEnviando(false);
    }
  }
  const nomeDe = (id: string) => itens.find((i) => i.documento_id === id)?.nome_original ?? id;

  // Acompanha POR DOCUMENTO enviado (`api/casos/[id]/reprocessar/status`): "lido" só com versão nova
  // e extração gravada. O botão fica desabilitado enquanto acompanha (`ocupado`).
  useEffect(() => {
    if (!sucesso || terminou) return;
    let cancelado = false;
    const limite = Date.now() + janelaPara(sucesso.ids.length);
    let espera: ReturnType<typeof setTimeout>;
    const verificar = async () => {
      if (cancelado) return;
      try {
        const q = new URLSearchParams({ desde: sucesso.desde, ids: sucesso.ids.join(",") });
        const resp = await fetch(`/api/casos/${casoId}/reprocessar/status?${q}`);
        const json = await resp.json().catch(() => ({}));
        if (!cancelado && resp.ok) {
          setVeredito(json as VeredictoDoReprocesso);
          if (json.estado === "pronto") { setTerminou("pronto"); router.refresh(); return; }
          if (json.estado === "recusado") { setTerminou("recusado"); return; }
        }
      } catch { /* a próxima volta tenta de novo; o teto abaixo encerra */ }
      if (cancelado) return;
      if (Date.now() > limite) { setTerminou("tempo"); return; }
      espera = setTimeout(verificar, INTERVALO_ACOMPANHAMENTO_MS);
    };
    espera = setTimeout(verificar, INTERVALO_ACOMPANHAMENTO_MS);
    return () => { cancelado = true; clearTimeout(espera); };
  }, [sucesso, terminou, casoId, router]);

  const ocupado = enviando || (sucesso !== null && terminou === null);

  return (
    <section aria-labelledby="fila-reprocesso">
      <div className="mb-2 flex items-baseline justify-between gap-3">
        <h2 id="fila-reprocesso" className="titulo-secao">Fila de reprocesso</h2>
        <p className="text-xs text-tinta-500">
          {itens.length} {itens.length === 1 ? "documento com leitura que falhou" : "documentos com leitura que falhou"}
        </p>
      </div>
      {!pode && motivoSemPermissao && (
        <p role="note" className="mb-2 rounded-lg border border-tinta-200 bg-tinta-50 px-3 py-2 text-sm text-tinta-700">{motivoSemPermissao}</p>
      )}
      <ZonaDeEscrita pode={pode}>
        <ul className="carta divide-y divide-tinta-100">
          {itens.map((i) => {
            const frase = fraseDoBloqueio(i.motivo_bloqueio);
            return (
              <li key={i.documento_id} className="flex flex-wrap items-start justify-between gap-3 px-4 py-3 text-sm">
                <div className="min-w-0 max-w-2xl">
                  <p className="valor-sensivel truncate font-medium text-tinta-900">{i.nome_original ?? "—"}</p>
                  <p className="text-xs text-tinta-500">falhou desde {new Date(i.falha_aberta_desde).toLocaleString("pt-BR")}</p>
                  {i.falha_descricao && <p className="mt-0.5 text-xs text-tinta-700">{i.falha_descricao}</p>}
                  {!i.reprocessavel && (
                    <p className="mt-1 text-xs text-alerta-800">Não dá para reprocessar: {frase.motivo}. {frase.oQueFazer}</p>
                  )}
                </div>
                {i.reprocessavel && (
                  <button type="button" disabled={ocupado} onClick={() => reprocessar([i.documento_id])} className="btn-secundario">
                    Reprocessar
                  </button>
                )}
              </li>
            );
          })}
        </ul>
        {reprocessaveis.length > 1 && (
          <button type="button" disabled={ocupado} onClick={() => reprocessar(reprocessaveis.map((i) => i.documento_id))} className="btn-secundario mt-2">
            Reprocessar todos os {reprocessaveis.length}
          </button>
        )}
      </ZonaDeEscrita>
      {enviando && <p role="status" className="mt-2 text-sm text-tinta-700">Enviando os originais…</p>}
      {erro && <p role="alert" className="mt-2 rounded-lg border border-risco-200 bg-risco-50 p-3 text-sm text-risco-800">{erro}</p>}
      {sucesso && (
        <div role="status" className={`mt-2 rounded-lg border p-3 text-sm ${terminou === "recusado" ? "border-risco-200 bg-risco-50 text-risco-800" : "border-ok-200 bg-ok-50 text-ok-800"}`}>
          {terminou === "recusado" ? veredito?.mensagem : (
            <>
              {sucesso.ids.length} {sucesso.ids.length === 1 ? "documento enviado" : "documentos enviados"} para leitura.
              {" "}
              {terminou === "pronto" && "A leitura terminou e a fila foi atualizada."}
              {terminou === "tempo" && `Parei de acompanhar com ${veredito?.lidos ?? 0} de ${sucesso.ids.length} lidos; recarregue a página mais tarde para ver o resultado.`}
              {!terminou && `A leitura roda no n8n (${veredito?.lidos ?? 0} de ${sucesso.ids.length} lidos até agora) e a fila atualiza quando terminar.`}
            </>
          )}
          {sucesso.recusados.map((r) => (
            <span key={r.documentoId} className="mt-1 block text-alerta-800">{nomeDe(r.documentoId)} não foi enviado: {r.motivo}</span>
          ))}
        </div>
      )}
    </section>
  );
}
