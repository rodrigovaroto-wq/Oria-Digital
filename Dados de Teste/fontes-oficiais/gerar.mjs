// GERADORES SINTÉTICOS das famílias de arquivo oficial (Espec. 12, G15).
//
// Cada arquivo gerado aqui é FICTÍCIO e diz isso no próprio conteúdo. Eles servem
// para provar que o leitor de envelope é coerente: conta o que o arquivo declara,
// acusa o truncado, recusa a versão desconhecida. Eles NÃO provam que o leitor lê
// um arquivo real (regra 4 do CLAUDE.md): as posições vêm do mesmo registro de
// leiautes que o leitor usa (`Leitor/lib/leiautes.mjs`). A prova contra arquivo real
// é o aceite de cada onda da F2T, com amostras de 3 mandatos.
//
// Determinísticos: mesma entrada, mesmos bytes. As opções `quebrar` produzem os
// defeitos que o leitor tem de acusar, e cada uma corresponde a um teste.

const CNPJ = '11222333000181';
// Acentuada de propósito: SPED e CNAB são latin1, e o teste confere que o nome
// chega inteiro (decodificado como UTF-8, "AÇÚCAR" vira "A��CAR").
const NOME = 'AÇÚCAR SINTÉTICO LTDA (fictícia)';

const pad = (v, n, c = ' ', esq = false) => { const s = String(v); return s.length >= n ? s.slice(0, n) : esq ? c.repeat(n - s.length) + s : s + c.repeat(n - s.length); };
const num = (v, n) => pad(v, n, '0', true);

/**
 * SPED sintético. subtipo: ECD | ECF | EFD_ICMS_IPI | EFD_CONTRIBUICOES.
 * opções: versao, retificadora, linhasDeMovimento, quebrar: 'truncar' | 'divergir_9999' | 'divergir_9900'
 */
export function gerarSped(subtipo, { versao, retificadora = false, linhasDeMovimento = 10, quebrar = null, ini = '01012025', fim = '31122025', cnpj = CNPJ, scp = '', indEsc = 'G' } = {}) {
  const l = [];
  // Campo a campo, na ordem do Guia Prático, para a posição de cada um ser legível.
  const linha = (campos) => '|' + campos.join('|') + '|';
  // ECD: 0000 LECD DT_INI DT_FIN NOME CNPJ UF IE COD_MUN IM IND_SIT_ESP IND_SIT_INI_PER IND_NIRE IND_FIN_ESC COD_HASH_SUB IND_GRANDE_PORTE TIP_ECD COD_SCP ...
  if (subtipo === 'ECD') l.push(linha(['0000', 'LECD', ini, fim, NOME, cnpj, 'SP', '', '3550308', '', '0', '0', '0', retificadora ? '1' : '0', '', '0', scp ? '2' : '0', scp, 'N', 'N', '0', '0', '']));
  // ECF: 0000 LECF COD_VER CNPJ NOME IND_SIT_INI_PER SIT_ESPECIAL PAT_REMAN_CIS DT_SIT_ESP DT_INI DT_FIN RETIFICADORA NUM_REC TIP_ECF COD_SCP
  if (subtipo === 'ECF') l.push(linha(['0000', 'LECF', versao ?? '0011', cnpj, NOME, '0', '0', '', '', ini, fim, retificadora ? 'S' : 'N', '', scp ? '2' : '0', scp]));
  if (subtipo === 'EFD_ICMS_IPI') l.push(`|0000|${versao ?? '019'}|${retificadora ? '1' : '0'}|${ini}|${fim}|${NOME}|${cnpj}||SP|111111111111|3550308|||A|0|`);
  if (subtipo === 'EFD_CONTRIBUICOES') l.push(`|0000|${versao ?? '006'}|${retificadora ? '1' : '0'}|||${ini}|${fim}|${NOME}|${cnpj}|SP|3550308||00|0|`);
  // Acentuação de propósito: o SPED é latin1, e o teste confere que "AÇÚCAR" não corrompe.
  l.push('|0001|0|');
  if (subtipo === 'ECD') l.push(`|I010|${indEsc}|${versao ?? '9.00'}|`);
  for (let i = 0; i < linhasDeMovimento; i++) l.push(`|C990|${i + 1}|AÇÚCAR E ÁLCOOL ${i},50|`);
  const regs = {};
  for (const x of l) { const r = x.split('|')[1]; regs[r] = (regs[r] || 0) + 1; }
  const n9900 = Object.keys(regs).length + 2; // + 9900 e 9999
  const bloco9 = Object.entries(regs).map(([r, n]) => `|9900|${r}|${n}|`);
  bloco9.push(`|9900|9900|${n9900}|`, '|9900|9999|1|');
  const total = l.length + bloco9.length + 1;
  if (quebrar === 'divergir_9900') bloco9[0] = bloco9[0].replace(/\|(\d+)\|$/, (_, n) => `|${Number(n) + 1}|`);
  l.push(...bloco9);
  if (quebrar !== 'truncar') l.push(`|9999|${quebrar === 'divergir_9999' ? total + 7 : total}|`);
  return Buffer.from(l.join('\r\n') + '\r\n', 'latin1');
}

/** CNAB 240 sintético (cobrança: segmentos P/Q; extrato: E). quebrar: 'truncar' | 'divergir' | 'linha_curta' */
export function gerarCnab240({ servico = 'cobranca', titulos = 3, quebrar = null, inscricaoCpf = false } = {}) {
  const banco = '341';
  const linhas = [];
  let h = num(banco, 3) + '0000' + '0' + pad('', 9) + (inscricaoCpf ? '1' : '2') + num(inscricaoCpf ? '12345678909' : CNPJ, 14) + pad('', 20) + pad('', 20) + pad(NOME, 30) + pad('BANCO SINTETICO', 30) + pad('', 10) + '2' + '13102025' + '120000';
  linhas.push(pad(h, 240));
  linhas.push(pad(num(banco, 3) + '0001' + '1', 240));
  const segs = servico === 'extrato' ? ['E'] : ['P', 'Q'];
  let seq = 1;
  for (let i = 0; i < titulos; i++) for (const s of segs) linhas.push(pad(num(banco, 3) + '0001' + '3' + num(seq++, 5) + s, 240));
  linhas.push(pad(num(banco, 3) + '0001' + '5' + pad('', 9) + num(linhas.length, 6), 240));
  const total = linhas.length + 1;
  linhas.push(pad(num(banco, 3) + '9999' + '9' + pad('', 9) + num(1, 6) + num(quebrar === 'divergir' ? total + 2 : total, 6), 240));
  if (quebrar === 'truncar') linhas.pop();
  if (quebrar === 'linha_curta') linhas[2] = linhas[2].slice(0, 200);
  return Buffer.from(linhas.join('\r\n') + '\r\n', 'latin1');
}

/** CNAB 400 sintético (retorno de cobrança). quebrar: 'buraco_na_sequencia' | 'truncar' */
export function gerarCnab400({ titulos = 3, quebrar = null } = {}) {
  const linhas = [];
  const linha = (corpo, seq) => pad(corpo, 394) + num(seq, 6);
  linhas.push(linha('02RETORNO01COBRANCA       ' + pad(NOME, 30) + pad('', 20) + '341' + pad('BANCO SINTETICO', 15), 1));
  for (let i = 0; i < titulos; i++) linhas.push(linha('1' + '02' + num(CNPJ, 14) + ' TITULO SINTETICO ' + i, i + 2));
  linhas.push(linha('9', titulos + 2));
  if (quebrar === 'buraco_na_sequencia') linhas.splice(2, 1, linha('1 TITULO TROCADO', 99));
  if (quebrar === 'truncar') linhas.pop();
  return Buffer.from(linhas.join('\r\n') + '\r\n', 'latin1');
}

/** CNAB 150 sintético (débito automático). */
export function gerarCnab150({ debitos = 3, quebrar = null } = {}) {
  const linhas = [pad('A1' + pad('CONVENIO', 20) + pad(NOME, 20) + '341', 150)];
  for (let i = 0; i < debitos; i++) linhas.push(pad('E' + pad('CLIENTE ' + i, 25), 150));
  const total = linhas.length + 1;
  linhas.push(pad('Z' + num(quebrar === 'divergir' ? total + 1 : total, 6), 150));
  return Buffer.from(linhas.join('\r\n') + '\r\n', 'latin1');
}

/** OFX sintético: 1.x (SGML, latin1) ou 2.x (XML). quebrar: 'truncar' */
export function gerarOfx({ versao = '102', transacoes = 4, quebrar = null, cartao = false, semDatas = false } = {}) {
  const trns = Array.from({ length: transacoes }, (_, i) => `<STMTTRN><TRNTYPE>DEBIT<DTPOSTED>2025010${(i % 9) + 1}<TRNAMT>-1${i}.50<FITID>SINT${i}<MEMO>PAGAMENTO FICTÍCIO ${i}</STMTTRN>`).join('\n');
  const corpo = `<OFX>\n<BANKMSGSRSV1><STMTTRNRS><STMTRS><CURDEF>BRL\n${cartao ? '<CCACCTFROM><ACCTID>4111-CARTAO</CCACCTFROM>' : '<BANKACCTFROM><BANKID>0341<ACCTID>12345-6<ACCTTYPE>CHECKING</BANKACCTFROM>'}\n<BANKTRANLIST>${semDatas ? '' : '<DTSTART>20250101<DTEND>20250131'}\n${trns}\n</BANKTRANLIST><LEDGERBAL><BALAMT>676.00<DTASOF>20250131</LEDGERBAL>\n</STMTRS></STMTTRNRS></BANKMSGSRSV1>\n</OFX>\n`;
  const cab = versao.startsWith('2')
    ? `<?xml version="1.0" encoding="UTF-8"?>\n<?OFX OFXHEADER="200" VERSION="${versao}" SECURITY="NONE" OLDFILEUID="NONE" NEWFILEUID="NONE"?>\n`
    : `OFXHEADER:100\nDATA:OFXSGML\nVERSION:${versao}\nSECURITY:NONE\nENCODING:USASCII\nCHARSET:1252\nCOMPRESSION:NONE\nOLDFILEUID:NONE\nNEWFILEUID:NONE\n\n`;
  let txt = cab + corpo;
  if (quebrar === 'truncar') txt = txt.slice(0, txt.indexOf('</OFX>'));
  return Buffer.from(txt, versao.startsWith('2') ? 'utf8' : 'latin1');
}

const CHAVE = '35251011222333000181550010000000011000000010';

/** NF-e/CT-e/MDF-e/NFS-e sintéticos. tipo: nfe | cte | mdfe | nfse | evento_cancelamento. quebrar: 'truncar' */
export function gerarXmlFiscal(tipo, { versao, quebrar = null, emitenteCpf = false, semId = false } = {}) {
  const ns = { nfe: 'http://www.portalfiscal.inf.br/nfe', cte: 'http://www.portalfiscal.inf.br/cte', mdfe: 'http://www.portalfiscal.inf.br/mdfe', nfse: 'http://www.sped.fazenda.gov.br/nfse' };
  let x;
  if (tipo === 'nfe') x = `<?xml version="1.0" encoding="UTF-8"?><nfeProc xmlns="${ns.nfe}" versao="4.00"><NFe><infNFe versao="${versao ?? '4.00'}"${semId ? '' : ` Id="NFe${CHAVE}"`}><ide><dhEmi>2025-10-01T10:00:00-03:00</dhEmi></ide><emit>${emitenteCpf ? '<CPF>12345678909</CPF>' : `<CNPJ>${CNPJ}</CNPJ>`}<xNome>${NOME}</xNome></emit><dest><CNPJ>99888777000166</CNPJ></dest></infNFe></NFe><protNFe><infProt><cStat>100</cStat></infProt></protNFe></nfeProc>`;
  if (tipo === 'evento_cancelamento') x = `<?xml version="1.0" encoding="UTF-8"?><procEventoNFe xmlns="${ns.nfe}" versao="1.00"><evento versao="1.00"><infEvento Id="ID110111${CHAVE}01"><CNPJ>${CNPJ}</CNPJ><chNFe>${CHAVE}</chNFe><tpEvento>110111</tpEvento><nSeqEvento>1</nSeqEvento></infEvento></evento></procEventoNFe>`;
  if (tipo === 'cte') x = `<?xml version="1.0" encoding="UTF-8"?><cteProc xmlns="${ns.cte}" versao="4.00"><CTe><infCte versao="${versao ?? '4.00'}" Id="CTe${CHAVE}"><ide><dhEmi>2025-10-02T08:00:00-03:00</dhEmi></ide><emit><CNPJ>${CNPJ}</CNPJ></emit><infDoc><infNFe><chave>${CHAVE}</chave></infNFe></infDoc></infCte></CTe></cteProc>`;
  if (tipo === 'mdfe') x = `<?xml version="1.0" encoding="UTF-8"?><mdfeProc xmlns="${ns.mdfe}" versao="3.00"><MDFe><infMDFe versao="${versao ?? '3.00'}" Id="MDFe${CHAVE}"><ide><dhEmi>2025-10-02T07:00:00-03:00</dhEmi></ide><emit><CNPJ>${CNPJ}</CNPJ></emit></infMDFe></MDFe></mdfeProc>`;
  if (tipo === 'nfse') x = `<?xml version="1.0" encoding="UTF-8"?><NFSe xmlns="${ns.nfse}" versao="1.00"><infNFSe versao="${versao ?? '1.00'}" Id="NFS${CHAVE}000"><dhProc>2025-10-03T09:00:00-03:00</dhProc><emit><CNPJ>${CNPJ}</CNPJ></emit><DPS><infDPS><dhEmi>2025-10-03T09:00:00-03:00</dhEmi></infDPS></DPS></infNFSe></NFSe>`;
  if (quebrar === 'truncar') x = x.slice(0, x.length - 20);
  return Buffer.from(x, 'utf8');
}

/** Evento eSocial ou Reinf sintético. */
export function gerarEvento(familia, { evento = familia === 'esocial' ? 'evtRemun' : 'evtServTom', versao, quebrar = null } = {}) {
  const v = versao ?? (familia === 'esocial' ? 'v_S_01_03_00' : 'v2_01_02');
  const ns = familia === 'esocial' ? `http://www.esocial.gov.br/schema/evt/${evento}/${v}` : `http://www.reinf.esocial.gov.br/schemas/${evento}/${v}`;
  const ide = familia === 'esocial' ? `<ideEmpregador><tpInsc>1</tpInsc><nrInsc>${CNPJ.slice(0, 8)}</nrInsc></ideEmpregador>` : `<ideContri><tpInsc>1</tpInsc><nrInsc>${CNPJ}</nrInsc></ideContri>`;
  const raiz = familia === 'esocial' ? 'eSocial' : 'Reinf';
  let x = `<?xml version="1.0" encoding="UTF-8"?><${raiz} xmlns="${ns}"><${evento} Id="ID1${CNPJ}20251013120000000${familia === 'esocial' ? '01' : '02'}"><ideEvento><perApur>2025-09</perApur></ideEvento>${ide}</${evento}></${raiz}>`;
  if (quebrar === 'truncar') x = x.slice(0, x.length - 12);
  return Buffer.from(x, 'utf8');
}

/** Zip "stored" (sem compressão) ou deflate, para testar a abertura e os limites. */
/** opções por entrada: `mentirTamanho` (declara 1/10 do tamanho real), `cifrado` (bit de senha);
 *  `sobrepor`: o diretório central ganha uma 2ª entrada apontando para os dados da 1ª. */
export async function gerarZip(entradas, { deflate = true, sobrepor = false } = {}) {
  const { deflateRawSync, crc32 } = await import('node:zlib');
  const locais = [], centrais = [];
  let off = 0;
  for (const { nome, buf, mentirTamanho = false, cifrado = false } of entradas) {
    const n = Buffer.from(nome, 'utf8');
    const dados = deflate ? deflateRawSync(buf) : buf;
    const crc = crc32(buf) >>> 0;
    const lh = Buffer.alloc(30);
    lh.writeUInt32LE(0x04034b50, 0); lh.writeUInt16LE(20, 4); lh.writeUInt16LE(0x800, 6); lh.writeUInt16LE(deflate ? 8 : 0, 8);
    lh.writeUInt32LE(crc, 14); lh.writeUInt32LE(dados.length, 18); lh.writeUInt32LE(buf.length, 22); lh.writeUInt16LE(n.length, 26);
    const ch = Buffer.alloc(46);
    ch.writeUInt32LE(0x02014b50, 0); ch.writeUInt16LE(20, 4); ch.writeUInt16LE(20, 6); ch.writeUInt16LE(0x800, 8); ch.writeUInt16LE(deflate ? 8 : 0, 10);
    ch.writeUInt32LE(crc, 16); ch.writeUInt32LE(dados.length, 20); ch.writeUInt32LE(mentirTamanho ? Math.ceil(buf.length / 10) : buf.length, 24); ch.writeUInt16LE(n.length, 28); ch.writeUInt32LE(off, 42);
    if (cifrado) ch.writeUInt16LE(0x801, 8);
    locais.push(lh, n, dados); centrais.push(ch, n);
    off += 30 + n.length + dados.length;
  }
  if (sobrepor) { const copia = Buffer.from(centrais[0]); centrais.push(copia, Buffer.from(centrais[1])); }
  const nTotal = centrais.length / 2;
  const cd = Buffer.concat(centrais);
  const fim = Buffer.alloc(22);
  fim.writeUInt32LE(0x06054b50, 0); fim.writeUInt16LE(nTotal, 8); fim.writeUInt16LE(nTotal, 10); fim.writeUInt32LE(cd.length, 12); fim.writeUInt32LE(off, 16);
  return Buffer.concat([...locais, cd, fim]);
}
