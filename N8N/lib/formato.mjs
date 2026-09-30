// DETECÇÃO DE FORMATO PELO CONTEÚDO — o que o arquivo É, não o que ele diz ser.
//
// POR QUE ESTE ARQUIVO EXISTE, e o defeito tem data e tamanho. Em 11/09/2026 o
// roteamento por formato (`e13ab69`) passou a decidir o destino de cada
// documento por `content_mime`, que vem DECLARADO no upload — na prática, da
// extensão do arquivo. Em 12/09 o dono subiu 60 documentos `.txt` (planilhas
// dentro de PDFs, convertidas para texto por ele para caberem no upload). Todos
// os 60 chegaram como `text/plain`, o padrão `csv: 'csv|^text/plain$'` casou, e
// os 60 foram para o nó nativo `Extract From File` em modo CSV — que VALIDA o
// mimeType do binário e rejeita `text/plain`. 60 de 60 falharam, o item de erro
// virou linha de planilha, e a mensagem `The file selected in 'Input Binary
// Field' is not in csv format` foi mandada à IA NO LUGAR DO BALANÇO. Zero linhas
// financeiras em 60 documentos, e o banco registrou os 60 como `ilegivel` com
// 84–98% de confiança — um registro FALSO sobre arquivos íntegros.
//
// A LIÇÃO, e é ela que dita a forma deste arquivo: extensão é DECLARAÇÃO de
// terceiro, não medição. Um `.txt` pode ser um PDF renomeado, um `.csv` pode ser
// um XLSX, e um `.xlsx` pode ser um HTML que o Excel abre. Enquanto a decisão de
// roteamento saiu de metadado declarado, ela foi tão confiável quanto quem
// nomeou o arquivo — e no caso da AMO, o próprio dono renomeou de boa-fé,
// exatamente como qualquer cliente faria.
//
// O CONTRATO: decide pelos BYTES quando os bytes decidem (assinatura de formato
// é definição, não heurística), e só cai no mimetype declarado quando os bytes
// não dizem nada. Quando cai, DIZ que caiu (`evidencia: 'mime-declarado'`) —
// quem lê a saída consegue distinguir "medido" de "acreditei no upload", que é a
// regra 1 do CLAUDE.md aplicada ao próprio detector.

// TUDO ABAIXO É EXPORTADO, inclusive o que parece detalhe interno — e a razão é
// a fronteira do nó Code do n8n. `build-workflow.mjs` serializa estas funções com
// `toString()` para dentro do nó, e `toString()` NÃO leva o escopo do módulo:
// uma função que referencie um `const` não-exportado morre com `ReferenceError`
// dentro do n8n, e a chamada nunca sai. É o mesmo motivo que `capacidadesDoModelo`
// e `PADRAO_MIME` já atravessam como literal — ver FONTE_PROVEDOR.

// ASSINATURAS — o primeiro byte de cada formato, como o formato as define.
// Fonte: as especificações (PDF 32000 §7.5.2, ISO/IEC 29500 para OOXML=ZIP,
// MS-CFB para OLE2, RFC 2083 para PNG, JFIF para JPEG). Não são chutes.
export const ASSINATURAS = [
  { formato: 'pdf', bytes: [0x25, 0x50, 0x44, 0x46] },                          // %PDF
  { formato: 'zip', bytes: [0x50, 0x4b, 0x03, 0x04] },                          // PK\x03\x04 — OOXML (.xlsx) OU zip comum
  { formato: 'zip', bytes: [0x50, 0x4b, 0x05, 0x06] },                          // zip vazio
  { formato: 'xls', bytes: [0xd0, 0xcf, 0x11, 0xe0, 0xa1, 0xb1, 0x1a, 0xe1] },  // OLE2 — .xls, .doc antigos
  { formato: 'imagem', bytes: [0x89, 0x50, 0x4e, 0x47] },                       // PNG
  { formato: 'imagem', bytes: [0xff, 0xd8, 0xff] },                             // JPEG
  { formato: 'imagem', bytes: [0x47, 0x49, 0x46, 0x38] },                       // GIF8
  { formato: 'imagem', bytes: [0x49, 0x49, 0x2a, 0x00] },                       // TIFF little-endian
  { formato: 'imagem', bytes: [0x4d, 0x4d, 0x00, 0x2a] },                       // TIFF big-endian
];

/** O byte `i` de um Buffer OU de um Uint8Array — o nó Code recebe os dois. */
export function byteEm(buf, i) {
  if (!buf) return -1;
  if (typeof buf.readUInt8 === 'function' && i < buf.length) return buf[i];
  if (typeof buf.length === 'number' && i < buf.length) return buf[i];
  return -1;
}

export function casaAssinatura(buf, bytes) {
  for (let i = 0; i < bytes.length; i += 1) if (byteEm(buf, i) !== bytes[i]) return false;
  return true;
}

// ZIP É AMBÍGUO DE PROPÓSITO e resolvê-lo aqui é o que evita o defeito irmão do
// que este arquivo fecha. `.xlsx`, `.docx`, `.odt` e um `.zip` de fotos têm a
// MESMA assinatura (PK\x03\x04): decidir "é xlsx" só pela assinatura mandaria um
// `.docx` para o extrator de planilha, que devolveria erro — e o erro viraria
// linha, como virou na AMO. O nome das entradas do zip é o que separa: um XLSX
// declara `xl/workbook.xml` no diretório central, um DOCX declara `word/`.
// Procura a string no CABEÇALHO do arquivo (os nomes ficam em claro, não
// comprimidos) em vez de descomprimir — o nó Code não tem biblioteca de zip.
export function saborDoZip(buf) {
  const janela = trechoLatin1(buf, 0, 8192);
  // `xl/` é o diretório que SÓ o XLSX tem. `spreadsheetml` no [Content_Types]
  // é o segundo caminho para o mesmo fato — parênteses explícitos porque `&&`
  // liga mais forte que `||` e a versão sem eles dizia outra coisa.
  if (janela.indexOf('xl/') !== -1
    || (janela.indexOf('[Content_Types].xml') !== -1 && janela.indexOf('spreadsheetml') !== -1)) return 'xlsx';
  if (janela.indexOf('word/') !== -1) return 'docx';
  if (janela.indexOf('ppt/') !== -1) return 'pptx';
  return 'zip';
}

// QUANTAS ABAS O XLSX TEM — sem descompactar. O `Extract From File` de XLSX lê UMA
// aba só (a primeira, porque o repositório não fixa `sheetName`), e o resto do
// arquivo some sem aviso: `Endividamento Krauspenhar.xlsx` gravou 0 linhas porque
// a 1ª aba é um índice e a tabela está em "Abertura endividamento". Cada aba é uma
// entrada `xl/worksheets/<nome>.xml` do zip, e o NOME DA ENTRADA fica em claro no
// diretório central — o mesmo fato que `saborDoZip` já usa para distinguir xlsx de
// docx, então é um caminho já em produção, não uma aposta no sandbox (sem `zlib`,
// sem `require`). O que NÃO dá para saber daqui: o NOME da aba, que mora em
// `xl/workbook.xml`, comprimido. Conta também aba oculta (limite conhecido: pode
// acusar a mais, nunca a menos). Devolve null quando não há buffer.
export function abasDoXlsx(buf) {
  if (!buf || !buf.length) return null;
  const texto = trechoLatin1(buf, 0, buf.length);
  const partes = new Set();
  const re = /xl\/worksheets\/([A-Za-z0-9_-]+)\.xml/g;
  let m = re.exec(texto);
  while (m !== null) {
    partes.add(m[1]);
    m = re.exec(texto);
  }
  return partes.size;
}

/** Bytes → string latin1, sem depender de TextDecoder (o nó Code não garante). */
export function trechoLatin1(buf, inicio, fim) {
  if (!buf) return '';
  if (typeof buf.toString === 'function' && typeof buf.readUInt8 === 'function') {
    return buf.toString('latin1', inicio, Math.min(fim, buf.length));
  }
  let s = '';
  const ate = Math.min(fim, buf.length || 0);
  for (let i = inicio; i < ate; i += 1) s += String.fromCharCode(buf[i]);
  return s;
}

// TEXTO OU BINÁRIO — a pergunta que decide se vale ler o conteúdo como texto.
//
// O critério é o byte NUL e a densidade de bytes de controle. Texto real (mesmo
// UTF-8, mesmo com acento) não tem NUL; formato binário quase sempre tem nos
// primeiros KB. Esta função é o que impede um `.txt` que na verdade é um PDF
// renomeado de ser tratado como texto corrido — a assinatura já pegaria esse
// caso, mas nem todo binário tem assinatura conhecida, e "não sei" precisa cair
// em binário e não em texto.
//
// O LIMITE DE 1% NÃO É ARBITRÁRIO: é a folga para os caracteres de controle
// legítimos que aparecem em texto real (TAB, CR, LF, e o form-feed \x0C que TODA
// conversão de PDF para texto usa como quebra de página — o caso da AMO).
export function pareceTexto(buf, amostra = 8192) {
  const n = Math.min(amostra, (buf && buf.length) || 0);
  if (n === 0) return false;
  let controle = 0;
  for (let i = 0; i < n; i += 1) {
    const b = byteEm(buf, i);
    if (b === 0) return false; // NUL: binário, sem discussão
    // Controle = C0 menos os que existem em texto de verdade.
    if (b < 0x20 && b !== 0x09 && b !== 0x0a && b !== 0x0d && b !== 0x0c) controle += 1;
  }
  return controle / n < 0.01;
}

// --------------------------------------------------------------------------
// A FORMA DO TEXTO — a segunda pergunta, e ela é diferente da primeira.
// --------------------------------------------------------------------------
//
// Saber que é texto não diz COMO extrair. Um `.txt` pode ser:
//   • delimitado (CSV/TSV de verdade) → parseia em linhas e colunas;
//   • tabular por ESPAÇO (o que sai de "PDF de planilha → texto", o caso da
//     AMO) → colunas alinhadas por espaço, que nenhum parser de CSV lê;
//   • texto corrido (um contrato, uma nota explicativa) → vai como está.
//
// E os três vão para o MESMO lugar — a IA, como texto. A distinção não muda o
// destino; muda o que se AFIRMA sobre o documento e, no caso delimitado, permite
// normalizar antes de enviar. Por isso aqui não há ramo novo no roteador: há um
// campo a mais no item, e ele é DECLARADO em vez de suposto.

export const SEPARADORES = [
  { nome: 'ponto-e-virgula', char: ';' },
  { nome: 'virgula', char: ',' },
  { nome: 'tab', char: '\t' },
  { nome: 'barra-vertical', char: '|' },
];

/** Conta ocorrências de `alvo` FORA de aspas — a mesma doutrina de `parseCsv`. */
export function contarFora(linha, alvo) {
  let n = 0; let dentro = false;
  for (let i = 0; i < linha.length; i += 1) {
    const c = linha[i];
    if (c === '"') { if (dentro && linha[i + 1] === '"') { i += 1; continue; } dentro = !dentro; }
    else if (c === alvo && !dentro) n += 1;
  }
  return n;
}

/**
 * A forma do texto: `delimitado` (com o separador), `tabular-espaco`, ou
 * `corrido`. Olha as primeiras `maxLinhas` linhas não vazias.
 *
 * O CRITÉRIO DE "DELIMITADO" É CONSISTÊNCIA, não presença. Um contrato tem
 * vírgulas em toda linha e não é CSV; o que separa é a contagem ser a MESMA
 * linha após linha. Exige ≥2 colunas e ≥70% das linhas com a contagem modal —
 * abaixo disso é texto que por acaso tem separador.
 */
export function formaDoTexto(texto, { maxLinhas = 50 } = {}) {
  const linhas = String(texto || '').split(/\r?\n/).filter((l) => l.trim() !== '').slice(0, maxLinhas);
  if (linhas.length === 0) return { forma: 'vazio', separador: null, colunas: 0 };

  let melhor = null;
  for (const sep of SEPARADORES) {
    const contagens = linhas.map((l) => contarFora(l, sep.char));
    const freq = new Map();
    for (const c of contagens) if (c > 0) freq.set(c, (freq.get(c) || 0) + 1);
    if (freq.size === 0) continue;
    let modal = 0; let vezes = 0;
    for (const [c, v] of freq) if (v > vezes || (v === vezes && c > modal)) { modal = c; vezes = v; }
    const fracao = vezes / linhas.length;
    // ≥1 separador = ≥2 colunas.
    if (modal >= 1 && fracao >= 0.7) {
      const cand = { forma: 'delimitado', separador: sep.char, nomeSeparador: sep.nome, colunas: modal + 1, consistencia: fracao };
      if (!melhor || cand.colunas > melhor.colunas) melhor = cand;
    }
  }
  if (melhor) return melhor;

  // TABULAR POR ESPAÇO — o caso que a AMO trouxe e que nenhum parser de CSV lê.
  // Duas ou mais corridas de 2+ espaços na maioria das linhas é coluna alinhada,
  // não prosa. Prosa tem espaço simples entre palavras.
  const comColunas = linhas.filter((l) => (l.match(/ {2,}/g) || []).length >= 2).length;
  if (comColunas / linhas.length >= 0.6) {
    return { forma: 'tabular-espaco', separador: null, colunas: null, consistencia: comColunas / linhas.length };
  }
  return { forma: 'corrido', separador: null, colunas: null };
}

// --------------------------------------------------------------------------
// A DECISÃO
// --------------------------------------------------------------------------

/** Os formatos que o pipeline sabe extrair, e o nó/caminho de cada um. */
export const DESTINOS = {
  pdf: 'Extrair Texto',
  imagem: null,      // vai direto: o provedor lê a imagem
  xlsx: 'Extrair XLSX',
  xls: 'Extrair XLS',
  xml: null,         // texto: lido no próprio nó
  texto: null,       // texto: lido no próprio nó
  desconhecido: null,
};

/**
 * O formato REAL de um arquivo, medido nos bytes.
 *
 * @param buf Buffer/Uint8Array com os bytes do arquivo.
 * @param mimeDeclarado O `mimeType` que o upload declarou — usado SÓ como
 *        último recurso, e o resultado diz quando foi usado.
 * @param nome O nome do arquivo — usado SÓ para desempate declarado, nunca
 *        como evidência primária. Foi confiar nele que custou a rodada da AMO.
 *
 * Devolve `{ formato, evidencia, confiavel, detalhe, texto }`:
 *   • `evidencia`: 'assinatura' (bytes, definitivo) | 'conteudo-texto'
 *     (analisado) | 'mime-declarado' (acreditei) | 'nenhuma'
 *   • `confiavel`: true só quando a decisão saiu dos BYTES.
 *   • `texto`: presente quando o formato é texto — `{forma, separador, colunas}`.
 */
export function detectarFormato(buf, { mimeDeclarado = '', nome = '' } = {}) {
  const mt = String(mimeDeclarado || '').toLowerCase();
  const temBytes = !!buf && typeof buf.length === 'number' && buf.length > 0;

  if (temBytes) {
    for (const a of ASSINATURAS) {
      if (casaAssinatura(buf, a.bytes)) {
        if (a.formato !== 'zip') {
          return { formato: a.formato, evidencia: 'assinatura', confiavel: true,
            detalhe: `assinatura de ${a.formato} nos primeiros bytes` };
        }
        const sabor = saborDoZip(buf);
        if (sabor === 'xlsx') {
          return { formato: 'xlsx', evidencia: 'assinatura', confiavel: true,
            detalhe: 'container OOXML (ZIP) com entradas `xl/` — planilha moderna' };
        }
        // ZIP que NÃO é planilha: dizer o que é vale mais que "não suportado".
        return { formato: 'desconhecido', evidencia: 'assinatura', confiavel: true,
          detalhe: `container ZIP do tipo ${sabor} — o pipeline não extrai este formato` };
      }
    }

    if (pareceTexto(buf)) {
      const texto = trechoLatin1(buf, 0, Math.min(buf.length, 65536));
      const cabeca = texto.slice(0, 512).trim();
      // XML/HTML se declaram na primeira linha — e a diferença importa, porque
      // um `.xls` que o Excel exporta como HTML tem tabela e não é planilha
      // binária. Ancorado no INÍCIO: a substring 'xml' solta é o defeito que
      // `/xml$` já teve de consertar uma vez em `PADRAO_MIME`.
      if (/^<\?xml[\s\S]/i.test(cabeca)) {
        return { formato: 'xml', evidencia: 'assinatura', confiavel: true,
          detalhe: 'declaração `<?xml` no início do arquivo', texto: { forma: 'corrido' } };
      }
      if (/^<!doctype\s+html/i.test(cabeca) || /^<html[\s>]/i.test(cabeca)) {
        return { formato: 'texto', evidencia: 'conteudo-texto', confiavel: true,
          detalhe: 'HTML — vai como texto (tabelas de HTML são legíveis pelo modelo)',
          texto: { forma: 'html' } };
      }
      if (/^<(?:\w+:)?\w+[\s>]/.test(cabeca)) {
        return { formato: 'xml', evidencia: 'conteudo-texto', confiavel: true,
          detalhe: 'começa com elemento de marcação', texto: { forma: 'corrido' } };
      }
      const forma = formaDoTexto(texto);
      // O CONFLITO DECLARADO. Os bytes dizem texto e o upload declarou um
      // formato BINÁRIO (pdf/imagem/planilha): as duas coisas não podem ser
      // verdade. Os bytes ganham — um arquivo sem assinatura de PDF não é um
      // PDF, e mandá-lo como anexo binário ao modelo entrega lixo —, mas a
      // discordância vira `confiavel: false` em vez de sumir. É a regra 1 do
      // CLAUDE.md: um palpite silencioso tem a mesma aparência de uma medição.
      // MESMA regra de agrupamento da tabela de queda mais abaixo (S5850): o `^`
      // vale só para a alternativa em que está, e aqui isso É o que se quer —
      // `image/` ancorado (para não casar com um mimetype que só CONTENHA
      // "image/"), os outros livres. Agrupado, ninguém precisa deduzir isso.
      // `ms-excel` saiu por ser redundante: `excel` já casa com ele.
      const declaradoBinario = /pdf|(?:^image\/)|spreadsheetml|excel/.test(mt);
      if (declaradoBinario) {
        return { formato: 'texto', evidencia: 'conteudo-texto', confiavel: false,
          detalhe: `o upload declarou "${mt}", mas os bytes são TEXTO (${forma.forma}) `
            + 'e não trazem assinatura desse formato binário — tratado como texto, '
            + 'que é o que os bytes são. Se este arquivo deveria ser um PDF/planilha, '
            + 'ele chegou corrompido ou foi convertido antes do upload.',
          texto: forma };
      }
      return { formato: 'texto', evidencia: 'conteudo-texto', confiavel: true,
        detalhe: `texto ${forma.forma}${forma.separador ? ` (separador "${forma.separador}")` : ''}`,
        texto: forma };
    }
  }

  // OS BYTES NÃO DECIDIRAM. Cair no mimetype declarado é legítimo — o que não é
  // legítimo é esconder que caiu. `confiavel: false` viaja com o item e é o que
  // permite a quem lê distinguir medição de suposição.
  if (mt) {
    // AS ALTERNÂNCIAS VÃO AGRUPADAS, e não é preciosismo de analisador (S5850,
    // achado pelo Sonar no PR #213): numa regex `^a|b`, a âncora vale SÓ para a
    // primeira alternativa. `/^text\/|csv/` lê-se "começa com text/" OU "contém
    // csv em qualquer lugar" — que é de fato o que se quer aqui (`application/
    // csv` tem de casar), mas quem ler depois não tem como saber se foi escolha
    // ou descuido. Agrupado, a intenção fica no código em vez de no comentário.
    const porMime = [
      [/pdf/, 'pdf'], [/^image\//, 'imagem'], [/spreadsheetml/, 'xlsx'],
      // `excel` sozinho já cobre `ms-excel` (a alternância era redundante).
      [/excel/, 'xls'],
      // `/xml` ou `+xml`, ambos NO FIM — `application/xml` e `image/svg+xml`.
      // Ancorado no fim porque a substring "xml" solta casa com o mimetype do
      // XLSX (`...openxmlformats...`), o defeito que `PADRAO_MIME` já corrigiu.
      [/[/+]xml$/, 'xml'],
      // "começa com text/" OU "contém csv" — as duas intencionais.
      [/(?:^text\/)|csv/, 'texto'],
    ];
    for (const [re, formato] of porMime) {
      if (re.test(mt)) {
        return { formato, evidencia: 'mime-declarado', confiavel: false,
          detalhe: `os bytes não trouxeram assinatura conhecida; decidido pelo mimetype declarado no upload ("${mt}")` };
      }
    }
  }
  // OS DOIS CASOS SÃO DIFERENTES e a `evidencia` tem de dizer qual é. "Havia
  // bytes e eles não casaram com nada que este detector conhece" é uma MEDIÇÃO
  // (o arquivo é de um formato que o pipeline não trata); "o arquivo chegou sem
  // bytes" é uma falha de TRANSPORTE, e quem lê precisa reenviar em vez de
  // converter. Até aqui os dois devolviam `'nenhuma'` — o `detalhe` distinguia e
  // a `evidencia` não, dois campos sobre o mesmo fato discordando.
  return { formato: 'desconhecido', evidencia: temBytes ? 'conteudo-binario' : 'sem-bytes', confiavel: false,
    detalhe: temBytes
      ? `conteúdo binário sem assinatura conhecida (mimetype declarado: "${mt || 'ausente'}"${nome ? `, nome: "${nome}"` : ''})`
      : 'o arquivo chegou sem bytes' };
}
