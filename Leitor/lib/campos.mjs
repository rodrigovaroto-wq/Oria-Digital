// AS PARTICULARIDADES DE FORMATO dos arquivos oficiais (Espec. 12, G10).
//
// Cada função aqui existe porque o erro dela é SILENCIOSO: nenhum desses formatos
// falha ao ser lido do jeito errado, ele só devolve outro número.
//   - SPED usa vírgula decimal ("1234,56"). `Number("1234,56")` dá NaN, e um
//     `parseFloat` dá 1234: a parte decimal some sem erro.
//   - SPED e CNAB trazem datas `ddmmaaaa` sem separador. Lidas como número, viram
//     um inteiro que ordena errado e passa por qualquer validação de tipo.
//   - CNAB tem decimais IMPLÍCITOS: "000000012345" com 2 casas é 123,45. Lido sem
//     a escala, o valor sai 100 vezes maior.
//   - SPED e CNAB são latin1 (ISO-8859-1). Decodificados como UTF-8 (o que o nó de
//     texto do n8n faz hoje, `buf.toString('utf-8')`), "AÇÚCAR" vira "A�CAR".
// Por isso nenhuma delas "tenta adivinhar": entrada fora do formato devolve null
// (ausência declarada, regra 1), nunca um número aproximado.

/** "1.234,56" | "1234,56" | "-12,5" | "" → número, ou null se não for decimal BR válido. */
export function decimalBR(texto) {
  if (texto === null || texto === undefined) return null;
  const t = String(texto).trim();
  if (t === '') return null;
  // Só dígitos, separador de milhar opcional e UMA vírgula decimal. Ponto como
  // decimal ("1234.56") é REJEITADO de propósito: no SPED ele não existe, e
  // aceitá-lo faria "1.234" (mil duzentos e trinta e quatro) virar 1,234.
  if (!/^-?(\d{1,3}(\.\d{3})+|\d+)(,\d+)?$/.test(t)) return null;
  return Number(t.replace(/\./g, '').replace(',', '.'));
}

/** "31122025" → "2025-12-31", ou null se não for uma data real. */
export function dataDDMMAAAA(texto) {
  const t = String(texto ?? '').trim();
  if (!/^\d{8}$/.test(t)) return null;
  const d = Number(t.slice(0, 2)), m = Number(t.slice(2, 4)), a = Number(t.slice(4, 8));
  // Valida o calendário inteiro (31/02 não passa): Date normaliza datas
  // impossíveis para o mês seguinte, então a conferência é ida E volta.
  const dt = new Date(Date.UTC(a, m - 1, d));
  if (dt.getUTCFullYear() !== a || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d) return null;
  return `${t.slice(4, 8)}-${t.slice(2, 4)}-${t.slice(0, 2)}`;
}

/** "AAAAMMDD" (OFX, CNAB 150) → "AAAA-MM-DD", ou null. OFX acrescenta hora e fuso depois dos 8 dígitos. */
export function dataAAAAMMDD(texto) {
  const t = String(texto ?? '').trim().slice(0, 8);
  if (!/^\d{8}$/.test(t)) return null;
  return dataDDMMAAAA(t.slice(6, 8) + t.slice(4, 6) + t.slice(0, 4));
}

/** Campo numérico posicional com decimais implícitos: ("000000012345", 2) → 123.45. */
export function valorImplicito(texto, casas) {
  const t = String(texto ?? '').trim();
  if (!/^\d+$/.test(t)) return null;
  return Number(t) / 10 ** casas;
}

/** Recorta um campo posicional pela numeração do leiaute FEBRABAN (posições começam em 1, fim inclusivo). */
export function posicao(linha, ini, fim) {
  return linha.slice(ini - 1, fim);
}

/** Contagem de um registro de controle: só dígitos. Campo vazio é AUSÊNCIA (null), nunca 0:
 * `Number('')` dá 0, e um upload cortado logo depois de `|9999|` gravaria "declarado 0". */
export function inteiro(texto) {
  const t = String(texto ?? '').trim();
  return /^\d+$/.test(t) ? Number(t) : null;
}

/** CNPJ só com dígitos e 14 posições, ou null. Não valida o dígito verificador: o arquivo oficial já foi validado pelo órgão. */
export function cnpj(texto) {
  const t = String(texto ?? '').replace(/\D/g, '');
  return t.length === 14 ? t : null;
}

/**
 * Bytes → texto em ISO-8859-1 (cada byte vira o caractere de mesmo código), igual no Node e no navegador.
 *
 * Por que não só `TextDecoder('latin1')`: pelo padrão WHATWG, "latin1" é apelido de
 * windows-1252, e o navegador decodifica 0x80–0x9F como cp1252 (0x96 vira "–"),
 * enquanto o Node devolve U+0096 para o mesmo byte. Medido em 13/10/2026: o mesmo
 * SPED daria textos diferentes no CLI e no navegador. O Guia Prático do SPED fixa
 * ISO-8859-1, que é o que o `Buffer.toString('latin1')` do CLI sempre fez.
 *
 * A volta é exata: os 27 caracteres próprios do cp1252 (todos acima de U+00FF) só
 * aparecem no texto se vieram de um byte 0x80–0x9F, porque latin1 nunca produz
 * caractere acima de U+00FF. Decodificar byte a byte em JS daria o mesmo resultado
 * a 2,1 s por 100 MB. O `TextDecoder` nativo faz 100 MB em 33 ms se receber fatias de
 * 64 KB, e em 1,6 s se receber os 100 MB de uma vez (medido no Node 22). Por isso a
 * decodificação vai em fatias.
 */
const CP1252 = '\u20AC\u0081\u201A\u0192\u201E\u2026\u2020\u2021\u02C6\u2030\u0160\u2039\u0152\u008D\u017D\u008F'
  + '\u0090\u2018\u2019\u201C\u201D\u2022\u2013\u2014\u02DC\u2122\u0161\u203A\u0153\u009D\u017E\u0178';
const DE_CP1252 = new Map();
for (let i = 0; i < 32; i++) if (CP1252.charCodeAt(i) > 0xff) DE_CP1252.set(CP1252[i], String.fromCharCode(0x80 + i));
const RE_CP1252 = new RegExp(`[${[...DE_CP1252.keys()].join('')}]`, 'g');
const DECODIFICADOR = new TextDecoder('latin1');
export function latin1(bytes, ini = 0, fim = bytes.length) {
  let s = '';
  for (let i = ini; i < fim; i += 65536) s += DECODIFICADOR.decode(bytes.subarray(i, Math.min(i + 65536, fim)));
  return desfazerCp1252(s);
}

/** Devolve os bytes 0x80–0x9F que um decodificador cp1252 trocou pelos caracteres dele.
 * Separada para ser testável: no Node o `TextDecoder` nunca decodifica como cp1252,
 * então este caminho só roda no navegador. */
export function desfazerCp1252(s) {
  RE_CP1252.lastIndex = 0;
  return RE_CP1252.test(s) ? s.replace(RE_CP1252, (c) => DE_CP1252.get(c)) : s;
}

/** "1.234,56" → 123456 (centavos, inteiro), ou null. Mais de 2 casas decimais é null: somar
 * em ponto flutuante milhões de lançamentos erra o centavo, e arredondar esconde o valor lido. */
export function centavosBR(texto) {
  if (decimalBR(texto) === null) return null;
  const t = String(texto).trim().replace(/\./g, '');
  const neg = t.startsWith('-');
  const [i, d = ''] = (neg ? t.slice(1) : t).split(',');
  if (d.length > 2) return null;
  const v = Number(i) * 100 + Number(d.padEnd(2, '0'));
  return neg ? -v : v;
}
