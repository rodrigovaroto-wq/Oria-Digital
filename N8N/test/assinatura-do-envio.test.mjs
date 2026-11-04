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
  normalizarMandato, mensagemAssinada, mensagemAssinadaV2, hmacSha256Hex, iguaisEmTempoConstante, verificarEnvio, veredictoDoEnvio,
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
  assert.deepEqual(v, { ok: true, usuario_id: USUARIO, caso_id: null }); // v1: por mandato, sem caso
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
  for (const t of ['lixo', 'v3.1.a.b', 'v1.x.y.z', `v1.${expEm(60)}.${USUARIO}.curto`, 'v1.1.2.3.4']) {
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
    assert.match(v.mensagem, /Vault/);
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
    const orig = String.prototype.codePointAt;
    let n = 0;
    String.prototype.codePointAt = function (...args) { n += 1; return orig.apply(this, args); };
    try { iguaisEmTempoConstante(x, y); } finally { String.prototype.codePointAt = orig; }
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

// --- o nó, como está no JSON commitado ---------------------------------------------
const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'));
const no = (nome) => wf.nodes.find((n) => n.name === nome);

// O QUE O NÓ FAZ HOJE: não há mais jsCode para executar — a conferência é `fn_conferir_envio` no
// banco (a prova do HMAC em si mora em Supabase/test). Aqui se prova a FIAÇÃO, por comportamento.
const conferir = no('Conferir Envio');

test('Conferir Envio é um nó Postgres que chama fn_conferir_envio com o token e o mandato DO FORM, nessa ordem', () => {
  assert.equal(conferir.type, 'n8n-nodes-base.postgres');
  assert.match(conferir.parameters.query, /from fn_conferir_envio\(\$1::text, \$2::text\)/);
  const repl = conferir.parameters.options.queryReplacement;
  // array (nunca texto com vírgula) e lido do Form, não de `$json`
  assert.match(repl, /^=\{\{ \[\$\('Intake \(Form\)'\)\.first\(\)\.json\['Token do envio'\] \?\? '', \$\('Intake \(Form\)'\)\.first\(\)\.json\['Mandato \(nome do caso\)'\] \?\? ''\] \}\}$/);
  assert.equal(conferir.jsCode, undefined);
});

test('Conferir Envio devolve as colunas que o IF e o Registrar Recusa leem (o formato do item que o Code devolvia)', () => {
  const colunas = [...conferir.parameters.query.matchAll(/\bas\s+(\w+)/g)].map((m) => m[1]);
  for (const c of ['envio_autorizado', 'caso_id', 'etapa_recusa', 'motivo_recusa', 'orcamento_mensagem']) {
    assert.ok(colunas.includes(c), `falta a coluna ${c}`);
  }
  assert.match(no('Envio autorizado?').parameters.conditions.conditions[0].leftValue, /\$json\.envio_autorizado/);
  const repl = no('Registrar Recusa').parameters.options.queryReplacement;
  for (const c of ['caso_id', 'etapa_recusa', 'orcamento_mensagem']) assert.match(repl, new RegExp(`\\$json\\.${c}\\b`));
});

test('Fail closed: banco fora NÃO deixa o envio passar (sem onError, com retry); o Upsert lê o caso do Conferir Envio e o nome do Form só como rótulo/transição', () => {
  assert.equal(conferir.onError, undefined, 'continueRegularOutput entregaria ao Upsert um item sem veredito');
  assert.equal(conferir.retryOnFail, true);
  assert.ok(conferir.maxTries >= 2);
  // O Postgres SUBSTITUI o item: nada vem de `$json`. No v2 o CASO vem do Conferir Envio (P3-F3); o nome do
  // Form segue como rotulo da auditoria de divergencia e como chave do v1 em voo (ramo que sai na F5).
  const up = no('Upsert Caso (Postgres)').parameters.options.queryReplacement;
  assert.match(up, /\$\('Conferir Envio'\)\.first\(\)\.json\.caso_id \?\? ''/);
  assert.match(up, /\$\('Intake \(Form\)'\)\.first\(\)\.json\['Mandato \(nome do caso\)'\]/);
  assert.doesNotMatch(up, /\$json/);
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
  // Postgres alcançável sem autorização: o próprio `Conferir Envio` (um select, que decide) e a
  // gravação da PRÓPRIA recusa (execucao_falha, sem caso). Nada além disso.
  assert.deepEqual(quemGrava, ['Conferir Envio', 'Registrar Recusa']);
  assert.match(no('Conferir Envio').parameters.query, /^select /);
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

// --- token v2 (roteado por caso_id) --------------------------------------------------
// VETOR FIXO, calculado FORA desta lib (node:crypto) e colado: segredo, exp, usuário e caso abaixo.
//   createHmac('sha256', SEGREDO).update(`v2|${CASO}|${EXP_V2}|${USUARIO}`).digest('hex')
const CASO = '7d2e4b18-5c63-4a9f-8e01-b3a6d5c9f742';
const EXP_V2 = 1893456000;
const TOKEN_V2_FIXO = 'v2.1893456000.3f1c9a52-7b0e-4d34-9a5e-0c2b1d6e8f10.7d2e4b18-5c63-4a9f-8e01-b3a6d5c9f742.'
  + 'f99872e4ecdb126c3d81e69bd34c957573fa70077980fd8dc4062a508f3780ea';
const AGORA_V2 = (EXP_V2 - 1000) * 1000;
const v2 = (token, agoraMs = AGORA_V2) => verificarEnvio({ token, mandato: 'qualquer', segredo: SEGREDO, agoraMs });
const tokenV2 = ({ caso = CASO, usuario = USUARIO, exp = EXP_V2, segredo = SEGREDO } = {}) =>
  `v2.${exp}.${usuario}.${caso}.${createHmac('sha256', segredo).update(`v2|${caso}|${exp}|${usuario}`, 'utf8').digest('hex')}`;

test('v2: o vetor fixo (calculado fora da lib) é aceito e devolve usuário E caso; a mensagem tem a etiqueta v2|', () => {
  assert.equal(mensagemAssinadaV2(CASO, EXP_V2, USUARIO), `v2|${CASO}|${EXP_V2}|${USUARIO}`);
  assert.equal(mensagemAssinadaV2(CASO.toUpperCase(), EXP_V2, USUARIO.toUpperCase()), `v2|${CASO}|${EXP_V2}|${USUARIO}`);
  assert.deepEqual(v2(TOKEN_V2_FIXO), { ok: true, usuario_id: USUARIO, caso_id: CASO });
  assert.equal(tokenV2(), TOKEN_V2_FIXO, 'o token do teste e o vetor colado concordam');
  // o mandato é irrelevante no v2: o caso vem no token
  assert.equal(verificarEnvio({ token: TOKEN_V2_FIXO, mandato: 'outro', segredo: SEGREDO, agoraMs: AGORA_V2 }).ok, true);
  const vd = veredictoDoEnvio({ token: TOKEN_V2_FIXO, mandato: 'x', segredo: SEGREDO, agoraMs: AGORA_V2 });
  assert.deepEqual(vd, { autorizado: true, motivo: null, mensagem: null, usuario_id: USUARIO, caso_id: CASO });
});

test('v2 adulterado (caso, usuário, exp, hmac, segredo) é recusado por assinatura', () => {
  const [, e, u, c, sig] = TOKEN_V2_FIXO.split('.');
  const outro = '00000000-0000-4000-8000-000000000001';
  const casos = {
    'outro caso': ['v2', e, u, outro, sig],
    'outro usuário': ['v2', e, outro, c, sig],
    'exp para o futuro': ['v2', '1999999999', u, c, sig],
    'um caractere do hmac': ['v2', e, u, c, (sig[0] === '0' ? '1' : '0') + sig.slice(1)],
  };
  for (const [o_que, p] of Object.entries(casos)) assert.deepEqual(v2(p.join('.')), { ok: false, motivo: 'assinatura' }, o_que);
  assert.equal(v2(tokenV2({ segredo: 'outro-segredo' })).motivo, 'assinatura');
});

test('v2 vencido é "expirado" (só depois da assinatura); no instante do exp já não vale', () => {
  assert.deepEqual(v2(TOKEN_V2_FIXO, EXP_V2 * 1000), { ok: false, motivo: 'expirado' });
  assert.equal(v2(TOKEN_V2_FIXO, EXP_V2 * 1000 - 1).ok, true);
  assert.equal(veredictoDoEnvio({ token: TOKEN_V2_FIXO, mandato: 'x', segredo: SEGREDO, agoraMs: EXP_V2 * 1000 + 1 }).caso_id, null);
});

test('v2 malformado: uuid inválido, MAIÚSCULAS, partes a mais/menos e hmac curto -> malformado', () => {
  const [, e, u, c, sig] = TOKEN_V2_FIXO.split('.');
  const casos = {
    'caso não é uuid': ['v2', e, u, 'nao-e-uuid', sig],
    'caso maiúsculo': ['v2', e, u, c.toUpperCase(), sig],
    'usuário maiúsculo': ['v2', e, u.toUpperCase(), c, sig],
    'caso sem hífens': ['v2', e, u, c.replaceAll('-', ''), sig],
    'exp não numérico': ['v2', 'x', u, c, sig],
    'hmac curto': ['v2', e, u, c, sig.slice(0, 10)],
    'hmac maiúsculo': ['v2', e, u, c, sig.toUpperCase()],
    'sem caso (4 partes com v2)': ['v2', e, u, sig],
    'parte a mais': ['v2', e, u, c, sig, 'x'],
  };
  for (const [o_que, p] of Object.entries(casos)) assert.deepEqual(v2(p.join('.')), { ok: false, motivo: 'malformado' }, o_que);
});

test('COLISÃO: token v1 de um mandato chamado <uuid-do-outro-caso> reescrito como v2 é recusado (a etiqueta v2|)', () => {
  // O Analista cria o mandato cujo NOME é o uuid do caso alheio e pede, legitimamente, um token v1 dele.
  const v1 = tokenDoPortal({ mandato: CASO, exp: EXP_V2 });
  const [, e, u, sig] = v1.split('.');
  assert.equal(verificarEnvio({ token: v1, mandato: CASO, segredo: SEGREDO, agoraMs: AGORA_V2 }).ok, true, 'o v1 original vale');
  // reescrito como v2 do caso alheio, com o MESMO hmac
  const forjado = ['v2', e, u, CASO, sig].join('.');
  assert.deepEqual(v2(forjado), { ok: false, motivo: 'assinatura' });
});
