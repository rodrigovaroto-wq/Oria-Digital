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
 * @returns {Array<{nome: string, buf?: Buffer, recusado?: string}>}
 */
export function abrirZip(buf, limites = LIMITES) {
  const fimDir = eocd(buf);
  if (fimDir < 0) return [{ nome: '(zip)', recusado: 'diretório central não encontrado: zip truncado ou corrompido' }];
  const nEntradas = buf.readUInt16LE(fimDir + 10);
  let p = buf.readUInt32LE(fimDir + 16);
  if (nEntradas === 0xffff || p === 0xffffffff) return [{ nome: '(zip)', recusado: 'ZIP64 não suportado' }];
  if (nEntradas > limites.entradas) return [{ nome: '(zip)', recusado: `${nEntradas} entradas, acima do limite de ${limites.entradas}` }];
  const saida = [];
  let total = 0;
  for (let i = 0; i < nEntradas; i++) {
    if (buf.readUInt32LE(p) !== 0x02014b50) { saida.push({ nome: '(zip)', recusado: 'diretório central corrompido' }); break; }
    const flags = buf.readUInt16LE(p + 8), metodo = buf.readUInt16LE(p + 10);
    const tamComp = buf.readUInt32LE(p + 20), tamOrig = buf.readUInt32LE(p + 24);
    const nNome = buf.readUInt16LE(p + 28), nExtra = buf.readUInt16LE(p + 30), nComent = buf.readUInt16LE(p + 32);
    const local = buf.readUInt32LE(p + 42);
    const nome = buf.subarray(p + 46, p + 46 + nNome).toString(flags & 0x800 ? 'utf8' : 'latin1');
    p += 46 + nNome + nExtra + nComent;
    if (nome.endsWith('/')) continue; // diretório
    const recusa = (motivo) => saida.push({ nome, recusado: motivo });
    if (flags & 0x1) { recusa('entrada cifrada (zip com senha)'); continue; }
    if (tamOrig > limites.bytesPorEntrada) { recusa(`${tamOrig} bytes descompactados, acima do limite por entrada`); continue; }
    if (tamComp > 0 && tamOrig / tamComp > limites.razaoMaxima) { recusa(`razão de compressão ${Math.round(tamOrig / tamComp)}x, acima de ${limites.razaoMaxima}x (suspeita de zip-bomb)`); continue; }
    if (total + tamOrig > limites.bytesTotal) { recusa('o pacote passa do limite total descompactado'); continue; }
    const ini = local + 30 + buf.readUInt16LE(local + 26) + buf.readUInt16LE(local + 28);
    const comp = buf.subarray(ini, ini + tamComp);
    let dados;
    try {
      // `maxOutputLength` é a segunda trava: se o cabeçalho mentir sobre o tamanho
      // original, a descompressão para no teto em vez de seguir até a memória acabar.
      if (metodo === 0) dados = comp;
      else if (metodo === 8) dados = inflateRawSync(comp, { maxOutputLength: limites.bytesPorEntrada });
      else { recusa(`método de compressão ${metodo} não suportado`); continue; }
    } catch (e) { recusa(`falha ao descompactar: ${e.message}`); continue; }
    if (dados.length !== tamOrig) { recusa(`tamanho descompactado ${dados.length} diferente do declarado ${tamOrig}`); continue; }
    // Zip dentro de zip: pela assinatura, não pelo nome. Planilha e documento
    // Office também são zip, e esses passam: quem os separa é `saborDoZip`.
    if (dados.length >= 4 && dados.readUInt32LE(0) === 0x04034b50 && saborDoZip(dados) === 'zip') { recusa('zip dentro de zip não é aberto: envie os arquivos num zip só'); continue; }
    total += dados.length;
    saida.push({ nome, buf: dados });
  }
  return saida;
}
