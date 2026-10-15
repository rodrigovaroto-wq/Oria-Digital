// ABRE UM ZIP NO WORKER E ENTREGA OS EVENTOS, UM DE CADA VEZ (ver `leitor-zip-worker.ts`).
//
// Os eventos são tratados em SÉRIE (uma fila de promessas): o tratamento de uma
// entrada oficial é assíncrono (grava o resumo no banco) e o worker só segue depois
// do `continuar`, que sai daqui quando o tratamento termina. Se o tratamento lançar,
// o worker é encerrado e a promessa rejeita: nada fica lendo um pacote de 3 GB sem
// ninguém para ouvir. `new Worker(new URL(...))` fica literal pelo mesmo motivo de
// `ler-no-navegador.ts`: é o padrão que o bundler reconhece.
import type { MensagemParaOWorkerZip } from "./leitor-zip-worker";
import type { EventoDoZip } from "./pacote";

export function lerZipNoNavegador(
  zip: File,
  aoEvento: (e: EventoDoZip) => Promise<void> | void,
): Promise<void> {
  return new Promise((resolver, rejeitar) => {
    const worker = new Worker(new URL("./leitor-zip-worker.ts", import.meta.url), { type: "module" });
    const enviar = (m: MensagemParaOWorkerZip) => worker.postMessage(m);
    let fila: Promise<void> = Promise.resolve();
    let encerrado = false;
    const encerrar = (erro?: Error) => {
      if (encerrado) return;
      encerrado = true;
      worker.terminate();
      if (erro) rejeitar(erro); else resolver();
    };
    worker.onmessage = (e: MessageEvent<EventoDoZip>) => {
      const m = e.data;
      fila = fila.then(async () => {
        if (encerrado) return;
        if (m.tipo === "erro") return encerrar(new Error(m.mensagem));
        await aoEvento(m);
        if (m.tipo === "oficial") enviar({ tipo: "continuar" });
        if (m.tipo === "fim") encerrar();
      }).catch((err) => encerrar(err as Error));
    };
    // Falha ao CARREGAR o worker (bundle, CSP): sem isto a promessa nunca resolve.
    worker.onerror = (e) => encerrar(new Error(e.message || "o leitor de zip não pôde ser iniciado no navegador"));
    enviar({ tipo: "abrir", zip });
  });
}
