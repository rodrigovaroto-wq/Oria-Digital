// O LEITOR TABULAR EM FLUXO: CSV e XLSX de centenas de milhares a milhões de linhas
// (MB1 do `Arquitetura do Sistema/3 Estado e Execução/PLANO_MVP_2026-11.md`).
//
// POR QUE EXISTE. Contas a receber, contas a pagar e razão chegam como planilha ou CSV de
// ERP, com até milhões de linhas. Pelo n8n não passam (um arquivo de 117 MB derruba a
// instância; ficha `n8n-binario-grande-derruba-a-instancia`) e pela IA não se prova que
// tudo foi lido. Então o arquivo é lido AQUI, no navegador do analista, em fluxo, como o
// SPED (decisão do dono de 13/10/2026, D12.9). É o mesmo código no Node (testes, CLI) e
// no navegador (`File` e `openAsBlob` são ambos `Blob`).
//
// O QUE ELE FAZ, e o que NÃO faz:
//   - Faz: decodificar, separar linhas e células, achar o cabeçalho da tabela e dar a
//     TODA linha um destino, contado. Nenhuma linha some sem contagem (regra 7: o
//     estágio que não rodou não pode parecer limpo).
//   - Não faz: dizer o que cada coluna significa. Isso é a MB2 (mapeamento confirmado
//     pelo analista). Por isso a classificação aqui é ESTRUTURAL (quantas células, de
//     que tipo), nunca pelo nome da coluna.
//
// Os destinos, e cada linha cai em exatamente um:
//   antes_do_cabecalho  título do relatório, filtros, data de emissão
//   cabecalho           a linha com os nomes das colunas
//   dado                linha da tabela
//   total               "TOTAL GERAL", "Subtotal": poucas células, a primeira começa com total
//   em_branco           nenhuma célula com conteúdo
//   fora_da_tabela      depois do cabeçalho, com menos da metade das colunas (quebra de
//                       página, título de grupo); a MB2 decide se descarta
//   largura_divergente  mais células com conteúdo do que o cabeçalho tem colunas: quase
//                       sempre um separador dentro de um nome sem aspas, que DESLOCA as
//                       colunas e faria o saldo ser lido da coluna do vencimento. Nunca
//                       vira dado em silêncio.

import { detectarFormato, formaDoTexto } from '../../N8N/lib/formato.mjs';
import { Sha256 } from './sha256.mjs';
import { entradasDoZip, motivoDoErro } from './zip.mjs';

const CABECA = 65536;
const AMOSTRA = 30;            // linhas de dado que a MB2 mostra à IA e ao analista
const BUSCA_DO_CABECALHO = 200; // linhas examinadas antes de desistir de achar o cabeçalho

export const DESTINOS = ['antes_do_cabecalho', 'cabecalho', 'dado', 'total', 'em_branco',
  'fora_da_tabela', 'largura_divergente'];

// ----------------------------------------------------------------- codificação --
// ERP brasileiro exporta windows-1252. O `TextDecoder('windows-1252')` é o mesmo no Node
// 22 e no navegador (WHATWG): 0x96 vira "–" nos dois, medido em 11/11/2026 (o teste
// "cp1252" reprova se isso mudar). O SPED é o contrário, ISO-8859-1 de verdade, e por
// isso `campos.mjs#latin1` desfaz o cp1252 — não reaproveitar aquele aqui.
// O BOM também é do `TextDecoder`: ele o descarta sozinho (o teste do BOM o prova).

/** A codificação pelos bytes iniciais. UTF-8 só se os 64 KB decodificarem SEM erro. */
export function codificacaoDe(cabeca) {
  if (cabeca[0] === 0xef && cabeca[1] === 0xbb && cabeca[2] === 0xbf) return { codificacao: 'utf-8', bom: 3 };
  // "Texto Unicode" do Excel é UTF-16LE com BOM: tem byte zero, e o detector de texto
  // o chamaria de binário. Decidido ANTES dele.
  if (cabeca[0] === 0xff && cabeca[1] === 0xfe) return { codificacao: 'utf-16le', bom: 2 };
  if (cabeca[0] === 0xfe && cabeca[1] === 0xff) return { codificacao: 'utf-16be', bom: 2 };
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(cabeca, { stream: true });
    return { codificacao: 'utf-8', bom: 0 };
  } catch {
    return { codificacao: 'windows-1252', bom: 0 };
  }
}

/** Byte inválido para a codificação decidida. Classe própria: só ELA dispara a releitura. */
class ErroDeCodificacao extends Error {}

function decodificador(codificacao) {
  // cp1252 não tem byte inválido (os 5 sem caractere viram controle): sem `fatal`.
  const d = new TextDecoder(codificacao, { fatal: codificacao !== 'windows-1252' });
  const seguro = (f) => { try { return f(); } catch (e) { throw new ErroDeCodificacao(`byte inválido para ${codificacao}: ${e.message}`); } };
  return { texto: (b) => seguro(() => d.decode(b, { stream: true })), fim: () => seguro(() => d.decode()) };
}

// ------------------------------------------------------------------- células --
const RE_NUMERO_OU_DATA = /^\s*-?[\d.,]+\s*$|^\s*\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\s*$/;

/** Uma linha de CSV em células, respeitando aspas ("a;b" é UMA célula; "" é uma aspa). */
export function celulasDoCsv(linha, sep) {
  if (!linha.includes('"')) return linha.split(sep);
  const out = [];
  let atual = '', dentro = false;
  for (let i = 0; i < linha.length; i++) {
    const c = linha[i];
    if (dentro) {
      if (c === '"') {
        if (linha[i + 1] === '"') { atual += '"'; i++; } else dentro = false;
      } else atual += c;
    } else if (c === '"') dentro = true;
    else if (c === sep) { out.push(atual); atual = ''; }
    else atual += c;
  }
  out.push(atual);
  return out;
}

function aspasEquilibradas(s) {
  let n = 0;
  for (let i = s.indexOf('"'); i !== -1; i = s.indexOf('"', i + 1)) n++;
  return n % 2 === 0;
}

// --------------------------------------------------------------- classificação --
function preenchidas(celulas) {
  let n = 0;
  for (const c of celulas) if (c !== undefined && c !== null && String(c).trim() !== '') n++;
  return n;
}

function ultimaPreenchida(celulas) {
  for (let i = celulas.length - 1; i >= 0; i--) if (String(celulas[i] ?? '').trim() !== '') return i + 1;
  return 0;
}

/** Linha de cabeçalho: ≥ 3 células, todas texto (nem número nem data). */
function pareceCabecalho(linha) {
  const { celulas, tipos } = linha;
  if (preenchidas(celulas) < 3) return false;
  for (let i = 0; i < celulas.length; i++) {
    const c = String(celulas[i] ?? '').trim();
    if (c === '') continue;
    if (tipos ? tipos[i] !== 's' : RE_NUMERO_OU_DATA.test(c)) return false;
  }
  return true;
}

/**
 * O classificador, em fluxo. Guarda as linhas só até achar o cabeçalho (no máximo
 * BUSCA_DO_CABECALHO); daí em diante cada linha sai na hora em que entra.
 */
function classificador(aoLinha) {
  const r = {
    por_destino: Object.fromEntries(DESTINOS.map((d) => [d, 0])),
    cabecalho: null, largura: 0, amostra: [], linhas: 0, primeira: {},
  };
  let espera = [];
  let decidido = false;

  function emitir(linha, destino) {
    r.por_destino[destino]++;
    if (!(destino in r.primeira)) r.primeira[destino] = linha.n;
    if (destino === 'dado' && r.amostra.length < AMOSTRA) r.amostra.push(linha.celulas);
    if (aoLinha) aoLinha({ ...linha, destino });
  }

  function destinoDepois(linha) {
    const n = preenchidas(linha.celulas);
    if (n === 0) return 'em_branco';
    if (ultimaPreenchida(linha.celulas) > r.largura) return 'largura_divergente';
    // Total: a primeira célula começa com "total" E a seguinte está vazia. Um cliente
    // chamado "TOTAL DISTRIBUIDORA" preenche a linha toda e continua dado; o "TOTAL
    // GERAL;;;5,00" de um relatório de 4 colunas tem 2 células, que é a metade, e só
    // pela contagem viraria dado (medido no teste) e somaria o total ao próprio total.
    const i = linha.celulas.findIndex((c) => String(c ?? '').trim() !== '');
    if (/^(total|subtotal|soma)\b/i.test(String(linha.celulas[i]).trim())
        && String(linha.celulas[i + 1] ?? '').trim() === '') return 'total';
    if (n < Math.max(2, Math.ceil(r.largura / 2))) return 'fora_da_tabela';
    return 'dado';
  }

  /** O cabeçalho é a primeira linha que parece cabeçalho e é seguida de linhas tão largas quanto a metade dele. */
  function tentarDecidir(fim) {
    for (let i = 0; i < espera.length; i++) {
      if (!pareceCabecalho(espera[i])) continue;
      const largura = ultimaPreenchida(espera[i].celulas);
      const seguintes = espera.slice(i + 1).filter((l) => preenchidas(l.celulas) > 0).slice(0, 5);
      if (seguintes.length === 0 && !fim) return false; // ainda não dá para saber
      if (!seguintes.some((l) => preenchidas(l.celulas) >= Math.ceil(largura / 2))) continue;
      r.cabecalho = { linha: espera[i].n, celulas: espera[i].celulas.slice(0, largura) };
      r.largura = largura;
      espera.forEach((l, j) => emitir(l, j < i ? (preenchidas(l.celulas) ? 'antes_do_cabecalho' : 'em_branco')
        : j === i ? 'cabecalho' : destinoDepois(l)));
      espera = [];
      return true;
    }
    if (fim || espera.length >= BUSCA_DO_CABECALHO) {
      // Sem cabeçalho: ninguém sabe onde a tabela começa. Tudo o que tem conteúdo
      // fica fora da tabela, e o resumo DIZ por quê (a tela não pode mostrar 0 dados
      // como se o arquivo estivesse vazio).
      r.sem_cabecalho = `nenhuma linha de cabeçalho (≥ 3 células de texto seguidas de linhas da mesma largura) nas primeiras ${espera.length} linhas`;
      for (const l of espera) emitir(l, preenchidas(l.celulas) ? 'fora_da_tabela' : 'em_branco');
      espera = [];
      return true;
    }
    return false;
  }

  return {
    linha(l) {
      r.linhas++;
      if (decidido) return emitir(l, r.sem_cabecalho ? (preenchidas(l.celulas) ? 'fora_da_tabela' : 'em_branco') : destinoDepois(l));
      espera.push(l);
      // Decidir a cada linha nas primeiras é O(n²) sobre no máximo 200 linhas: desprezível.
      decidido = tentarDecidir(false);
    },
    fim() {
      if (!decidido) tentarDecidir(true);
      return r;
    },
  };
}

// ------------------------------------------------------------------------ CSV --
async function lerCsv(blob, cabeca, aoLinha, forcar) {
  const cod = forcar ? { codificacao: forcar, bom: 0 } : codificacaoDe(cabeca);
  const amostraTexto = decodificador(cod.codificacao).texto(cabeca);
  // O separador vem do mesmo detector do n8n (escada, degrau 2). Limite conhecido: ele
  // quebra linha sem respeitar aspas, então um arquivo cujas primeiras 50 linhas têm
  // muitas células com quebra de linha dentro cai abaixo dos 70% de consistência. Aí o
  // leitor RECUSA com o motivo (abaixo); nunca lê com o separador errado.
  const forma = formaDoTexto(amostraTexto);
  if (forma.forma !== 'delimitado') {
    throw new Error(`o texto não é uma tabela delimitada (forma: ${forma.forma}); nenhuma das colunas por ';', ',', tab ou '|' é consistente nas primeiras linhas`);
  }
  const sep = forma.separador;
  const dec = decodificador(cod.codificacao);
  const cls = classificador(aoLinha);
  const sha = new Sha256();
  const leitor = blob.stream().getReader();
  let buf = '', pendente = null, fisicas = 0, n = 0, bytes = 0;

  const fechar = (texto) => {
    fisicas++;
    pendente = pendente === null ? texto : pendente + '\n' + texto;
    if (!aspasEquilibradas(pendente)) return; // a célula entre aspas continua na próxima linha física
    cls.linha({ n: n++, celulas: celulasDoCsv(pendente, sep) });
    pendente = null;
  };

  const RE = /\r\n|\n|\r/g;
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    sha.update(value);
    bytes += value.length;
    buf += dec.texto(value);
    RE.lastIndex = 0;
    let ini = 0, m;
    while ((m = RE.exec(buf)) !== null) {
      // Um \r no fim da fatia pode ser metade de um \r\n: espera a próxima.
      if (m[0] === '\r' && m.index === buf.length - 1) break;
      fechar(buf.slice(ini, m.index));
      ini = m.index + m[0].length;
    }
    buf = buf.slice(ini);
  }
  // O que sobrou é a última linha sem quebra no fim (ou com um \r adiado acima).
  buf += dec.fim();
  if (buf.endsWith('\r')) fechar(buf.slice(0, -1));
  else if (buf !== '') fechar(buf);
  const avisos = [];
  if (pendente !== null) {
    // Aspas abertas até o fim: o que sobrou vira UMA linha, contada e marcada, nunca descartada.
    avisos.push(`aspas abertas a partir da linha ${n + 1} até o fim do arquivo: o resto foi lido como uma linha só`);
    cls.linha({ n: n++, celulas: celulasDoCsv(pendente + '"', sep) });
  }
  return {
    formato: 'csv', codificacao: cod.codificacao, separador: sep, bytes, sha256: sha.hex(),
    linhas_fisicas: fisicas, avisos, ...cls.fim(),
  };
}

// ----------------------------------------------------------------------- XLSX --
const ENTIDADES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
function desescapar(s) {
  if (!s.includes('&')) return s;
  return s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : Number(e.slice(1)));
    return ENTIDADES[e] ?? m;
  });
}

function atributo(attrs, nome) {
  const m = new RegExp(`(?:^|\\s)${nome}="([^"]*)"`).exec(attrs);
  return m ? m[1] : null;
}

async function textoDaEntrada(entrada) {
  return new Response(entrada.fluxo()).text(); // UTF-8, como o OOXML exige; parte pequena
}

/** Percorre os elementos `tag` de um XML grande, em fluxo, sem montar o documento. */
async function* elementos(entrada, tag) {
  const leitor = entrada.fluxo().pipeThrough(new TextDecoderStream()).getReader();
  const re = new RegExp(`<${tag}\\b[^>]*?/>|<${tag}\\b[^>]*>[\\s\\S]*?</${tag}>`, 'g');
  let buf = '';
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    buf += value;
    re.lastIndex = 0;
    let fim = 0, m;
    while ((m = re.exec(buf)) !== null) { yield m[0]; fim = re.lastIndex; }
    // O que sobrou pode ser o começo de um elemento: fica para a próxima fatia.
    buf = buf.slice(fim);
    const abre = buf.indexOf(`<${tag}`);
    if (abre !== -1) buf = buf.slice(abre);
    else if (buf.length > 64) buf = buf.slice(-64); // um `<ro` cortado no fim da fatia cabe em 64
  }
}

// Formatos de número embutidos que são data (ECMA-376, 18.8.30).
const FORMATOS_DATA = new Set([14, 15, 16, 17, 18, 19, 20, 21, 22, 27, 30, 36, 45, 46, 47, 50, 57]);
function formatoEhData(codigo) {
  const limpo = codigo.replace(/"[^"]*"|\[[^\]]*\]|\\./g, '');
  return /[dy]/i.test(limpo);
}

function estilosDeData(xml) {
  const proprios = new Map();
  for (const m of xml.matchAll(/<numFmt\b([^>]*)\/?>/g)) {
    proprios.set(Number(atributo(m[1], 'numFmtId')), desescapar(atributo(m[1], 'formatCode') ?? ''));
  }
  const xfs = /<cellXfs\b[^>]*>([\s\S]*?)<\/cellXfs>/.exec(xml);
  const ehData = [];
  if (xfs) for (const m of xfs[1].matchAll(/<xf\b([^>]*)/g)) {
    const id = Number(atributo(m[1], 'numFmtId') ?? 0);
    ehData.push(FORMATOS_DATA.has(id) || (proprios.has(id) && formatoEhData(proprios.get(id))));
  }
  return ehData;
}

function serialParaData(serial, de1904) {
  const dias = Math.floor(serial);
  const base = de1904 ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 30);
  const d = new Date(base + dias * 86400000);
  const iso = d.toISOString().slice(0, 10);
  const frac = serial - dias;
  if (frac === 0) return iso;
  const seg = Math.round(frac * 86400);
  return `${iso}T${String(Math.floor(seg / 3600)).padStart(2, '0')}:${String(Math.floor(seg / 60) % 60).padStart(2, '0')}:${String(seg % 60).padStart(2, '0')}`;
}

function colunaDe(ref) {
  let c = 0;
  for (const ch of ref) {
    const k = ch.charCodeAt(0);
    if (k < 65 || k > 90) break;
    c = c * 26 + (k - 64);
  }
  return c - 1;
}

const RE_CELULA = /<c\b([^>]*?)(?:\/>|>([\s\S]*?)<\/c>)/g;
const RE_V = /<v>([\s\S]*?)<\/v>/;
const RE_T = /<t(?:\s[^>]*)?>([\s\S]*?)<\/t>/g;

async function lerXlsx(blob, aoLinha) {
  const entradas = new Map();
  const recusadas = [];
  for await (const e of entradasDoZip(blob)) {
    if (e.recusado) recusadas.push(`${e.nome}: ${e.recusado}`);
    else entradas.set(e.nome.replace(/^\//, ''), e);
  }
  const exigir = (nome) => {
    const e = entradas.get(nome);
    if (!e) throw new Error(`a planilha não tem ${nome}${recusadas.length ? ` (entradas recusadas: ${recusadas.join('; ')})` : ''}`);
    return e;
  };

  const workbook = await textoDaEntrada(exigir('xl/workbook.xml'));
  const de1904 = /<workbookPr\b[^>]*\bdate1904="(1|true)"/.test(workbook);
  const abas = [...workbook.matchAll(/<sheet\b([^>]*)\/?>/g)].map((m) => ({
    nome: desescapar(atributo(m[1], 'name') ?? ''), rid: atributo(m[1], 'r:id'),
    oculta: (atributo(m[1], 'state') ?? 'visible') !== 'visible',
  }));
  const rels = await textoDaEntrada(exigir('xl/_rels/workbook.xml.rels'));
  const alvo = new Map([...rels.matchAll(/<Relationship\b([^>]*)\/?>/g)].map((m) => [atributo(m[1], 'Id'), atributo(m[1], 'Target')]));
  const aba = abas.find((a) => !a.oculta) ?? abas[0];
  if (!aba) throw new Error('a planilha não declara nenhuma aba');
  const caminhoDaAba = (t) => (t.startsWith('/') ? t.slice(1) : `xl/${t}`).replace(/\/\.\//g, '/');

  const sst = [];
  const entradaSst = entradas.get('xl/sharedStrings.xml');
  if (entradaSst) {
    for await (const si of elementos(entradaSst, 'si')) {
      // Texto rico: vários <r><t>; a leitura fonética (<rPh>) não é texto da célula.
      const sem = si.replace(/<rPh\b[\s\S]*?<\/rPh>/g, '');
      let s = '';
      for (const m of sem.matchAll(RE_T)) s += m[1];
      sst.push(desescapar(s));
    }
  }
  const estilos = entradas.get('xl/styles.xml') ? estilosDeData(await textoDaEntrada(entradas.get('xl/styles.xml'))) : [];

  const cls = classificador(aoLinha);
  let anterior = 0, ausentes = 0;
  const tiposVistos = {};
  for await (const row of elementos(exigir(caminhoDaAba(alvo.get(aba.rid) ?? 'worksheets/sheet1.xml')), 'row')) {
    const abre = /^<row\b([^>]*)/.exec(row)[1];
    const r = Number(atributo(abre, 'r') ?? anterior + 1);
    // A linha que o XML não traz existe para quem abre a planilha: é linha em branco.
    for (let k = anterior + 1; k < r; k++) { cls.linha({ n: k - 1, celulas: [], tipos: [] }); ausentes++; }
    anterior = r;
    const celulas = [], tipos = [];
    let col = -1;
    RE_CELULA.lastIndex = 0;
    let m;
    while ((m = RE_CELULA.exec(row)) !== null) {
      const ref = atributo(m[1], 'r');
      col = ref ? colunaDe(ref) : col + 1;
      const t = atributo(m[1], 't') ?? 'n';
      const corpo = m[2] ?? '';
      let valor, tipo;
      if (t === 'inlineStr') {
        valor = '';
        for (const x of corpo.matchAll(RE_T)) valor += x[1];
        valor = desescapar(valor); tipo = 's';
      } else {
        const v = RE_V.exec(corpo);
        if (!v) continue; // célula só com estilo: vazia
        const bruto = v[1];
        if (t === 's') {
          valor = sst[Number(bruto)];
          if (valor === undefined) throw new Error(`a célula ${ref ?? col} aponta para a string ${bruto}, e a tabela tem ${sst.length}`);
          tipo = 's';
        } else if (t === 'str') { valor = desescapar(bruto); tipo = 's'; }
        else if (t === 'b') { valor = bruto === '1' ? 'VERDADEIRO' : 'FALSO'; tipo = 'b'; }
        else if (t === 'e') { valor = desescapar(bruto); tipo = 'e'; }
        else if (t === 'd') { valor = bruto; tipo = 'd'; }
        else if (estilos[Number(atributo(m[1], 's') ?? 0)]) { valor = serialParaData(Number(bruto), de1904); tipo = 'd'; }
        else { valor = bruto; tipo = 'n'; } // o texto do XML, sem passar por float
      }
      while (celulas.length < col) { celulas.push(''); tipos.push(''); }
      celulas[col] = valor; tipos[col] = tipo;
      tiposVistos[tipo] = (tiposVistos[tipo] ?? 0) + 1;
    }
    cls.linha({ n: r - 1, celulas, tipos });
  }

  const sha = new Sha256();
  const leitor = blob.stream().getReader();
  let bytes = 0;
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    sha.update(value);
    bytes += value.length;
  }
  const avisos = [];
  if (recusadas.length) avisos.push(`entradas do zip recusadas: ${recusadas.join('; ')}`);
  const naoLidas = abas.filter((a) => a !== aba).map((a) => a.nome);
  if (naoLidas.length) avisos.push(`só a aba "${aba.nome}" foi lida; NÃO lidas: ${naoLidas.map((x) => `"${x}"`).join(', ')}`);
  if (!entradaSst && (tiposVistos.s ?? 0) > 0) avisos.push('a planilha não tem tabela de strings compartilhadas (texto em linha): formato incomum');
  return {
    formato: 'xlsx', aba: aba.nome, abas: abas.map((a) => a.nome), data_1904: de1904, bytes, sha256: sha.hex(),
    linhas_ausentes_no_xml: ausentes, strings_compartilhadas: sst.length, tipos_de_celula: tiposVistos, avisos, ...cls.fim(),
  };
}

// -------------------------------------------------------------------- entrada --
/**
 * Lê uma tabela (CSV ou XLSX) de um `Blob`/`File`, em fluxo.
 *
 * `aoLinha({ n, celulas, tipos, destino })` é chamado para TODA linha, na ordem: é
 * por ele que a MB3 agrega sem guardar o arquivo. `n` começa em 0 (linha 1 da planilha
 * ou do CSV); `tipos` só existe no XLSX ('s' texto, 'n' número, 'd' data ISO, 'b', 'e').
 * Número do XLSX sai como o texto do XML ("15172.12"), sem passar por float.
 *
 * Se o CSV parecia UTF-8 nos primeiros 64 KB e não era, ele é RELIDO do zero como
 * windows-1252, e `aoLinha({ reinicio: true })` avisa quem agrega para zerar o que
 * somou. Sem isso o resumo de quem agrega contaria as linhas duas vezes.
 *
 * Devolve o resumo: formato, codificação, separador ou aba, bytes, sha256, o cabeçalho,
 * a largura, as linhas por destino (somam `linhas`), a primeira linha de cada destino,
 * a amostra de até 30 linhas de dado (para a MB2) e os avisos.
 */
export async function lerTabela(blob, { aoLinha } = {}) {
  if (typeof blob?.stream !== 'function') blob = new Blob([blob]);
  const cabeca = new Uint8Array(await blob.slice(0, CABECA).arrayBuffer());
  const { codificacao, bom } = codificacaoDe(cabeca);
  // UTF-16 tem byte zero: o detector de formato o chamaria de binário. É texto.
  const det = codificacao.startsWith('utf-16') ? { formato: 'texto' } : detectarFormato(cabeca);
  if (det.formato === 'xlsx') {
    try { return await lerXlsx(blob, aoLinha); } catch (e) { throw new Error(`a planilha não pôde ser lida: ${motivoDoErro(e)}`); }
  }
  if (det.formato !== 'texto') throw new Error(`não é CSV nem XLSX (formato detectado: ${det.formato}${det.detalhe ? `, ${det.detalhe}` : ''})`);
  try {
    return await lerCsv(blob, cabeca, aoLinha, null);
  } catch (e) {
    // Os primeiros 64 KB eram ASCII puro e a decisão foi UTF-8; um byte do cp1252 mais
    // adiante quebra o decodificador estrito. Relê do zero como windows-1252, e diz.
    if (codificacao === 'utf-8' && !bom && e instanceof ErroDeCodificacao) {
      if (aoLinha) aoLinha({ reinicio: true });
      const r = await lerCsv(blob, cabeca, aoLinha, 'windows-1252');
      r.avisos.push('os primeiros 64 KB pareciam UTF-8 e um byte adiante não era: o arquivo foi relido como windows-1252');
      return r;
    }
    throw e;
  }
}
