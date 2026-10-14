// Baixa a fatia [ini, fim] em pedaços de 4 MB (o binário viaja do processo
// principal ao runner como array de números: 4 MB por vez mantém isso pequeno)
// e devolve só as linhas que COMEÇAM dentro dela.
const { url, ini, fim, total } = $json;
const PEDACO = 4 * 1048576, EXTRA = 65536;
const de = Math.max(0, ini - 1), ate = Math.min(fim + EXTRA, total - 1);
const partes = [];
for (let p = de; p <= ate; p += PEDACO) {
  const r = await this.helpers.httpRequest({ url, headers: { Range: `bytes=${p}-${Math.min(p + PEDACO - 1, ate)}` }, returnFullResponse: true, encoding: 'arraybuffer', json: false });
  partes.push(Buffer.isBuffer(r.body) ? r.body : Buffer.from(r.body));
}
const b = Buffer.concat(partes);
// começo: se ini > 0, a linha só é desta fatia se o byte anterior (b[0]) for \n
const s = ini === 0 ? 0 : b.indexOf(10) + 1;
// fim: até o primeiro \n a partir de fim (posição relativa fim - de)
let e = b.indexOf(10, fim - de);
e = e === -1 ? b.length : e + 1;
const texto = s >= e ? '' : b.toString('latin1', s, e);
return { json: { ini, texto } };
