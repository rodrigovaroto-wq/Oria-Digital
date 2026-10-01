// Monta um .xlsx REAL e MINIMO (zip com deflate de verdade, como o Excel grava) para
// os testes de abas. NAO e planilha de cliente: e a estrutura descrita no caso
// `Endividamento Krauspenhar.xlsx` — uma 1a aba "indice" e a tabela na 2a —, gerada
// aqui porque o repositorio nao tem esse arquivo (regra 4: sem fixture inventada
// passando por real; este comentario e' a declaracao). O nome de cada aba mora em
// `xl/workbook.xml`, COMPRIMIDO, exatamente como num xlsx de verdade.
import { deflateRawSync } from 'node:zlib';

const TABELA_CRC = (() => {
  const t = new Uint32Array(256);
  for (let n = 0; n < 256; n += 1) {
    let c = n;
    for (let k = 0; k < 8; k += 1) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c >>> 0;
  }
  return t;
})();
const crc32 = (buf) => {
  let c = 0xffffffff;
  for (const b of buf) c = TABELA_CRC[(c ^ b) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
};

export function zip(entradas) {
  const locais = []; const centrais = []; let deslocamento = 0;
  for (const [nome, conteudo] of entradas) {
    const nomeB = Buffer.from(nome, 'latin1');
    const cru = Buffer.from(conteudo, 'utf8');
    const comp = deflateRawSync(cru);
    const crc = crc32(cru);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0); local.writeUInt16LE(20, 4); local.writeUInt16LE(8, 8);
    local.writeUInt32LE(crc, 14); local.writeUInt32LE(comp.length, 18); local.writeUInt32LE(cru.length, 22);
    local.writeUInt16LE(nomeB.length, 26);
    locais.push(local, nomeB, comp);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0); central.writeUInt16LE(20, 4); central.writeUInt16LE(20, 6);
    central.writeUInt16LE(8, 10); central.writeUInt32LE(crc, 16); central.writeUInt32LE(comp.length, 20);
    central.writeUInt32LE(cru.length, 24); central.writeUInt16LE(nomeB.length, 28);
    central.writeUInt32LE(deslocamento, 42);
    centrais.push(central, nomeB);
    deslocamento += 30 + nomeB.length + comp.length;
  }
  const dirCentral = Buffer.concat(centrais);
  const fim = Buffer.alloc(22);
  fim.writeUInt32LE(0x06054b50, 0); fim.writeUInt16LE(entradas.length, 8); fim.writeUInt16LE(entradas.length, 10);
  fim.writeUInt32LE(dirCentral.length, 12); fim.writeUInt32LE(deslocamento, 16);
  return Buffer.concat([...locais, dirCentral, fim]);
}

/** xlsx minimo: `abas` = [[nome, [[celula, ...], ...]], ...]. */
const celula = (v) => '<c t="inlineStr"><is><t>' + v + '</t></is></c>';
const linhaXml = (l, i) => '<row r="' + (i + 1) + '">' + l.map(celula).join('') + '</row>';
const planilhaXml = (linhas) => '<worksheet><sheetData>' + linhas.map(linhaXml).join('') + '</sheetData></worksheet>';
const abaNoWorkbook = ([n], i) => '<sheet name="' + n + '" sheetId="' + (i + 1) + '" r:id="rId' + (i + 1) + '"/>';

export function xlsxMinimo(abas) {
  return zip([
    ['[Content_Types].xml', '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">spreadsheetml</Types>'],
    ['xl/workbook.xml', '<workbook><sheets>' + abas.map(abaNoWorkbook).join('') + '</sheets></workbook>'],
    ...abas.map(([, linhas], i) => ['xl/worksheets/sheet' + (i + 1) + '.xml', planilhaXml(linhas)]),
  ]);
}
