// Os scripts de medição recebem nomes pela linha de comando e servem arquivos por
// HTTP. Nada aqui roda em produção, mas um caminho mal passado (um `..` a mais, uma
// URL com `%2e%2e/`) leria ou escreveria fora de onde a medição mora. Por isso:
//   - da linha de comando vem só um NOME (sem barra), e o arquivo fica no diretório
//     de onde o script foi chamado;
//   - por URL, só o que estiver dentro da pasta servida.
import { basename, resolve, sep } from 'node:path';

/** Nome de arquivo da linha de comando → caminho no diretório atual. Barra ou `..` encerram o script. */
export function nomeDaLinhaDeComando(arg, rotulo = 'nome') {
  const nome = basename(String(arg ?? ''));
  if (nome === '' || nome !== arg || nome === '.' || nome === '..') {
    console.error(`${rotulo}: passe só o nome do arquivo (sem pasta); ele é gravado no diretório atual (${process.cwd()})`);
    process.exit(2);
  }
  return resolve(process.cwd(), nome);
}

/** Caminho pedido por URL a um servidor de arquivos: só dentro da pasta servida. Null = recusar. */
export function caminhoDaUrl(raiz, url) {
  let pedido;
  try { pedido = decodeURIComponent(String(url).split('?')[0]); } catch { return null; }
  const base = resolve(raiz);
  const c = resolve(base, '.' + (pedido.startsWith('/') ? pedido : '/' + pedido));
  return c === base || c.startsWith(base + sep) ? c : null;
}
