import http from 'node:http'; import fs from 'node:fs';
const dir = process.argv[2];
http.createServer((q, s) => {
  const f = dir + '/' + decodeURIComponent(q.url.split('?')[0].slice(1));
  let st; try { st = fs.statSync(f); } catch { s.writeHead(404); return s.end(); }
  const m = /bytes=(\d+)-(\d*)/.exec(q.headers.range || '');
  if (!m) { s.writeHead(200, { 'content-length': st.size }); return fs.createReadStream(f).pipe(s); }
  const a = +m[1], b = Math.min(m[2] ? +m[2] : st.size - 1, st.size - 1);
  s.writeHead(206, { 'content-range': `bytes ${a}-${b}/${st.size}`, 'content-length': b - a + 1 });
  fs.createReadStream(f, { start: a, end: b }).pipe(s);
}).listen(8099, '127.0.0.1');
