// SHA-256 INCREMENTAL em JS puro (FIPS 180-4) — o mesmo no CLI e no navegador.
//
// POR QUE EXISTE (sessão 108, 13/10/2026): o leitor passou a rodar no navegador do
// analista, que lê o arquivo em fluxo e nunca o tem inteiro na memória. O
// `crypto.subtle.digest` do navegador só faz o hash de um buffer inteiro, e o
// `node:crypto` não existe no navegador. O hash é a IDENTIDADE do arquivo na `0206`
// (idempotência e versão vigente): se o navegador e o CLI calculassem de jeitos
// diferentes, o mesmo SPED enviado pelos dois caminhos viraria dois arquivos.
//
// Medido: numa ECD sintética de 10.000.180 linhas (929 MB), este hash no Chromium
// saiu idêntico ao `sha256sum`, com a leitura inteira em 22,9 s
// (`Leitor/medicao-n8n/README.md`). O teste compara com `node:crypto` em cortes de
// fatia que atravessam a fronteira de bloco de 64 bytes.
//
// `N8N/lib/hash.mjs` é o hash de um buffer inteiro, auto-contido para entrar num nó
// Code por `toString()`. Este é outro contrato (incremental), e não o substitui.

const K = new Uint32Array([
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
]);

export class Sha256 {
  constructor() {
    this.h = new Uint32Array([0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19]);
    this.w = new Uint32Array(64);
    this.bloco = new Uint8Array(64);
    this.nb = 0;      // bytes pendentes em `bloco`
    this.len = 0;     // total de bytes (Number é exato até 2^53: 8 PB)
    this.fechado = false;
  }

  comprimir(b, o) {
    const w = this.w, h = this.h;
    for (let t = 0; t < 16; t++) w[t] = (b[o + 4 * t] << 24) | (b[o + 4 * t + 1] << 16) | (b[o + 4 * t + 2] << 8) | b[o + 4 * t + 3];
    for (let t = 16; t < 64; t++) {
      const x = w[t - 15], y = w[t - 2];
      w[t] = (((x >>> 7) | (x << 25)) ^ ((x >>> 18) | (x << 14)) ^ (x >>> 3))
        + w[t - 16] + w[t - 7]
        + (((y >>> 17) | (y << 15)) ^ ((y >>> 19) | (y << 13)) ^ (y >>> 10));
    }
    let a = h[0], b1 = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (let t = 0; t < 64; t++) {
      const t1 = (hh + (((e >>> 6) | (e << 26)) ^ ((e >>> 11) | (e << 21)) ^ ((e >>> 25) | (e << 7)))
        + ((e & f) ^ (~e & g)) + K[t] + w[t]) | 0;
      const t2 = ((((a >>> 2) | (a << 30)) ^ ((a >>> 13) | (a << 19)) ^ ((a >>> 22) | (a << 10)))
        + ((a & b1) ^ (a & c) ^ (b1 & c))) | 0;
      hh = g; g = f; f = e; e = (d + t1) | 0; d = c; c = b1; b1 = a; a = (t1 + t2) | 0;
    }
    h[0] += a; h[1] += b1; h[2] += c; h[3] += d; h[4] += e; h[5] += f; h[6] += g; h[7] += hh;
  }

  /** Acrescenta bytes (Uint8Array ou Buffer). Pode ser chamado com qualquer fatiamento. */
  update(dados) {
    if (this.fechado) throw new Error('Sha256: update depois de hex()');
    let i = 0;
    const n = dados.length;
    this.len += n;
    if (this.nb) {
      while (this.nb < 64 && i < n) this.bloco[this.nb++] = dados[i++];
      if (this.nb === 64) { this.comprimir(this.bloco, 0); this.nb = 0; }
    }
    for (; i + 64 <= n; i += 64) this.comprimir(dados, i);
    while (i < n) this.bloco[this.nb++] = dados[i++];
    return this;
  }

  /** O hash em hexadecimal minúsculo. Fecha o objeto. */
  hex() {
    this.fechado = true;
    const cauda = new Uint8Array(((this.nb + 9 + 63) >> 6) << 6);
    cauda.set(this.bloco.subarray(0, this.nb));
    cauda[this.nb] = 0x80;
    const dv = new DataView(cauda.buffer);
    // Comprimento em BITS em 64 bits big-endian, alto e baixo separados: `len * 8`
    // passa de 32 bits a partir de 512 MB, e um SPED de 10M de linhas tem 929 MB.
    dv.setUint32(cauda.length - 8, Math.floor(this.len / 0x20000000));
    dv.setUint32(cauda.length - 4, (this.len * 8) >>> 0);
    for (let o = 0; o < cauda.length; o += 64) this.comprimir(cauda, o);
    return Array.from(this.h, (x) => x.toString(16).padStart(8, '0')).join('');
  }
}

/** Hash de um buffer inteiro. */
export function sha256Hex(bytes) {
  return new Sha256().update(bytes).hex();
}
