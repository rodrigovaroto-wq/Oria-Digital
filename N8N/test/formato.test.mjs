import { test } from 'node:test';
import assert from 'node:assert/strict';
import { detectarFormato, formaDoTexto, abasDoXlsx } from '../lib/formato.mjs';
import { xlsxMinimo } from './zip-minimo.mjs';

// --------------------------------------------------------------------------
// O CASO DA AMO, REPRODUZIDO — 60/60 documentos em 12/09/2026.
// --------------------------------------------------------------------------
//
// Planilha que estava dentro de um PDF, convertida para texto por quem subiu
// o arquivo: colunas alinhadas por ESPAÇO, com \x0C (form-feed) separando
// página — exatamente o que uma conversão de PDF para texto produz — e
// mimeType declarado `text/plain`, porque foi assim que o upload chegou.
const TEXTO_TABULAR_AMO = [
  'Balanço Patrimonial',
  '',
  'Caixa e equivalentes        1.234.567     987.654',
  'Contas a receber             456.789     321.098',
  'Estoques                     234.567     198.765',
  '\x0C',
  'Fornecedores                 345.678     287.654',
  'Empréstimos                  567.890     498.321',
  'Patrimônio líquido          1.987.654   1.654.321',
].join('\n');

test('AMO: texto tabular por espaço declarado text/plain vira formato texto, forma tabular-espaco, confiavel', () => {
  const buf = Buffer.from(TEXTO_TABULAR_AMO, 'latin1');
  const r = detectarFormato(buf, { mimeDeclarado: 'text/plain', nome: 'balanco.txt' });
  assert.equal(r.formato, 'texto');
  assert.notEqual(r.formato, 'xlsx');
  assert.equal(r.texto.forma, 'tabular-espaco');
  assert.equal(r.confiavel, true);
  // Nunca pode exigir nó nativo de planilha (Extrair XLSX/XLS) — é exatamente
  // o roteamento que rejeitou os 60 arquivos por mimeType inválido.
  assert.notEqual(r.formato, 'xls');
});

// --------------------------------------------------------------------------
// EXTENSÃO MENTIROSA NÃO ENGANA.
// --------------------------------------------------------------------------

test('bytes de PDF declarados text/plain: formato decide pela assinatura, não pelo mimetype', () => {
  const buf = Buffer.concat([Buffer.from('%PDF-1.7\n%âãÏÓ\n'), Buffer.from('resto do conteudo binario')]);
  const r = detectarFormato(buf, { mimeDeclarado: 'text/plain', nome: 'planilha.txt' });
  assert.equal(r.formato, 'pdf');
  assert.equal(r.evidencia, 'assinatura');
});

test('bytes de XLSX (zip + xl/) declarados text/plain: formato decide pela assinatura', () => {
  const buf = Buffer.concat([
    Buffer.from([0x50, 0x4b, 0x03, 0x04]),
    Buffer.from('algum preenchimento xl/workbook.xml resto do diretorio central'),
  ]);
  const r = detectarFormato(buf, { mimeDeclarado: 'text/plain', nome: 'demonstrativo.txt' });
  assert.equal(r.formato, 'xlsx');
  assert.equal(r.evidencia, 'assinatura');
});

// --------------------------------------------------------------------------
// ZIP QUE NÃO É PLANILHA NÃO VIRA PLANILHA.
// --------------------------------------------------------------------------

test('zip com entradas word/ nao vira xlsx — rotear docx ao extrator de planilha é o defeito irmao', () => {
  const buf = Buffer.concat([
    Buffer.from([0x50, 0x4b, 0x03, 0x04]),
    Buffer.from('word/document.xml resto do conteudo do pacote OOXML'),
  ]);
  const r = detectarFormato(buf, { mimeDeclarado: 'application/octet-stream' });
  assert.notEqual(r.formato, 'xlsx');
});

// --------------------------------------------------------------------------
// DELIMITADO DE VERDADE É DISTINGUIDO DE PROSA.
// --------------------------------------------------------------------------

test('CSV com ponto-e-virgula consistente: forma delimitado, separador correto', () => {
  const csv = [
    'conta;jan;fev;mar',
    'caixa;100;110;120',
    'receber;200;210;220',
    'estoques;50;55;60',
  ].join('\n');
  const r = formaDoTexto(csv);
  assert.equal(r.forma, 'delimitado');
  assert.equal(r.separador, ';');
});

test('contrato em prosa com virgulas em toda linha: NUNCA delimitado', () => {
  const contrato = [
    'O presente instrumento, doravante denominado Contrato, é celebrado entre as partes.',
    'A CONTRATANTE, pessoa jurídica de direito privado, e a CONTRATADA, sociedade limitada.',
    'As partes acordam, de comum acordo, os termos abaixo, sujeitos à legislação vigente.',
    'Fica eleito, para dirimir quaisquer controvérsias, o foro da comarca de São Paulo.',
  ].join('\n');
  const r = formaDoTexto(contrato);
  assert.notEqual(r.forma, 'delimitado');
  assert.equal(r.forma, 'corrido');
});

// --------------------------------------------------------------------------
// BINÁRIO SEM ASSINATURA CONHECIDA NÃO VIRA TEXTO.
// --------------------------------------------------------------------------

test('buffer com NUL nao vira formato texto mesmo sem assinatura conhecida', () => {
  // ATENÇÃO À FIXTURE: um NUL sozinho não basta para isolar esta checagem —
  // um buffer curto e majoritariamente de bytes de controle já reprova pelo
  // limiar de DENSIDADE (regra 4 do CLAUDE.md: fixture nasceu vazia na
  // primeira tentativa, com poucos bytes de controle "de sobra" — o mesmo
  // teste passava IGUAL com a checagem de NUL desligada, porque a densidade
  // sozinha já classificava como binário). Aqui o corpo é texto de verdade
  // — só o NUL, no meio de ~700 bytes de prosa normal, precisa decidir.
  const prosaAntes = 'Balanco patrimonial da empresa em 31 de dezembro. '.repeat(10);
  const prosaDepois = ' Ativos totais e passivos totais conferem com o razao.'.repeat(10);
  const buf = Buffer.concat([Buffer.from(prosaAntes, 'latin1'), Buffer.from([0x00]), Buffer.from(prosaDepois, 'latin1')]);
  const r = detectarFormato(buf, { mimeDeclarado: '' });
  assert.notEqual(r.formato, 'texto');
});

// --------------------------------------------------------------------------
// SUPOSIÇÃO É DECLARADA (regra 1 do CLAUDE.md aplicada ao detector).
// --------------------------------------------------------------------------

test('quando os bytes nao decidem, confiavel é false e evidencia é mime-declarado', () => {
  // Bytes sem assinatura conhecida E que não passam em pareceTexto (tem NUL) —
  // então cai direto no mimetype declarado.
  const buf = Buffer.from([0x01, 0x02, 0x00, 0x03, 0x04, 0x00, 0x05]);
  const r = detectarFormato(buf, { mimeDeclarado: 'application/pdf' });
  assert.equal(r.confiavel, false);
  assert.equal(r.evidencia, 'mime-declarado');
  assert.equal(r.formato, 'pdf');
});

test('desconhecido distingue "havia bytes" de "chegou sem bytes" — dois casos, duas evidencias', () => {
  // ACHADO PELO SONAR (S3923, PR #213): os dois ramos devolviam `'nenhuma'`,
  // enquanto o `detalhe` logo abaixo já distinguia — dois campos sobre o mesmo
  // fato discordando. E a distinção MUDA O QUE FAZER: bytes que não casam com
  // nada é um formato que este pipeline não trata (converter e reenviar); zero
  // bytes é falha de TRANSPORTE (reenviar o mesmo arquivo). Sem este teste, a
  // correção do Sonar teria sido só calar o analisador.
  const binarioDesconhecido = Buffer.from([0x00, 0x01, 0xab, 0xcd, 0x00, 0xef]);
  const r1 = detectarFormato(binarioDesconhecido, { mimeDeclarado: 'application/octet-stream' });
  assert.equal(r1.formato, 'desconhecido');
  assert.equal(r1.evidencia, 'conteudo-binario', 'havia bytes, e eles não casaram com nada conhecido');

  const r2 = detectarFormato(Buffer.alloc(0), { mimeDeclarado: '' });
  assert.equal(r2.formato, 'desconhecido');
  assert.equal(r2.evidencia, 'sem-bytes', 'o arquivo chegou sem bytes — é falha de transporte');
  assert.notEqual(r1.evidencia, r2.evidencia, 'os dois casos NUNCA podem colapsar num rótulo só');
});

test('queda por mimetype declarado: a tabela mapeia cada familia ao formato certo', () => {
  // O ramo de queda tem uma ALTERNÂNCIA ANCORADA que o Sonar apontou (S5850, PR
  // #213): em `^text/|csv` a âncora vale só para a primeira alternativa, ou seja
  // "começa com text/" OU "contém csv em qualquer lugar". As duas são
  // intencionais — `application/csv` tem de casar —, e é isso que este teste
  // trava: sem ele, "consertar" a regex para `^(?:text\/|csv)` passa despercebido
  // e todo `application/csv` deixa de ser reconhecido.
  //
  // Bytes sem assinatura E com NUL (para não cair em `pareceTexto`), forçando a
  // decisão para o mimetype declarado.
  const opaco = Buffer.from([0x01, 0x00, 0x02, 0x00, 0x03]);
  const porMime = (mt) => detectarFormato(opaco, { mimeDeclarado: mt }).formato;

  assert.equal(porMime('application/pdf'), 'pdf');
  assert.equal(porMime('image/png'), 'imagem');
  assert.equal(porMime('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), 'xlsx');
  assert.equal(porMime('application/vnd.ms-excel'), 'xls');
  assert.equal(porMime('application/xml'), 'xml');
  assert.equal(porMime('text/plain'), 'texto');
  assert.equal(porMime('application/csv'), 'texto',
    'csv NÃO é ancorado no início de propósito — `application/csv` tem de casar');
  assert.equal(porMime('text/csv'), 'texto');

  // SVG é IMAGEM, não XML, porque `^image/` é avaliado antes. A ordem da tabela
  // é comportamento, não detalhe: invertida, todo SVG iria para o ramo de XML.
  assert.equal(porMime('image/svg+xml'), 'imagem');
});

// --------------------------------------------------------------------------
// formaDoTexto COM TEXTO VAZIO NÃO ESTOURA.
// --------------------------------------------------------------------------

test('formaDoTexto de texto vazio devolve forma vazio, sem lançar', () => {
  assert.deepEqual(formaDoTexto(''), { forma: 'vazio', separador: null, colunas: 0 });
  assert.deepEqual(formaDoTexto('   \n  \n'), { forma: 'vazio', separador: null, colunas: 0 });
  assert.deepEqual(formaDoTexto(null), { forma: 'vazio', separador: null, colunas: 0 });
});

// --------------------------------------------------------------------------
// QUANTAS ABAS — o que o extrator nativo não diz (lê só a primeira).
// --------------------------------------------------------------------------
// `Endividamento Krauspenhar.xlsx` (mandato real) gravou 0 linhas: a 1ª aba é um
// índice e a tabela está em "Abertura endividamento". O arquivo real não está no
// repositório; o xlsx abaixo é MÍNIMO, gerado com a estrutura descrita (zip com
// deflate de verdade), não a planilha do cliente.
const ABERTURA = [['Conta', 'Saldo'], ['Banco A', '1000']];
test('abasDoXlsx: xlsx com índice + tabela tem 2 abas, e o NOME da aba não é legível sem descompactar', () => {
  const buf = xlsxMinimo([['Índice', [['Abas']]], ['Abertura endividamento', ABERTURA]]);
  assert.equal(detectarFormato(buf, { mimeDeclarado: '', nome: 'Endividamento.xlsx' }).formato, 'xlsx');
  assert.equal(abasDoXlsx(buf), 2);
  // O limite, dito em teste: o nome mora no workbook.xml comprimido.
  assert.equal(buf.includes('Abertura endividamento'), false);
});

test('abasDoXlsx: uma aba conta 1; buffer vazio é null (ausência, não zero); não-zip é 0', () => {
  assert.equal(abasDoXlsx(xlsxMinimo([['Única', ABERTURA]])), 1);
  assert.equal(abasDoXlsx(Buffer.alloc(0)), null);
  assert.equal(abasDoXlsx(null), null);
  assert.equal(abasDoXlsx(Buffer.from('conta;saldo\n1;2')), 0);
});
