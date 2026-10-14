// Envelope de um SPED lido no nó Code SEM pegar o binário inteiro: baixa o arquivo
// em fatias por Range HTTP, como bytes, e decodifica cada fatia em latin1.
// `?mb=` é o tamanho da fatia. Acima de ~4 MB o custo não cai (medido: 10M linhas,
// 4 MB = 114 s, 8 MB = 120 s) e o pico sobe, porque cada fatia viaja do processo
// principal ao runner como array de números.
const url = 'http://127.0.0.1:8099/' + $json.query.arq;
const FATIA = Number($json.query.mb || 4) * 1048576;
const t0 = Date.now();
// O 9999 declarado é atribuído dentro de `linha()`; o analisador estático não vê isso e
// acusa a comparação de "sempre falsa" (Sonar S3403). Por isso `Object.is`, que para
// números é o mesmo que `===`.
const ctrl = { decl9999: null };
let pos = 0, linhas = 0, resto = '', fatias = 0, total = Infinity, amostra = null;
const regs = {};
const linha = (l) => {
  if (l.endsWith('\r')) l = l.slice(0, -1);
  if (!l) return;
  linhas++;
  const reg = l.slice(1, 5);
  regs[reg] = (regs[reg] || 0) + 1;
  if (reg === '9999') ctrl.decl9999 = Number(l.split('|')[2]);
};
while (pos < total) {
  const r = await this.helpers.httpRequest({ url, headers: { Range: `bytes=${pos}-${pos + FATIA - 1}` }, returnFullResponse: true, encoding: 'arraybuffer', json: false });
  fatias++;
  total = Number(r.headers['content-range'].split('/')[1]);
  // No runner o corpo chega como {type:'Buffer', data:[...]}, não como Buffer.
  const corpo = Buffer.isBuffer(r.body) ? r.body : Buffer.from(r.body);
  const txt = resto + corpo.toString('latin1');
  if (pos === 0) amostra = txt.split('\n').find(x => x.startsWith('|I250|'));
  const partes = txt.split('\n');
  resto = partes.pop();
  for (const p of partes) linha(p);
  pos += FATIA;
}
if (resto) linha(resto);
return { json: { linhas, decl9999: ctrl.decl9999, bate9999: Object.is(ctrl.decl9999, linhas), fatias, amostra, ms: Date.now() - t0 } };
