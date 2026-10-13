// Envelope de um SPED lido DENTRO do nó Code: varre os bytes do Buffer sem nunca
// virar o arquivo inteiro em string (o V8 recusa string acima de ~512 MB).
const t0 = Date.now();
const buf = await this.helpers.getBinaryDataBuffer($itemIndex, 'data');
const t1 = Date.now();
let linhas = 0, ini = 0, decl9999 = null;
const regs = {}, decl9900 = {};
const n = buf.length;
while (ini < n) {
  let fim = buf.indexOf(10, ini);
  if (fim === -1) fim = n;
  let f = fim; if (f > ini && buf[f - 1] === 13) f--;
  if (f > ini) {
    linhas++;
    // o registro: entre o 1º e o 2º pipe, 4 caracteres
    const reg = buf.latin1Slice ? buf.latin1Slice(ini + 1, ini + 5) : buf.toString('latin1', ini + 1, ini + 5);
    regs[reg] = (regs[reg] || 0) + 1;
    if (reg === '9900' || reg === '9999') {
      const campos = buf.toString('latin1', ini, f).split('|');
      if (reg === '9999') decl9999 = Number(campos[2]);
      else decl9900[campos[2]] = Number(campos[3]);
    }
  }
  ini = fim + 1;
}
let mem = null;
try { mem = Math.round(process.memoryUsage().rss / 1048576); } catch (e) { mem = 'sem process: ' + e.message; }
return { json: {
  bytes: n, linhas, decl9999, bate9999: decl9999 === linhas,
  bate9900: Object.entries(decl9900).every(([r, q]) => regs[r] === q),
  ms_buffer: t1 - t0, ms_varredura: Date.now() - t1, rss_runner_mb: mem,
} };
