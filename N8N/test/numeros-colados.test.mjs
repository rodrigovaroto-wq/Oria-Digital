// P6b (10/11/2026): números COLADOS no texto do PDF. Ver o comentário de `fracaoDeNumerosColados`.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, existsSync } from 'node:fs';
import { fracaoDeNumerosColados, camadaDeTextoDoPdf, MAX_FRACAO_NUMEROS_COLADOS } from '../lib/cobertura.mjs';

// REAL (regra 4): as 70 primeiras linhas do texto que o `Extrair Texto` de produção devolveu para
// `balancete_janaago26.pdf` (KRAUSPENHAR, execução 9586), copiadas de um arquivo salvo na sessão.
// O que NÃO está reproduzido: a resposta da IA (5 ou 3 valores, 303 contas descartadas) — é o relato
// da medição de produção. Aqui se prova só a metade determinística: este texto não vai como texto.
const KRAUS = readFileSync(new URL('./texto-krauspenhar-colado.txt', import.meta.url), 'utf8');
const BOOKS = ['canastra', 'vertentes', 'distress', 'espelho'].map((b) => new URL(`../../Dados de Teste/book-${b}/pdf/TEXTO_EXTRAIDO.json`, import.meta.url));
const CAPTURA = new URL('../../Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/textos.json', import.meta.url);

test('MEDIDO (P6b): o texto real do Krauspenhar dispara, com motivo e fração', () => {
  assert.ok(fracaoDeNumerosColados(KRAUS) > MAX_FRACAO_NUMEROS_COLADOS);
  const v = camadaDeTextoDoPdf(KRAUS, { paginas: 1 });
  assert.equal(v.usarTexto, false);
  assert.equal(v.motivo, 'numeros-colados');
  assert.ok(v.fracaoColados > MAX_FRACAO_NUMEROS_COLADOS);
  assert.match(v.explicacao, /colados/);
});

test('o que parece colado e não é: "1.234,56 " solto, milhar americano, câmbio de 4 casas, data, CNPJ, percentual', () => {
  const limpo = [
    'Caixa 1.234,56 2.345,67', 'Aging 3,829 1,356 957 7,978 31.0%', 'CONSOLIDADO (Empresas: 98,467)',
    'Taxa de fechamento 5,4408/US$. em 31/12/2025', 'CNPJ 11.507.766/0001-83 em 23/09/2026', 'Margem 12,5% (3,2%)',
    'Clientes (1.234,56) 7,00 D',
  ].join('\n');
  assert.equal(fracaoDeNumerosColados(limpo), 0);
  assert.equal(fracaoDeNumerosColados(''), 0);
  assert.equal(fracaoDeNumerosColados(null), 0);
});

test('CONTROLE NEGATIVO (P6b): nenhum documento dos books sintéticos nem das capturas de produção dispara', () => {
  let n = 0;
  const docs = [];
  for (const b of BOOKS) {
    assert.ok(existsSync(b), `falta ${b.pathname} — gere o book (ver .claude/COMANDOS-CANONICOS.md)`);
    docs.push(...Object.entries(JSON.parse(readFileSync(b, 'utf8')).documentos).map(([k, v]) => [k, Array.isArray(v) ? v.join('\n') : v.texto]));
  }
  docs.push(...Object.entries(JSON.parse(readFileSync(CAPTURA, 'utf8')).documentos).map(([k, v]) => [k, v.texto]));
  for (const [nome, texto] of docs) {
    n += 1;
    assert.equal(fracaoDeNumerosColados(texto), 0, `${nome}: falso positivo custa imagem à toa`);
  }
  assert.ok(n >= 90, `só ${n} documentos medidos — o controle ficou vazio`);
});
