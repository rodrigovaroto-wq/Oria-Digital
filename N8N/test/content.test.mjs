// A PARTE DE CONTEÚDO, NOS DOIS DIALETOS.
//
// Este arquivo testava só a forma da OpenAI, e por isso não teria dito nada no
// dia em que o provedor mudou: `contentPartFromFile` continuava devolvendo um
// objeto, só que um que o Google recusa com 400. Agora cada asserção roda para
// TODO provedor do catálogo, com a forma esperada declarada por dialeto — a
// entrada de um provedor novo em `lib/provedor.mjs` sem a sua linha aqui é uma
// suíte que reprova, não um silêncio.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { contentPartFromFile, isSpreadsheet, buildClassificationRequest } from '../lib/ia.mjs';
import { PROVEDORES } from '../lib/provedor.mjs';

const CADA_PROVEDOR = Object.values(PROVEDORES);

/** O texto de uma parte, seja qual for o dialeto (`text` nos dois, na verdade). */
const textoDaParte = (p) => (typeof p.text === 'string' ? p.text : null);

test('isSpreadsheet reconhece xlsx/xls/csv', () => {
  assert.equal(isSpreadsheet('application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'), true);
  assert.equal(isSpreadsheet('application/vnd.ms-excel'), true);
  assert.equal(isSpreadsheet('text/csv'), true);
  assert.equal(isSpreadsheet('application/pdf'), false);
});

test('contentPartFromFile — o PDF chega ao modelo COMO PDF em todo provedor', () => {
  for (const prov of CADA_PROVEDOR) {
    const p = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'dre.pdf' }, prov);
    if (prov.dialeto === 'gemini') {
      assert.equal(p.inlineData.mimeType, 'application/pdf', prov.id);
      assert.equal(p.inlineData.data, 'QUJD', prov.id);
    } else {
      assert.equal(p.type, 'file', prov.id);
      assert.equal(p.file.filename, 'dre.pdf', prov.id);
      assert.match(p.file.file_data, /^data:application\/pdf;base64,QUJD$/);
    }
    // O INVARIANTE QUE VALE PARA OS DOIS, e é o que esta troca comprou: o PDF vai
    // inteiro, como PDF, sem ninguém no meio o transformando em imagem de página.
    assert.ok(JSON.stringify(p).includes('QUJD'), `${prov.id}: o conteúdo do arquivo tem de ir junto`);
  }
});

test('contentPartFromFile — imagem vira parte de imagem em todo provedor', () => {
  for (const prov of CADA_PROVEDOR) {
    const p = contentPartFromFile({ mimeType: 'image/png', base64: 'QUJD' }, prov);
    if (prov.dialeto === 'gemini') {
      assert.equal(p.inlineData.mimeType, 'image/png', prov.id);
      assert.equal(p.inlineData.data, 'QUJD', prov.id);
    } else {
      assert.equal(p.type, 'image_url', prov.id);
      assert.match(p.image_url.url, /^data:image\/png;base64,QUJD$/);
    }
  }
});

test('contentPartFromFile — texto extraído (planilha) vira parte de texto e é truncado', () => {
  for (const prov of CADA_PROVEDOR) {
    const p = contentPartFromFile({ mimeType: 'text/csv', text: 'a'.repeat(30000) }, prov);
    assert.equal(textoDaParte(p).length, 20000, prov.id);
  }
});

test('contentPartFromFile — tipo não suportado não lança (fail-safe), em todo provedor', () => {
  for (const prov of CADA_PROVEDOR) {
    const p = contentPartFromFile({ mimeType: 'application/zip', filename: 'x.zip' }, prov);
    assert.match(textoDaParte(p), /requer extração prévia/, prov.id);
  }
});

test('buildClassificationRequest leva o conteúdo na mensagem do usuário, em todo provedor', () => {
  for (const prov of CADA_PROVEDOR) {
    const part = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'x.pdf' }, prov);
    const req = buildClassificationRequest({ nomeOriginal: 'x.pdf', conteudo: part, prov });
    const partes = prov.dialeto === 'gemini'
      ? req.body.contents[req.body.contents.length - 1].parts
      : req.body.messages[req.body.messages.length - 1].content;
    assert.equal(partes.length, 2, `${prov.id}: a dica do nome e o arquivo`);
    assert.deepEqual(partes[1], part, prov.id);
  }
});

test('buildClassificationRequest põe o prompt de sistema em campo PRÓPRIO — é a condição do cache', () => {
  // Concatenar o prompt de sistema na mensagem do usuário funcionaria e custaria
  // ~40% a mais em toda chamada: o cache de prefixo só vale para o prefixo
  // IDÊNTICO, e a mensagem do usuário carrega o nome do arquivo. Nos dois
  // dialetos o sistema tem casa própria — este teste é o que impede alguém de
  // "simplificar" juntando os dois.
  for (const prov of CADA_PROVEDOR) {
    const req = buildClassificationRequest({
      nomeOriginal: 'x.pdf',
      conteudo: contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD' }, prov),
      prov,
    });
    const sistema = prov.dialeto === 'gemini'
      ? req.body.systemInstruction.parts[0].text
      : req.body.messages[0].content;
    assert.match(sistema, /classifica documentos financeiros/i, prov.id);
    assert.ok(!sistema.includes('x.pdf'), `${prov.id}: nada do documento pode entrar no prefixo`);
  }
});

test('a URL da chamada é a do provedor, e o modelo do Google vai NELA', () => {
  for (const prov of CADA_PROVEDOR) {
    const req = buildClassificationRequest({
      nomeOriginal: 'x.pdf',
      conteudo: contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD' }, prov),
      model: 'modelo-de-teste',
      prov,
    });
    assert.equal(req.method, 'POST', prov.id);
    if (prov.dialeto === 'gemini') {
      // No Google o modelo é parte do ENDEREÇO. Um id errado é 404 na URL, e não
      // erro de corpo — é por isso que `diagnosticarErroApi` trata 404 como
      // modelo indisponível, e é isso que este assert trava.
      assert.match(req.url, /models\/modelo-de-teste:generateContent$/, prov.id);
      assert.equal(req.body.model, undefined, `${prov.id}: modelo no corpo seria campo desconhecido`);
    } else {
      assert.equal(req.url, 'https://api.openai.com/v1/chat/completions');
      assert.equal(req.body.model, 'modelo-de-teste');
    }
  }
});

test('o prompt de classificação manda o acumulado no ano virar NM+ano, nunca anual (DRE jan-ago/2026)', () => {
  for (const prov of CADA_PROVEDOR) {
    const part = contentPartFromFile({ mimeType: 'application/pdf', base64: 'QUJD', filename: 'x.pdf' }, prov);
    const req = buildClassificationRequest({ nomeOriginal: 'DRE_janaago26.pdf', conteudo: part, prov });
    assert.match(JSON.stringify(req.body), /MENOS de 12 meses[^]*8M26[^]*nunca[^]*anual/, prov.id);
  }
});
