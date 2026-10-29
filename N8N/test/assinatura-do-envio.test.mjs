// A SUÍTE DA ASSINATURA DO ENVIO — o Form público do n8n só grava para quem o portal autorizou.
//
// O DEFEITO QUE ELA TRAVA (revisão do PR #265): o `formTrigger` não tem autenticação e a URL é a
// mesma para todo mandato. O portal confere o papel, mas o POST direto ao Form contorna o portal,
// e o n8n grava pela conexão de serviço (BYPASSRLS). O token HMAC por mandato fecha isso, e cada
// teste abaixo é uma forma de ele deixar de fechar SEM erro nenhum:
//   - exp não conferido  -> um token roubado vale para sempre;
//   - mandato fora da mensagem assinada -> o token do "Beta" grava no "Alfa" (o defeito inteiro);
//   - segredo ausente aceito -> a configuração esquecida abre o Form em vez de fechá-lo;
//   - o nó conferir DEPOIS do `Upsert Caso` -> o mandato já foi criado quando a recusa chega.
//
// DUAS IMPLEMENTAÇÕES DO MESMO HMAC. Os tokens aqui são assinados com `node:crypto` (o que o
// portal usa) e conferidos pelo JS puro (o que o Code node do n8n roda, porque ele não expõe
// `crypto`). O nó é executado a partir do `jsCode` COMMITADO, não da lib: o que roda em produção.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';

import {
  normalizarMandato, mensagemAssinada, hmacSha256Hex, iguaisEmTempoConstante, verificarEnvio, veredictoDoEnvio,
} from '../lib/assinatura-do-envio.mjs';

const SEGREDO = 's3gredo-de-teste-do-n8n';
const USUARIO = '3f1c9a52-7b0e-4d34-9a5e-0c2b1d6e8f10';
const agora = () => Date.now();

// O que o PORTAL faz, com node:crypto — escrito aqui à mão, de propósito, e não importado da lib.
function tokenDoPortal({ mandato, usuario = USUARIO, exp, segredo = SEGREDO }) {
  const sig = createHmac('sha256', segredo).update(`${normalizarMandato(mandato)}|${exp}|${usuario}`, 'utf8').digest('hex');
  return `v1.${exp}.${usuario}.${sig}`;
}
const expEm = (segundos) => Math.floor(agora() / 1000) + segundos;

// --- o HMAC em si ------------------------------------------------------------
test('HMAC de JS puro = node:crypto: RFC 4231 caso 1, chave de bloco+ e texto com acento/emoji', () => {
  // RFC 4231 §4.2 (chave 0x0b x20, "Hi There"); 0x0b é ASCII, então a chave-string é fiel.
  assert.equal(hmacSha256Hex('\x0b'.repeat(20), 'Hi There'),
    'b0344c61d8db38535ca8afceaf0bf12b881dc200c9833da726e9376c2e32cff7');
  // RFC 4231 §4.3 ("Jefe")
  assert.equal(hmacSha256Hex('Jefe', 'what do ya want for nothing?'),
    '5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843');
  for (const [k, m] of [
    ['a'.repeat(65), 'chave maior que o bloco de 64 bytes é hasheada primeiro'],
    ['a'.repeat(200), 'm'.repeat(1000)],
    ['segredo', 'balanço|1|Ç ã é 😀 mandato'],
    ['çãõ😀'.repeat(30), ''],
  ]) {
    assert.equal(hmacSha256Hex(k, m), createHmac('sha256', k).update(m, 'utf8').digest('hex'), `k=${k.slice(0, 12)}`);
  }
});

// --- a decisão ---------------------------------------------------------------
test('token válido do portal é aceito, e devolve o usuário que o portal assinou', () => {
  const token = tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800) });
  const v = verificarEnvio({ token, mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() });
  assert.deepEqual(v, { ok: true, usuario_id: USUARIO });
});

test('a normalização é a do índice caso_nome_unico: caixa e espaço nas pontas valem o mesmo mandato', () => {
  const token = tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800) });
  for (const m of ['alfa', '  ALFA ', 'AlFa']) {
    assert.equal(verificarEnvio({ token, mandato: m, segredo: SEGREDO, agoraMs: agora() }).ok, true, JSON.stringify(m));
  }
  // btrim tira só ESPAÇO: tab/quebra de linha ficam no nome, e "alfa\t" é OUTRO mandato para o banco.
  for (const m of ['alfa\t', 'alfa\n', 'alfa x', 'alf']) {
    assert.equal(verificarEnvio({ token, mandato: m, segredo: SEGREDO, agoraMs: agora() }).ok, false, JSON.stringify(m));
  }
});

test('token EXPIRADO é recusado, com o motivo certo (e só depois de a assinatura provar o segredo)', () => {
  const exp = expEm(-1);
  const token = tokenDoPortal({ mandato: 'Alfa', exp });
  assert.deepEqual(verificarEnvio({ token, mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() }),
    { ok: false, motivo: 'expirado' });
  // exatamente no instante do exp já não vale; um milissegundo antes ainda vale.
  const t2 = tokenDoPortal({ mandato: 'Alfa', exp: 2000000000 });
  assert.equal(verificarEnvio({ token: t2, mandato: 'Alfa', segredo: SEGREDO, agoraMs: 2000000000 * 1000 }).ok, false);
  assert.equal(verificarEnvio({ token: t2, mandato: 'Alfa', segredo: SEGREDO, agoraMs: 2000000000 * 1000 - 1 }).ok, true);
  // exp adulterado para o futuro: a assinatura não bate, não "expirado".
  const [v1, , u, sig] = token.split('.');
  assert.equal(verificarEnvio({ token: [v1, expEm(9999), u, sig].join('.'), mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() }).motivo,
    'assinatura');
});

test('MANDATO TROCADO é recusado: o token do Beta não grava no Alfa (o defeito do PR #265)', () => {
  const token = tokenDoPortal({ mandato: 'Beta', exp: expEm(1800) });
  assert.deepEqual(verificarEnvio({ token, mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() }),
    { ok: false, motivo: 'assinatura' });
});

test('assinatura adulterada, usuário trocado e segredo errado são recusados', () => {
  const exp = expEm(1800);
  const token = tokenDoPortal({ mandato: 'Alfa', exp });
  const [v1, e, u, sig] = token.split('.');
  const troca = sig[0] === '0' ? '1' : '0';
  const casos = {
    'um caractere da assinatura': [v1, e, u, troca + sig.slice(1)].join('.'),
    'o último caractere': [v1, e, u, sig.slice(0, -1) + (sig.endsWith('0') ? '1' : '0')].join('.'),
    'outro usuário': [v1, e, '00000000-0000-4000-8000-000000000000', sig].join('.'),
    'segredo errado': tokenDoPortal({ mandato: 'Alfa', exp, segredo: 'outro-segredo' }),
  };
  for (const [o_que, t] of Object.entries(casos)) {
    assert.equal(verificarEnvio({ token: t, mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() }).ok, false, o_que);
  }
});

test('token ausente ou malformado é recusado, nunca aceito por omissão', () => {
  for (const t of [undefined, null, '', '   ']) {
    assert.deepEqual(verificarEnvio({ token: t, mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() }), { ok: false, motivo: 'sem_token' });
  }
  for (const t of ['lixo', 'v2.1.a.b', 'v1.x.y.z', `v1.${expEm(60)}.${USUARIO}.curto`, 'v1.1.2.3.4']) {
    assert.equal(verificarEnvio({ token: t, mandato: 'Alfa', segredo: SEGREDO, agoraMs: agora() }).motivo, 'malformado', t);
  }
});

test('SEGREDO AUSENTE no n8n recusa tudo (fail closed), mesmo com um token que "parece" certo, e a mensagem é a do dono', () => {
  // O token é válido para QUALQUER segredo que o atacante escolha: sem segredo, a assinatura "vazia" não pode passar.
  const falso = tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800), segredo: 'x' });
  for (const segredo of [undefined, null, '', '   ']) {
    const v = veredictoDoEnvio({ token: falso, mandato: 'Alfa', segredo, agoraMs: agora() });
    assert.equal(v.autorizado, false, JSON.stringify(segredo));
    assert.equal(v.motivo, 'sem_segredo');
    assert.match(v.mensagem, /N8N_INTAKE_SEGREDO/);
  }
  // e o token genuinamente assinado com segredo vazio no portal também não vale
  const comVazio = tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800), segredo: '' });
  assert.equal(verificarEnvio({ token: comVazio, mandato: 'Alfa', segredo: '', agoraMs: agora() }).ok, false);
});

test('as mensagens de recusa dizem o que aconteceu e que nada foi gravado', () => {
  const exp = veredictoDoEnvio({ token: tokenDoPortal({ mandato: 'A', exp: expEm(-5) }), mandato: 'A', segredo: SEGREDO, agoraMs: agora() });
  assert.match(exp.mensagem, /envio sem autorização válida/i);
  assert.match(exp.mensagem, /expirou/);
  const sem = veredictoDoEnvio({ token: '', mandato: 'A', segredo: SEGREDO, agoraMs: agora() });
  assert.match(sem.mensagem, /envio sem autorização válida/i);
  for (const v of [exp, sem]) assert.match(v.mensagem, /Nada foi gravado/);
});

// --- tempo constante ---------------------------------------------------------
test('comparação em tempo constante: o trabalho não depende de ONDE as duas strings divergem', () => {
  const a = 'a'.repeat(64);
  const contar = (x, y) => {
    const orig = String.prototype.charCodeAt;
    let n = 0;
    String.prototype.charCodeAt = function (...args) { n += 1; return orig.apply(this, args); };
    try { iguaisEmTempoConstante(x, y); } finally { String.prototype.charCodeAt = orig; }
    return n;
  };
  const noInicio = contar(a, 'b' + a.slice(1));
  const noFim = contar(a, a.slice(0, -1) + 'b');
  const igual = contar(a, a);
  assert.ok(noInicio > 0, 'a medição tem de enxergar o trabalho (medida não-vazia)');
  assert.equal(noInicio, noFim, 'divergência no início custa o mesmo que no fim');
  assert.equal(noInicio, igual, 'e o mesmo que strings iguais');
  // e continua correta
  assert.equal(iguaisEmTempoConstante(a, a), true);
  assert.equal(iguaisEmTempoConstante(a, a + 'x'), false);
  assert.equal(iguaisEmTempoConstante(a + 'x', a), false);
  assert.equal(iguaisEmTempoConstante('', ''), true);
  assert.equal(iguaisEmTempoConstante(null, ''), true);
});

// --- o nó, como roda em produção ---------------------------------------------
const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'));
const no = (nome) => wf.nodes.find((n) => n.name === nome);
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor;

async function conferirEnvio({ form, env, vars }) {
  const $input = { first: () => ({ json: form }), all: () => [{ json: form }] };
  const fn = new AsyncFunction('$input', '$env', '$vars', no('Conferir Envio').parameters.jsCode);
  const out = await fn($input, env, vars);
  assert.equal(out.length, 1, 'um item só, como a recusa de tamanho/orçamento');
  return out[0].json;
}
const formCom = (mandato, token) => ({ 'Mandato (nome do caso)': mandato, 'Token do envio': token });

test('Conferir Envio (o jsCode commitado): válido passa; expirado, mandato trocado e adulterado são recusados com a mensagem', async () => {
  const ok = await conferirEnvio({ form: formCom('Alfa', tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800) })), env: { N8N_INTAKE_SEGREDO: SEGREDO } });
  assert.equal(ok.envio_autorizado, true);
  assert.equal(ok.orcamento_mensagem, null);

  const recusas = {
    expirado: formCom('Alfa', tokenDoPortal({ mandato: 'Alfa', exp: expEm(-30) })),
    'mandato trocado': formCom('Alfa', tokenDoPortal({ mandato: 'Beta', exp: expEm(1800) })),
    adulterado: formCom('Alfa', tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800) }).replace(/.$/, (c) => (c === '0' ? '1' : '0'))),
    'sem token': formCom('Alfa', undefined),
  };
  for (const [o_que, form] of Object.entries(recusas)) {
    const r = await conferirEnvio({ form, env: { N8N_INTAKE_SEGREDO: SEGREDO } });
    assert.equal(r.envio_autorizado, false, o_que);
    assert.equal(r.caso_id, null, `${o_que}: nenhum caso foi criado`);
    assert.equal(r.etapa_recusa, 'envio');
    assert.match(r.orcamento_mensagem, /envio sem autorização válida/i, o_que);
  }
});

test('Conferir Envio: sem segredo no n8n recusa tudo — `$env` vazio, `$env` BLOQUEADO (lança) e sem `$vars`', async () => {
  const token = tokenDoPortal({ mandato: 'Alfa', exp: expEm(1800) });
  const bloqueado = new Proxy({}, { get() { throw new Error('access to env vars denied'); } });
  const semVars = new Proxy({}, { get() { throw new Error('vars indisponível'); } });
  for (const [o_que, env, vars] of [
    ['env vazio', {}, {}], ['env bloqueado', bloqueado, semVars], ['env vazio e vars lançando', {}, semVars],
    ['segredo só com espaços', { N8N_INTAKE_SEGREDO: '  ' }, {}],
  ]) {
    const r = await conferirEnvio({ form: formCom('Alfa', token), env, vars });
    assert.equal(r.envio_autorizado, false, o_que);
    assert.equal(r.motivo_recusa, 'sem_segredo', o_que);
    assert.match(r.orcamento_mensagem, /N8N_INTAKE_SEGREDO/);
  }
  // $vars é o plano B: com o segredo ali e `$env` bloqueado, o envio legítimo passa.
  const viaVars = await conferirEnvio({ form: formCom('Alfa', token), env: bloqueado, vars: { N8N_INTAKE_SEGREDO: SEGREDO } });
  assert.equal(viaVars.envio_autorizado, true);
});

// --- a topologia: a conferência vem ANTES de qualquer gravação -----------------
test('Topologia: Form -> Conferir Envio -> Envio autorizado?; só o "sim" chega ao Upsert; o "não" vai ao Registrar Recusa -> Abortar Lote', () => {
  const dest = (n, i = 0) => (wf.connections[n].main[i] || []).map((c) => `${c.node}:${c.index}`);
  assert.deepEqual(dest('Intake (Form)'), ['Conferir Envio:0']);
  assert.deepEqual(dest('Conferir Envio'), ['Envio autorizado?:0']);
  assert.deepEqual(dest('Envio autorizado?', 0), ['Upsert Caso (Postgres):0']);
  assert.deepEqual(dest('Envio autorizado?', 1), ['Juntar Recusas:2']);
  assert.equal(no('Juntar Recusas').parameters.numberInputs, 3, 'três entradas: tamanho, orçamento e envio');
  assert.deepEqual(dest('Juntar Recusas'), ['Registrar Recusa:0']);
  assert.deepEqual(dest('Registrar Recusa'), ['Abortar Lote:0']);
  // o `Abortar Lote` lança, e o nó de conferência aborta se ele mesmo falhar (fail closed)
  assert.equal(no('Conferir Envio').onError, undefined);
});

test('Propriedade: nenhum nó que GRAVA é alcançável do Form sem passar pelo "sim" do Envio autorizado?', () => {
  const alcancados = new Set(['Intake (Form)']);
  const fila = ['Intake (Form)'];
  while (fila.length) {
    const n = fila.shift();
    (wf.connections[n]?.main || []).forEach((ramo, i) => {
      if (n === 'Envio autorizado?' && i === 0) return; // o "sim" é a única porta, e não se atravessa
      for (const c of ramo || []) if (!alcancados.has(c.node)) { alcancados.add(c.node); fila.push(c.node); }
    });
  }
  const tipos = (nome) => no(nome).type;
  const quemGrava = [...alcancados].filter((n) => ['n8n-nodes-base.postgres', 'n8n-nodes-base.httpRequest'].includes(tipos(n)));
  // A única gravação sem autorização é a da PRÓPRIA recusa (execucao_falha, sem caso).
  assert.deepEqual(quemGrava, ['Registrar Recusa']);
  assert.ok(alcancados.has('Abortar Lote') && !alcancados.has('Upsert Caso (Postgres)') && !alcancados.has('Listar Arquivos'));
});

test('Registrar Recusa grava a etapa que a recusa informa (envio) e mantém "orcamento" para as outras duas', () => {
  const repl = no('Registrar Recusa').parameters.options.queryReplacement;
  assert.match(repl, /\$json\.etapa_recusa \|\| 'orcamento'/);
});

test('O formulário declara o campo do token DEPOIS do mandato (o portal acha o mandato como o 1º texto do HTML)', () => {
  const rotulos = no('Intake (Form)').parameters.formFields.values.map((f) => f.fieldLabel);
  assert.deepEqual(rotulos, ['Mandato (nome do caso)', 'Arquivos', 'Token do envio']);
  assert.equal(no('Intake (Form)').parameters.formFields.values[2].requiredField, false);
});

test('mensagemAssinada: o vetor que o portal e o n8n usam (mandato normalizado | exp | usuário)', () => {
  assert.equal(mensagemAssinada('  Alfa Ltda ', 1893456000, USUARIO), `alfa ltda|1893456000|${USUARIO}`);
});
