// O WORKER QUE LÊ O ARQUIVO OFICIAL (ver `envio-oficial.ts` para a decisão).
//
// Roda `lerEnvelopeDeFluxo` — o MESMO código do CLI, importado de `Leitor/lib` e
// não copiado — fora da thread principal: medido num Chromium, 10M de linhas
// levam 37,5 s, e esse tempo na thread da tela é a aba congelada. O progresso é
// o de bytes passados ao leitor (`fluxoComProgresso`), limitado a ~10 mensagens
// por segundo para a thread principal não gastar o tempo do worker redesenhando.
import { lerEnvelopeDeFluxo } from "../../../Leitor/lib/envelope.mjs";
import { fluxoComProgresso, type EnvelopeDoLeitor, type ResumoDoLeitor } from "./envio-oficial";

export type MensagemParaOWorker = { arquivo: File };
export type MensagemDoWorker =
  | { tipo: "progresso"; lidos: number }
  | { tipo: "pronto"; envelope: EnvelopeDoLeitor; resumo: ResumoDoLeitor }
  | { tipo: "erro"; mensagem: string };

const contexto = self as unknown as {
  postMessage(m: MensagemDoWorker): void;
  onmessage: ((e: MessageEvent<MensagemParaOWorker>) => void) | null;
};

contexto.onmessage = async (e) => {
  try {
    let ultimo = 0;
    const fluxo = fluxoComProgresso(e.data.arquivo.stream(), (lidos) => {
      const agora = Date.now();
      if (agora - ultimo < 100) return;
      ultimo = agora;
      contexto.postMessage({ tipo: "progresso", lidos });
    });
    const { envelope, resumo } = await lerEnvelopeDeFluxo(fluxo, { resumir: true });
    contexto.postMessage({ tipo: "pronto", envelope, resumo });
  } catch (err) {
    contexto.postMessage({ tipo: "erro", mensagem: (err as Error).message });
  }
};
