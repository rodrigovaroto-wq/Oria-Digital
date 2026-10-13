// ABRIR O ZIP DO CONTADOR, com limites (Espec. 12, G5).
//
// O pacote do contador (canal C) chega como um zip com dezenas de SPEDs e milhares
// de XMLs. O `formato.mjs` só reconhece zip quando ele é planilha (xlsx/docx); o
// resto sai `desconhecido` e nunca é aberto. Este arquivo abre.
//
// Biblioteca padrão (escada, degrau 3): o diretório central do zip é uma estrutura
// fixa, e a descompressão é `zlib.inflateRawSync`. Nada de dependência nova.
//
// Os LIMITES são a parte que não pode faltar, porque o zip vem de fora:
//   - zip-bomb: uma entrada de 1 MB que infla para 10 GB derruba o leitor. Cada
//     entrada tem teto de tamanho e de razão de compressão, e o total também;
//   - zip dentro de zip NÃO é aberto (vira item recusado, com motivo);
//   - tamanho declarado mentiroso: nunca se descompacta além do declarado;
//   - entradas que apontam para os mesmos dados (zip sobreposto) são recusadas;
//   - entrada cifrada e ZIP64 não são suportados: recusados com motivo, nunca
//     lidos pela metade.
// Toda entrada recusada volta na lista com `recusado` preenchido: um arquivo que
// ficou de fora aparece (regra 7), em vez de sumir do pacote.

import { inflateRawSync } from 'node:zlib';
import { saborDoZip } from '../../N8N/lib/formato.mjs';

export const LIMITES = {
  entradas: 20000,
  bytesPorEntrada: 512 * 1024 * 1024,
  bytesTotal: 4 * 1024 * 1024 * 1024,
  razaoMaxima: 200,
};

function eocd(buf) {
  // O registro de fim do diretório central fica nos últimos 22 bytes + comentário (até 64 KB).
  for (let i = buf.length - 22; i >= Math.max(0, buf.length - 22 - 65535); i--) {
    if (buf.readUInt32LE(i) === 0x06054b50) return i;
  }
  return -1;
}

/**
 * As entradas do zip, UMA DE CADA VEZ (gerador): quem consome processa e descarta,
 * e as entradas não se acumulam na memória. O zip em si continua inteiro na
 * memória: o diretório central fica no FIM do arquivo. Teto conhecido: zip maior
 * que a memória do leitor não abre. Sobe quando o serviço ganhar leitura por
 * posição (fs.read com offset) em vez de buffer.
 * @returns {Generator<{nome: string, buf?: Buffer, recusado?: string}>}
 */
export function* entradasDoZip(buf, limites = LIMITES) {
  const fimDir = eocd(buf);
  if (fimDir < 0) { yield { nome: '(zip)', recusado: 'diretório central não encontrado: zip truncado ou corrompido' }; return; }
  const nEntradas = buf.readUInt16LE(fimDir + 10);
  let p = buf.readUInt32LE(fimDir + 16);
  if (nEntradas === 0xffff || p === 0xffffffff) { yield { nome: '(zip)', recusado: 'ZIP64 não suportado' }; return; }
  if (nEntradas > limites.entradas) { yield { nome: '(zip)', recusado: `${nEntradas} entradas, acima do limite de ${limites.entradas}` }; return; }
  let total = 0;
  // Os trechos de dados já usados. O diretório central pode apontar VÁRIAS entradas
  // para o mesmo bloco comprimido (a "better zip bomb"): cada uma infla o mesmo
  // bloco de novo, e o total explode sem nenhum arquivo grande no pacote.
  const usados = [];
  for (let i = 0; i < nEntradas; i++) {
    if (p + 46 > buf.length || buf.readUInt32LE(p) !== 0x02014b50) { yield { nome: '(zip)', recusado: 'diretório central corrompido' }; return; }
    const flags = buf.readUInt16LE(p + 8), metodo = buf.readUInt16LE(p + 10);
    const tamComp = buf.readUInt32LE(p + 20), tamOrig = buf.readUInt32LE(p + 24);
    const nNome = buf.readUInt16LE(p + 28), nExtra = buf.readUInt16LE(p + 30), nComent = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const nome = buf.subarray(p + 46, p + 46 + nNome).toString(flags & 0x800 ? 'utf8' : 'latin1');
    p += 46 + nNome + nExtra + nComent;
    if (nome.endsWith('/')) continue; // diretório
    if (flags & 0x1) { yield { nome, recusado: 'entrada cifrada (zip com senha)' }; continue; }
    if (tamOrig > limites.bytesPorEntrada) { yield { nome, recusado: `${tamOrig} bytes descompactados, acima do limite por entrada` }; continue; }
    if (tamComp > 0 && tamOrig / tamComp > limites.razaoMaxima) { yield { nome, recusado: `razão de compressão ${Math.round(tamOrig / tamComp)}x, acima de ${limites.razaoMaxima}x (suspeita de zip-bomb)` }; continue; }
    // O total é cobrado ANTES de descompactar, pelo tamanho declarado: uma entrada
    // que falha depois também gastou o que inflou.
    if (total + tamOrig > limites.bytesTotal) { yield { nome, recusado: 'o pacote passa do limite total descompactado' }; continue; }
    total += tamOrig;
    if (local + 30 > buf.length || buf.readUInt32LE(local) !== 0x04034b50) { yield { nome, recusado: 'cabeçalho local ausente: zip corrompido' }; continue; }
    const ini = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const fim = ini + tamComp;
    if (usados.some(([a, b]) => ini < b && a < fim)) { yield { nome, recusado: 'entrada aponta para dados de outra entrada (zip sobreposto, suspeita de zip-bomb)' }; continue; }
    usados.push([ini, fim]);
    let dados;
    try {
      // A trava que fecha o tamanho declarado MENTIROSO: nunca descompactar além
      // do que o próprio zip declarou. Uma entrada que diz 1 KB e infla 500 MB
      // para em 1 KB + 1 byte e é recusada, em vez de inflar até o teto.
      if (metodo === 0) dados = buf.subarray(ini, fim);
      else if (metodo === 8) dados = inflateRawSync(buf.subarray(ini, fim), { maxOutputLength: Math.max(1, tamOrig + 1) });
      else { yield { nome, recusado: `método de compressão ${metodo} não suportado` }; continue; }
    } catch (e) { yield { nome, recusado: `o conteúdo passa do tamanho declarado ou está corrompido (${e.code || e.message})` }; continue; }
    if (dados.length !== tamOrig) { yield { nome, recusado: `tamanho descompactado ${dados.length} diferente do declarado ${tamOrig}` }; continue; }
    // Zip dentro de zip: pela assinatura, não pelo nome. Planilha e documento
    // Office também são zip, e esses passam: quem os separa é `saborDoZip`.
    if (dados.length >= 4 && dados.readUInt32LE(0) === 0x04034b50 && saborDoZip(dados) === 'zip') { yield { nome, recusado: 'zip dentro de zip não é aberto: envie os arquivos num zip só' }; continue; }
    yield { nome, buf: dados };
  }
}

/** Todas as entradas numa lista (testes e pacotes pequenos). */
export function abrirZip(buf, limites = LIMITES) {
  return [...entradasDoZip(buf, limites)];
}
