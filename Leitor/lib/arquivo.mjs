// O arquivo do DISCO como fluxo, para o CLI (`ler.mjs`). É a única parte do leitor
// que depende do Node: o resto (`envelope.mjs`) é o mesmo código que roda no
// navegador do analista, e `openAsBlob` entrega o mesmo `ReadableStream` que o
// `File.stream()` do navegador.
import { openAsBlob } from 'node:fs';
import { lerEnvelopeDeFluxo } from './envelope.mjs';

export async function lerEnvelopeDeArquivo(caminho, opcoes) {
  return lerEnvelopeDeFluxo((await openAsBlob(caminho)).stream(), opcoes);
}
