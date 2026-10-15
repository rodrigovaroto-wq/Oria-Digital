// O PACOTE (ZIP) PERCORRIDO ENTRADA A ENTRADA — a parte pura do worker de zip.
//
// Mora aqui, e não no worker, pelo motivo de sempre neste repositório: a conta que
// ninguém consegue CHAMAR num teste é a que erra em silêncio. O worker
// (`leitor-zip-worker.ts`) só liga isto à thread principal; `verificar-envio-oficial.mts`
// chama `percorrerPacote` — a MESMA função — com um zip gerado no teste.
//
// O zip passa de 3 GB, então não é lido inteiro: `entradasDoZip` (o MESMO código do
// CLI, `Leitor/lib/zip.mjs`) lê o diretório e cada entrada por posição (`slice`) e
// infla em fluxo (`DecompressionStream`). Cada entrada cai num de três lugares:
//   - família oficial: lida por `lerEnvelopeDeFluxo`, como um arquivo avulso;
//   - não oficial que cabe no processamento: inflada numa `File` (≤ 15 MiB);
//   - o resto: nome, tamanho e motivo — nunca silêncio.
// Uma falha em UMA entrada vira `recusada` e o pacote segue.
import { entradasDoZip, lerCabeca, motivoDoErro } from "../../../Leitor/lib/zip.mjs";
import { lerEnvelopeDeFluxo } from "../../../Leitor/lib/envelope.mjs";
import { detectarFamilia } from "../../../Leitor/lib/familia.mjs";
import {
  CABECA_BYTES, decidirNaoOficial, fluxoComProgresso, nomeParaN8n,
  type EnvelopeDoLeitor, type ResumoDoLeitor,
} from "./envio-oficial";

export type EventoDoZip =
  /** Começou a ler uma entrada oficial (família já reconhecida). */
  | { tipo: "oficial_inicio"; indice: number; total: number; nome: string; bytes: number; familia: string; subtipo: string | null }
  | { tipo: "progresso"; lidos: number }
  /** Entrada oficial lida. Quem emite ESPERA o `emitir` terminar antes de seguir (o worker espera o `continuar`). */
  | { tipo: "oficial"; nome: string; envelope: EnvelopeDoLeitor; resumo: ResumoDoLeitor }
  /** Entrada não oficial: `arquivo` quando vai ao n8n; `situacao` + `motivo` quando não. */
  | { tipo: "nao_oficial"; indice: number; total: number; nome: string; bytes: number; arquivo?: File; situacao?: "nao_enviada" | "ignorada"; motivo?: string }
  /** Recusada pelo zip (limite, cifrada, sobreposta...) OU falha ao ler uma entrada já aberta (deflate, CRC, tamanho). */
  | { tipo: "recusada"; indice: number | null; total: number | null; nome: string; motivo: string }
  | { tipo: "fim"; entradas: number }
  | { tipo: "erro"; mensagem: string };

/**
 * Percorre o pacote e emite um evento por entrada. `emitir` é aguardado a cada
 * evento que não é `progresso`: a leitura da entrada seguinte só começa quando quem
 * escuta terminou (o resumo anterior, de ~5 MB, não fica esperando na memória).
 * Falha ao abrir o zip é o evento `erro`; nunca lança.
 */
export async function percorrerPacote(
  zip: Blob,
  nomeDoZip: string,
  emitir: (e: EventoDoZip) => void | Promise<void>,
  /** `orcamentoNaoOficialBytes`: só os testes mudam (o padrão são os 256 MiB de `envio-oficial.ts`). */
  opcoes: { orcamentoNaoOficialBytes?: number } = {},
): Promise<void> {
  try {
    let usadoBytes = 0;
    let n = 0;
    for await (const e of entradasDoZip(zip)) {
      n++;
      if (e.recusado !== undefined) {
        // Sem `indice` a recusa é do PACOTE, não de uma entrada (diretório central ausente ou corrompido,
        // acima do limite de entradas, ZIP64 inválido): não há o que ler, e "pacote lido" seria falso.
        if (e.indice === undefined) { await emitir({ tipo: "erro", mensagem: e.recusado }); return; }
        await emitir({ tipo: "recusada", indice: e.indice ?? null, total: e.total ?? null, nome: e.nome, motivo: e.recusado });
        continue;
      }
      const { nome, tamanho, indice, total, fluxo } = e;
      try {
        const cabeca = await lerCabeca(fluxo(), CABECA_BYTES);
        const fam = detectarFamilia(cabeca) as { familia: string | null; subtipo?: string | null };
        if (fam.familia && fam.familia !== "zip") {
          await emitir({ tipo: "oficial_inicio", indice, total, nome, bytes: tamanho, familia: fam.familia, subtipo: fam.subtipo ?? null });
          let ultimo = 0;
          const lido = await lerEnvelopeDeFluxo(
            fluxoComProgresso(fluxo(), (lidos) => {
              const agora = Date.now();
              if (agora - ultimo < 100) return;
              ultimo = agora;
              void emitir({ tipo: "progresso", lidos });
            }),
            { resumir: true },
          );
          await emitir({ tipo: "oficial", nome, envelope: lido.envelope, resumo: lido.resumo });
          continue;
        }
        const destino = decidirNaoOficial(nome, tamanho, usadoBytes, undefined, opcoes.orcamentoNaoOficialBytes);
        if (destino.destino !== "n8n") {
          await emitir({
            tipo: "nao_oficial", indice, total, nome, bytes: tamanho,
            situacao: destino.destino === "fora" ? "nao_enviada" : "ignorada", motivo: destino.motivo,
          });
          continue;
        }
        // Cabe: infla a entrada inteira (≤ 15 MiB) NUMA `File`. Esta leitura também confere o
        // CRC e o tamanho declarado, o que a espiada de 64 KB acima não faz.
        const partes: Uint8Array<ArrayBuffer>[] = [];
        const r = fluxo().getReader();
        for (;;) {
          const { done, value } = await r.read();
          if (done) break;
          partes.push(value as Uint8Array<ArrayBuffer>);
        }
        usadoBytes += tamanho;
        await emitir({ tipo: "nao_oficial", indice, total, nome, bytes: tamanho, arquivo: new File(partes, nomeParaN8n(nomeDoZip, nome)) });
      } catch (err) {
        // A falha de UMA entrada (deflate corrompido, CRC, tamanho mentiroso no meio da leitura):
        // ela é recusada com o motivo e o pacote segue. Nada foi gravado dela (o resumo só sai
        // depois de a leitura terminar sem erro).
        await emitir({ tipo: "recusada", indice, total, nome, motivo: motivoDoErro(err) });
      }
    }
    await emitir({ tipo: "fim", entradas: n });
  } catch (err) {
    await emitir({ tipo: "erro", mensagem: (err as Error).message });
  }
}
