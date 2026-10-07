// SHA-256 do conteúdo do arquivo — em JS puro, sem depender do que o sandbox expõe.
//
// POR QUE ESTE ARQUIVO EXISTE (medido em produção, 2026-07-31): a primeira
// implementação usava `crypto.subtle.digest`, global no Node 18+, com abstenção
// (`hash = null`) caso o sandbox não o expusesse. O dono conferiu a saída de
// `Preparar Conteudo` no n8n dele e o campo veio **null** — o Code node do n8n
// não expõe `crypto` (nem `crypto.subtle`) por padrão no runner de tarefas, e
// `require('crypto')` depende de `NODE_FUNCTION_ALLOW_BUILTIN`, que é
// configuração de servidor e não está ao alcance deste repositório.
//
// A abstenção funcionou como projetada — não inventou hash fraco — mas o efeito
// prático é que a idempotência da `0026` seguia ADORMECIDA: `p_hash is not null`
// nunca era verdade, e todo reenvio do mesmo arquivo continuava virando
// documento novo em vez de versão nova (o "15 colunas para 5 empresas" do teste
// v27). Um caminho que só funciona quando o ambiente coopera, num ambiente que
// não coopera, é o mesmo que não existir.
//
// Esta implementação depende só de `Uint8Array`/`DataView`/aritmética de 32
// bits — não há sandbox de JS onde ela não rode. É o SHA-256 da FIPS 180-4, o
// MESMO algoritmo de antes: a força não foi trocada por conveniência, e é isso
// que importa aqui, porque o cabeçalho da `0026` chama colisão de hash de "o
// erro mais caro possível" (fundiria documentos DIFERENTES numa versão só).
// O teste compara byte a byte com `node:crypto` em 9 comprimentos, incluindo as
// fronteiras de bloco (55/56/63/64/65) onde erro de padding se esconde.
//
// Custo: ~10-20 MB/s em JS. Um PDF de 5 MB leva algumas centenas de ms, uma vez
// por documento, contra uma chamada de IA que leva dezenas de segundos. Quando
// `crypto.subtle` existe (é o caso do Node local e das suítes), o nó usa o
// caminho nativo por ser mais rápido; os dois produzem o mesmo hexadecimal, e o
// teste exercita os dois.
//
// AUTO-CONTIDA de propósito: o gerador embute o `toString()` desta função no
// `jsCode` do nó (Code node não importa arquivo). Nada de referência a nada
// fora do próprio corpo — inclusive as constantes, que ficam DENTRO.
export function sha256Hex(bytes) {
  const K = [
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];
  const rotr = (x, n) => ((x >>> n) | (x << (32 - n))) >>> 0;

  const src = bytes instanceof Uint8Array ? bytes : new Uint8Array(bytes);
  const len = src.length;
  // Padding da FIPS 180-4: byte 0x80, zeros, e o COMPRIMENTO EM BITS em 64 bits
  // big-endian. O total precisa ser múltiplo de 64 e caber os 9 bytes mínimos —
  // por isso `+8` e não `+9` na divisão (o `+1` do bloco extra já cobre o 0x80).
  const total = (Math.floor((len + 8) / 64) + 1) * 64;
  const m = new Uint8Array(total);
  m.set(src);
  m[len] = 0x80;
  const dv = new DataView(m.buffer);
  // Alto e baixo separados porque `len * 8` estoura 32 bits a partir de 512 MB e
  // `<<` em JS opera em 32 bits: 2^32 / 8 = 536870912.
  dv.setUint32(total - 8, Math.floor(len / 536870912));
  dv.setUint32(total - 4, (len << 3) >>> 0);

  const h = [0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  const w = new Uint32Array(64);
  for (let off = 0; off < total; off += 64) {
    for (let t = 0; t < 16; t++) w[t] = dv.getUint32(off + t * 4);
    for (let t = 16; t < 64; t++) {
      const a = w[t - 15];
      const b = w[t - 2];
      const s0 = (rotr(a, 7) ^ rotr(a, 18) ^ (a >>> 3)) >>> 0;
      const s1 = (rotr(b, 17) ^ rotr(b, 19) ^ (b >>> 10)) >>> 0;
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, hh] = h;
    for (let t = 0; t < 64; t++) {
      const S1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch = ((e & f) ^ (~e & g)) >>> 0;
      const t1 = (hh + S1 + ch + K[t] + w[t]) >>> 0;
      const S0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const t2 = (S0 + maj) >>> 0;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) >>> 0;
    }
    const add = [a, b, c, d, e, f, g, hh];
    for (let i = 0; i < 8; i++) h[i] = (h[i] + add[i]) >>> 0;
  }
  let hex = '';
  for (let i = 0; i < 8; i++) hex += h[i].toString(16).padStart(8, '0');
  return hex;
}

// A CHAVE DO ORIGINAL NO STORAGE — e a mesma string vai para `arquivo_ref`.
//
// MEDIDO EM PRODUCAO (07/10/2026, workflow descartavel, requisicao identica a do
// `Upload Storage`): o Storage recusa chave com caractere nao-ASCII mesmo com
// encodeURIComponent — `sonda teste ç.pdf` deu HTTP 400 InvalidKey; `sonda
// teste.pdf` deu 200 (193 bytes, application/pdf). Nome brasileiro tem acento
// ("BALANÇO ..."), entao a chave por NOME falharia justamente nos documentos reais.
//
// Chave = caso_id/<sha256><.ext>: ASCII por construcao, e e a identidade da 0026
// (mesmo caso + mesmo hash = mesmo documento). Com chave por NOME, um arquivo
// DIFERENTE de mesmo nome sobrescreveria o original anterior via x-upsert
// (perda de dado); por hash, o upsert so reescreve bytes identicos. A extensao
// (minuscula, so se for [a-z0-9]{1,8}) existe para o objeto sair com o mimetype
// certo ao ser baixado.
//
// SEM HASH (so acontece se o SHA-256 nativo E o de JS puro falharem — nunca
// medido): cai no nome saneado (sem acento, so [A-Za-z0-9._-]). Ai a chave volta a
// ser por nome e um arquivo diferente de mesmo nome sobrescreve o anterior; e a
// unica troca que ainda guarda ALGUM original. Aceito por ser inalcancavel hoje.
export function chaveDoOriginal(casoId, hash, nome) {
  const n = String(nome == null ? '' : nome);
  const m = /\.([A-Za-z0-9]{1,8})$/.exec(n);
  const ext = m ? '.' + m[1].toLowerCase() : '';
  if (typeof hash === 'string' && /^[0-9a-f]{64}$/.test(hash)) return casoId + '/' + hash + ext;
  const base = n.normalize('NFD').replace(/[\u0300-\u036f]/g, '')
    .replace(/[^A-Za-z0-9._-]+/g, '_').replace(/^[_.]+|_+$/g, '').slice(0, 120);
  return casoId + '/' + (base || 'sem_nome');
}
