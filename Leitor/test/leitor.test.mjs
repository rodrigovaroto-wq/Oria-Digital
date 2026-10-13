// O LEITOR DE ENVELOPE (Espec. 12, F2T etapa 1). Afirma COMPORTAMENTO (regra 3):
// dado um arquivo, que família, que identificação e que veredito de leitura saem.
// Os arquivos são SINTÉTICOS (`Dados de Teste/fontes-oficiais/gerar.mjs`); ver o
// cabeçalho de lá sobre o que isso prova e o que não prova (regra 4).

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { writeFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { decimalBR, dataDDMMAAAA, dataAAAAMMDD, valorImplicito } from '../lib/campos.mjs';
import { detectarFamilia } from '../lib/familia.mjs';
import { lerEnvelopeDeBuffer, lerEnvelopeDeArquivo } from '../lib/envelope.mjs';
import { abrirZip } from '../lib/zip.mjs';
import { gerarSped, gerarCnab240, gerarCnab400, gerarCnab150, gerarOfx, gerarXmlFiscal, gerarEvento, gerarZip } from '../../Dados de Teste/fontes-oficiais/gerar.mjs';

// ---------------------------------------------------------------- particularidades (G10)
test('vírgula decimal: a parte decimal nunca some, e ponto como decimal é recusado', () => {
  assert.equal(decimalBR('1.234,56'), 1234.56);
  assert.equal(decimalBR('1234,56'), 1234.56);
  assert.equal(decimalBR('-12,5'), -12.5);
  assert.equal(decimalBR('1.234'), 1234);           // milhar, não 1,234
  assert.equal(decimalBR('1234.56'), null);         // o SPED não usa ponto decimal
  assert.equal(decimalBR(''), null);                // ausência, não zero (regra 1)
});

test('datas ddmmaaaa e aaaammdd: data impossível é recusada, não normalizada', () => {
  assert.equal(dataDDMMAAAA('31122025'), '2025-12-31');
  assert.equal(dataDDMMAAAA('31022025'), null);
  assert.equal(dataDDMMAAAA('2025-12-31'), null);
  assert.equal(dataAAAAMMDD('20250131120000[-3:BRT]'), '2025-01-31');
});

test('decimais implícitos do CNAB: 000000012345 com 2 casas é 123,45, não 12345', () => {
  assert.equal(valorImplicito('000000012345', 2), 123.45);
  assert.equal(valorImplicito('00001A', 2), null);
});

// ---------------------------------------------------------------- roteador de família (G5)
test('cada família oficial é reconhecida pelos bytes, com o subtipo certo', () => {
  const casos = [
    [gerarSped('ECD'), 'sped', 'ECD'],
    [gerarSped('ECF'), 'sped', 'ECF'],
    [gerarSped('EFD_ICMS_IPI'), 'sped', 'EFD_ICMS_IPI'],
    [gerarSped('EFD_CONTRIBUICOES'), 'sped', 'EFD_CONTRIBUICOES'],
    [gerarCnab240(), 'cnab240', null],
    [gerarCnab400(), 'cnab400', null],
    [gerarCnab150(), 'cnab150', null],
    [gerarOfx(), 'ofx', undefined],
    [gerarOfx({ versao: '211' }), 'ofx', undefined],
    [gerarXmlFiscal('nfe'), 'nfe', null],
    [gerarXmlFiscal('cte'), 'cte', null],
    [gerarXmlFiscal('mdfe'), 'mdfe', null],
    [gerarXmlFiscal('nfse'), 'nfse', null],
    [gerarEvento('esocial'), 'esocial', 'evtRemun'],
    [gerarEvento('reinf'), 'reinf', 'evtServTom'],
  ];
  for (const [buf, familia, subtipo] of casos) {
    const f = detectarFamilia(buf);
    assert.equal(f.familia, familia, `esperava ${familia}, veio ${f.familia} (${f.evidencia})`);
    if (subtipo !== undefined) assert.equal(f.subtipo ?? null, subtipo, `subtipo de ${familia}`);
  }
});

test('o que não é arquivo oficial segue o caminho atual (familia null), inclusive texto com pipe', () => {
  assert.equal(detectarFamilia(Buffer.from('%PDF-1.7\n...')).familia, null);
  assert.equal(detectarFamilia(Buffer.from('conta;saldo\nCaixa;100\nBancos;200\n')).familia, null);
  // Texto delimitado por | que NÃO começa pelo 0000 não é SPED.
  assert.equal(detectarFamilia(Buffer.from('|conta|saldo|\n|Caixa|100|\n')).familia, null);
  // XML qualquer não é NF-e só por ser XML.
  assert.equal(detectarFamilia(Buffer.from('<?xml version="1.0"?><balanco><ativo>1</ativo></balanco>')).familia, null);
});

// ---------------------------------------------------------------- envelope: SPED
test('SPED inteiro: lido, com contagem declarada = lida, CNPJ, período e chave natural', () => {
  for (const sub of ['ECD', 'ECF', 'EFD_ICMS_IPI', 'EFD_CONTRIBUICOES']) {
    const e = lerEnvelopeDeBuffer(gerarSped(sub));
    assert.equal(e.status, 'lido', `${sub}: ${e.detalhe.motivo}`);
    assert.equal(e.controle_declarado, e.controle_lido);
    assert.equal(e.cnpj, '11222333000181');
    assert.equal(e.periodo_ini, '2025-01-01');
    assert.equal(e.periodo_fim, '2025-12-31');
    assert.equal(e.chave_natural, `11222333000181|${sub}|2025-01-01|2025-12-31|-|${sub === 'ECD' ? 'G' : '-'}`);
    assert.equal(e.retificadora, false);
  }
});

test('SPED truncado (sem 9999) não é aceito como lido', () => {
  const e = lerEnvelopeDeBuffer(gerarSped('EFD_ICMS_IPI', { quebrar: 'truncar' }));
  assert.equal(e.status, 'falhou');
  assert.equal(e.controle_declarado, null);
  assert.match(e.detalhe.motivo, /truncado/);
});

test('SPED com 9999 diferente do lido é controle_divergente, com as duas contagens', () => {
  const e = lerEnvelopeDeBuffer(gerarSped('ECF', { quebrar: 'divergir_9999' }));
  assert.equal(e.status, 'controle_divergente');
  assert.notEqual(e.controle_declarado, e.controle_lido);
});

test('SPED com total certo e 9900 errado também não passa', () => {
  const e = lerEnvelopeDeBuffer(gerarSped('ECD', { quebrar: 'divergir_9900' }));
  assert.equal(e.status, 'falhou');
  assert.equal(e.detalhe.divergencias_9900.length, 1);
});

test('SPED de versão fora do registro de leiautes reprova alto (G7)', () => {
  const e = lerEnvelopeDeBuffer(gerarSped('EFD_ICMS_IPI', { versao: '099' }));
  assert.equal(e.status, 'versao_desconhecida');
  assert.match(e.detalhe.motivo, /099/);
  // A versão da ECD vem do I010, não do 0000.
  assert.equal(lerEnvelopeDeBuffer(gerarSped('ECD', { versao: '7.00' })).status, 'versao_desconhecida');
});

test('SPED retificadora é marcada, com a mesma chave natural da original (G9)', () => {
  const o = lerEnvelopeDeBuffer(gerarSped('EFD_CONTRIBUICOES'));
  const r = lerEnvelopeDeBuffer(gerarSped('EFD_CONTRIBUICOES', { retificadora: true }));
  assert.equal(r.retificadora, true);
  assert.equal(r.chave_natural, o.chave_natural);
  assert.notEqual(r.hash_sha256, o.hash_sha256);
});

test('SPED latin1: o leitor não corrompe acento (o nó de texto do n8n corromperia)', () => {
  const buf = gerarSped('ECD');
  assert.ok(!buf.toString('utf8').includes('AÇÚCAR'), 'a leitura em UTF-8 é a que corrompe');
  const e = lerEnvelopeDeBuffer(buf);
  assert.equal(e.status, 'lido');
  assert.equal(e.detalhe.nome, 'AÇÚCAR SINTÉTICO LTDA (fictícia)');
});

// ---------------------------------------------------------------- envelope: CNAB e OFX
test('CNAB 240/400/150 inteiros: lidos, com o trailer igual à contagem', () => {
  const c240 = lerEnvelopeDeBuffer(gerarCnab240());
  assert.equal(c240.status, 'lido', c240.detalhe.motivo);
  assert.equal(c240.subtipo, 'cobranca');
  assert.equal(c240.cnpj, '11222333000181');
  assert.equal(lerEnvelopeDeBuffer(gerarCnab240({ servico: 'extrato' })).subtipo, 'extrato');
  const c400 = lerEnvelopeDeBuffer(gerarCnab400());
  assert.equal(c400.status, 'lido', c400.detalhe.motivo);
  assert.equal(c400.subtipo, 'retorno');
  assert.equal(c400.detalhe.banco, '341');
  assert.equal(lerEnvelopeDeBuffer(gerarCnab150()).status, 'lido');
});

test('CNAB truncado, divergente, com linha curta ou buraco na sequência não passa', () => {
  assert.equal(lerEnvelopeDeBuffer(gerarCnab240({ quebrar: 'truncar' })).status, 'falhou');
  assert.equal(lerEnvelopeDeBuffer(gerarCnab240({ quebrar: 'divergir' })).status, 'controle_divergente');
  assert.equal(lerEnvelopeDeBuffer(gerarCnab240({ quebrar: 'linha_curta' })).status, 'falhou');
  assert.equal(lerEnvelopeDeBuffer(gerarCnab400({ quebrar: 'buraco_na_sequencia' })).status, 'falhou');
  assert.equal(lerEnvelopeDeBuffer(gerarCnab150({ quebrar: 'divergir' })).status, 'controle_divergente');
});

test('OFX: diz que não há contagem no formato, conta as transações e acusa o truncado', () => {
  for (const versao of ['102', '211']) {
    const e = lerEnvelopeDeBuffer(gerarOfx({ versao }));
    assert.equal(e.status, 'lido', `${versao}: ${e.detalhe.motivo}`);
    assert.equal(e.controle_tipo, 'sem_controle_no_formato');
    assert.equal(e.controle_lido, 4);
    assert.equal(e.periodo_ini, '2025-01-01');
    assert.equal(e.chave_natural, '0341|12345-6|2025-01-01|2025-01-31');
  }
  assert.equal(lerEnvelopeDeBuffer(gerarOfx({ quebrar: 'truncar' })).status, 'falhou');
  assert.equal(lerEnvelopeDeBuffer(gerarOfx({ versao: '999' })).status, 'versao_desconhecida');
});

// ---------------------------------------------------------------- envelope: XML
test('NF-e, CT-e, MDF-e, NFS-e: chave de acesso, versão, CNPJ do emitente e data', () => {
  for (const tipo of ['nfe', 'cte', 'mdfe', 'nfse']) {
    const e = lerEnvelopeDeBuffer(gerarXmlFiscal(tipo));
    assert.equal(e.status, 'lido', `${tipo}: ${e.detalhe.motivo}`);
    assert.equal(e.controle_tipo, 'documento_unico');
    assert.equal(e.cnpj, '11222333000181');
    assert.ok(e.chave_natural.startsWith('35251011222333000181'), `${tipo}: ${e.chave_natural}`);
    assert.match(e.periodo_ini, /^2025-10-0\d$/);
  }
});

test('evento de cancelamento é um arquivo próprio, com chave diferente da nota (não conta a nota duas vezes)', () => {
  const nota = lerEnvelopeDeBuffer(gerarXmlFiscal('nfe'));
  const canc = lerEnvelopeDeBuffer(gerarXmlFiscal('evento_cancelamento'));
  assert.equal(canc.status, 'lido', canc.detalhe.motivo);
  assert.equal(canc.subtipo, 'evento');
  assert.equal(canc.detalhe.tp_evento, '110111');
  assert.equal(canc.detalhe.chave_documento, nota.chave_natural);
  assert.notEqual(canc.chave_natural, nota.chave_natural);
});

test('XML truncado ou de versão desconhecida não passa', () => {
  assert.equal(lerEnvelopeDeBuffer(gerarXmlFiscal('nfe', { quebrar: 'truncar' })).status, 'falhou');
  assert.equal(lerEnvelopeDeBuffer(gerarXmlFiscal('cte', { versao: '3.00' })).status, 'versao_desconhecida');
});

test('eSocial e Reinf: Id do evento, versão pelo namespace e competência', () => {
  const es = lerEnvelopeDeBuffer(gerarEvento('esocial'));
  assert.equal(es.status, 'lido', es.detalhe.motivo);
  assert.equal(es.subtipo, 'evtRemun');
  assert.equal(es.versao_leiaute, 'v_S_01_03_00');
  assert.equal(es.periodo_ini, '2025-09-01');
  assert.equal(es.detalhe.raiz_cnpj, '11222333');  // o eSocial identifica pela raiz de 8 dígitos
  const rf = lerEnvelopeDeBuffer(gerarEvento('reinf'));
  assert.equal(rf.status, 'lido', rf.detalhe.motivo);
  assert.equal(rf.cnpj, '11222333000181');
  assert.equal(lerEnvelopeDeBuffer(gerarEvento('esocial', { versao: 'v_S_01_01_00' })).status, 'versao_desconhecida');
  assert.equal(lerEnvelopeDeBuffer(gerarEvento('reinf', { quebrar: 'truncar' })).status, 'falhou');
});

// ---------------------------------------------------------------- zip (G5)
test('o zip do contador abre, e cada arquivo dentro vira um envelope', async () => {
  const zip = await gerarZip([
    { nome: 'ECD_2025.txt', buf: gerarSped('ECD') },
    { nome: 'xml/nota1.xml', buf: gerarXmlFiscal('nfe') },
    { nome: 'retorno.ret', buf: gerarCnab400() },
  ]);
  assert.equal(detectarFamilia(zip).familia, 'zip');
  const entradas = abrirZip(zip);
  assert.equal(entradas.length, 3);
  assert.deepEqual(entradas.map(e => lerEnvelopeDeBuffer(e.buf).familia), ['sped', 'nfe', 'cnab400']);
});

test('zip: zip dentro de zip, zip-bomb e excesso de entradas são recusados COM motivo, nunca somem', async () => {
  const dentro = await gerarZip([{ nome: 'a.txt', buf: Buffer.from('x') }]);
  const bomba = Buffer.alloc(5 * 1024 * 1024, 0x41); // comprime ~1000x
  const zip = await gerarZip([
    { nome: 'interno.zip', buf: dentro },
    { nome: 'bomba.txt', buf: bomba },
    { nome: 'ok.xml', buf: gerarXmlFiscal('nfe') },
  ]);
  const e = abrirZip(zip);
  assert.equal(e.length, 3);
  assert.match(e.find(x => x.nome === 'interno.zip').recusado, /zip dentro de zip/);
  assert.match(e.find(x => x.nome === 'bomba.txt').recusado, /zip-bomb/);
  assert.ok(e.find(x => x.nome === 'ok.xml').buf);
  assert.match(abrirZip(zip, { entradas: 2, bytesPorEntrada: 1e9, bytesTotal: 1e12, razaoMaxima: 1e9 })[0].recusado, /limite de 2/);
  assert.match(abrirZip(zip.subarray(0, 40))[0].recusado, /truncado/);
});

// ---------------------------------------------------------------- volume (G6)
test('arquivo em disco é lido em fluxo: 300 mil linhas, acima do teto de ~150 mil itens do n8n', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'leitor-'));
  try {
    const caminho = join(dir, 'efd_grande.txt');
    const buf = gerarSped('EFD_ICMS_IPI', { linhasDeMovimento: 300000 });
    writeFileSync(caminho, buf);
    const emDisco = await lerEnvelopeDeArquivo(caminho);
    assert.equal(emDisco.status, 'lido', emDisco.detalhe.motivo);
    assert.ok(emDisco.controle_lido > 300000);
    // O caminho em fluxo e o caminho em memória dão o MESMO envelope, hash incluído.
    assert.deepEqual(emDisco, lerEnvelopeDeBuffer(buf));
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

// ---------------------------------------------------------------- achados da revisão independente (13/10/2026)
test('SCP e livro auxiliar são escriturações diferentes: chave própria, nenhuma substitui a outra (G9)', () => {
  const empresa = lerEnvelopeDeBuffer(gerarSped('ECD'));
  const scp = lerEnvelopeDeBuffer(gerarSped('ECD', { scp: '99888777000166' }));
  const auxiliar = lerEnvelopeDeBuffer(gerarSped('ECD', { indEsc: 'A' }));
  assert.equal(scp.cnpj, empresa.cnpj);              // o 0000 da SCP traz o CNPJ do ostensivo
  assert.equal(scp.detalhe.cod_scp, '99888777000166');
  assert.notEqual(scp.chave_natural, empresa.chave_natural);
  assert.notEqual(auxiliar.chave_natural, empresa.chave_natural);
  assert.notEqual(lerEnvelopeDeBuffer(gerarSped('ECF', { scp: '99888777000166' })).chave_natural, lerEnvelopeDeBuffer(gerarSped('ECF')).chave_natural);
});

test('chave com componente ausente não é aceita como lida (juntaria arquivos diferentes)', () => {
  // A ECD se reconhece pela marca LECD, então chega até a identidade e é recusada nela.
  const semCnpj = lerEnvelopeDeBuffer(gerarSped('ECD', { cnpj: '' }));
  assert.equal(semCnpj.status, 'falhou');
  assert.match(semCnpj.detalhe.motivo, /identidade/);
  // A EFD só se distingue PELO CNPJ no 0000: sem ele, nem chega a ser EFD, e também não é lida.
  assert.notEqual(lerEnvelopeDeBuffer(gerarSped('EFD_ICMS_IPI', { cnpj: '' })).status, 'lido');
  assert.equal(lerEnvelopeDeBuffer(gerarOfx({ semDatas: true })).status, 'falhou');
  const cartao = lerEnvelopeDeBuffer(gerarOfx({ cartao: true }));
  assert.equal(cartao.status, 'lido', cartao.detalhe.motivo);
  assert.equal(cartao.chave_natural, 'cartao|4111-CARTAO|2025-01-01|2025-01-31');
  const nfeSemId = lerEnvelopeDeBuffer(gerarXmlFiscal('nfe', { semId: true }));
  assert.equal(nfeSemId.status, 'falhou');
  assert.match(nfeSemId.detalhe.motivo, /identificador/);
});

test('depois do 9999: assinatura digital é aceita, um segundo SPED não', () => {
  const assinado = Buffer.concat([gerarSped('ECD'), Buffer.from([0x30, 0x82, 0x0a, 0x0d, 0xff, 0x00, 0x41])]);
  const a = lerEnvelopeDeBuffer(assinado);
  assert.equal(a.status, 'lido', a.detalhe.motivo);
  assert.ok(a.detalhe.linhas_apos_9999 >= 1);
  const dois = lerEnvelopeDeBuffer(Buffer.concat([gerarSped('ECD'), gerarSped('ECD', { cnpj: '99888777000166' })]));
  assert.equal(dois.status, 'falhou');
  assert.match(dois.detalhe.motivo, /concatenados/);
});

test('contagem de controle vazia é ausência (null), nunca zero', () => {
  const buf = Buffer.from(gerarSped('ECF').toString('latin1').replace(/\r\n\|9999\|\d+\|/, '\r\n|9999||'), 'latin1');
  const e = lerEnvelopeDeBuffer(buf);
  assert.equal(e.controle_declarado, null);
  assert.equal(e.status, 'falhou');
});

test('memória e fluxo dão o MESMO envelope com LF, CRLF, CR solto e sem quebra final', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'leitor-q-'));
  try {
    for (const [nome, base] of [['sped', gerarSped('EFD_CONTRIBUICOES')], ['ofx', gerarOfx()]]) {
      const txt = base.toString('latin1').replace(/\r\n/g, '\n');
      const variantes = { lf: txt, crlf: txt.replace(/\n/g, '\r\n'), cr: txt.replace(/\n/g, '\r'), sem_final: txt.replace(/\n$/, '') };
      for (const [v, conteudo] of Object.entries(variantes)) {
        const buf = Buffer.from(conteudo, 'latin1');
        const caminho = join(dir, `${nome}-${v}.txt`);
        writeFileSync(caminho, buf);
        const mem = lerEnvelopeDeBuffer(buf);
        assert.equal(mem.status, 'lido', `${nome} ${v}: ${mem.detalhe.motivo}`);
        assert.deepEqual(await lerEnvelopeDeArquivo(caminho), mem, `${nome} ${v}`);
      }
    }
  } finally { rmSync(dir, { recursive: true, force: true }); }
});

test('relatório de largura fixa não vira CNAB (falso positivo tiraria o documento da IA)', () => {
  const l150 = (t) => t.padEnd(150, ' ');
  assert.equal(detectarFamilia(Buffer.from([l150('ADMINISTRATIVO RELATORIO DE VENDAS'), l150('ADMINISTRATIVO PAGINA 2')].join('\n'))).familia, null);
  const l240 = (t) => t.padEnd(240, ' ');
  // Passa em banco numérico, lote 0000 e tipo 0 na posição 8; só a segunda linha
  // (que não é header de lote) separa o relatório de um CNAB.
  assert.equal(detectarFamilia(Buffer.from([l240('12300000RELATORIO'), l240('12300000CONTINUA')].join('\n'))).familia, null);
  // Linhas de tamanhos diferentes não são CNAB, mesmo com o header perfeito.
  const cnab = gerarCnab240().toString('latin1').split('\r\n');
  assert.equal(detectarFamilia(Buffer.from([cnab[0], cnab[1].slice(0, 239)].join('\r\n'), 'latin1')).familia, null);
});

test('CNAB 240 de pessoa física: o CPF não é gravado como CNPJ', () => {
  const e = lerEnvelopeDeBuffer(gerarCnab240({ inscricaoCpf: true }));
  assert.equal(e.status, 'lido', e.detalhe.motivo);
  assert.equal(e.cnpj, null);
});

test('NF-e emitida por CPF (produtor rural): o CNPJ do destinatário NÃO vira o do emitente', () => {
  const e = lerEnvelopeDeBuffer(gerarXmlFiscal('nfe', { emitenteCpf: true }));
  assert.equal(e.cnpj, null);
  assert.equal(e.detalhe.cpf_emitente, '12345678909');
});

test('eSocial: a competência vai do primeiro ao último dia do mês', () => {
  const e = lerEnvelopeDeBuffer(gerarEvento('esocial'));
  assert.equal(e.periodo_ini, '2025-09-01');
  assert.equal(e.periodo_fim, '2025-09-30');
});

test('zip: tamanho mentiroso, entrada cifrada e entradas sobrepostas são recusados com motivo', async () => {
  const nota = gerarXmlFiscal('nfe');
  const mentiroso = abrirZip(await gerarZip([{ nome: 'grande.xml', buf: Buffer.alloc(20000, 0x20), mentirTamanho: true }]));
  // O motivo prova que a descompressão PAROU no tamanho declarado, e não que
  // inflou tudo e só depois comparou (o que custaria até 512 MB por entrada).
  assert.match(mentiroso[0].recusado, /passa do tamanho declarado/);
  const cifrado = abrirZip(await gerarZip([{ nome: 'senha.xml', buf: nota, cifrado: true }]));
  assert.match(cifrado[0].recusado, /cifrada/);
  const sobreposto = abrirZip(await gerarZip([{ nome: 'a.xml', buf: nota }], { sobrepor: true }));
  assert.equal(sobreposto.length, 2);
  assert.ok(sobreposto[0].buf);
  assert.match(sobreposto[1].recusado, /sobreposto/);
});
