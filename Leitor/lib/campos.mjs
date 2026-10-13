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
