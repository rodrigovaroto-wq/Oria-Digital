// O LEITOR NO NAVEGADOR (sessão 108, 13/10/2026): o mesmo código lê em fluxo, no
// navegador e no CLI, e produz o RESUMO que vai para o banco no lugar do arquivo.
//
// Quantos testes reprovaram com cada guarda desligada (regra 2) está na mensagem do
// commit. O desvio real do navegador (o `TextDecoder('latin1')` dele é cp1252) não roda
// no Node: aqui ele é coberto por `desfazerCp1252` contra a tabela do Python, e num
// Chromium de verdade por `Leitor/medicao-n8n/navegador-igual-ao-cli.mjs`.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createHash, randomBytes } from 'node:crypto';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { Sha256, sha256Hex } from '../lib/sha256.mjs';
import { latin1, desfazerCp1252, centavosBR } from '../lib/campos.mjs';
import { detectarFamilia } from '../lib/familia.mjs';
import { lerEnvelopeDeBuffer, lerEnvelopeDeFluxo } from '../lib/envelope.mjs';
import { lerEnvelopeDeArquivo } from '../lib/arquivo.mjs';
import { gerarSped, gerarCnab240, gerarCnab400, gerarCnab150, gerarOfx, gerarXmlFiscal, gerarEvento, gerarEcdComLancamentos } from '../../Dados de Teste/fontes-oficiais/gerar.mjs';

/** Um ReadableStream que entrega `buf` em fatias de `tam` bytes, como Uint8Array. */
const fluxoEmFatias = (buf, tam) => {
  let i = 0;
  return new ReadableStream({
    pull(c) {
      if (i >= buf.length) { c.close(); return; }
      c.enqueue(new Uint8Array(buf.subarray(i, i + tam)));
      i += tam;
    },
  });
};

const TODAS = () => [
  ...['ECD', 'ECF', 'EFD_ICMS_IPI', 'EFD_CONTRIBUICOES'].map(s => [`sped ${s}`, gerarSped(s)]),
  ['sped truncado', gerarSped('ECD', { quebrar: 'truncar' })],
  ['cnab240', gerarCnab240()], ['cnab400', gerarCnab400()], ['cnab150', gerarCnab150()],
  ['ofx', gerarOfx()], ['nfe', gerarXmlFiscal('nfe')], ['cte', gerarXmlFiscal('cte')], ['esocial', gerarEvento('esocial')],
  ['ecd com lançamentos', gerarEcdComLancamentos().buf],
  ['ecd com lançamentos LF', gerarEcdComLancamentos({ crlf: false }).buf],
  // Acima de 64 KB: só aqui uma fatia pequena parte um \r\n ao meio (abaixo disso o
  // arquivo inteiro entra na cabeça que reconhece a família, numa fatia só).
  ['ecd acima de 64 KB', gerarEcdComLancamentos({ extras: 1200 }).buf],
];

test('SHA-256 incremental = node:crypto, em qualquer fatiamento (é a identidade do arquivo na 0206)', () => {
  for (const n of [0, 1, 55, 56, 63, 64, 65, 127, 128, 129, 1000, 70000]) {
    const b = randomBytes(n);
    const esperado = createHash('sha256').update(b).digest('hex');
    assert.equal(sha256Hex(b), esperado, `inteiro, ${n} bytes`);
    for (const f of [1, 3, 63, 64, 65, 4096]) {
      const s = new Sha256();
      for (let i = 0; i < n; i += f) s.update(b.subarray(i, i + f));
      assert.equal(s.hex(), esperado, `${n} bytes em fatias de ${f}`);
    }
  }
});

test('latin1: cada byte vira o caractere de mesmo código, e o cp1252 do navegador é desfeito', () => {
  const todos = Uint8Array.from({ length: 256 }, (_, i) => i);
  assert.equal(latin1(todos), Buffer.from(todos).toString('latin1'));
  // O que o Chromium devolve para 0x80–0x9F com TextDecoder('latin1'), tirado do codec
  // cp1252 do Python (fonte independente da tabela do código), com os 5 bytes sem
  // caractere no cp1252 mantidos, como o WHATWG faz.
  const comoONavegadorDecodifica = '€\u0081‚ƒ„…†‡ˆ‰Š‹Œ\u008dŽ\u008f'
    + '\u0090‘’“”•–—˜™š›œ\u009džŸ';
  assert.equal(desfazerCp1252(comoONavegadorDecodifica), Buffer.from(todos.subarray(0x80, 0xa0)).toString('latin1'));
  assert.equal(desfazerCp1252('AÇÚCAR'), 'AÇÚCAR');
});

test('a família sai igual de um Uint8Array (navegador) e de um Buffer (CLI)', () => {
  for (const [nome, buf] of TODAS()) {
    const u8 = new Uint8Array(buf);
    assert.deepEqual(detectarFamilia(u8), detectarFamilia(buf), nome);
  }
});

test('fluxo em fatias de 1, 7 e 4096 bytes dá o MESMO envelope e o MESMO resumo que o arquivo inteiro', async () => {
  for (const [nome, buf] of TODAS()) {
    const inteiro = lerEnvelopeDeBuffer(buf, { resumir: true });
    for (const tam of [1, 7, 4096]) {
      const fluxo = await lerEnvelopeDeFluxo(fluxoEmFatias(buf, tam), { resumir: true });
      assert.deepEqual(fluxo, inteiro, `${nome}, fatias de ${tam}`);
    }
  }
});

test('o número de linha do resumo aponta para o texto daquela linha do arquivo, com \\r\\n partido entre fatias', async () => {
  for (const crlf of [true, false]) {
    const { buf, linhas } = gerarEcdComLancamentos({ crlf, extras: 1200 });
    assert.ok(buf.length > 65536 * 1.5, 'o arquivo precisa passar da cabeça de 64 KB');
    // Fatia de 1 byte: todo \r\n do arquivo fica partido entre duas fatias.
    const { resumo } = await lerEnvelopeDeFluxo(fluxoEmFatias(buf, 1), { resumir: true });
    assert.ok(resumo.registros.length > 0);
    for (const [n, texto] of resumo.registros) assert.equal(linhas[n - 1], texto, `linha ${n} (crlf=${crlf})`);
    for (const g of resumo.lancamentos_por_conta_mes) assert.match(linhas[g.primeira_linha - 1], /^\|I250\|/);
  }
});

test('resumo da ECD: guarda a íntegra dos registros pequenos e SOMA os lançamentos por conta, mês e indicador', () => {
  const { buf, linhas } = gerarEcdComLancamentos();
  const { envelope, resumo } = lerEnvelopeDeBuffer(buf, { resumir: true });
  assert.equal(envelope.status, 'lido');
  assert.equal(resumo.hash_sha256, envelope.hash_sha256);
  const guardados = resumo.registros.map(([, t]) => t.split('|')[1]);
  for (const r of ['0000', 'I010', 'I050', 'I150', 'I155', 'J005', 'J150', 'J900']) assert.ok(guardados.includes(r), `guarda ${r}`);
  for (const r of ['I200', 'I250', '9900', '0001']) assert.ok(!guardados.includes(r), `não guarda ${r} na íntegra`);
  const g = (conta, mes, ind) => resumo.lancamentos_por_conta_mes.find(x => x.conta === conta && x.mes === mes && x.ind_lcto === ind);
  assert.deepEqual([g('1.1.01', '2025-01', 'N').debito, g('1.1.01', '2025-01', 'N').credito], [150000, 0]);
  assert.deepEqual([g('3.1.01', '2025-01', 'N').credito, g('3.1.01', '2025-01', 'N').partidas], [150000, 2]);
  // O encerramento não soma com o normal do mesmo mês e conta: somado, a receita de dezembro sumiria.
  assert.deepEqual([g('3.1.01', '2025-12', 'E').debito, g('3.1.01', '2025-12', 'E').credito], [180000, 0]);
  assert.deepEqual([g('3.1.01', '2025-12', 'N').debito, g('3.1.01', '2025-12', 'N').credito], [0, 10000]);
  const i250 = linhas.filter(x => x.startsWith('|I250|')).length;
  assert.equal(resumo.conferencia.i250_lidos, i250);
  assert.equal(resumo.lancamentos_por_conta_mes.reduce((s, x) => s + x.partidas, 0), envelope.detalhe.por_registro.I250);
  assert.equal(resumo.status_do_arquivo, 'lido');
  assert.equal(resumo.conferencia.i250_sem_i200, 0);
  assert.equal(resumo.conferencia.lancamentos_desbalanceados, 0);
  assert.equal(resumo.conferencia.valores_invalidos, 0);
  assert.match(resumo.descartado, /lançamento individual/);
});

test('resumo da ECD acusa lançamento desbalanceado, valor fora do formato e partida sem I200, sem descartar nada', () => {
  const des = lerEnvelopeDeBuffer(gerarEcdComLancamentos({ desbalanceado: true }).buf, { resumir: true }).resumo;
  assert.equal(des.conferencia.lancamentos_desbalanceados, 1);
  assert.deepEqual([des.conferencia.lancamentos_desbalanceados_amostra[0].debitos, des.conferencia.lancamentos_desbalanceados_amostra[0].creditos], [20000, 19000]);
  const inv = lerEnvelopeDeBuffer(gerarEcdComLancamentos({ valorInvalido: true }).buf, { resumir: true }).resumo;
  assert.equal(inv.conferencia.valores_invalidos, 1);
  assert.equal(inv.conferencia.valores_invalidos_amostra[0].valor, '1,234');
  // O valor inválido não entra na soma, e o GRUPO diz que uma partida ficou de fora.
  const grupoInv = inv.lancamentos_por_conta_mes.find(x => x.conta === '1.1.01' && x.mes === '2025-02');
  assert.equal(grupoInv.partidas_sem_valor, 1);
  assert.equal(inv.conferencia.grupos_com_partida_sem_valor, 1);
  const orfa = lerEnvelopeDeBuffer(gerarEcdComLancamentos({ partidaOrfa: true }).buf, { resumir: true }).resumo;
  const semMes = orfa.lancamentos_por_conta_mes.find(x => x.mes === null);
  assert.ok(semMes, 'a partida sem I200 aparece, no grupo de mês null');
  assert.equal(semMes.partidas, 1);
  assert.equal(orfa.conferencia.i250_sem_i200, 1);
});

test('indicador D/C fora do padrão: a partida conta, não soma, e o grupo diz que ficou sem valor', () => {
  const { buf } = gerarEcdComLancamentos();
  const s = buf.toString('latin1').replace('|I250|3.1.01||1.000,00|C|||VENDA||', '|I250|3.1.01||1.000,00|c|||VENDA||');
  const { envelope, resumo } = lerEnvelopeDeBuffer(Buffer.from(s, 'latin1'), { resumir: true });
  assert.equal(envelope.status, 'lido');
  const g = resumo.lancamentos_por_conta_mes.find(x => x.conta === '3.1.01' && x.mes === '2025-01');
  assert.deepEqual([g.credito, g.partidas, g.partidas_sem_valor], [50000, 2, 1]);
});

test('arquivo NÃO lido por inteiro não tem resumo: truncado e dois SPEDs concatenados', () => {
  const { buf } = gerarEcdComLancamentos();
  const truncado = buf.subarray(0, Math.floor(buf.length * 0.6));
  const t = lerEnvelopeDeBuffer(truncado, { resumir: true });
  assert.notEqual(t.envelope.status, 'lido');
  assert.match(t.resumo.ausente, /não lido por inteiro/);
  assert.equal(t.resumo.lancamentos_por_conta_mes, undefined);
  const c = lerEnvelopeDeBuffer(Buffer.concat([buf, buf]), { resumir: true });
  assert.equal(c.envelope.status, 'falhou');
  assert.match(c.resumo.ausente, /não lido por inteiro/);
});

test('SPED com BOM UTF-8 e linha indentada: o resumo conta o mesmo que o envelope e guarda o 0000', () => {
  const { buf } = gerarEcdComLancamentos();
  const s = buf.toString('latin1').replace('|I250|3.1.01||500,00|C|||VENDA||', ' |I250|3.1.01||500,00|C|||VENDA||');
  const comBom = Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(s, 'latin1')]);
  const { envelope, resumo } = lerEnvelopeDeBuffer(comBom, { resumir: true });
  assert.equal(envelope.status, 'lido');
  assert.equal(resumo.ausente, undefined, resumo.ausente);
  assert.ok(resumo.registros.some(([n, l]) => n === 1 && l.includes('|0000|')), 'o 0000 (identidade) fica no resumo');
  assert.equal(resumo.conferencia.i250_lidos, envelope.detalhe.por_registro.I250);
});

test('centavos: inteiro, sem ponto flutuante, e mais de 2 casas é ausência', () => {
  assert.deepEqual(['1.234,56', '0,5', '-12,30', '12', '1,234', '', 'abc'].map(centavosBR), [123456, 50, -1230, 1200, null, null, null]);
});

test('família sem resumo diz em que onda o conteúdo será lido; a ECF guarda os blocos de demonstração', () => {
  for (const [buf, onda] of [[gerarSped('EFD_ICMS_IPI'), /onda 3/], [gerarCnab240(), /onda 2/], [gerarOfx(), /onda 2/], [gerarXmlFiscal('nfe'), /onda 3/], [gerarEvento('esocial'), /onda 4/]]) {
    const { resumo } = lerEnvelopeDeBuffer(buf, { resumir: true });
    assert.match(resumo.ausente, onda);
    assert.equal(resumo.registros, undefined);
  }
  const ecf = lerEnvelopeDeBuffer(gerarSped('ECF'), { resumir: true }).resumo;
  assert.ok(ecf.registros.some(([, t]) => t.startsWith('|0000|')));
});

test('arquivo que não é oficial: família null sem ler o resto; com resumir, a forma é sempre {envelope, resumo}', async () => {
  const pdf = Buffer.concat([Buffer.from('%PDF-1.7\n'), randomBytes(200000)]);
  assert.deepEqual(await lerEnvelopeDeFluxo(fluxoEmFatias(pdf, 4096)), { familia: null, evidencia: detectarFamilia(pdf).evidencia, hash_sha256: null });
  // Quem chama com resumir faz `const {envelope} = ...`: o zip e o PDF não podem vir em outra forma.
  const r = await lerEnvelopeDeFluxo(fluxoEmFatias(pdf, 4096), { resumir: true });
  assert.equal(r.envelope.familia, null);
  assert.match(r.resumo.ausente, /não é arquivo de leiaute oficial/);
  const z = lerEnvelopeDeBuffer(Buffer.concat([Buffer.from('PK\x03\x04'), randomBytes(100)]), { resumir: true });
  assert.equal(z.envelope.familia, 'zip');
  assert.match(z.resumo.ausente, /^zip/);
  const env = await lerEnvelopeDeFluxo(fluxoEmFatias(gerarSped('ECD'), 100));
  assert.equal(env.familia, 'sped');
  assert.equal(env.resumo, undefined);
});

test('disco (openAsBlob, o CLI) e fluxo em fatias (a forma do navegador) dão o mesmo envelope e resumo', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'leitor-'));
  try {
    const { buf } = gerarEcdComLancamentos({ desbalanceado: true });
    const caminho = join(dir, 'ecd.txt');
    writeFileSync(caminho, buf);
    assert.deepEqual(await lerEnvelopeDeArquivo(caminho, { resumir: true }), await lerEnvelopeDeFluxo(fluxoEmFatias(buf, 13), { resumir: true }));
  } finally { rmSync(dir, { recursive: true }); }
});

test('ECD e ECF assinadas: o bloco da assinatura depois do 9999 não entra no resumo, e o resumo existe', () => {
  // Bytes da assinatura PKCS#7 com '|' no meio: contados pelo resumo e não pelo envelope,
  // a conferência de `resultado()` recusaria o resumo de TODA escrituração assinada.
  const assinatura = Buffer.from([0x30, 0x82, 0x7c, 0x49, 0x32, 0x35, 0x30, 0x7c, 0x0d, 0x0a, 0x7c, 0x30, 0x30, 0x30, 0x30, 0x41]);
  for (const buf of [gerarEcdComLancamentos().buf, gerarSped('ECF')]) {
    const { envelope, resumo } = lerEnvelopeDeBuffer(Buffer.concat([buf, assinatura]), { resumir: true });
    assert.equal(envelope.status, 'lido', envelope.detalhe.motivo);
    assert.equal(resumo.ausente, undefined, resumo.ausente);
  }
});
