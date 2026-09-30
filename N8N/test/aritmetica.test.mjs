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
import {
  conferirIdentidadeDeLinha, conferirTotalDaSerie, conferirBalanceteLinhaALinha,
  papelDeColunaDeBalancete, agruparContasDeBalancete, classificarContasDeBalancete, mensagemDoBalancete,
  conferirHierarquiaDeCodigos, blocosDeLinha, linhasDaHierarquia, fechaComDeslocamento, filhasDiretas, classificarHierarquia,
} from '../lib/aritmetica.mjs';
import { readFileSync } from 'node:fs';

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

// A função é embutida por toString() e toString() NÃO leva o escopo do módulo: os 4
// helpers extraídos (Sonar S3776) têm de ir junto, como declarações irmãs. Este
// teste monta o escopo SÓ com o que o gerador embute; helper que faltasse lá
// reprovaria aqui com ReferenceError (precedente: bc439fa, 11 testes).
const HELPERS_DO_BALANCETE = [
  papelDeColunaDeBalancete, agruparContasDeBalancete, classificarContasDeBalancete, mensagemDoBalancete,
];
test('balancete: a função + os helpers embutidos funcionam isolados (toString, sem o escopo do módulo)', () => {
  const fonte = [...HELPERS_DO_BALANCETE, conferirBalanceteLinhaALinha]
    .map((f) => `const ${f.name} = ${f.toString()};`).join('\n');
  const isolada = new Function(`${fonte}\nreturn conferirBalanceteLinhaALinha;`)();
  assert.equal(isolada(docMisto()).length, 1);
  assert.deepEqual(isolada(docReal(['rot'])), []);
});

test('balancete: o workflow publicado embute a função E cada helper dela', () => {
  const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'));
  const codigo = JSON.stringify(wf.nodes.find((n) => n.name === 'Juntar Blocos').parameters.jsCode);
  for (const f of [...HELPERS_DO_BALANCETE, conferirBalanceteLinhaALinha]) {
    assert.ok(codigo.includes(`const ${f.name} = `), `${f.name} não está embutida em Juntar Blocos`);
  }
});

// -----------------------------------------------------------------------------
// conferirHierarquiaDeCodigos — DRE analítica real do Krauspenhar (DRE 2025)
// -----------------------------------------------------------------------------
// FIXTURE REAL (regra 4): as 223 linhas da DRE 2025 como a extração as gravou em
// produção (30/09/2026), só a coluna Total, [chave, valor] na ordem do documento.
// O defeito: a partir de certo ponto cada rótulo carrega o valor do rótulo
// seguinte, e cada linha continua somando certo mês a mês contra o próprio Total.
// NÃO existe aqui um documento real GRANDE que feche (as ordens 1-13 da página 1
// têm 3 sintéticas); o controle negativo com dado real de outro caso depende de
// consulta à produção e está pendente — o que este arquivo prova é a regra sobre o
// documento deslocado, o mínimo de 10 avaliáveis e o fechamento das sintéticas
// alinhadas da página 1.
const DRE_TOTAL = [
  ['3 RESULTADO', -6805591.61],
  ['3.01 RECEITA LIQUIDA', 97950953.78],
  ['3.01.01 VENDA DE EQUIPAMENTOS', 63195010.98],
  ['3.01.01.01 VENDAS DE MAQUINAS E IMPLEMENTOS MASSEY F', 46341096.97],
  ['000880 Colheitadeira', 2940000],
  ['000883 Plantadeiras', 10335999.98],
  ['000881 Plataforma', 8112],
  ['000882 Pulverizadores', 2390000],
  ['000878 Tratores', 30641984.99],
  ['002200 Venda de implementos massey', 25000],
  ['3.01.01.02 VENDA DE OUTRAS MARCAS NOVAS', 15942754.6],
  ['006540 Venda de equipamentos para pulverizacao', 187166.35],
  ['000887 Venda de implementos', 15755588.25],
  ['3.01.01.03 VENDAS DE USADOS', 12945617.98],
  ['3.01.01.03 VENDAS DE USADOS', 3222699],
  ['000889 Colheitadeiras usados', 1952000.08],
  ['000897 Implementos - usados', 581500],
  ['000896 Plantadeiras usados', 875000],
  ['000890 Plataformas usados', 1010000],
  ['000895 Pulverizadores - usados', 5304418.9],
  ['000888 Tratores - usados', -7115901.16],
  ['3.01.01.04 (-) DEDUCOES DE VENDAS E SERVICOS', -12864.22],
  ['000915 (-) cofins', -4830798.87],
  ['000910 (-) devolução venda', -2289101.75],
  ['000912 (-) icms mtz', 19655.81],
  ['001241 (-) iss', -2792.13],
  ['000913 (-) pis', -3294795.69],
  ['3.01.01.05 (-) DEDUÇÃO VENDA DE OUTRAS MARCAS NOVOS', -2271500],
  ['001243 (-) devolução de venda de om novos', -1027540.39],
  ['001244 (-) icms sobre venda om novos', 4244.7],
  ['001246 (-) pis sobre venda de om novos', -1623761.72],
  ['3.01.01.06 (-) DEDUÇÃO VENDA DE USADOS', -69974.15],
  ['000930 (-) cofins sobre vendas usados', -1538125],
  ['000922 (-) devolução vendas de usados', -501.5],
  ['000924 (-) icms sobre venda usados', -15161.07],
  ['000929 (-) pis sobre vendas usados', 0],
  ['3.01.02 VENDA DE PEÇAS E LUBRIFICANTES', 32964473.02],
  ['3.01.02.01 VENDA DE PEÇAS E LUBRIFICANTES', 36189770.85],
  ['000934 Lubrificantes', 1860921.99],
  ['000936 Peças gts', 12214979.4],
  ['000933 Peças massey fergusson', 19504227.12],
  ['000935 Peças mp agro', 805193.22],
  ['001255 Peças woods', 30961.46],
  ['001259 Receita com venda de outras peças', 1773487.66],
  ['001259 Receita com venda de outras peças', 1773487.66],
  ['3.01.02.02 (-) DEDUÇÃO COM VENDA DE PEÇAS E LUBRIFICAN', -3225297.83],
  ['000945 (-) cofins sobre venda de peças e lubrificantes', -989850.09],
  ['000939 (-) devolução venda de peças e lubrificantes', -990842.52],
  ['000941 (-) icms sobre venda de peças e lubrificantes', -1030063.1],
  ['000946 (-) icms st sobre vendas de peças e lubrificantes', 364.02],
  ['000943 (-) pis sobre venda de peças e lubrificantes', -214906.14],
  ['3.01.03 OUTRAS RECEITAS', 1791469.78],
  ['3.01.03.01 SERVIÇOS DE ASSISTENCIA TECNICA E CONSERTO', 1450178.96],
  ['000953 Assistência técnica e conserto', 772558.9],
  ['000955 Serviço de garantia', 677620.06],
  ['3.01.03.02 SERVIÇO DE ENTREGA TECNICA/COMISSOES', 514495.66],
  ['003705 Representacao comercial', -173204.84],
  ['3.01.03.04 (-) DEDUÇÃO RECEITA DE SERVIÇOS', -98196.5],
  ['000960 (-) cofins sobre serviços', -53688.78],
  ['000958 (-) iss sobre serviços', -21319.56],
  ['000959 (-) pis sobre serviços', -87341204.08],
  ['3.02 CUSTOS', -85305637.32],
  ['3.02.01 CUSTOS DAS MERCADORIAS VENDIDAS / SERVIÇOS P', -37219870.1],
  ['3.02.01.01 CUSTO DE VENDA DE EQUIP MS NOVOS', -3674730.7],
  ['001015 Custo com venda de colheitadeira', -19247.47],
  ['001019 Custo com venda de implementos', -6176383.54],
  ['001018 Custo com venda de plantadeira', -4509.34],
  ['001016 Custo com venda de plataformas', -2790589.22],
  ['001017 Custo com venda de pulverizadores', -24504591.68],
  ['000994 Custo com venda de trator', 4203.39],
  ['001181 Descontos obtidos (recuperacao de custos)', -54021.54],
  ['001840 Devolução de compra', -10339916.47],
  ['3.02.01.02 CUSTO DE VENDA DE OUTRAS MARCAS NOVOS', -10263855.22],
  ['001296 Custo com venda de implementos om', -76061.25],
  ['006537 Custo com venda equipamentos para pulverizacao', -13822777.36],
  ['3.02.01.03 CUSTO DE VENDA DE USADOS', -1097265.6],
  ['001022 Custo com colheitadeiras usadas', -6004400.25],
  ['001021 Custo com tratores usados', -680850],
  ['001247 Custo com venda de plantadeiras usadas', -535500],
  ['001023 Custo com venda de plataformas - usados', -2927811.51],
  ['001026 Custo de venda de implementos - usados', -2576950],
  ['000995 Custo de venda de pulverizadores - usados', -23923073.39],
  ['3.02.01.04 CUSTO DE VENDA DE PEÇAS E LUBRIFICANTES', 137726.69],
  ['005838 (-) cofins outros creditos', -71700.01],
  ['005588 Cofins outros debitos', -372017.42],
  ['003302 Custo com peças/consumo interno', -72056.43],
  ['002612 Custo com venda de agricultura de precisão', -1416257.74],
  ['001038 Custo com venda de lubrificantes', -1088526.37],
  ['001260 Custo com venda de outras peças', -7628757.77],
  ['001042 Custo com venda de peças gts', -13396286.7],
  ['001005 Custo com venda de peças massey fergusson', -473151.87],
  ['001034 Custo de venda de peças mp agro', -14590.98],
  ['001028 Custo de venda de peças woods', -74198.29],
  ['005617 Embalagens', 547836.04],
  ['006356 (-) icms outros creditos', -5393.62],
  ['006743 Icms outros debitos', -8903.55],
  ['008686 Icms st', 29434.23],
  ['005839 (-) pis outros cretidos', -16229.6],
  ['005589 Pis outros debitos', -2035566.76],
  ['3.02.02 CUSTO DE SERVIÇOS', -28455.62],
  ['3.02.02.01 CUSTO COM SERVIÇO DE ASSIST TECNICA E CONS', -11206.46],
  ['001896 13º salario', -10867.7],
  ['001900 Comissoes', -6381.46],
  ['002004 Vale compra', -2006860.46],
  ['3.02.02.02 CUSTO SERVICOS DE TERCEIROS', -539946.54],
  ['004711 Custo combustivel/lubrificantes', -54113],
  ['004714 Custo com munck', -556987.9],
  ['004712 Custo manutencao de veiculos', -855813.02],
  ['004713 Custo serviços terceiros', -250.68],
  ['3.02.02.04 CUSTO COM SERVIÇO DE GARANTIA', -250.68],
  ['001045 Custo com serviço de garantia', -12136521.35],
  ['3.03 DESPESAS OPERACIONAIS', -12136521.35],
  ['3.03.01 DESPESAS OPERACIONAIS GERAIS', -6883410.06],
  ['3.03.01.01 PESSOAL', -258984.41],
  ['000334 13 salario', -719.31],
  ['005663 Anuenio', -116951.31],
  ['001056 Assistência médica e odontológica', -813],
  ['006744 Brindes e bonificacoes a funcionarios', -1744261.09],
  ['000308 Comissoes', -6275.5],
  ['006548 Dias afastados inss', 10548.59],
  ['005815 Dias faltas/dsr faltas', -2723],
  ['000937 Exames admissional, demissional e periódico', -353989.3],
  ['000335 Ferias', -384807.18],
  ['000304 Fgts', -323967.06],
  ['001050 Hora extra', -122417.09],
  ['007048 Insalubridade', -1084899.81],
  ['000303 Inss', -829.53],
  ['001057 Outras despesas com pessoal', -76182.86],
  ['000300 Premios e gratificacoes', -36326],
  ['000299 Pro-labore', -5837.42],
  ['005565 Provisao de 13 salario - d', -18787.96],
  ['005564 Provisao de ferias - d', -219668.54],
  ['000680 Rescisao', -1826947.67],
  ['000298 Salarios e ordenados', 28019.5],
  ['001053 Seguro de vida', -14000],
  ['006747 Servicos prestados - pessoal', -329841.65],
  ['003902 Vale alimentação', -5253111.29],
  ['002006 Vale compra', -311.73],
  ['000492 Vale transporte', -4175640.79],
  ['001959 Brindes e gratificações', -29182.85],
  ['001271 Cartório', -27979.3],
  ['001060 Combustiveis e lubrificantes', -35663.09],
  ['008504 Condominio', -434241.84],
  ['001256 Confraternizações, feiras e eventos', -37746.6],
  ['001601 Contribuição associativa', -85.9],
  ['000664 Correios', -288102.53],
  ['001067 Cursos e treinamentos', -14854.46],
  ['007353 Doaçoes', -50074.76],
  ['001064 Energia elétrica', -745818.77],
  ['001066 Fretes e carretos', -14192],
  ['001068 Honorários advocaticios', -19410.95],
  ['000679 Lanches e refeiçoes', -14933.74],
  ['001100 Legais e judiciais', -343145.08],
  ['001076 Locação de veículos', -22315.84],
  ['000893 Manutencao e reparo de maquinas e veiculos', -82828.73],
  ['001522 Manutenção e reparos', -17933.14],
  ['001077 Material de escritório', -7980.1],
  ['001266 Material de higiene e limpeza', -377777.16],
  ['001061 Material de uso e consumo', -14790.76],
  ['007449 Proteção veicular', -88844.94],
  ['000658 Publicidade e propaganda', -31118],
  ['001088 Segurança e monitoramento', -106514.21],
  ['001086 Seguros', -12630.61],
  ['001270 Serasa', -241645.82],
  ['001269 Serviços de terceiros', -251576.16],
  ['002181 Sistemas e softwares', -31693.93],
  ['001087 Telefone celular', -10206.47],
  ['001071 Telefone e internet', -72046.23],
  ['001923 Uniformes/epi', -355858.45],
  ['001001 Viagem e hospedagens', -355858.45],
  ['3.03.02.02 DEPRECIACOES E AMORTIZACOES', -580100.93],
  ['001063 Depreciação e amortização', -497369.57],
  ['3.03.02.03 TRIBUTARIAS', -141767.48],
  ['002396 Icms diferencial de aliquota', 93782.18],
  ['005570 (-) icms outros creditos', -11206.95],
  ['005569 Icms outros debitos', -14827.37],
  ['001089 Iptu', -15013.64],
  ['001995 Ipva/dpvat', -31871.76],
  ['005585 Pis/cofins sobre receitas financeiras', -73599.21],
  ['005688 Taxas e impostos estaduais', -7519.27],
  ['000663 Taxas e impostos municipais', -302865.34],
  ['3.05 OUTRAS RECEITAS E DESPESAS', 976094.21],
  ['3.05.01 OUTRAS RECEITAS E DESPESAS OPERACIONAIS', 973661.57],
  ['3.05.01.01 OUTRAS RECEITAS E DESPESAS OPERACIONAIS', 1032964.41],
  ['3.05.01.01 OUTRAS RECEITAS E DESPESAS OPERACIONAIS', 1032964.41],
  ['001521 Doação e bonificação recebidas', 12619.68],
  ['003117 Perdas com liquidação duvidosas', -59679.27],
  ['007038 Receita com bonificação de serviços massey', 0],
  ['002129 Receita com bonificação massey', 1080024],
  ['3.05.01.02 DESPESAS NÃO DEDUTIVEIS', -171352.6],
  ['008631 Comissoes - nd', -8040.34],
  ['007448 Despesa com pessoal - nd', -74628.17],
  ['001274 Doações - nd', 0],
  ['006745 Material de uso e consumo - nd', -8926.38],
  ['001160 Multas de transito - nd', -27119.13],
  ['005989 Servicos terceiros - nd', 112049.76],
  ['3.05.01.03 GANHO/PERDA NA ALIENAÇÃO ATIVO IMOBILIZADO', 0],
  ['009025 Baixa de ativo imobilizado', -38450.24],
  ['009024 Venda de ativo imobilizado', 150500],
  ['3.05.02 RECEITAS E DESPESAS NÃO OPERACIONAL', 2432.64],
  ['3.05.02 RECEITAS E DESPESAS NÃO OPERACIONAL', 2432.64],
  ['3.05.02.01 RECEITAS E DESPESAS NÃO OPERACIONAL', -9777.93],
  ['006279 Reembolso de despesas', 12210.57],
  ['008160 Ressarcimento de seguro', 0],
  ['3.06 RESULTADO FINANCEIRO', -6254914.17],
  ['3.06.01 RECEITAS FINANCEIRAS', 734494.88],
  ['3.06.01.01 RECEITAS FINANCEIRAS', 108036.15],
  ['005571 Contribuição agco/fundo bradesco', 168275.03],
  ['001180 Juros ativos', 458183.7],
  ['001179 Rendimento de aplicação financeira', -6989409.05],
  ['3.06.02 DESPESAS FINANCEIRAS', -6989409.05],
  ['3.06.02.01 DESPESAS FINANCEIRAS', -7519.27],
  ['001189 Credito concedido a cliente', -566.15],
  ['006561 Custos/taxas/emolumentos com investimentos em bolsa', -145144.7],
  ['001188 Descontos concedidos', -184282.49],
  ['001185 Iof', -184282.49],
  ['007546 Irrf s/aplicaçao financeira', -38870.36],
  ['003192 Juros e multas s/ tributos', -169775.24],
  ['001186 Juros passivos', -3301838.68],
  ['001190 Juros s/ emprestimos e financiamentos', -2863530.56],
  ['001184 Tarifas bancárias', -196014.64],
  ['006146 Taxa flat', -81866.96],
  ['TOTAL', -6805591.61],
];
const camposDaDre = (linhas) => linhas.map(([chave, v], i) => ({
  ordem: i, chave, periodo_coluna: 'Total', valor_num: Number(v),
}));

test('hierarquia: a DRE real deslocada reprova — UM problema, com contagens, exemplo e rótulos repetidos', () => {
  const campos = camposDaDre(DRE_TOTAL);
  const copia = JSON.stringify(campos);
  const problemas = conferirHierarquiaDeCodigos(campos);
  assert.equal(problemas.length, 1);
  assert.match(problemas[0], /33 de 43 contas sintéticas não fecham com a soma das filhas diretas \(coluna total\)/);
  assert.match(problemas[0], /10 fecham como gravadas e a hipótese de valor deslocado uma linha explica 18 delas/);
  assert.match(problemas[0], /Rótulo repetido em sequência em: 3\.01\.01\.03 VENDAS DE USADOS; 001259 Receita com venda de outras peças/);
  assert.match(problemas[0], /Exemplo: "3\.01\.01\.04 \(-\) DEDUCOES DE VENDAS E SERVICOS" declara -12\.864,22/);
  assert.doesNotMatch(problemas[0], /a partir da p[áa]gina/i, 'não afirma página de início');
  assert.equal(JSON.stringify(campos), copia, 'não corrige o dado');
});

test('hierarquia: as sintéticas ALINHADAS da página 1 real fecham como gravadas (medição, abaixo do mínimo de 10)', () => {
  // ordens 0-13: 3.01.01.01 e 3.01.01.02 fecham com as analíticas (números reais)
  const { linhas } = linhasDaHierarquia(camposDaDre(DRE_TOTAL.slice(0, 14)));
  const r = classificarHierarquia(linhas, ['total']);
  assert.ok(r.avaliaveis < 10, 'abaixo do mínimo: não pode acusar');
  assert.ok(r.fecham >= 2, 'as sintéticas alinhadas fecham como gravadas');
  assert.deepEqual(conferirHierarquiaDeCodigos(camposDaDre(DRE_TOTAL.slice(0, 14))), []);
});

test('hierarquia: chave repetida em sequência não conta duas vezes como filha; linha sem código fica fora', () => {
  const { linhas, repetidas } = linhasDaHierarquia(camposDaDre(DRE_TOTAL));
  assert.deepEqual(repetidas.slice(0, 2), ['3.01.01.03 VENDAS DE USADOS', '001259 Receita com venda de outras peças']);
  assert.equal(linhas.length, DRE_TOTAL.length - 5, '4 repetidas + a linha "TOTAL" sem código saem da hierarquia');
  assert.ok(!linhas.some((l) => l.chave === 'TOTAL'));
  const i = linhas.findIndex((l) => l.cod === '001259');
  assert.equal(linhas.filter((l) => l.cod === '001259').length, 1, 'repetida vira uma linha só');
  assert.ok(i > 0 && filhasDiretas(linhas, linhas.findIndex((l) => l.cod === '3.01.02.01')).includes(i));
});

test('hierarquia: sem códigos hierárquicos, entrada inválida e coluna Total ausente não acusam nem quebram', () => {
  assert.deepEqual(conferirHierarquiaDeCodigos(null), []);
  assert.deepEqual(conferirHierarquiaDeCodigos([]), []);
  const semCodigo = Array.from({ length: 30 }, (_, i) => ({ ordem: i, chave: `Conta ${i}`, periodo_coluna: 'Total', valor_num: i }));
  assert.deepEqual(conferirHierarquiaDeCodigos(semCodigo), []);
});

test('hierarquia: a função + helpers embutidos funcionam isolados (toString) e estão no workflow', () => {
  const fs = [blocosDeLinha, linhasDaHierarquia, filhasDiretas, fechaComDeslocamento, classificarHierarquia, conferirHierarquiaDeCodigos];
  const fonte = fs.map((f) => `const ${f.name} = ${f.toString()};`).join('\n');
  const isolada = new Function(`${fonte}\nreturn conferirHierarquiaDeCodigos;`)();
  assert.equal(isolada(camposDaDre(DRE_TOTAL)).length, 1);
  const wf = JSON.parse(readFileSync(new URL('../workflow.e1-ingestao.json', import.meta.url), 'utf8'));
  const codigo = JSON.stringify(wf.nodes.find((n) => n.name === 'Juntar Blocos').parameters.jsCode);
  for (const f of fs) assert.ok(codigo.includes(`const ${f.name} = `), `${f.name} não está em Juntar Blocos`);
});
