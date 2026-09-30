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
import { conferirIdentidadeDeLinha, conferirTotalDaSerie, conferirBalanceteLinhaALinha } from '../lib/aritmetica.mjs';

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

// O ARRANJO REAL do doc 63a36efe (FATURAMENTO OMNIBEAUTY PR 202606.pdf, caso
// "AMO teste 00"): o modelo devolveu "Totais" na ordem 0, ANTES dos 12 meses, e com
// os valores deslocados de coluna ("Outros R$" = soma dos meses contra meses que
// somam 0; "Total R$" = 0 contra meses que somam a soma). A pendência que o código
// anterior à 9bd2f88 abria está CERTA; com a regra "só o que vem antes do total" ela
// sumia e a checagem era pulada sem aviso (6 grupos no campo_extraido de produção).
// Os valores dos meses são os da reprodução do revisor, não os do PDF.
test('total da série: total impresso ANTES dos meses — os meses que vêm depois entram e a coluna deslocada reprova', () => {
  const meses = [242930.61, 267912.14, 264724.14, 280000, 290000, 300000, 310000, 320000, 330000, 250000, 246100.73, 250000];
  const soma = meses.reduce((a, b) => a + b, 0);
  const campos = [
    linha(0, 'Totais', 'Outros R$', soma),
    linha(0, 'Totais', 'Total R$', 0),
    ...meses.flatMap((v, i) => [
      linha(i + 1, `Mes ${i + 1} 2025`, 'Outros R$', 0),
      linha(i + 1, `Mes ${i + 1} 2025`, 'Total R$', v),
    ]),
  ];
  const problemas = conferirTotalDaSerie(campos);
  assert.equal(problemas.length, 2);
  assert.ok(problemas.some((p) => /coluna "Outros R\$"/.test(p) && /soma das 12 linha/.test(p)));
  assert.ok(problemas.some((p) => /coluna "Total R\$"/.test(p) && /soma das 12 linha/.test(p)));
});

test('total da série: total no topo que FECHA com os meses depois não acusa', () => {
  const meses = [100, 200, 300];
  const campos = [
    linha(0, 'Totais', '2025', 600),
    ...meses.map((v, i) => linha(i + 1, `mes ${i + 1}`, '2025', v)),
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

test('total da série: total no topo, memória depois dos meses, nunca entra na soma', () => {
  const campos = [
    linha(0, 'Totais', '2025', 600),
    linha(1, 'mes 1', '2025', 100), linha(2, 'mes 2', '2025', 200), linha(3, 'mes 3', '2025', 300),
    linha(4, 'Média mensal', '2025', 200),
    linha(5, 'Ticket médio', '2025', 38.2),
  ];
  assert.deepEqual(conferirTotalDaSerie(campos), []);
});

// Coluna não aditiva por PALAVRA INTEIRA: "Intermediação" contém "media" e
// "Receita variável" contém "varia", e são colunas de R$ com série.
test('total da série: coluna de R$ cujo nome CONTÉM media/varia por substring ainda é conferida', () => {
  for (const col of ['Intermediação R$', 'Receita variável', 'Taxas de serviço']) {
    const campos = [
      linha(0, 'mes 1', col, 100), linha(1, 'mes 2', col, 200), linha(2, 'Total', col, 999),
    ];
    assert.equal(conferirTotalDaSerie(campos).length, 1, col);
  }
});

test('total da série: colunas não aditivas continuam fora (%, ticket, taxa, variação)', () => {
  for (const col of ['% do total', 'Ticket médio (R$)', '%', 'Taxa', 'Taxa anual', 'Variação %', '(%)', 'Variação', 'Média', 'Margem bruta']) {
    const campos = [
      linha(0, 'mes 1', col, 100), linha(1, 'mes 2', col, 200), linha(2, 'Total', col, 999),
    ];
    assert.deepEqual(conferirTotalDaSerie(campos), [], col);
  }
});

// -----------------------------------------------------------------------------
// conferirBalanceteLinhaALinha — balancete_janaago26.pdf, mandato real Krauspenhar
// -----------------------------------------------------------------------------
// conferirBalanceteLinhaALinha — balancete_janaago26.pdf, mandato real Krauspenhar
// -----------------------------------------------------------------------------
// FIXTURE 100% REAL (regra 4): as 28 contas com movimento nao nulo do
// `campo_extraido` de producao (30/09/2026), valores copiados como gravados em
// Saldo anterior | Debito | Credito | Saldo atual. 14 fecham SO com a troca de
// colunas (paginas 1-2) e 14 SO como rotuladas (paginas 8-9). Nenhum numero
// inventado. CHEQUES A COMPENSAR aparece DUAS vezes identica no documento real e
// conta como duas contas. O que isto NAO prova: os 111/196/288 do documento
// inteiro (so 28 contas foram copiadas); prova a regra sobre contas reais.
const QUATRO = ['Saldo anterior', 'Débito', 'Crédito', 'Saldo atual'];
const REAIS = [
  ['perm', 1, 'ADIANTAMENTOS A FUNCIONARIOS', [156963.24, 356454.33, 494860.28, -295369.19]],
  ['perm', 1, 'ADIANTAMENTO A EMPREGADOS', [6831.09, 1501.35, 161022.66, -166352.4]],
  ['perm', 1, 'ADIANTAMENTO PARA VIAGEM', [146543.97, 328211.21, 220176.12, -38508.88]],
  ['perm', 1, 'EMPRESTIMO P/ FUNCIONARIOS', [3588.18, 6596.18, 11508, -8500]],
  ['perm', 1, 'TRIBUTOS A COMPENSAR E A RECUPERAR', [147843.76, 294533.56, 3200616.28, -3053926.48]],
  ['perm', 1, 'IRRF SOBRE APLICAÇÃO', [1378.72, 31930.39, 38525.6, -7973.93]],
  ['perm', 1, 'IRRF SOBRE SERVIÇOS', [3478.6, 3009.21, 3009.21, -3478.6]],
  ['perm', 2, 'CHEQUES A COMPENSAR', [376206.47, 270803.47, 0, -105403]],
  ['perm', 2, 'CHEQUES A COMPENSAR', [376206.47, 270803.47, 0, -105403]],
  ['perm', 2, 'FUNDO DE RESERVA MASSEY - CP', [3667595.49, 3635861.87, 1330672.66, -1362406.28]],
  ['perm', 2, 'BRADESCO FICFI RF CAPITALIZAÇÃO REDE APLICAÇÃO', [126937.38, 95203.76, 439020.86, -470754.48]],
  ['perm', 2, 'ESTOQUES', [43569482.33, 47956795.9, 65971485.41, -61584171.84]],
  ['perm', 2, 'MARCA MASSEY FERGUSSON - NOVOS', [12004600.42, 16032443.29, 22364938.8, -18337095.93]],
  ['perm', 2, 'PLANTADEIRAS', [3441426.09, 2212053.88, 1853550.64, -3082922.85]],
  ['rot', 8, '(-) DEVOLUÇÃO VENDA DE PEÇAS E LUBRIFICANTES', [-903659.2, 903659.2, 0, 0]],
  ['rot', 9, 'CUSTO COM VENDA DE COLHEITADEIRA', [-1434850.56, 1434850.56, 0, 0]],
  ['rot', 9, 'CUSTO COM VENDA DE PLATAFORMAS', [-113.23, 113.23, 0, 0]],
  ['rot', 9, 'CUSTO COM TRATORES USADOS', [-1207826.53, 1207826.53, 0, 0]],
  ['rot', 9, 'COFINS OUTROS DEBITOS', [-9922.11, 9922.11, 0, 0]],
  ['rot', 9, 'CUSTO COM VENDA DE AGRICULTURA DE PRECISÃO', [-67550.28, 67550.28, 0, 0]],
  ['rot', 9, 'CUSTO DE VENDA DE PEÇAS WOODS', [-6491.84, 6491.84, 0, 0]],
  ['rot', 9, 'EMBALAGENS', [-34723.28, 34723.28, 0, 0]],
  ['rot', 9, 'ICMS OUTROS DEBITOS', [-2875.12, 2875.12, 0, 0]],
  ['rot', 9, 'PIS OUTROS DEBITOS', [-1777.13, 1777.13, 0, 0]],
  ['rot', 9, 'CUSTO DE SERVIÇOS', [-1002864.05, 1002864.05, 0, 0]],
  ['rot', 9, 'CUSTO COM SERVIÇO DE ASSIST TECNICA E CONSERTO', [-30736.16, 30736.16, 0, 0]],
  ['rot', 9, 'ASSISTÊNCIA MÉDICA E ODONTOLÓGICA', [-4687.83, 4687.83, 0, 0]],
  ['rot', 9, 'COMISSOES', [-16338.4, 16338.4, 0, 0]],
];
let ordemBalancete = 0;
const docReal = (tipos) => REAIS.filter(([t]) => tipos.includes(t)).flatMap(([, pg, chave, v]) =>
  QUATRO.map((pc, j) => linha(ordemBalancete++, chave, pc, v[j], { secao: 'Balancete', origem_pagina: pg })));
const docMisto = () => docReal(['perm', 'rot']);

test('balancete: o documento MISTO real (14 com a troca + 14 rotuladas, muda por página) reprova e dá as contagens', () => {
  const campos = docMisto();
  const copia = JSON.stringify(campos);
  const problemas = conferirBalanceteLinhaALinha(campos);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /das 28 conta\(s\) com movimento, 14 fecham como rotuladas, 14 fecham só com a troca/);
  assert.match(problemas[0], /e 0 não fecham de jeito nenhum/);
  assert.match(problemas[0], /gravada como "Débito" é o saldo atual/);
  assert.match(problemas[0], /Exemplo com a troca: "ADIANTAMENTOS A FUNCIONARIOS" \(p\. 1\).*saldo atual -295369\.19/);
  assert.equal(JSON.stringify(campos), copia, 'não corrige o dado');
});

test('balancete: só as páginas com a troca (14 reais) reprova com 0 rotuladas', () => {
  const problemas = conferirBalanceteLinhaALinha(docReal(['perm']));
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /das 14 conta\(s\) com movimento, 0 fecham como rotuladas, 14 fecham só com a troca/);
});

test('balancete: só as contas reais que fecham como rotuladas (14) não reprova', () => {
  assert.deepEqual(conferirBalanceteLinhaALinha(docReal(['rot'])), []);
});

test('balancete: 1 conta real com a troca entre 13 rotuladas reais (7%, abaixo do limiar) não reprova', () => {
  const rot = REAIS.filter(([t]) => t === 'rot').slice(0, 13);
  const perm = REAIS.filter(([t]) => t === 'perm').slice(0, 1);
  const campos = [...rot, ...perm].flatMap(([, pg, chave, v], i) =>
    QUATRO.map((pc, j) => linha(i * 4 + j, chave, pc, v[j], { secao: 'Balancete', origem_pagina: pg })));
  assert.deepEqual(conferirBalanceteLinhaALinha(campos), []);
});

test('balancete: conta de movimento zero não conta (nem como fechada, nem como aberta)', () => {
  // Contas reais com a troca + contas paradas: se as paradas contassem como
  // "fecham como rotuladas", 14/214 < 20% e o defeito sumia.
  const paradas = Array.from({ length: 200 }, (_, i) =>
    QUATRO.map((pc, j) => linha(5000 + i * 4 + j, `PARADA ${i}`, pc, [500, 0, 0, 500][j], { secao: 'Balancete', origem_pagina: 3 }))).flat();
  const problemas = conferirBalanceteLinhaALinha([...docReal(['perm']), ...paradas]);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /das 14 conta\(s\) com movimento/);
  assert.deepEqual(conferirBalanceteLinhaALinha(paradas), []);
});

test('balancete: documento sem as quatro colunas ou entrada inválida não reprova', () => {
  assert.deepEqual(conferirBalanceteLinhaALinha(docReal(['perm']).filter((c) => c.periodo_coluna !== 'Crédito')), []);
  assert.deepEqual(conferirBalanceteLinhaALinha(null), []);
});

test('balancete: conferirBalanceteLinhaALinha é AUTO-CONTIDA (embutida por toString no nó Code)', () => {
  const isolada = new Function(`return (${conferirBalanceteLinhaALinha.toString()})`)();
  assert.equal(isolada(docMisto()).length, 1);
  assert.deepEqual(isolada(docReal(['rot'])), []);
});
