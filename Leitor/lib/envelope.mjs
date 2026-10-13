// O ENVELOPE DE UM ARQUIVO OFICIAL: o que é, de quem, de quando, quantos registros
// ele DECLARA ter e quantos foram LIDOS (Espec. 12 §8, passos 1 a 3).
//
// Por que contar, e não só ler: um arquivo truncado no upload (o teto de ~4,5 MB da
// borda da Vercel já cortou lote em 13/09/2026) é lido sem erro nenhum — só com
// menos linhas. Os formatos oficiais trazem a própria contagem (o 9999 do SPED, o
// trailer do CNAB), e é ela que separa "li tudo" de "li o que chegou" (regra 7).
// Formato sem contagem declarada (OFX) é dito como tal: `sem_controle_no_formato`.
//
// A saída tem os nomes das colunas de `arquivo_oficial` (migration 0206), para o
// CLI gravar sem tradução. Este arquivo NÃO lê o conteúdo registro a registro (os
// lançamentos, as notas, a folha): isso é das ondas 1 a 5 da F2T.
//
// O leitor consome LINHAS, uma de cada vez, e guarda só contadores: a memória não
// cresce com o tamanho do arquivo. É o oposto do merge do n8n, que estoura a pilha
// com ~125–150 mil itens (roadmap, 17/09/2026, G6) — e é por isso que este leitor
// roda fora do n8n (D12.9).

import { createHash } from 'node:crypto';
import { createReadStream } from 'node:fs';
import { open } from 'node:fs/promises';
import { createInterface } from 'node:readline';
import { SPED, XML, CNAB, OFX, LEITOR_VERSAO } from './leiautes.mjs';
import { dataDDMMAAAA, dataAAAAMMDD, cnpj, posicao, inteiro } from './campos.mjs';
import { detectarFamilia } from './familia.mjs';

function envelopeBase(familia, subtipo, hash) {
  return {
    familia, subtipo: subtipo ?? null, versao_leiaute: null, hash_sha256: hash,
    cnpj: null, periodo_ini: null, periodo_fim: null, chave_natural: null,
    retificadora: false, controle_tipo: 'contagem_declarada',
    controle_declarado: null, controle_lido: null, status: 'falhou',
    detalhe: {}, leitor_versao: LEITOR_VERSAO,
  };
}

/** A mesma quebra de linha nos dois caminhos (memória e fluxo). O `readline` do
 * fluxo quebra em \r\n, \n e \r solto; um `split('\n')` não quebraria no \r solto
 * e o MESMO arquivo daria envelopes diferentes conforme viesse do disco ou de um zip. */
export const QUEBRA = /\r\n|\n|\r/;

/** Chave natural com um componente ausente junta arquivos diferentes na mesma
 * vigência ("null|ECD|..." de duas empresas): não é aceita como lida. */
function exigirChaveCompleta(env, partes, motivo) {
  if (env.status === 'lido' && partes.some(p => p === null || p === undefined || p === '')) {
    env.status = 'falhou';
    env.detalhe.motivo = motivo;
  }
}

/** Status a partir das contagens: a regra é a mesma para toda família que declara contagem. */
function statusPorContagem(env) {
  if (env.controle_declarado === null) {
    env.status = 'falhou';
    env.detalhe.motivo = env.detalhe.motivo || 'o arquivo não traz o registro de controle: provavelmente truncado';
  } else {
    env.status = env.controle_declarado === env.controle_lido ? 'lido' : 'controle_divergente';
  }
}

// ---------------------------------------------------------------- SPED
function leitorSped(env) {
  const porRegistro = {};
  const declaradoPorRegistro = {};
  let total = 0, l0000 = null, i010 = null, qtdLin = null, aposFim = 0, fechado = false, outroSped = false;
  return {
    linha(linha) {
      // Depois do 9999 só pode vir o bloco da assinatura digital (ECD assinada),
      // que não é registro. Um NOVO |0000| ali é um segundo SPED concatenado, e
      // aceitar o primeiro como "lido" esconderia o segundo inteiro.
      if (fechado) { if (linha.trim() !== '') aposFim++; if (linha.startsWith('|0000|')) outroSped = true; return; }
      if (linha.trim() === '') return;
      total++;
      const c = linha.split('|');
      const reg = c[1];
      porRegistro[reg] = (porRegistro[reg] || 0) + 1;
      if (reg === '0000' && !l0000) l0000 = c;
      else if (reg === 'I010') i010 = c;
      else if (reg === '9900') declaradoPorRegistro[c[2]] = inteiro(c[3]);
      // O 9999 fecha a escrituração. O que vem depois (a ECD assinada traz o bloco
      // da assinatura digital) não é registro e não entra na contagem.
      else if (reg === '9999') { qtdLin = inteiro(c[2]); fechado = true; }
    },
    fim() {
      const lay = SPED[env.subtipo];
      if (!lay || !l0000) {
        env.status = 'familia_desconhecida';
        env.detalhe.motivo = 'registro 0000 de leiaute SPED não reconhecido';
        return;
      }
      env.versao_leiaute = lay.versao.registro === 'I010' ? (i010 ? i010[lay.versao.indice] ?? null : null) : l0000[lay.versao.indice] ?? null;
      env.cnpj = cnpj(l0000[lay.cnpj]);
      env.periodo_ini = dataDDMMAAAA(l0000[lay.dtIni]);
      env.periodo_fim = dataDDMMAAAA(l0000[lay.dtFim]);
      env.retificadora = lay.retificadora.valores.includes(l0000[lay.retificadora.indice]);
      // SCP e livro entram na identidade (ver leiautes.mjs). Ausentes são legítimos
      // (a empresa não é SCP, o livro é o principal), e por isso viram '-', nunca null.
      const scp = lay.scp ? (l0000[lay.scp] || '').trim() || '-' : '-';
      const esc = lay.indEsc ? ((i010 && i010[lay.indEsc.indice]) || '').trim() || '-' : '-';
      env.chave_natural = [env.cnpj, env.subtipo, env.periodo_ini, env.periodo_fim, scp, esc].join('|');
      env.detalhe.cod_scp = scp === '-' ? null : scp;
      env.detalhe.ind_esc = esc === '-' ? null : esc;
      // A razão social é o primeiro texto livre do arquivo, e é por ela que a
      // entidade do caso se confere (F1). Ela também é o que acusa uma decodificação
      // errada: o resto do envelope é número e não muda com a codificação.
      env.detalhe.nome = l0000[lay.nome] ?? null;
      env.controle_declarado = qtdLin;
      env.controle_lido = total;
      // O 9900 declara a contagem de CADA tipo de registro. Uma divergência aqui
      // com o total batendo é um arquivo editado à mão: registro trocado de tipo.
      const divergencias = Object.entries(declaradoPorRegistro)
        .filter(([reg, n]) => (porRegistro[reg] || 0) !== n)
        .map(([reg, n]) => ({ registro: reg, declarado: n, lido: porRegistro[reg] || 0 }));
      env.detalhe = { ...env.detalhe, por_registro: porRegistro, divergencias_9900: divergencias, linhas_apos_9999: aposFim };
      statusPorContagem(env);
      if (env.status === 'lido' && divergencias.length) {
        // O total bate e a contagem por tipo não: as contagens ficam como estão
        // (são verdadeiras), e o arquivo NÃO é aceito como lido. 'falhou', e não
        // 'controle_divergente', porque divergente na tabela significa total
        // diferente, e aqui o total é igual.
        env.status = 'falhou';
        env.detalhe.motivo = `o total do 9999 bate, mas a contagem por registro do 9900 não (${divergencias.length} registro(s)): arquivo editado à mão ou corrompido`;
      }
      if (outroSped) {
        env.status = 'falhou';
        env.detalhe.motivo = 'há um segundo registro 0000 depois do 9999: dois SPEDs concatenados num arquivo só. Separe os arquivos';
      }
      exigirChaveCompleta(env, [env.cnpj, env.periodo_ini, env.periodo_fim], 'o 0000 não traz CNPJ e período válidos: sem eles a escrituração não tem identidade e poderia substituir a de outra empresa');
      if (env.versao_leiaute && !lay.versoes.includes(env.versao_leiaute)) {
        env.detalhe.motivo = `versão ${env.versao_leiaute} de ${env.subtipo} fora do registro de leiautes (conhecidas: ${lay.versoes.join(', ')})`;
        env.status = 'versao_desconhecida';
      }
    },
  };
}

// ---------------------------------------------------------------- CNAB
function leitorCnab(env, familia) {
  const lay = CNAB[familia];
  const porTipo = {}, porSegmento = {};
  let total = 0, foraDoTamanho = 0, header = null, trailer = null, quebraSequencia = 0;
  return {
    linha(linha) {
      if (linha.trim() === '') return;
      total++;
      if (linha.length !== lay.tamanho) foraDoTamanho++;
      const tipo = posicao(linha, ...lay.tipoRegistro);
      porTipo[tipo] = (porTipo[tipo] || 0) + 1;
      if (familia === 'cnab240' && tipo === '3') {
        const s = posicao(linha, ...lay.segmento);
        porSegmento[s] = (porSegmento[s] || 0) + 1;
      }
      if (!header) header = linha;
      if ((familia === 'cnab240' && tipo === '9') || (familia === 'cnab400' && tipo === '9') || (familia === 'cnab150' && tipo === 'Z')) trailer = linha;
      // O CNAB 400 numera cada linha: um buraco na numeração é uma linha perdida
      // que a contagem total sozinha não acusa se outra sobrar no lugar.
      if (familia === 'cnab400' && inteiro(posicao(linha, ...lay.sequencial)) !== total) quebraSequencia++;
    },
    fim() {
      env.chave_natural = env.hash_sha256;
      env.controle_lido = total;
      if (trailer) {
        env.controle_declarado = familia === 'cnab400'
          ? inteiro(posicao(trailer, ...lay.sequencial))
          : inteiro(posicao(trailer, ...lay.trailerQtdRegistros));
      }
      // Posição 18 é o tipo de inscrição: 2 = CNPJ, 1 = CPF. Um CPF com zeros à
      // esquerda tem 14 posições e passaria por CNPJ.
      if (familia === 'cnab240' && header && posicao(header, 18, 18) === '2') env.cnpj = cnpj(posicao(header, ...lay.cnpjHeader));
      env.versao_leiaute = familia;
      const segs = Object.keys(porSegmento);
      env.subtipo = familia === 'cnab240'
        ? (segs.some(s => 'PQRSTUY'.includes(s)) ? 'cobranca' : segs.some(s => 'ABCJNOW'.includes(s)) ? 'pagamentos' : segs.includes('E') ? 'extrato' : null)
        : familia === 'cnab400' ? (header && posicao(header, ...lay.operacao) === '2' ? 'retorno' : 'remessa')
        : 'debito_automatico';
      env.detalhe = { banco: header ? posicao(header, ...lay.banco) : null, por_tipo_registro: porTipo, por_segmento: porSegmento, linhas_fora_do_tamanho: foraDoTamanho, quebras_de_sequencia: quebraSequencia };
      statusPorContagem(env);
      if (env.status === 'lido' && (foraDoTamanho || quebraSequencia)) {
        env.status = 'falhou';
        env.detalhe.motivo = `${foraDoTamanho} linha(s) fora de ${lay.tamanho} posições e ${quebraSequencia} quebra(s) de sequência: o arquivo foi alterado ou corrompido`;
      }
    },
  };
}

// ---------------------------------------------------------------- OFX
function leitorOfx(env) {
  let transacoes = 0, versao = null, banco = null, conta = null, ini = null, fim = null, saldo = false, fechado = false, cartao = false;
  const valor = (l, tag) => { const m = l.match(new RegExp(`<${tag}>\\s*([^<\\r\\n]+)`, 'i')); return m ? m[1].trim() : null; };
  return {
    linha(l) {
      const v = l.match(/^VERSION:(\d+)/) || l.match(/OFXHEADER="\d+"[^>]*VERSION="(\d+)"/);
      if (v && !versao) versao = v[1];
      transacoes += (l.match(/<STMTTRN>/gi) || []).length;
      banco = banco || valor(l, 'BANKID');
      conta = conta || valor(l, 'ACCTID');
      ini = ini || valor(l, 'DTSTART');
      fim = fim || valor(l, 'DTEND');
      if (/<LEDGERBAL>/i.test(l)) saldo = true;
      if (/<CCACCTFROM>/i.test(l)) cartao = true;
      if (/<\/OFX>/i.test(l)) fechado = true;
    },
    fim() {
      env.versao_leiaute = versao;
      env.periodo_ini = dataAAAAMMDD(ini);
      env.periodo_fim = dataAAAAMMDD(fim);
      // Extrato de cartão (CCACCTFROM) não tem BANKID: a conta do cartão é a identidade.
      const instituicao = banco || (cartao ? 'cartao' : null);
      env.chave_natural = [instituicao, conta, env.periodo_ini, env.periodo_fim].join('|');
      // O OFX não declara quantos lançamentos tem. O que ele tem é DTSTART–DTEND
      // e o saldo do banco, que a onda 2 usa para conciliar. Aqui: dizer que não há
      // contagem, e exigir que o arquivo feche (</OFX>), senão está truncado.
      env.controle_tipo = 'sem_controle_no_formato';
      env.controle_lido = transacoes;
      env.detalhe = { banco, conta, tem_saldo_do_banco: saldo, fechado };
      if (!fechado) { env.status = 'falhou'; env.detalhe.motivo = 'o arquivo não fecha com </OFX>: truncado'; }
      else if (!OFX.versoes.includes(versao)) { env.status = 'versao_desconhecida'; env.detalhe.motivo = `versão OFX ${versao} fora do registro de leiautes`; }
      else env.status = 'lido';
      exigirChaveCompleta(env, [instituicao, conta, env.periodo_ini, env.periodo_fim], 'o OFX não traz instituição, conta e período (DTSTART/DTEND): sem eles dois extratos diferentes se confundem');
    },
  };
}

// ---------------------------------------------------------------- XML (NF-e, CT-e, MDF-e, NFS-e, eSocial, Reinf)
// Um XML oficial é UM documento (uma nota, um evento). Não há contagem a conferir:
// o controle é ele estar inteiro, isto é, fechar o elemento raiz que abriu.
function lerXml(env, texto) {
  const fam = env.familia;
  env.controle_tipo = 'documento_unico';
  const raiz = (texto.replace(/^﻿/, '').replace(/<\?xml[^>]*\?>/, '').match(/<([A-Za-z][\w:.-]*)/) || [])[1];
  const fechado = raiz ? new RegExp(`</${raiz}>\\s*$`).test(texto.trimEnd()) : false;
  const tag = (nome, base = texto) => {
    const m = base.match(new RegExp(`<${nome}>([^<]+)</${nome}>`));
    return m ? m[1] : null;
  };
  // O conteúdo de um bloco (<emit>…</emit>). Procurar o CNPJ "depois de <emit>"
  // pegaria o do DESTINATÁRIO quando o emitente é pessoa física (produtor rural,
  // que emite por CPF).
  const bloco = (nome) => { const m = texto.match(new RegExp(`<${nome}>([\\s\\S]*?)</${nome}>`)); return m ? m[1] : null; };
  if (fam === 'esocial' || fam === 'reinf') {
    const ns = texto.match(fam === 'esocial' ? /\/evt\/evt\w+\/(v_S_\d\d_\d\d_\d\d)"/ : /\/schemas\/evt\w+\/(v\d+_\d+_\d+)"/);
    env.versao_leiaute = ns ? ns[1] : null;
    const id = texto.match(/<evt\w+[^>]*\bId="([^"]+)"/);
    env.chave_natural = id ? id[1] : null;
    const insc = tag('nrInsc', bloco(fam === 'esocial' ? 'ideEmpregador' : 'ideContri') || '');
    env.cnpj = insc && insc.length === 14 ? insc : null;
    const per = tag('perApur') || tag('perApuracao');
    if (per && /^\d{4}-\d{2}$/.test(per)) {
      const [a, m] = per.split('-').map(Number);
      env.periodo_ini = `${per}-01`;
      env.periodo_fim = new Date(Date.UTC(a, m, 0)).toISOString().slice(0, 10);   // último dia da competência
    }
    env.detalhe = { raiz, raiz_cnpj: insc && insc.length === 8 ? insc : null };
  } else {
    const lay = XML[fam];
    const evento = /<(procEvento\w*|evento\w*)\b/.test(texto) && !texto.includes(`<${lay.elemento}`);
    if (evento) {
      // Cancelamento, carta de correção e manifestação são XMLs PRÓPRIOS. Lidos
      // como se fossem a nota, a nota cancelada contaria duas vezes (G9).
      const ch = tag(`ch${lay.prefixoId === 'NFS' ? 'NFSe' : lay.prefixoId}`) || tag('chNFe') || tag('chCTe') || tag('chMDFe');
      const tp = tag('tpEvento'), seq = tag('nSeqEvento');
      env.subtipo = 'evento';
      env.chave_natural = `${ch}|evento|${tp}|${seq}`;
      env.versao_leiaute = (texto.match(/<(?:evento|infEvento)[^>]*\bversao="([^"]+)"/) || [])[1] || null;
      env.cnpj = tag('CNPJ');
      env.detalhe = { raiz, tp_evento: tp, chave_documento: ch };
    } else {
      const inf = texto.match(new RegExp(`<${lay.elemento}\\b([^>]*)>`));
      const attrs = inf ? inf[1] : '';
      env.versao_leiaute = (attrs.match(/\bversao="([^"]+)"/) || [])[1] || null;
      const id = (attrs.match(/\bId="([^"]+)"/) || [])[1] || null;
      env.chave_natural = id ? id.replace(new RegExp(`^${lay.prefixoId}`), '') : null;
      const emit = bloco('emit') || bloco('prest') || '';
      env.cnpj = tag('CNPJ', emit);
      const cpfEmit = tag('CPF', emit);
      const emissao = tag('dhEmi') || tag('dhEmiss');
      if (emissao) { env.periodo_ini = emissao.slice(0, 10); env.periodo_fim = emissao.slice(0, 10); }
      env.detalhe = { raiz, autorizado: /<cStat>100<\/cStat>/.test(texto), cpf_emitente: cpfEmit };
    }
  }
  env.controle_lido = 1;
  const versoes = env.subtipo === 'evento' ? (XML[fam].versoesEvento || []) : XML[fam].versoes;
  if (!fechado) { env.status = 'falhou'; env.detalhe.motivo = `o XML não fecha o elemento raiz <${raiz}>: truncado`; }
  else if (!env.chave_natural || /null/.test(env.chave_natural)) { env.status = 'falhou'; env.detalhe.motivo = 'XML oficial sem identificador (Id, chave de acesso ou chave do documento do evento)'; }
  else if (!versoes.includes(env.versao_leiaute)) { env.status = 'versao_desconhecida'; env.detalhe.motivo = `versão ${env.versao_leiaute} de ${fam} fora do registro de leiautes`; }
  else env.status = 'lido';
}

function leitorDeLinhas(env) {
  if (env.familia === 'sped') return leitorSped(env);
  if (env.familia === 'ofx') return leitorOfx(env);
  if (env.familia.startsWith('cnab')) return leitorCnab(env, env.familia);
  return null;
}

function codificacao(familia, cabeca) {
  // SPED e CNAB são latin1 por leiaute. O OFX 1.x declara CHARSET:1252 (latin1 é
  // o subconjunto que importa); o 2.x é XML em UTF-8. XML oficial é UTF-8.
  if (familia === 'sped' || familia.startsWith('cnab')) return 'latin1';
  if (familia === 'ofx' && /CHARSET:(1252|ISO-8859-1)/i.test(cabeca)) return 'latin1';
  return 'utf8';
}

/** Envelope de um arquivo que já está em memória (testes, e cada entrada de um zip). */
export function lerEnvelopeDeBuffer(buf) {
  const fam = detectarFamilia(buf);
  const hash = createHash('sha256').update(buf).digest('hex');
  if (!fam.familia || fam.familia === 'zip') return { familia: fam.familia, evidencia: fam.evidencia, hash_sha256: hash };
  const env = envelopeBase(fam.familia, fam.subtipo, hash);
  const texto = buf.toString(codificacao(fam.familia, buf.subarray(0, 512).toString('latin1')));
  const leitor = leitorDeLinhas(env);
  if (leitor) { for (const l of texto.split(QUEBRA)) leitor.linha(l); leitor.fim(); }
  else lerXml(env, texto);
  return env;
}

/**
 * Envelope de um arquivo em disco, lido em FLUXO: a memória não depende do tamanho.
 * XML é lido inteiro (um documento por arquivo, de KBs); zip devolve a família
 * 'zip' e quem chama abre com `zip.mjs`.
 */
export async function lerEnvelopeDeArquivo(caminho) {
  const fh = await open(caminho, 'r');
  const { buffer, bytesRead } = await fh.read(Buffer.alloc(65536), 0, 65536, 0);
  await fh.close();
  const cabeca = buffer.subarray(0, bytesRead);
  const fam = detectarFamilia(cabeca);
  if (!fam.familia || fam.familia === 'zip' || !['sped', 'ofx', 'cnab240', 'cnab400', 'cnab150'].includes(fam.familia)) {
    const { readFile } = await import('node:fs/promises');
    if (fam.familia && fam.familia !== 'zip') return lerEnvelopeDeBuffer(await readFile(caminho));
    const hash = createHash('sha256').update(await readFile(caminho)).digest('hex');
    return { familia: fam.familia, evidencia: fam.evidencia, hash_sha256: hash };
  }
  const env = envelopeBase(fam.familia, fam.subtipo, null);
  const leitor = leitorDeLinhas(env);
  const h = createHash('sha256');
  const fluxo = createReadStream(caminho);
  fluxo.on('data', d => h.update(d));
  const enc = codificacao(fam.familia, cabeca.subarray(0, 512).toString('latin1'));
  const rl = createInterface({ input: createReadStream(caminho, { encoding: enc }), crlfDelay: Infinity });
  for await (const l of rl) leitor.linha(l);
  await new Promise((ok, erro) => { if (fluxo.readableEnded) ok(); else { fluxo.on('end', ok); fluxo.on('error', erro); } });
  env.hash_sha256 = h.digest('hex');
  leitor.fim();
  if (env.familia.startsWith('cnab')) env.chave_natural = env.hash_sha256;
  return env;
}
