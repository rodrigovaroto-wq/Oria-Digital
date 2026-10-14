// Os scripts de medição recebem caminhos pela linha de comando e servem arquivos
// por HTTP. Nada aqui roda em produção, mas um caminho mal passado (um `..` a mais,
// uma URL com `%2e%2e/`) leria ou escreveria fora de onde a medição mora. A regra
// é a mesma nos dois lados: o caminho resolvido tem de ficar DENTRO de uma raiz
// permitida, senão o script para com o motivo.
import { resolve, sep } from 'node:path';
import { tmpdir } from 'node:os';
import { realpathSync } from 'node:fs';

const dentro = (caminho, raiz) => caminho === raiz || caminho.startsWith(raiz + sep);

/** Caminho da linha de comando: só dentro do diretório atual ou do temporário do sistema. */
export function caminhoDaLinhaDeComando(arg, rotulo = 'caminho') {
  if (typeof arg !== 'string' || arg === '') { console.error(`falta o ${rotulo}`); process.exit(2); }
  const c = resolve(arg);
  const raizes = [process.cwd(), realpathSync(tmpdir()), '/tmp'].map((r) => resolve(r));
  if (!raizes.some((r) => dentro(c, r))) { console.error(`${rotulo} fora do diretório atual e do temporário: ${c}`); process.exit(2); }
  return c;
}

/** Caminho pedido por URL a um servidor de arquivos: só dentro da pasta servida. Null = recusar. */
export function caminhoDaUrl(raiz, url) {
  let pedido;
  try { pedido = decodeURIComponent(String(url).split('?')[0]); } catch { return null; }
  const c = resolve(raiz, '.' + (pedido.startsWith('/') ? pedido : '/' + pedido));
  return dentro(c, resolve(raiz)) ? c : null;
}
