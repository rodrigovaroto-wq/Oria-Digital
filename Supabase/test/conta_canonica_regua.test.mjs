// A SEGUNDA RÉGUA do catálogo `conta_canonica` (0242, P26): o catálogo do banco e `SECAO_CANONICA_ENUM`
// (N8N/lib/extract.mjs) têm de ser o MESMO conjunto, e a demonstração de cada seção tem de ser a que o portal
// roteia (`FAMILIA_POR_SECAO_CANONICA`, portal/src/lib/statement-templates.ts).
//
// POR QUE ESTE ARQUIVO EXISTE. A lista das 15 seções morava em duas cópias de código ("mantê-los IDÊNTICOS", diz o
// cabeçalho do extract.mjs) sem portão nenhum, e agora há uma terceira, no banco. O teste SQL mede o catálogo contra o
// DADO carregado (o que o extrator gravou nas fixtures), mas não importa .mjs: sozinho ele deixaria o enum ganhar uma
// 16ª seção que o catálogo não conhece — a IA passaria a devolvê-la e nenhuma conta a receberia. Este portão fecha
// esse lado e reprova quando UM dos três lados muda sozinho.
//
// COMO LÊ. O enum, por import (é o valor vivo, não texto). O mapa do portal e o seed, por texto: o primeiro é .ts (sem
// import cruzado, de propósito) e o segundo é SQL. O seed é lido de TODA migration que insere em `conta_canonica`, uma
// linha por nó no formato ('codigo', 'Nome', pai|null, 'demonstracao', 'natureza', secao|null, ordem).
// TETO: um UPDATE/DELETE em `conta_canonica` numa migration futura NÃO é visto aqui; quem alterar o catálogo por esses
// comandos atualiza o enum e este teste no mesmo commit (o teste SQL mede o banco montado e pega a outra metade).
//
// MEDIÇÃO NÃO-VAZIA (regra 2): os três últimos testes alimentam o comparador com a cópia ADULTERADA de cada lado
// (seção a mais no enum, seção a menos no seed, demonstração trocada no mapa do portal) e exigem que ele aponte
// exatamente a diferença; o número medido por lado está no cabeçalho de
// Supabase/migrations/0242_a_secao_que_so_existia_em_codigo.sql.

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { SECAO_CANONICA_ENUM } from '../../N8N/lib/extract.mjs';

const RAIZ = new URL('../..', import.meta.url).pathname.replace(/\/$/, '');
const MIGRATIONS = join(RAIZ, 'Supabase/migrations');
const TEMPLATES = join(RAIZ, 'portal/src/lib/statement-templates.ts');
const ESCAPE = 'NAO_CLASSIFICAVEL';

/** Os nós semeados por toda migration que insere em conta_canonica. */
export function lerSeed(textoDasMigrations) {
  const nos = [];
  const re = /^\s*\('(\w+)',\s*'[^']*',\s*(null|'\w+'),\s*'(\w+)',\s*'(\w+)',\s*(null|'\w+'),\s*(\d+)\)/;
  for (const texto of textoDasMigrations) {
    if (!/insert into conta_canonica/i.test(texto)) continue;
    for (const linha of texto.split('\n')) {
      if (linha.trimStart().startsWith('--')) continue;
      const m = linha.match(re);
      if (!m) continue;
      nos.push({
        codigo: m[1],
        pai: m[2] === 'null' ? null : m[2].slice(1, -1),
        demonstracao: m[3],
        natureza: m[4],
        secao: m[5] === 'null' ? null : m[5].slice(1, -1),
      });
    }
  }
  return nos;
}

/** O mapa seção → demonstração do portal. */
export function lerFamilia(textoTs) {
  const corpo = textoTs.match(/const FAMILIA_POR_SECAO_CANONICA[^{]*\{([\s\S]*?)\n\};/)?.[1] ?? '';
  const mapa = {};
  for (const m of corpo.matchAll(/^\s*(\w+):\s*"(\w+)",/gm)) mapa[m[1]] = m[2];
  return mapa;
}

/** As diferenças entre os três lados; vazio = o mesmo conjunto. */
export function comparar({ enumSecoes, seed, familia }) {
  const doEnum = new Set(enumSecoes.filter((s) => s !== ESCAPE));
  const doCatalogo = new Set(seed.filter((n) => n.secao).map((n) => n.secao));
  const doPortal = new Set(Object.keys(familia));
  const dif = [];
  for (const s of doEnum) if (!doCatalogo.has(s)) dif.push(`enum tem ${s}, o catálogo não`);
  for (const s of doCatalogo) if (!doEnum.has(s)) dif.push(`o catálogo tem ${s}, o enum não`);
  for (const s of doEnum) if (!doPortal.has(s)) dif.push(`enum tem ${s}, o mapa do portal não`);
  for (const s of doPortal) if (!doEnum.has(s)) dif.push(`o mapa do portal tem ${s}, o enum não`);
  for (const n of seed) {
    if (n.secao && familia[n.secao] && familia[n.secao] !== n.demonstracao) {
      dif.push(`${n.secao}: catálogo diz ${n.demonstracao}, o portal roteia para ${familia[n.secao]}`);
    }
  }
  return dif;
}

const migracoes = readdirSync(MIGRATIONS).filter((f) => f.endsWith('.sql')).sort()
  .map((f) => readFileSync(join(MIGRATIONS, f), 'utf8'));
const seed = lerSeed(migracoes);
const familia = lerFamilia(readFileSync(TEMPLATES, 'utf8'));

test('o portão não corre sobre o vazio: leu o enum, o mapa do portal e os 26 nós do seed', () => {
  assert.equal(SECAO_CANONICA_ENUM.length, 16, 'o enum tem as 15 seções e o escape');
  assert.equal(Object.keys(familia).length, 15);
  assert.equal(seed.length, 26);
});

test('o catálogo, o enum do extrator e o mapa do portal são o mesmo conjunto de seções, com a mesma demonstração', () => {
  assert.deepEqual(comparar({ enumSecoes: SECAO_CANONICA_ENUM, seed, familia }), []);
});

test('uma seção a mais no enum (a IA passaria a devolvê-la sem conta) é apontada', () => {
  const dif = comparar({ enumSecoes: [...SECAO_CANONICA_ENUM, 'provisoes'], seed, familia });
  assert.ok(dif.includes('enum tem provisoes, o catálogo não'), dif.join(' | '));
});

test('uma seção a menos no seed (conta que a IA ainda devolve some do catálogo) é apontada', () => {
  const sem = seed.filter((n) => n.secao !== 'dmpl');
  const dif = comparar({ enumSecoes: SECAO_CANONICA_ENUM, seed: sem, familia });
  assert.ok(dif.includes('enum tem dmpl, o catálogo não'), dif.join(' | '));
});

test('a demonstração trocada num dos lados (o portal roteia para outra aba) é apontada', () => {
  const dif = comparar({ enumSecoes: SECAO_CANONICA_ENUM, seed, familia: { ...familia, custos: 'balanco' } });
  assert.ok(dif.includes('custos: catálogo diz dre, o portal roteia para balanco'), dif.join(' | '));
});

test('o escape NAO_CLASSIFICAVEL não é seção do catálogo', () => {
  assert.ok(!seed.some((n) => n.secao === ESCAPE));
  assert.ok(SECAO_CANONICA_ENUM.includes(ESCAPE), 'o enum ainda tem o escape (senão este teste não mede nada)');
});
