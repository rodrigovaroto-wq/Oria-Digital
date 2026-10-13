// Leitor de SPED NO NAVEGADOR, para a medição de 13/10/2026: lê o arquivo em fluxo
// (File.stream), confere o 9999/9900, guarda os registros-chave da ECD na íntegra
// com o número da linha e SOMA os lançamentos (I250) por conta e mês. O arquivo
// inteiro nunca fica na memória e nunca sai da máquina; o que viaja é o resumo.

// SHA-256 incremental (FIPS 180-4): o crypto.subtle só faz o arquivo inteiro de uma
// vez, e o hash TEM de ser o do arquivo, igual ao do CLI (identidade da 0206).
class Sha256 {
  constructor() {
    this.h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
    this.w = new Uint32Array(64); this.bloco = new Uint8Array(64); this.nb = 0; this.len = 0;
    this.K = new Uint32Array([0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2]);
  }
  comprimir(b, o) {
    const w = this.w, K = this.K, h = this.h;
    for (let t = 0; t < 16; t++) w[t] = (b[o + 4 * t] << 24) | (b[o + 4 * t + 1] << 16) | (b[o + 4 * t + 2] << 8) | b[o + 4 * t + 3];
    for (let t = 16; t < 64; t++) {
      const x = w[t - 15], y = w[t - 2];
      w[t] = (((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3)) + w[t - 16] + w[t - 7] + (((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10));
    }
    let a = h[0], c1 = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (let t = 0; t < 64; t++) {
      const t1 = (hh + (((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7))) + ((e & f) ^ (~e & g)) + K[t] + w[t]) | 0;
      const t2 = ((((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10))) + ((a & c1) ^ (a & c) ^ (c1 & c))) | 0;
      hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = c1; c1 = a; a = (t1 + t2) | 0;
    }
    h[0] += a; h[1] += c1; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }
  update(dados) {
    let i = 0; const n = dados.length; this.len += n;
    if (this.nb) { while (this.nb < 64 && i < n) this.bloco[this.nb++] = dados[i++]; if (this.nb === 64) { this.comprimir(this.bloco, 0); this.nb = 0; } }
    for (; i + 64 <= n; i += 64) this.comprimir(dados, i);
    while (i < n) this.bloco[this.nb++] = dados[i++];
  }
  hex() {
    const bits = this.len * 8, cauda = new Uint8Array(((this.nb + 9 + 63) >> 6) << 6);
    cauda.set(this.bloco.subarray(0, this.nb)); cauda[this.nb] = 0x80;
    const dv = new DataView(cauda.buffer); dv.setUint32(cauda.length - 8, Math.floor(bits / 2 ** 32)); dv.setUint32(cauda.length - 4, bits >>> 0);
    for (let o = 0; o < cauda.length; o += 64) this.comprimir(cauda, o);
    return Array.from(this.h, x => x.toString(16).padStart(8, '0')).join('');
  }
}

const GUARDAR = new Set(['0000', 'I010', 'I050', 'I051', 'I150', 'I155', 'J005', 'J100', 'J150', 'J900', '9900', '9999']);
const centavos = (s) => { const [i, d = ''] = s.split(','); return Number(i) * 100 + Number((d + '00').slice(0, 2)); };

async function lerSped(file) {
  const t0 = performance.now();
  const sha = new Sha256(), dec = new TextDecoder('latin1'), leitor = file.stream().getReader();
  let resto = '', linha = 0, mes = null, decl9999 = null;
  const contagem = {}, decl9900 = {}, guardadas = [], agregado = new Map();
  const processar = (l) => {
    if (l.endsWith('\r')) l = l.slice(0, -1);
    if (!l) return;
    linha++;
    const reg = l.slice(1, 5);
    contagem[reg] = (contagem[reg] || 0) + 1;
    if (GUARDAR.has(reg)) {
      guardadas.push([linha, l]);
      if (reg === '9999') decl9999 = Number(l.split('|')[2]);
      else if (reg === '9900') { const c = l.split('|'); decl9900[c[2]] = Number(c[3]); }
    } else if (reg === 'I200') {
      mes = l.split('|')[3].slice(2, 4);
    } else if (reg === 'I250') {
      const c = l.split('|'), k = c[2] + '|' + mes;
      let a = agregado.get(k); if (!a) agregado.set(k, a = [0, 0, 0, linha]);
      const v = centavos(c[4]);
      if (c[5] === 'D') a[0] += v; else a[1] += v;
      a[2]++;
    }
  };
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    sha.update(value);
    const partes = (resto + dec.decode(value, { stream: true })).split('\n');
    resto = partes.pop();
    for (const p of partes) processar(p);
  }
  processar(resto + dec.decode());
  const resumo = {
    hash_sha256: sha.hex(), bytes: file.size, linhas: linha, controle_declarado: decl9999,
    bate9999: decl9999 === linha,
    bate9900: Object.entries(decl9900).every(([r, q]) => contagem[r] === q),
    contagem, guardadas,
    i250_por_conta_mes: Array.from(agregado, ([k, [deb, cred, n, primeira]]) => { const [conta, mes] = k.split('|'); return { conta, mes, deb, cred, n, primeira }; }),
  };
  const json = JSON.stringify(resumo);
  const gz = await new Response(new Blob([json]).stream().pipeThrough(new CompressionStream('gzip'))).arrayBuffer();
  return { ms: Math.round(performance.now() - t0), resumo_bytes: json.length, resumo_gzip_bytes: gz.byteLength, resumo };
}
window.lerSped = lerSped;
