// A ASSINATURA DO ENVIO — o token que o portal entrega e o BANCO confere antes de gravar.
//
// O DEFEITO. O Form de ingestão do n8n é PÚBLICO (formTrigger, sem autenticação) e a URL é a
// mesma para todos os mandatos. O portal confere o papel do usuário (Fase 5, migration 0216) em
// `/api/intake` e `/api/intake/destino`, mas isso só protege quem passa pelo portal: um Analista
// alocado só em "Beta" pega a URL e faz POST direto com `Mandato=Alfa`, e o n8n grava no Alfa pela
// conexão de serviço (BYPASSRLS). A permissão estava no portal; o que grava estava no n8n.
//
// O DESENHO. O portal, depois de `conferirEnvioAoMandato`, assina
//     HMAC-SHA256(segredo, mandato_normalizado | exp | usuario_id)
// e manda o token junto com o lote, como um campo do Form. O nó `Conferir Envio` do n8n chama
// `fn_conferir_envio(token, mandato)` (migration 0217), que recalcula com o segredo do Vault do
// banco ANTES do `Upsert Caso` (que já é uma gravação: cria o mandato) e recusa se não bater.
//   token = "v1.<exp>.<usuario_id>.<hmac hex>"       exp = segundos desde 1970 (UTC)
// O mandato NÃO vai no token: vem do campo Mandato do próprio POST e entra na conta de quem
// confere. Trocar o mandato depois de assinado muda a mensagem e, portanto, a assinatura.
//
// O QUE ESTA LIB É HOJE (30/10/2026). A conferência MUDOU DE LUGAR: era um nó Code que lia o
// segredo de `$env`/`$vars`, e em produção nenhum dos dois existe (a licença do n8n não tem
// Variables e o PikaPods não cria variável de ambiente) — o n8n publicado recusava TODO envio.
// Ela agora é SQL, e esta lib deixou de ser embutida em nó nenhum. Duas coisas dela continuam
// em uso de produção: `normalizarMandato` e `mensagemAssinada`, que o portal importa para ASSINAR.
// `verificarEnvio`/`veredictoDoEnvio` (e `hmacSha256Hex`, `iguaisEmTempoConstante`, `utf8Bytes`,
// que eles usam) ficam como a implementação de REFERÊNCIA do lado que confere — o único chamador
// é `portal/scripts/verificar-envio-oficial.mts` (seção 8, portão do CI), que prova que o token
// que o portal gera (node:crypto) é aceito, e o vetor fixo. Quem tirar daqui tem de levar aquela
// seção junto. Não rodam mais em produção: o que confere em produção é `fn_conferir_envio`.
//
// JS PURO (sem `node:crypto`) é herança do tempo em que isto rodava no Code node do n8n, que NÃO
// expõe `crypto` (medido em 2026-07-31: o `hash` de `Preparar Conteudo` vinha null — ver
// lib/hash.mjs). Fica assim porque trocar a implementação de referência não compra nada.
import { sha256Hex } from './hash.mjs';

/**
 * O mandato como o índice `caso_nome_unico` o vê: `lower(btrim(nome))`. `btrim` tira só ESPAÇO
 * (não tab nem quebra de linha — `String.trim` tiraria), então a regex é a mesma: normalização
 * mais larga que a do banco deixaria "beta\t" assinar por "beta" e cair, no `fn_upsert_caso`, num
 * mandato diferente do assinado.
 */
export function normalizarMandato(nome) {
  const t = String(nome == null ? '' : nome);
  // Sem regex: `/^ +| +$/g` tem desempenho super-linear em texto longo de espaços (Sonar S8786).
  let ini = 0;
  let fim = t.length;
  while (ini < fim && t[ini] === ' ') ini++;
  while (fim > ini && t[fim - 1] === ' ') fim--;
  return t.slice(ini, fim).toLowerCase();
}

/** A mensagem que o HMAC cobre. O portal e o n8n a montam por ESTA função. */
export function mensagemAssinada(mandato, exp, usuarioId) {
  return normalizarMandato(mandato) + '|' + String(exp) + '|' + String(usuarioId);
}

/**
 * A mensagem do token v2 (roteado por caso_id): `v2|<caso>|<exp>|<usuario>`, tudo em minúsculas.
 * A etiqueta `v2|` é OBRIGATÓRIA e é o que separa os dois domínios de assinatura: a mensagem v1 é
 * `normalizar(nome)|exp|usuario`, e o nome de um mandato é texto livre. Sem a etiqueta, um Analista
 * cria um mandato cujo NOME é o uuid de outro caso, pede um token v1 dele e o reescreve como v2 do
 * outro caso com o mesmo hmac (`<uuid>|exp|usuario` seria idêntico nos dois formatos). A etiqueta
 * desloca a colisão para um mandato chamado literalmente `v2|<uuid>` (o `|` no nome): quem criar o
 * mandato precisa recusar `|` no nome, ou a colisão volta. Esta lib não vê o nome de ninguém.
 * O portal e o banco (fn_conferir_envio) montam a mensagem por ESTE contrato.
 */
export function mensagemAssinadaV2(casoId, exp, usuarioId) {
  return 'v2|' + String(casoId).toLowerCase() + '|' + String(exp) + '|' + String(usuarioId).toLowerCase();
}

/** UTF-8 sem `TextEncoder` (que o sandbox também pode não expor). */
export function utf8Bytes(texto) {
  const s = String(texto);
  const out = [];
  for (let i = 0; i < s.length; i++) {
    // `codePointAt` já junta o par substituto; surrogato solitário devolve o próprio valor (3 bytes), como antes.
    const c = s.codePointAt(i);
    if (c > 0xffff) i++;
    if (c < 0x80) out.push(c);
    else if (c < 0x800) out.push(0xc0 | (c >> 6), 0x80 | (c & 63));
    else if (c < 0x10000) out.push(0xe0 | (c >> 12), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
    else out.push(0xf0 | (c >> 18), 0x80 | ((c >> 12) & 63), 0x80 | ((c >> 6) & 63), 0x80 | (c & 63));
  }
  return Uint8Array.from(out);
}

/** HMAC-SHA256 (RFC 2104) sobre o `sha256Hex` de JS puro. Devolve hexadecimal minúsculo. */
export function hmacSha256Hex(chave, mensagem) {
  const BLOCO = 64;
  const doHex = (h) => Uint8Array.from(h.match(/../g).map((x) => Number.parseInt(x, 16)));
  let k = utf8Bytes(chave);
  if (k.length > BLOCO) k = doHex(sha256Hex(k));
  const ipad = new Uint8Array(BLOCO).fill(0x36);
  const opad = new Uint8Array(BLOCO).fill(0x5c);
  for (let i = 0; i < k.length; i++) { ipad[i] ^= k[i]; opad[i] ^= k[i]; }
  const m = utf8Bytes(mensagem);
  const interno = new Uint8Array(BLOCO + m.length);
  interno.set(ipad, 0); interno.set(m, BLOCO);
  const ih = doHex(sha256Hex(interno));
  const externo = new Uint8Array(BLOCO + ih.length);
  externo.set(opad, 0); externo.set(ih, BLOCO);
  return sha256Hex(externo);
}

/**
 * Comparação em tempo constante: percorre SEMPRE o comprimento do maior e acumula a diferença com
 * OR, sem `return` antecipado — o tempo não revela em qual posição a assinatura divergiu. O
 * comprimento diferente também reprova, mas só no fim.
 */
export function iguaisEmTempoConstante(a, b) {
  const x = String(a == null ? '' : a);
  const y = String(b == null ? '' : b);
  let diff = x.length ^ y.length;
  const n = Math.max(x.length, y.length);
  for (let i = 0; i < n; i++) diff |= (x.codePointAt(i) || 0) ^ (y.codePointAt(i) || 0);
  return diff === 0;
}

/**
 * Confere o token, v1 ou v2. `{ ok: true, usuario_id, caso_id }` (caso_id null no v1, que é por
 * mandato) ou `{ ok: false, motivo }`, motivo em `sem_segredo` | `sem_token` | `malformado` |
 * `assinatura` | `expirado`.
 *   v1 = "v1.<exp>.<usuario_id>.<hmac>"            assina normalizar(mandato)|exp|usuario
 *   v2 = "v2.<exp>.<usuario>.<caso>.<hmac>"        assina v2|caso|exp|usuario (mandato IGNORADO:
 *        o caso vem no token; os dois uuids em minúsculas — maiúscula é `malformado`, não normalizada)
 * Mandato trocado (v1) cai em `assinatura` (ele está dentro da mensagem assinada) — não há como
 * distinguir "mandato trocado" de "assinatura adulterada" sem guardar o mandato no token, e guardá-lo
 * ali só entregaria a quem adulterar o que tentar. A assinatura é conferida ANTES do `exp`, para a
 * recusa por expiração só existir para quem provou ter o segredo.
 */
const UUID_MIN = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/;

export function verificarEnvio({ token, mandato, segredo, agoraMs }) {
  if (typeof segredo !== 'string' || segredo.trim() === '') return { ok: false, motivo: 'sem_segredo' };
  if (typeof token !== 'string' || token.trim() === '') return { ok: false, motivo: 'sem_token' };
  const partes = token.trim().split('.');
  let exp; let usuario; let caso = null; let sig; let mensagem;
  if (partes.length === 4 && partes[0] === 'v1') {
    [, exp, usuario, sig] = partes;
    if (!/^\d{1,12}$/.test(exp) || !/^[0-9a-fA-F-]{8,64}$/.test(usuario) || !/^[0-9a-f]{64}$/.test(sig)) {
      return { ok: false, motivo: 'malformado' };
    }
    mensagem = mensagemAssinada(mandato, exp, usuario);
  } else if (partes.length === 5 && partes[0] === 'v2') {
    [, exp, usuario, caso, sig] = partes;
    if (!/^\d{1,12}$/.test(exp) || !UUID_MIN.test(usuario) || !UUID_MIN.test(caso) || !/^[0-9a-f]{64}$/.test(sig)) {
      return { ok: false, motivo: 'malformado' };
    }
    mensagem = mensagemAssinadaV2(caso, exp, usuario);
  } else {
    return { ok: false, motivo: 'malformado' };
  }
  if (!iguaisEmTempoConstante(hmacSha256Hex(segredo, mensagem), sig)) return { ok: false, motivo: 'assinatura' };
  if (!(Number(exp) * 1000 > agoraMs)) return { ok: false, motivo: 'expirado' };
  return { ok: true, usuario_id: usuario, caso_id: caso };
}

/**
 * O que o `Conferir Envio` (hoje `fn_conferir_envio`) decide, com a mensagem que o portal vai ler (a recusa entra no
 * `Registrar Recusa` -> `Abortar Lote`, que grava em `execucao_falha`). A falta de segredo no banco
 * tem mensagem PRÓPRIA: é erro de configuração do dono, não de quem enviou.
 */
export function veredictoDoEnvio({ token, mandato, segredo, agoraMs }) {
  const v = verificarEnvio({ token, mandato, segredo, agoraMs });
  if (v.ok) return { autorizado: true, motivo: null, mensagem: null, usuario_id: v.usuario_id, caso_id: v.caso_id };
  const mensagem = v.motivo === 'sem_segredo'
    ? 'Envio recusado: o banco não tem o segredo de autorização do envio no Vault. '
      + 'Nada foi gravado. Peça ao responsável pelo banco para configurá-lo.'
    : v.motivo === 'expirado'
      ? 'Envio sem autorização válida: o token do envio expirou. Nada foi gravado. Reenvie pelo portal.'
      : 'Envio sem autorização válida. Nada foi gravado. Envie pelo portal, com o login de quem tem acesso ao mandato.';
  return { autorizado: false, motivo: v.motivo, mensagem, usuario_id: null, caso_id: null };
}
