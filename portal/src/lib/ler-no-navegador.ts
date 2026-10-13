// LÊ UM ARQUIVO OFICIAL NO WORKER E DEVOLVE ENVELOPE + RESUMO (ver `leitor-worker.ts`).
//
// Um worker por arquivo, e ele morre no fim: a memória do leitor (61 MB de heap
// medidos para 10M de linhas) volta toda ao sistema a cada arquivo, em vez de o
// lote acumular heap de worker. O `new Worker(new URL(...))` tem de ficar
// literal aqui: é o padrão que o bundler reconhece para empacotar o worker.
import type { EnvelopeDoLeitor, ResumoDoLeitor } from "./envio-oficial";
import type { MensagemDoWorker } from "./leitor-worker";

export function lerNoNavegador(
  arquivo: File,
  aoLer: (bytesLidos: number) => void,
): Promise<{ envelope: EnvelopeDoLeitor; resumo: ResumoDoLeitor }> {
  return new Promise((resolver, rejeitar) => {
    const worker = new Worker(new URL("./leitor-worker.ts", import.meta.url), { type: "module" });
    const encerrar = () => worker.terminate();
    worker.onmessage = (e: MessageEvent<MensagemDoWorker>) => {
      const m = e.data;
      if (m.tipo === "progresso") return aoLer(m.lidos);
      encerrar();
      if (m.tipo === "pronto") resolver({ envelope: m.envelope, resumo: m.resumo });
      else rejeitar(new Error(m.mensagem));
    };
    // Falha ao CARREGAR o worker (bundle, CSP): sem isto a promessa nunca
    // resolve e a barra fica parada para sempre, com cara de leitura longa.
    worker.onerror = (e) => {
      encerrar();
      rejeitar(new Error(e.message || "o leitor não pôde ser iniciado no navegador"));
    };
    worker.postMessage({ arquivo });
  });
}
