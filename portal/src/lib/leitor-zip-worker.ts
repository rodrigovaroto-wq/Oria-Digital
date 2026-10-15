// O WORKER QUE ABRE O ZIP DO CONTADOR (a lógica está em `pacote.ts`; ver `envio-oficial.ts`, seção 7).
//
// Aqui só se liga o percurso do pacote à thread principal. Cada evento sai por
// `postMessage`; o de entrada oficial ESPERA o `continuar` antes de o pacote seguir.
// O ACK existe para a memória: sem ele o worker leria a próxima entrada (37 s por 10M
// de linhas) enquanto o resumo anterior, de ~5 MB, espera na fila de mensagens — com
// dezenas de SPEDs, a fila vira o heap.
import { percorrerPacote, type EventoDoZip } from "./pacote";

export type MensagemParaOWorkerZip =
  | { tipo: "abrir"; zip: File }
  | { tipo: "continuar" };

const contexto = self as unknown as {
  postMessage(m: EventoDoZip): void;
  onmessage: ((e: MessageEvent<MensagemParaOWorkerZip>) => void) | null;
};

let liberar: (() => void) | null = null;

contexto.onmessage = (e) => {
  if (e.data.tipo === "continuar") { liberar?.(); return; }
  const zip = e.data.zip;
  void percorrerPacote(zip, zip.name, async (ev) => {
    if (ev.tipo !== "oficial") { contexto.postMessage(ev); return; }
    // O resolvedor é criado ANTES do envio: o `continuar` não pode chegar antes de existir quem o espere.
    const ack = new Promise<void>((resolver) => { liberar = resolver; });
    contexto.postMessage(ev);
    await ack;
  });
};
