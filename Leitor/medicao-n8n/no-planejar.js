// Planeja as fatias: só o tamanho do arquivo (Range 0-0) e os intervalos de bytes.
const url = 'http://127.0.0.1:8099/' + $input.first().json.query.arq;
const FATIA = Number($input.first().json.query.mb || 32) * 1048576;
const r = await this.helpers.httpRequest({ url, headers: { Range: 'bytes=0-0' }, returnFullResponse: true, encoding: 'text', json: false });
const total = Number(r.headers['content-range'].split('/')[1]);
const itens = [];
for (let ini = 0; ini < total; ini += FATIA) itens.push({ json: { url, ini, fim: Math.min(ini + FATIA, total) - 1, total } });
return itens;
