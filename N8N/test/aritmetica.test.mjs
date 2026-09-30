// Testa as duas identidades novas de N8N/lib/aritmetica.mjs.
//
// REGRA 4 DO CLAUDE.md (não fabricar fixture para provar bug de produção):
// os casos de LINHA usam os números REAIS medidos no relatório de faturamento
// OMNIBEAUTY 2025 (12/09/2026) — Saídas 2.371.829,89 e Total 2.311.829,89,
// diferença de R$ 60.000,00. A coluna "Total" reduzida a DUAS colunas (Saídas
// e Total, em vez das quatro reais — Saídas | Serviços | Outros | Total) é a
// única simplificação: não tenho os valores reais de Serviços/Outros daquele
// mês, e inventá-los seria fabricar o que a regra 4 proíbe. Com duas colunas
// a identidade testada é a mesma aritmética (soma das partes vs. coluna
// Total) e a divergência medida (R$ 60 mil) é preservada exatamente.
//
// O caso de SÉRIE (Totais do rodapé contra os 12 meses) não tem os 12 valores
// reais medidos — só o total do rodapé (51.271.444,92) e que "a leitura mais
// próxima erra em R$ 660". Reproduzir os 12 meses seria fabricar 11 números
// que não medi. Os testes de série abaixo usam números SINTÉTICOS, limpos,
// para provar o MECANISMO (soma de N parcelas contra o total da coluna) —
// não para reproduzir o defeito da OMNIBEAUTY especificamente.
//
// AMOBELEZA (ATIVO=PASSIVO) e GENERAL TABACO (CIRCULANTE+NAO_CIRCULANTE=
// ATIVO) são as identidades (a) e (b) do pedido — já cobertas no Postgres
// (fn_reconciliar_ativo_passivo_pl, 0009→0034; fn_reconciliar_arvore, 0133/
// 0151), rodando por documento no nó "Reconciliar (Classe A)", já wired no
// grafo. Os testes "AMOBELEZA não dispara aqui" abaixo confirmam que as
// funções NOVAS deste arquivo ficam caladas nesse formato de rótulo — não
// reimplementam (a)/(b) e não abrem pendência duplicada para o que o Postgres
// já pega.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { conferirIdentidadeDeLinha, conferirTotalDaSerie } from '../lib/aritmetica.mjs';

const linha = (ordem, chave, periodo_coluna, valor_num, extra = {}) => ({
  ordem, chave, periodo_coluna, entidade_coluna: null, valor_num,
  unidade: 'unidade', moeda: 'BRL', ...extra,
});

// -----------------------------------------------------------------------------
// conferirIdentidadeDeLinha — identidade (c), forma de LINHA
// -----------------------------------------------------------------------------

test('identidade de linha: acusa a divergência REAL da OMNIBEAUTY (Jan/2025, R$ 60.000,00)', () => {
  const campos = [
    linha(0, 'Janeiro', 'Saídas', 2_371_829.89),
    linha(0, 'Janeiro', 'Total', 2_311_829.89),
  ];
  const problemas = conferirIdentidadeDeLinha(campos);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /Janeiro/);
  assert.match(problemas[0], /60000\.00|60,000\.00/);
});

test('identidade de linha: fecha quando as parcelas batem com o total (dentro da tolerância)', () => {
  const campos = [
    linha(0, 'Fevereiro', 'Saídas', 1_000_000),
    linha(0, 'Fevereiro', 'Serviços', 200_000),
    linha(0, 'Fevereiro', 'Outros', 50_000),
    linha(0, 'Fevereiro', 'Total', 1_250_000),
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
});

test('identidade de linha: 1 centavo de arredondamento NÃO acusa (tolerância cobre)', () => {
  const campos = [
    linha(0, 'Março', 'Saídas', 100.00),
    linha(0, 'Março', 'Serviços', 50.005),
    linha(0, 'Março', 'Total', 150.00), // soma real 150.005, diff 0.005
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
});

test('identidade de linha: parcela AUSENTE (valor_num null) não vira zero — não confere, não acusa', () => {
  const campos = [
    linha(0, 'Maio', 'Saídas', null), // "Bed DedI 9" — texto não numérico, valor_num nunca chega a existir
    linha(0, 'Maio', 'Serviços', 10_000),
    linha(0, 'Maio', 'Total', 500_000), // divergiria muito se Saídas virasse 0 — e não pode
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), [],
    'ausência de uma parcela é "não dá para conferir", nunca "não confere" (regra 1 do CLAUDE.md)');
});

test('identidade de linha: unidade mista entre parcela e total — pré-condição não satisfeita, não acusa', () => {
  const campos = [
    linha(0, 'Junho', 'Saídas', 1000, { unidade: 'milhar' }),
    linha(0, 'Junho', 'Total', 1000, { unidade: 'unidade' }), // mesma leitura, unidade diferente: 1000x de diferença real
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
});

test('identidade de linha: duas colunas "Total" na mesma linha é ambíguo — não acusa', () => {
  const campos = [
    linha(0, 'Julho', 'Total', 100),
    linha(0, 'Julho', 'Total Geral', 999), // ambas casam no regex de "total"
    linha(0, 'Julho', 'Saídas', 100),
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
});

test('identidade de linha: "Total do Ativo" NÃO é tratado aqui — é conceito específico, já é o Postgres que confere', () => {
  const campos = [
    linha(0, 'ATIVO', 'Total do Ativo', 100),
    linha(0, 'ATIVO', 'Circulante', 40),
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
});

test('identidade de linha: entrada não-array ou vazia não estoura', () => {
  assert.deepEqual(conferirIdentidadeDeLinha([]), []);
  assert.deepEqual(conferirIdentidadeDeLinha(null), []);
  assert.deepEqual(conferirIdentidadeDeLinha(undefined), []);
});

// -----------------------------------------------------------------------------
// conferirTotalDaSerie — identidade (c), forma de SÉRIE
// -----------------------------------------------------------------------------

test('total da série: acusa quando o "Totais" do rodapé não bate com a soma da série (mecanismo, números sintéticos)', () => {
  const campos = [
    linha(0, 'Jan', 'Total', 100_000),
    linha(1, 'Fev', 'Total', 100_000),
    linha(2, 'Mar', 'Total', 100_000),
    linha(3, 'Totais', 'Total', 250_000), // deveria ser 300.000
  ];
  const problemas = conferirTotalDaSerie(campos);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /Totais/);
  assert.match(problemas[0], /50000\.00/);
});

test('total da série: fecha quando o total bate com a soma da série', () => {
  const campos = [
    linha(0, 'Jan', 'Total', 100_000),
    linha(1, 'Fev', 'Total', 100_000),
    linha(2, 'Mar', 'Total', 100_000),
    linha(3, 'Totais', 'Total', 300_000),
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('total da série: uma única parcela não é série — não acusa (evita falso positivo com 1 mês)', () => {
  const campos = [
    linha(0, 'Jan', 'Total', 100_000),
    linha(1, 'Totais', 'Total', 999_000_000), // absurdo, mas só há UMA parcela: não é série
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('total da série: parcela ausente (mês não extraído/ilegível) — não acusa, cobertura.mjs é quem mede isso', () => {
  const campos = [
    linha(0, 'Jan', 'Total', 100_000),
    linha(1, 'Fev', 'Total', null), // mês corrompido: valor nunca chegou a existir
    linha(2, 'Mar', 'Total', 100_000),
    linha(3, 'Totais', 'Total', 300_000), // divergiria se Fev virasse 0, e não pode
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('total da série: sem linha "Totais" na coluna — nada a conferir', () => {
  const campos = [
    linha(0, 'Jan', 'Total', 100_000),
    linha(1, 'Fev', 'Total', 100_000),
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

// -----------------------------------------------------------------------------
// AMOBELEZA / GENERAL TABACO — (a) e (b) já são do Postgres; as funções NOVAS
// deste arquivo ficam caladas nesse formato, e não duplicam a pendência.
// -----------------------------------------------------------------------------

test('AMOBELEZA (ATIVO=PASSIVO=64.126.203,52): nenhuma das duas funções novas dispara — é (a), já é do Postgres', () => {
  const campos = [
    linha(0, 'ATIVO', null, 64_126_203.52),
    linha(1, 'PASSIVO', null, 64_126_203.52),
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('GENERAL TABACO (CIRCULANTE+NAO_CIRCULANTE=ATIVO): nenhuma das duas funções novas dispara — é (b), já é do Postgres', () => {
  const campos = [
    linha(0, 'CIRCULANTE', null, 10_035_063.87),
    linha(1, 'NAO_CIRCULANTE', null, 2_295_330.92),
    linha(2, 'ATIVO', null, 12_330_394.79),
  ];
  assert.deepEqual(conferirIdentidadeDeLinha(campos), []);
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

// O ARRANJO REAL do faturamento 24M do book Vertentes, como a extração de
// produção o gravou (30/09/2026, caso bb37f726, `10_Faturamento_24M_...pdf`):
// 12 meses, a linha "TOTAL DO EXERCÍCIO", e DEPOIS dela duas linhas de memória
// na MESMA coluna ("Média mensal" e um indicador). Os 12 meses fecham EXATOS em
// 183.480. A checagem somava as memórias como parcela e abria `extracao_falhou`
// falsa: "soma das 14 linha(s) 198808.2" = 183.480 + 15.290 + 38,2.
test('total da série: as linhas DEPOIS do total são memória, não parcela (arranjo medido em produção)', () => {
  const meses = [15493, 15948, 16404, 16100, 16708, 15796, 15189, 15644, 14885, 14429, 13974, 12910];
  const campos = [
    ...meses.map((v, i) => linha(i, `mes ${i + 1}`, '2024', v)),
    linha(12, 'TOTAL DO EXERCÍCIO', '2024', 183480),
    linha(13, 'Média mensal', '2024', 15290),
    linha(14, 'Ticket médio por pedido (R$ mil) — indicador gerencial', '2024', 38.2),
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('total da série: uma coluna de variação % não é série (somar variações mensais não dá a anual)', () => {
  const variacoes = [-2.1, -3.4, -5, -1.2, -4.8, -2.2, -0.9, -3.1, -2.5, -1.7, -2.8, -3.4];
  const campos = [
    ...variacoes.map((v, i) => linha(i, `mes ${i + 1}`, 'Variação %', v)),
    linha(12, 'TOTAL DO EXERCÍCIO', 'Variação %', -24.6),
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('total da série: o controle — um mês perdido ANTES do total continua acusando', () => {
  const meses = [15493, 15948, 16404, 16100, 16708, 15796, 15189, 15644, 14885, 14429, 13974];
  const campos = [
    ...meses.map((v, i) => linha(i, `mes ${i + 1}`, '2024', v)),
    linha(11, 'TOTAL DO EXERCÍCIO', '2024', 183480),
    linha(12, 'Média mensal', '2024', 15290),
  ];
  const problemas = conferirTotalDaSerie(campos);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /12910\.00/);
});
