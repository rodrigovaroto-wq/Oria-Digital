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
// O QUE ELE PROMETE, e o que NÃO promete:
//   - Promete: decodificar, separar linhas e células, achar o cabeçalho e dar a TODA linha
//     um destino ESTRUTURAL, contado. Nenhuma linha some sem contagem (regra 7).
//   - NÃO promete dizer se uma linha do corpo é título, subtotal ou lixo. Sem saber o que
//     cada coluna significa, isso é palpite. Medido na revisão de 11/11/2026: a primeira
//     versão decidia pela contagem de células e mandava o título EM ABERTO (colunas de
//     pagamento vazias) para fora da tabela, enquanto "Sub-Total;;;10,00" virava dado.
//     Quem decide é a MB2, com o mapeamento: título é a linha cujo vencimento é data e
//     cujo saldo é número. O que aqui é palpite vira SINAL na linha, contado no resumo.
//
// Os destinos, e cada linha cai em exatamente um:
//   antes_do_cabecalho  título do relatório, filtros, data de emissão
//   cabecalho           a linha com os nomes das colunas, e cada repetição dela (página nova)
//   corpo               linha da tabela: a MB2 decide o que ela é
//   em_branco           nenhuma célula com conteúdo
//   largura_divergente  conteúdo além da última coluna do cabeçalho: um separador dentro de
//                       um nome sem aspas. ATENÇÃO: o deslocamento que cabe na largura (a
//                       última coluna costuma vir vazia) NÃO aparece aqui; quem o pega é a
//                       MB2, porque o saldo deslocado deixa de ser número.
// Os sinais (vários por linha, contados em `sinais` do resumo):
//   rotulo_de_total     uma das duas primeiras células preenchidas fala em total, subtotal,
//                       totais, soma ou saldo geral. É SINAL: "SOMA ENGENHARIA LTDA" também.
//   poucas_celulas      menos da metade das colunas do cabeçalho preenchidas.

import { detectarFormato, formaDoTexto } from '../../N8N/lib/formato.mjs';
import { Sha256 } from './sha256.mjs';
import { entradasDoZip, motivoDoErro } from './zip.mjs';

const CABECA = 65536;
const AMOSTRA = 30;             // linhas do corpo que a MB2 mostra à IA e ao analista
const BUSCA_DO_CABECALHO = 200; // linhas examinadas antes de desistir de achar o cabeçalho
const MAX_LINHAS_NUMA_CELULA = 50; // aspas que não fecham em 50 linhas físicas são aspa solta

export const DESTINOS = ['antes_do_cabecalho', 'cabecalho', 'corpo', 'em_branco', 'largura_divergente'];
export const SINAIS = ['rotulo_de_total', 'poucas_celulas'];
const RE_TOTAL = /^\W*(sub[\s-]?)?tota(l|is)\b|^\W*soma\b|^\W*saldo\s+geral\b/i;

// ----------------------------------------------------------------- codificação --
// ERP brasileiro exporta windows-1252. O `TextDecoder('windows-1252')` é o mesmo no Node
// 22 e no navegador (WHATWG): 0x96 vira "–" nos dois, medido em 11/11/2026 (o teste
// "cp1252" reprova se isso mudar). O SPED é o contrário, ISO-8859-1 de verdade, e por
// isso `campos.mjs#latin1` desfaz o cp1252 — não reaproveitar aquele aqui.
// O BOM também é do `TextDecoder`: ele o descarta sozinho (o teste do BOM o prova).

/** A codificação pelos bytes iniciais. `certa: false` = só ASCII, não dá para saber ainda. */
export function codificacaoDe(cabeca) {
  if (cabeca[0] === 0xef && cabeca[1] === 0xbb && cabeca[2] === 0xbf) return { codificacao: 'utf-8', certa: true };
  // "Texto Unicode" do Excel é UTF-16LE com BOM: tem byte zero, e o detector de texto
  // o chamaria de binário. Decidido ANTES dele.
  if (cabeca[0] === 0xff && cabeca[1] === 0xfe) return { codificacao: 'utf-16le', certa: true };
  if (cabeca[0] === 0xfe && cabeca[1] === 0xff) return { codificacao: 'utf-16be', certa: true };
  try {
    new TextDecoder('utf-8', { fatal: true }).decode(cabeca, { stream: true });
  } catch {
    return { codificacao: 'windows-1252', certa: true };
  }
  return { codificacao: 'utf-8', certa: cabeca.some((b) => b > 0x7f) };
}

/**
 * O arquivo inteiro é UTF-8 válido? Só roda quando os 64 KB iniciais são ASCII puro.
 * Antes, a decisão era tomada pelos 64 KB e corrigida com uma RELEITURA no meio do
 * caminho; medido na revisão de 11/11/2026, num CSV de 5 MB lido em fatias de 64 KB,
 * 199.863 linhas já tinham sido entregues antes do reinício, e quem não tratava o aviso
 * somava em dobro. Uma passada a mais só de decodificação é mais barata que esse risco.
 */
async function todoUtf8(blob) {
  const d = new TextDecoder('utf-8', { fatal: true });
  const r = blob.stream().getReader();
  try {
    for (;;) {
      const { done, value } = await r.read();
      if (done) { d.decode(); return true; }
      d.decode(value, { stream: true });
    }
  } catch {
    await r.cancel();
    return false;
  }
}

function decodificador(codificacao) {
  // cp1252 não tem byte inválido (os 5 sem caractere viram controle): sem `fatal`.
  const d = new TextDecoder(codificacao, { fatal: codificacao !== 'windows-1252' });
  return { texto: (b) => d.decode(b, { stream: true }), fim: () => d.decode() };
}

// ------------------------------------------------------------------- células --
const RE_NUMERO_OU_DATA = /^\s*-?[\d.,]+\s*$|^\s*\d{1,4}[/-]\d{1,2}[/-]\d{1,4}\s*$/;

/**
 * Varre `texto` a partir do estado `dentro` (entre aspas ou não) e devolve o estado no fim.
 * Aspa só ABRE no começo de uma célula (RFC 4180): `MONITOR 15"` é texto. Medido na revisão
 * de 11/11/2026: tratada como abertura em qualquer lugar, uma polegada juntava 6 linhas num
 * título só, com o nome da primeira e o saldo da última, sem aviso.
 */
function estadoDasAspas(texto, sep, dentro, inicioDeCelula) {
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (dentro) {
      if (c === '"') {
        if (texto[i + 1] === '"') i++;
        else dentro = false;
      }
    } else if (c === '"' && inicioDeCelula) dentro = true;
    inicioDeCelula = !dentro && c === sep;
  }
  return dentro;
}

/** Uma linha de CSV em células: aspa no começo da célula protege o separador e a quebra. */
export function celulasDoCsv(linha, sep) {
  if (!linha.includes('"')) return linha.split(sep);
  const out = [];
  let atual = '', dentro = false, inicio = true;
  for (let i = 0; i < linha.length; i++) {
    const c = linha[i];
    if (dentro) {
      if (c === '"') {
        if (linha[i + 1] === '"') { atual += '"'; i++; } else dentro = false;
      } else atual += c;
    } else if (c === '"' && inicio) { dentro = true; inicio = false; }
    else if (c === sep) { out.push(atual); atual = ''; inicio = true; }
    else { atual += c; inicio = false; }
  }
  out.push(atual);
  return out;
}

// --------------------------------------------------------------- classificação --
const vazia = (c) => c === undefined || c === null || String(c).trim() === '';
function preenchidas(celulas) {
  let n = 0;
  for (const c of celulas) if (!vazia(c)) n++;
  return n;
}
function ultimaPreenchida(celulas) {
  for (let i = celulas.length - 1; i >= 0; i--) if (!vazia(celulas[i])) return i + 1;
  return 0;
}
/** A linha como chave de comparação com o cabeçalho: células aparadas, minúsculas, sem as vazias do fim. */
const normalizar = (celulas) => {
  const c = celulas.map((x) => String(x ?? '').trim().toLowerCase());
  while (c.length && c[c.length - 1] === '') c.pop();
  return JSON.stringify(c);
};

/** Candidata a cabeçalho: ≥ 3 células, todas texto (nem número nem data). */
function pareceCabecalho({ celulas, tipos }) {
  if (preenchidas(celulas) < 3) return false;
  for (let i = 0; i < celulas.length; i++) {
    if (vazia(celulas[i])) continue;
    if (tipos ? tipos[i] !== 's' : RE_NUMERO_OU_DATA.test(String(celulas[i]))) return false;
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
    sinais: Object.fromEntries(SINAIS.map((s) => [s, 0])),
    cabecalho: null, largura: 0, amostra: [], linhas: 0, primeira: {},
  };
  let espera = [];
  let decidido = false, chaveDoCabecalho = null, primeiraDoCabecalho = null;

  function emitir(linha, destino, sinais = []) {
    r.por_destino[destino]++;
    for (const s of sinais) r.sinais[s]++;
    if (!(destino in r.primeira)) r.primeira[destino] = linha.n;
    if (destino === 'corpo' && r.amostra.length < AMOSTRA) {
      r.amostra.push(linha.celulas);
      // O tipo de cada célula do XLSX vai junto: sem ele, a MB2 lia o "15172.12" do XML como
      // texto com ponto decimal e propunha o formato errado para o arquivo (medido no teste).
      if (linha.tipos) (r.amostra_tipos ??= []).push(linha.tipos);
    }
    if (aoLinha) aoLinha({ ...linha, destino, sinais });
  }

  function depois(linha) {
    const n = preenchidas(linha.celulas);
    if (n === 0) return emitir(linha, 'em_branco');
    if (ultimaPreenchida(linha.celulas) > r.largura) return emitir(linha, 'largura_divergente');
    // A primeira célula filtra antes: montar a chave da linha inteira em toda linha custava
    // ~1 s em 1M de linhas.
    if (String(linha.celulas[0] ?? '').trim().toLowerCase() === primeiraDoCabecalho
        && normalizar(linha.celulas) === chaveDoCabecalho) return emitir(linha, 'cabecalho');
    const sinais = [];
    const primeiras = linha.celulas.filter((c) => !vazia(c)).slice(0, 2);
    if (primeiras.some((c) => RE_TOTAL.test(String(c)))) sinais.push('rotulo_de_total');
    if (n < Math.ceil(r.largura / 2)) sinais.push('poucas_celulas');
    return emitir(linha, 'corpo', sinais);
  }

  /**
   * O cabeçalho é a primeira candidata cujas linhas seguintes cabem nela: das próximas 5
   * com conteúdo, ao menos 3 com 2 células ou mais e NADA além da última coluna. É o "nada
   * além" que impede um preâmbulo de 3 células ("Empresa:;ACME;CNPJ ...") de virar
   * cabeçalho de uma tabela de 12 colunas (achado da revisão de 11/11/2026). Não se exige
   * metade das colunas: o título em aberto de um AR tem as colunas de pagamento vazias
   * (5 de 12, medido no teste), e exigir metade recusava o cabeçalho de um AR só de abertos.
   */
  function tentarDecidir(fim) {
    for (let i = 0; i < espera.length; i++) {
      if (!pareceCabecalho(espera[i])) continue;
      const largura = ultimaPreenchida(espera[i].celulas);
      const seguintes = espera.slice(i + 1).filter((l) => preenchidas(l.celulas) > 0).slice(0, 5);
      if (seguintes.length < 5 && !fim) return false; // ainda não dá para saber
      const cabem = seguintes.filter((l) => ultimaPreenchida(l.celulas) <= largura
        && preenchidas(l.celulas) >= 2).length;
      if (cabem < Math.min(3, seguintes.length) || seguintes.length === 0) continue;
      r.cabecalho = { linha: espera[i].n, celulas: espera[i].celulas.slice(0, largura) };
      r.largura = largura;
      chaveDoCabecalho = normalizar(r.cabecalho.celulas);
      primeiraDoCabecalho = String(r.cabecalho.celulas[0] ?? '').trim().toLowerCase();
      espera.forEach((l, j) => {
        if (j < i) emitir(l, preenchidas(l.celulas) ? 'antes_do_cabecalho' : 'em_branco');
        else if (j === i) emitir(l, 'cabecalho');
        else depois(l);
      });
      espera = [];
      return true;
    }
    if (fim || espera.length >= BUSCA_DO_CABECALHO) {
      // Sem cabeçalho: ninguém sabe onde a tabela começa. Nada vira corpo, e o resumo DIZ
      // por quê (a tela não pode mostrar 0 linhas como se o arquivo estivesse vazio).
      r.sem_cabecalho = `nenhuma linha de cabeçalho (≥ 3 células de texto, seguida de linhas que cabem nela) nas primeiras ${espera.length} linhas`;
      for (const l of espera) emitir(l, preenchidas(l.celulas) ? 'antes_do_cabecalho' : 'em_branco');
      espera = [];
      return true;
    }
    return false;
  }

  return {
    linha(l) {
      r.linhas++;
      if (decidido) {
        if (r.sem_cabecalho) emitir(l, preenchidas(l.celulas) ? 'antes_do_cabecalho' : 'em_branco');
        else depois(l);
        return;
      }
      espera.push(l);
      // Decidir a cada linha nas primeiras é O(n²) sobre no máximo 200 linhas: desprezível.
      decidido = tentarDecidir(false);
    },
    fim() {
      if (!decidido) tentarDecidir(true);
      return r;
    },
    /** Já há o que a proposta da MB2 precisa: cabeçalho decidido e a amostra cheia. */
    basta() {
      return decidido && (!!r.sem_cabecalho || r.amostra.length >= AMOSTRA);
    },
  };
}

/** O resumo de uma leitura interrompida em `soAmostra`: o que não foi contado não aparece como contado. */
function parcial(r) {
  return { ...r, parcial: true, bytes: null, sha256: null,
    efeito_parcial: 'leitura interrompida depois do cabeçalho e da amostra: contagens, bytes e sha256 são só do trecho lido' };
}

// ------------------------------------------------------------------------ CSV --
async function lerCsv(blob, cabeca, aoLinha, codificacao, soAmostra) {
  // O separador vem do mesmo detector do n8n (escada, degrau 2). Limite conhecido: ele
  // quebra linha sem respeitar aspas, então um arquivo cujas primeiras 50 linhas têm
  // muitas células com quebra de linha dentro cai abaixo dos 70% de consistência. Aí o
  // leitor RECUSA com o motivo (abaixo); nunca lê com o separador errado.
  const forma = formaDoTexto(decodificador(codificacao).texto(cabeca));
  if (forma.forma !== 'delimitado') {
    throw new Error(`o texto não é uma tabela delimitada (forma: ${forma.forma}); nenhuma das colunas por ';', ',', tab ou '|' é consistente nas primeiras linhas`);
  }
  const sep = forma.separador;
  const dec = decodificador(codificacao);
  const cls = classificador(aoLinha);
  const sha = new Sha256();
  const leitor = blob.stream().getReader();
  const avisos = [];
  let buf = '', fisicas = 0, n = 0, bytes = 0;
  let pendentes = [], dentro = false; // linhas físicas de uma célula entre aspas ainda aberta

  const registro = (texto) => cls.linha({ n: n++, celulas: celulasDoCsv(texto, sep) });
  const fechar = (texto) => {
    fisicas++;
    // O estado das aspas é carregado de uma linha física para a outra: cada linha é
    // varrida UMA vez. A primeira versão revarria tudo o que estava pendente a cada linha
    // nova (40 mil linhas depois de uma aspa solta: 22 s; 1M congelava a aba).
    // Linha sem aspa nenhuma não muda o estado: o atalho evita varrer caractere a
    // caractere as ~100% das linhas de um ERP (1M de linhas: 4,2 s sem ele, medido).
    if (dentro || texto.includes('"')) dentro = estadoDasAspas(texto, sep, dentro, !dentro);
    pendentes.push(texto);
    if (dentro && pendentes.length < MAX_LINHAS_NUMA_CELULA) return;
    if (dentro) {
      // Uma "célula" de 50 linhas é uma aspa que nunca fecha. Cada linha física volta a
      // ser um registro, lido sem aspas, e o resumo diz onde.
      avisos.push(`aspas abertas na linha física ${fisicas - pendentes.length + 1} sem fechar em ${MAX_LINHAS_NUMA_CELULA} linhas: essas linhas foram lidas uma a uma, sem tratar aspas`);
      for (const p of pendentes) cls.linha({ n: n++, celulas: p.split(sep) });
      dentro = false;
    } else registro(pendentes.join('\n'));
    pendentes = [];
  };

  const RE = /\r\n|\n|\r/g;
  for (;;) {
    if (soAmostra && cls.basta()) {
      // A 1ª leitura da tela só precisa do cabeçalho e da amostra: com 1M de linhas, ir até
      // o fim custava uma leitura inteira a mais (8,1 s em vez de ~4 s no CSV, medido).
      await leitor.cancel();
      return parcial({ formato: 'csv', codificacao, separador: sep, linhas_fisicas: fisicas, avisos, ...cls.fim() });
    }
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
      if (soAmostra && cls.basta()) break; // a parada é por linha, não por fatia de 64 KB
    }
    buf = buf.slice(ini);
  }
  // O que sobrou é a última linha sem quebra no fim (ou com um \r adiado acima).
  buf += dec.fim();
  if (buf.endsWith('\r')) fechar(buf.slice(0, -1));
  else if (buf !== '') fechar(buf);
  if (pendentes.length) {
    avisos.push(`aspas abertas na linha física ${fisicas - pendentes.length + 1} até o fim do arquivo: essas linhas foram lidas uma a uma, sem tratar aspas`);
    for (const p of pendentes) cls.linha({ n: n++, celulas: p.split(sep) });
  }
  return {
    formato: 'csv', codificacao, separador: sep, bytes, sha256: sha.hex(),
    linhas_fisicas: fisicas, avisos, ...cls.fim(),
  };
}

// ----------------------------------------------------------------------- XLSX --
// O XML é varrido por expressão regular, em fluxo, sem montar documento (no Web Worker
// não há DOMParser). Por isso cada detalhe de XML que o Excel ou outro gerador pode usar é
// tratado aqui de propósito: prefixo de namespace (`<x:row>`), aspas simples nos
// atributos, comentário e CDATA.
const P = '(?:[\\w.-]+:)?'; // prefixo de namespace opcional
const ENTIDADES = { amp: '&', lt: '<', gt: '>', quot: '"', apos: "'" };
function desescapar(s) {
  if (!s.includes('&')) return s;
  return s.replace(/&(#x[0-9a-f]+|#\d+|\w+);/gi, (m, e) => {
    if (e[0] === '#') return String.fromCodePoint(e[1] === 'x' || e[1] === 'X' ? parseInt(e.slice(2), 16) : Number(e.slice(1)));
    return ENTIDADES[e] ?? m;
  });
}
/** Texto de um nó: CDATA literal, o resto desescapado. */
function textoXml(s) {
  if (!s.includes('<![CDATA[')) return desescapar(s);
  return s.split(/(<!\[CDATA\[[\s\S]*?\]\]>)/).map((p) => (p.startsWith('<![CDATA[') ? p.slice(9, -3) : desescapar(p))).join('');
}

/** Valor do atributo `nome` (com ou sem prefixo, aspas duplas ou simples). */
function atributo(attrs, nome) {
  const m = new RegExp(`(?:^|\\s)${nome}\\s*=\\s*(?:"([^"]*)"|'([^']*)')`).exec(attrs);
  return m ? desescapar(m[1] ?? m[2]) : null;
}

async function textoDaEntrada(entrada) {
  const t = await new Response(entrada.fluxo()).text(); // UTF-8, como o OOXML exige; parte pequena
  return t.replace(/<!--[\s\S]*?-->/g, '');
}

/** Percorre os elementos `tag` (com ou sem prefixo) de um XML grande, em fluxo. */
async function* elementos(entrada, tag) {
  const leitor = entrada.fluxo().pipeThrough(new TextDecoderStream()).getReader();
  const re = new RegExp(`<${P}${tag}\\b[^>]*?/>|<${P}${tag}\\b[^>]*>[\\s\\S]*?</${P}${tag}>`, 'g');
  const abre = new RegExp(`<${P}${tag}\\b`);
  let buf = '';
  for (;;) {
    const { done, value } = await leitor.read();
    if (done) break;
    buf += value;
    // Comentário inteiro sai; um comentário ainda aberto espera a próxima fatia, senão
    // um `<row>` comentado viraria linha (achado da revisão de 11/11/2026).
    buf = buf.replace(/<!--[\s\S]*?-->/g, '');
    const aberto = buf.indexOf('<!--');
    const ate = aberto === -1 ? buf.length : aberto;
    const trecho = buf.slice(0, ate);
    re.lastIndex = 0;
    let fim = 0, m;
    while ((m = re.exec(trecho)) !== null) { yield m[0]; fim = re.lastIndex; }
    buf = buf.slice(fim);
    // O que sobrou pode ser o começo de um elemento: fica para a próxima fatia.
    const k = aberto === -1 ? buf.search(abre) : 0;
    if (k > 0) buf = buf.slice(k);
    else if (k === -1 && buf.length > 64) buf = buf.slice(-64); // um `<x:ro` cortado cabe em 64
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
  for (const m of xml.matchAll(new RegExp(`<${P}numFmt\\b([^>]*)`, 'g'))) {
    proprios.set(Number(atributo(m[1], 'numFmtId')), atributo(m[1], 'formatCode') ?? '');
  }
  const xfs = new RegExp(`<${P}cellXfs\\b[^>]*>([\\s\\S]*?)</${P}cellXfs>`).exec(xml);
  const ehData = [];
  if (xfs) for (const m of xfs[1].matchAll(new RegExp(`<${P}xf\\b([^>]*)`, 'g'))) {
    const id = Number(atributo(m[1], 'numFmtId') ?? 0);
    ehData.push(FORMATOS_DATA.has(id) || (proprios.has(id) && formatoEhData(proprios.get(id))));
  }
  return ehData;
}

function serialParaData(serial, de1904) {
  // Segundos inteiros desde a época: 46022.9999999999 é 46023 à meia-noite, não "24:00:00".
  const seg = Math.round(serial * 86400);
  const base = de1904 ? Date.UTC(1904, 0, 1) : Date.UTC(1899, 11, 30);
  const iso = new Date(base + seg * 1000).toISOString();
  return seg % 86400 === 0 ? iso.slice(0, 10) : iso.slice(0, 19);
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

const RE_CELULA = new RegExp(`<${P}c\\b([^>]*?)(?:/>|>([\\s\\S]*?)</${P}c>)`, 'g');
const RE_V = new RegExp(`<${P}v>([\\s\\S]*?)</${P}v>`);
const RE_T = new RegExp(`<${P}t(?:\\s[^>]*)?>([\\s\\S]*?)</${P}t>`, 'g');
const RE_RPH = new RegExp(`<${P}rPh\\b[\\s\\S]*?</${P}rPh>`, 'g');
const textoDosT = (s) => {
  let t = '';
  for (const m of s.matchAll(RE_T)) t += textoXml(m[1]);
  return t;
};

async function lerXlsx(blob, aoLinha, soAmostra) {
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
  const pr = new RegExp(`<${P}workbookPr\\b([^>]*)`).exec(workbook);
  const de1904 = !!pr && /^(1|true)$/.test(atributo(pr[1], 'date1904') ?? '');
  // O id da relação é sempre um atributo COM prefixo (r:id, ns:id...): o `sheetId` não tem.
  const abas = [...workbook.matchAll(new RegExp(`<${P}sheet\\b([^>]*)`, 'g'))].map((m) => ({
    nome: atributo(m[1], 'name') ?? '', rid: atributo(m[1], '[\\w.-]+:id'),
    oculta: (atributo(m[1], 'state') ?? 'visible') !== 'visible',
  }));
  const rels = await textoDaEntrada(exigir('xl/_rels/workbook.xml.rels'));
  const alvo = new Map([...rels.matchAll(new RegExp(`<${P}Relationship\\b([^>]*)`, 'g'))]
    .map((m) => [atributo(m[1], 'Id'), atributo(m[1], 'Target')]));
  const aba = abas.find((a) => !a.oculta) ?? abas[0];
  if (!aba) throw new Error('a planilha não declara nenhuma aba');
  const destino = alvo.get(aba.rid);
  // Sem alvo, NÃO há palpite (`sheet1.xml` seria outra aba, talvez a oculta, rotulada
  // com o nome desta: achado da revisão de 11/11/2026).
  if (!destino) throw new Error(`a aba "${aba.nome}" aponta para a relação ${aba.rid ?? '(sem id)'}, que não existe em workbook.xml.rels`);
  const caminhoDaAba = destino.startsWith('/') ? destino.slice(1) : `xl/${destino}`.replace(/\/\.\//g, '/');

  const sst = [];
  const entradaSst = entradas.get('xl/sharedStrings.xml');
  // Texto rico: vários <r><t>; a leitura fonética (<rPh>) não é texto da célula.
  if (entradaSst) for await (const si of elementos(entradaSst, 'si')) sst.push(textoDosT(si.replace(RE_RPH, '')));
  const estilos = entradas.get('xl/styles.xml') ? estilosDeData(await textoDaEntrada(entradas.get('xl/styles.xml'))) : [];

  const cls = classificador(aoLinha);
  let anterior = 0, ausentes = 0, rows = 0;
  const tiposVistos = {};
  const folha = exigir(caminhoDaAba);
  for await (const row of elementos(folha, 'row')) {
    rows++;
    const abreRow = new RegExp(`^<${P}row\\b([^>]*)`).exec(row)[1];
    const r = Number(atributo(abreRow, 'r') ?? anterior + 1);
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
      if (t === 'inlineStr') { valor = textoDosT(corpo); tipo = 's'; }
      else {
        const v = RE_V.exec(corpo);
        if (!v) continue; // célula só com estilo: vazia
        const bruto = textoXml(v[1]);
        if (t === 's') {
          // Índice fora da tabela de strings é arquivo corrompido: erro, nunca célula vazia.
          const indice = Number(bruto);
          if (!Number.isInteger(indice) || indice < 0 || indice >= sst.length) {
            throw new Error(`a célula ${ref ?? col} aponta para a string ${bruto}, e a tabela tem ${sst.length}`);
          }
          valor = sst[indice];
          tipo = 's';
        } else if (t === 'str') { valor = bruto; tipo = 's'; }
        else if (t === 'b') { valor = bruto === '1' ? 'VERDADEIRO' : 'FALSO'; tipo = 'b'; }
        else if (t === 'e') { valor = bruto; tipo = 'e'; }
        else if (t === 'd') { valor = bruto; tipo = 'd'; }
        else if (estilos[Number(atributo(m[1], 's') ?? 0)]) { valor = serialParaData(Number(bruto), de1904); tipo = 'd'; }
        else { valor = bruto; tipo = 'n'; } // o texto do XML, sem passar por float (ver lerTabela)
      }
      while (celulas.length < col) { celulas.push(''); tipos.push(''); }
      celulas[col] = valor; tipos[col] = tipo;
      tiposVistos[tipo] = (tiposVistos[tipo] ?? 0) + 1;
    }
    cls.linha({ n: r - 1, celulas, tipos });
    if (soAmostra && cls.basta()) break;
  }
  // Folha com conteúdo e nenhuma linha reconhecida é leitura que falhou, não tabela vazia.
  if (rows === 0 && folha.tamanho > 200) throw new Error(`a aba "${aba.nome}" tem ${folha.tamanho} bytes e nenhuma linha reconhecida`);

  const basta = soAmostra && cls.basta();
  const sha = new Sha256();
  const leitor = blob.stream().getReader();
  if (basta) await leitor.cancel();
  let bytes = 0;
  for (;;) {
    if (basta) break;
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
  const r = {
    formato: 'xlsx', aba: aba.nome, abas: abas.map((a) => a.nome), data_1904: de1904, bytes, sha256: sha.hex(),
    linhas_ausentes_no_xml: ausentes, strings_compartilhadas: sst.length, tipos_de_celula: tiposVistos, avisos, ...cls.fim(),
  };
  return basta ? parcial(r) : r;
}

// -------------------------------------------------------------------- entrada --
/**
 * Lê uma tabela (CSV ou XLSX) de um `Blob`/`File`, em fluxo.
 *
 * `aoLinha({ n, celulas, tipos, destino, sinais })` é chamado UMA vez por linha, na ordem:
 * é por ele que a MB3 agrega sem guardar o arquivo. `n` começa em 0 (linha 1 da planilha
 * ou registro 1 do CSV); `tipos` só existe no XLSX ('s' texto, 'n' número, 'd' data ISO,
 * 'b', 'e').
 *
 * NÚMERO DO XLSX sai como o texto do XML, sem passar por float: pode vir em notação
 * científica ("1.5E-2") e com o ruído de 17 dígitos que o Excel grava ("1234.5599999999999").
 * Quem converte para centavos (MB2/MB3) arredonda e DECLARA que arredondou.
 *
 * `soAmostra: true` para depois do cabeçalho e de 30 linhas do corpo (a 1ª leitura da tela,
 * que só alimenta a proposta da MB2). O resumo sai com `parcial: true` e SEM bytes e sha256:
 * nada do que não foi lido aparece como contado. No XLSX a tabela de strings é lida inteira
 * mesmo assim (as linhas apontam para ela).
 *
 * Devolve o resumo: formato, codificação, separador ou aba, bytes, sha256, o cabeçalho,
 * a largura, as linhas por destino (somam `linhas`), os sinais, a primeira linha de cada
 * destino, a amostra de até 30 linhas do corpo (para a MB2) e os avisos.
 */
export async function lerTabela(blob, { aoLinha, soAmostra = false } = {}) {
  if (typeof blob?.stream !== 'function') blob = new Blob([blob]);
  const cabeca = new Uint8Array(await blob.slice(0, CABECA).arrayBuffer());
  const cod = codificacaoDe(cabeca);
  // UTF-16 tem byte zero: o detector de formato o chamaria de binário. É texto.
  const det = cod.codificacao.startsWith('utf-16') ? { formato: 'texto' } : detectarFormato(cabeca);
  if (det.formato === 'xlsx') {
    try { return await lerXlsx(blob, aoLinha, soAmostra); } catch (e) { throw new Error(`a planilha não pôde ser lida: ${motivoDoErro(e)}`); }
  }
  if (det.formato !== 'texto') throw new Error(`não é CSV nem XLSX (formato detectado: ${det.formato}${det.detalhe ? `, ${det.detalhe}` : ''})`);
  let codificacao = cod.codificacao;
  const avisos = [];
  if (!cod.certa && !(await todoUtf8(blob))) {
    codificacao = 'windows-1252';
    avisos.push('os primeiros 64 KB eram ASCII puro e o arquivo não é UTF-8 válido adiante: lido como windows-1252');
  }
  const r = await lerCsv(blob, cabeca, aoLinha, codificacao, soAmostra);
  r.avisos.unshift(...avisos);
  return r;
}
