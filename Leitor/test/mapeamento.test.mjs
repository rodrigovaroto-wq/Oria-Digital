// O MAPEAMENTO DE COLUNAS (MB2): proposta, confirmação e aplicação.
//
// Parte 1, contra os sintéticos de `Dados de Teste/volume`: a proposta acerta as 11 colunas,
// e o arquivo inteiro aplicado dá exatamente os títulos e o saldo do GABARITO (que o
// `conferir_volume.py` prova contra o balanço do book-distress), no CSV e no XLSX.
// Parte 2, o que a MB1 deixou para cá: decidir título × subtotal × rejeitada COM o
// significado das colunas, e ler valor e data pelo formato do ARQUIVO, não do valor.
// Sem python3 a parte 1 REPROVA (não pula).
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { mkdtempSync, openAsBlob, readFileSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import { lerTabela } from '../lib/tabela.mjs';
import {
  proporMapeamento, validarMapeamento, aplicadorDeMapeamento, valorEmCentavos, dataIso,
  formatoDaAmostra, impressaoDoCabecalho, CAMPOS,
} from '../lib/mapeamento.mjs';

const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..', '..');
const N = 3000;
const CONFIRMACAO = { confirmado_por: '00000000-0000-0000-0000-000000000001', confirmado_em: '2026-11-11T12:00:00Z' };

/** Lê, propõe, confirma a proposta como está e aplica: o caminho inteiro da MB2. */
async function aplicar(blob, { mapa, formato } = {}) {
  const r1 = await lerTabela(blob);
  const prop = proporMapeamento(r1.cabecalho.celulas, r1.amostra, { tipos: r1.amostra_tipos });
  const ap = aplicadorDeMapeamento({ mapa: mapa ?? prop.mapa, formato: formato ?? prop.formato, cabecalho: r1.cabecalho.celulas, ...CONFIRMACAO });
  const titulos = [], classes = [];
  await lerTabela(blob, { aoLinha: (l) => { const x = ap.linha(l); classes.push(x); if (x.titulo) titulos.push(x.titulo); } });
  return { r1, prop, resumo: ap.resumo(), titulos, classes };
}

// ============================================== 1. contra os sintéticos =====
const dir = mkdtempSync(join(tmpdir(), 'mapeamento-'));
const gerado = spawnSync('python3', [join(RAIZ, 'Dados de Teste/volume/gerar_volume.py'), '--linhas', String(N), '--saida', dir], { encoding: 'utf8' });
const gab = gerado.status === 0 ? JSON.parse(readFileSync(join(dir, `GABARITO_${N}.json`), 'utf8')) : null;
process.on('exit', () => rmSync(dir, { recursive: true, force: true }));

test('o gerador das bases sintéticas rodou (sem ele a parte 1 não prova nada)', () => {
  assert.equal(gerado.status, 0, `python3 gerar_volume.py falhou: ${gerado.stderr || gerado.error}`);
});

const CABECALHO = { Cliente: 'contraparte', Fornecedor: 'contraparte', 'CNPJ/CPF': 'documento_contraparte', Título: 'titulo', Parcela: 'parcela', Emissão: 'emissao', Vencimento: 'vencimento', 'Valor Original': 'valor_original', 'Valor Pago': 'valor_pago', Saldo: 'saldo', 'Data Pagamento': 'data_pagamento', Situação: 'situacao' };

for (const [chave, arquivo] of [['contas_a_receber', `contas_a_receber_${N}.csv`], ['contas_a_receber', `contas_a_receber_${N}.xlsx`], ['contas_a_pagar', `contas_a_pagar_${N}.csv`]]) {
  test(`${arquivo}: proposta acerta as 11 colunas e a aplicação dá os títulos e o saldo do gabarito`, { skip: !gab && 'sem gabarito' }, async () => {
    const { r1, prop, resumo, titulos } = await aplicar(await openAsBlob(join(dir, arquivo)));
    const g = gab[chave];
    // A proposta: cada campo na coluna certa, nenhum faltando, nenhum ambíguo.
    for (const [campo, i] of Object.entries(prop.mapa)) assert.equal(CABECALHO[r1.cabecalho.celulas[i]], campo, `campo ${campo}`);
    assert.deepEqual(prop.faltando, []);
    assert.deepEqual(prop.ambiguos, []);
    assert.deepEqual([prop.formato.decimal, prop.formato.datas], ['virgula', 'dia_mes_ano']);
    // A aplicação: títulos = abertos + parciais + liquidados; o TOTAL GERAL é subtotal.
    const t = g.titulos;
    assert.equal(resumo.titulo, t.abertos + t.parciais + t.liquidados);
    assert.equal(resumo.subtotal, 1);
    assert.equal(resumo.rejeitada, 0, JSON.stringify(resumo.primeira_rejeitada));
    assert.equal(resumo.saldo_titulos, String(g.saldo_em_aberto_centavos));
    assert.equal(resumo.conferencia_com_o_total_do_arquivo.estado, 'confere');
    // Por contraparte, só os que têm saldo: = o gabarito (que = o aging do book).
    const porCp = {};
    for (const x of titulos) {
      if (x.saldo === 0n) continue;
      const cod = x.documento_contraparte; // o código não é campo; o CNPJ identifica
      porCp[cod] = (porCp[cod] ?? 0n) + x.saldo;
    }
    assert.equal(Object.keys(porCp).length, g.contrapartes_em_aberto);
    assert.equal(Object.values(porCp).reduce((a, b) => a + b, 0n), BigInt(g.saldo_em_aberto_centavos));
    // Datas e valores ISO/centavos: o primeiro título é o do gabarito ordenado.
    assert.match(titulos[0].vencimento, /^\d{4}-\d{2}-\d{2}$/);
    assert.equal(typeof titulos[0].saldo, 'bigint');
  });
}

test('contas_a_receber .csv e .xlsx dão os MESMOS títulos, campo a campo', { skip: !gab && 'sem gabarito' }, async () => {
  const csv = await aplicar(await openAsBlob(join(dir, `contas_a_receber_${N}.csv`)));
  const xl = await aplicar(await openAsBlob(join(dir, `contas_a_receber_${N}.xlsx`)));
  assert.deepEqual(xl.titulos, csv.titulos);
});

// ================================================ 2. a decisão por linha =====
const csv = (linhas) => new Blob([linhas.join('\n') + '\n']);

test('sem confirmação (autor e data) ou sem formato, o arquivo não vira dado', () => {
  const base = { mapa: { contraparte: 0, vencimento: 1, saldo: 2 }, cabecalho: ['Nome', 'Vencimento', 'Saldo'], formato: { decimal: 'virgula', datas: 'dia_mes_ano' } };
  assert.throws(() => aplicadorDeMapeamento(base), /sem confirmação/);
  assert.throws(() => aplicadorDeMapeamento({ ...base, confirmado_por: 'x' }), /sem confirmação/);
  assert.throws(() => aplicadorDeMapeamento({ ...base, ...CONFIRMACAO, formato: undefined }), /sem o formato/);
  assert.throws(() => aplicadorDeMapeamento({ ...base, ...CONFIRMACAO, formato: { decimal: 'virgula', datas: 'ano_mes_dia' } }), /sem o formato/);
  assert.doesNotThrow(() => aplicadorDeMapeamento({ ...base, ...CONFIRMACAO }));
});

test('o cabeçalho do arquivo tem de ser o do mapeamento confirmado', () => {
  const conf = { mapa: { contraparte: 0, vencimento: 1, saldo: 2 }, cabecalho: ['Nome', 'Vencimento', 'Saldo'], formato: { decimal: 'virgula', datas: 'dia_mes_ano' }, ...CONFIRMACAO };
  assert.throws(() => aplicadorDeMapeamento(conf, { cabecalhoDoArquivo: ['Nome', 'Saldo', 'Vencimento'] }), /não é o do mapeamento/);
  assert.doesNotThrow(() => aplicadorDeMapeamento(conf, { cabecalhoDoArquivo: [' Nome ', 'Vencimento', 'Saldo', ''] }));
});

test('validar: obrigatório faltando, coluna repetida, índice fora e campo desconhecido', () => {
  const cab = ['A', 'B', 'C'];
  assert.match(validarMapeamento({ contraparte: 0, vencimento: 1 }, cab).erros.join(), /falta o campo obrigatório saldo: sem saldo não há aging/);
  assert.match(validarMapeamento({ contraparte: 0, vencimento: 1, saldo: 1 }, cab).erros.join(), /"B" está em vencimento e em saldo/);
  assert.match(validarMapeamento({ contraparte: 0, vencimento: 1, saldo: 3 }, cab).erros.join(), /fora do cabeçalho/);
  assert.match(validarMapeamento({ contraparte: 0, vencimento: 1, saldo: 2, cor: 0 }, cab).erros.join(), /campo desconhecido: cor/);
  assert.equal(validarMapeamento({ contraparte: 0, vencimento: 1, saldo: 2 }, cab).ok, true);
});

test('coluna deslocada que CABE na largura (a MB1 não via): rejeitada, com o campo e o valor', async () => {
  const linhas = ['Nome;Vencimento;Saldo;Obs', 'A;01/01/2025;1,00;', 'B;01/01/2025;1,00;', 'C;01/01/2025;1,00;', 'SILVA; JOAO;01/01/2025;2,00'];
  const { resumo, classes } = await aplicar(csv(linhas));
  assert.equal(classes[4].classe, 'rejeitada');
  assert.equal(classes[4].motivo, "saldo não é número: '01/01/2025'");
  assert.equal(resumo.rejeitada, 1);
  assert.equal(resumo.saldo_titulos, '300', 'o 2,00 deslocado NÃO entra na soma');
});

test('subtotal × título × rejeitada: o total nunca soma; linha com rótulo de total E data fica de fora, visível com o saldo', async () => {
  const linhas = ['Nome;Vencimento;Valor;Saldo', 'A;01/01/2025;1,00;1,00', 'B;01/01/2025;1,00;1,00', 'C;01/01/2025;1,00;1,00',
    'Sub-Total;;;3,00', 'ACME;Total do cliente;3,00;3,00', '*** TOTAL;;;3,00', 'SOMA ENGENHARIA LTDA;01/01/2025;7,00;7,00',
    'TOTAL DISTRIBUIDORA;02/01/2025;5,00;5,00', ';;;15,00'];
  const { resumo, classes } = await aplicar(csv(linhas));
  // "SOMA ENGENHARIA" e "TOTAL DISTRIBUIDORA" com data: sem o analista, não se distinguem de um
  // total por data; somá-las triplicava o aging (revisão de 11/11/2026). Ficam de fora, com o saldo.
  assert.deepEqual(classes.slice(1).map((c) => c.classe), ['titulo', 'titulo', 'titulo', 'subtotal', 'subtotal', 'subtotal', 'rejeitada', 'rejeitada', 'subtotal']);
  assert.equal(resumo.saldo_titulos, '300');
  const motivo = Object.entries(resumo.motivos).find(([k]) => k.startsWith('rótulo de total com vencimento'));
  assert.deepEqual(motivo[1], { linhas: 2, saldo: '1200' });
  assert.equal(resumo.conferencia_com_o_total_do_arquivo.estado, 'confere', 'um dos totais do arquivo (3,00) = Σ dos títulos');
});

test('o total do arquivo que NÃO bate com a soma lida aparece como divergência', async () => {
  const { resumo } = await aplicar(csv(['Nome;Vencimento;Saldo', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00', 'TOTAL GERAL;;4,00']));
  assert.deepEqual(resumo.conferencia_com_o_total_do_arquivo, { estado: 'diverge', maior_total_do_arquivo: '400', soma_lida: '300', linha_do_maior_total: 4 });
});

test('arquivo sem linha de total: a conferência diz que não houve com o que conferir, e o efeito', async () => {
  const { resumo } = await aplicar(csv(['Nome;Vencimento;Saldo', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00']));
  assert.equal(resumo.conferencia_com_o_total_do_arquivo.estado, 'sem_total_no_arquivo');
  assert.match(resumo.conferencia_com_o_total_do_arquivo.efeito, /não tem com o que ser conferida/);
});

test('título em aberto com as colunas de pagamento vazias é título', async () => {
  const cab = 'Cliente;Doc;Emissao;Venc;Valor;DtPgto;VlPago;Juros;Multa;Desc;Saldo;Obs';
  const aberto = (c) => `${c};2;;01/02/2025;10,00;;;;;;10,00;`;
  const { resumo, prop } = await aplicar(csv([cab, aberto('B'), aberto('C'), aberto('D')]));
  assert.ok('vencimento' in prop.mapa && 'saldo' in prop.mapa);
  assert.equal(resumo.titulo, 3);
  assert.equal(resumo.saldo_titulos, '3000');
});

test('campo obrigatório que a proposta não acha: faltando, com o efeito; nada é inventado', () => {
  const prop = proporMapeamento(['Nome', 'Saldo', 'Observação'], [['A', '1,00', 'x'], ['B', '2,00', 'y']]);
  const venc = prop.faltando.find((f) => f.campo === 'vencimento');
  assert.deepEqual(venc, { campo: 'vencimento', obrigatorio: true, efeito: CAMPOS.vencimento.efeito });
  assert.ok(!('vencimento' in prop.mapa));
});

test('a proposta não põe texto na coluna de saldo só pelo nome', () => {
  const prop = proporMapeamento(['Cliente', 'Vencimento', 'Saldo', 'Valor'], [['A', '01/01/2025', 'quitado', '1,00'], ['B', '02/01/2025', 'quitado', '2,00']]);
  assert.ok(!('saldo' in prop.mapa), 'a coluna "Saldo" tem texto na amostra: não é saldo');
});

// ======================================== 3. valor e data pelo formato =====
test('valor: vírgula, ponto, sinal na frente, no fim, parênteses, R$, XLSX científico e ruído de float', () => {
  const c = (t, tipo, dec) => valorEmCentavos(t, tipo, dec)?.centavos;
  assert.equal(c('1.234,56'), 123456n);
  assert.equal(c('1234,5'), 123450n);
  assert.equal(c('-1.234,56'), -123456n);
  assert.equal(c('(1.234,56)'), -123456n);
  assert.equal(c('1.234,56-'), -123456n);
  assert.equal(c('R$ 1.234,56'), 123456n);
  assert.equal(c('1,234.56', '', 'ponto'), 123456n);
  assert.equal(c('1234.56', '', 'ponto'), 123456n);
  assert.equal(c('1234.56', 'n'), 123456n);
  assert.equal(c('1.5E-2', 'n'), 2n);
  assert.equal(c('9.87654321E7', 'n'), 9876543210n, 'notação científica grande, sem float');
  assert.deepEqual(valorEmCentavos('1234.5599999999999', 'n'), { centavos: 123456n, arredondado: false, casas_extras: false });
  assert.deepEqual(valorEmCentavos('15172.120000000001', 'n'), { centavos: 1517212n, arredondado: false, casas_extras: false });
  assert.deepEqual(valorEmCentavos('1234,567'), { centavos: 123457n, arredondado: true, casas_extras: true });
  assert.deepEqual(valorEmCentavos('1,000'), { centavos: 100n, arredondado: false, casas_extras: true }, '"1,000" com vírgula decimal: marcado');
  assert.equal(c('-R$ 1,00'), -100n);
  assert.equal(c('(R$ 1,00)'), -100n);
  assert.equal(c('R$-1,00'), -100n);
  assert.equal(valorEmCentavos('(-1,00)'), null, 'dois sinais: recusa, não positivo');
  assert.equal(valorEmCentavos('-1,00-'), null);
  assert.equal(valorEmCentavos('--1,00'), null);
  assert.equal(c('quitado'), undefined);
  assert.equal(valorEmCentavos(''), null);
});

test('valor: "1.250" é mil duzentos e cinquenta com vírgula decimal e um e vinte e cinco com ponto', () => {
  assert.equal(valorEmCentavos('1.250', '', 'virgula').centavos, 125000n);
  assert.equal(valorEmCentavos('1.250', '', 'ponto').centavos, 125n);
  assert.equal(valorEmCentavos('1.234,56', '', 'ponto'), null, 'formato trocado é recusa, não outro número');
});

test('data: ISO sempre; dd/mm × mm/dd pelo formato; data impossível é null', () => {
  assert.equal(dataIso('2025-12-31'), '2025-12-31');
  assert.equal(dataIso('2025-12-31T10:00:00', 'mes_dia_ano'), '2025-12-31');
  assert.equal(dataIso('03/04/2025'), '2025-04-03');
  assert.equal(dataIso('03/04/2025', 'mes_dia_ano'), '2025-03-04');
  assert.equal(dataIso('31/12/25'), '2025-12-31');
  assert.equal(dataIso('31/02/2025'), null);
  assert.equal(dataIso('12/31/2025'), null, 'mês 31 no formato dia/mês');
});

test('o formato da amostra: com prova e sem prova, e a evidência diz qual', () => {
  const br = formatoDaAmostra([['A', '15/03/2025', '1.234,56'], ['B', '02/04/2025', '10,00']]);
  assert.deepEqual([br.decimal, br.datas], ['virgula', 'dia_mes_ano']);
  assert.match(br.evidencia.datas, /1 datas provam dia\/mês/);
  const us = formatoDaAmostra([['A', '03/15/2025', '1,234.56'], ['B', '04/02/2025', '10.00']]);
  assert.deepEqual([us.decimal, us.datas], ['ponto', 'mes_dia_ano']);
  const semProva = formatoDaAmostra([['A', '03/04/2025', '10']]);
  assert.match(semProva.evidencia.datas, /SEM prova/);
  assert.match(semProva.evidencia.decimal, /SEM prova/);
});

test('arquivo americano inteiro (ponto decimal, mês/dia): proposto, aplicado, mesma soma', async () => {
  const linhas = ['Customer;Due Date;Balance', 'Cliente A;03/15/2025;1,234.56', 'Cliente B;04/20/2025;10.00', 'Cliente C;12/31/2025;0.44'];
  const r1 = await lerTabela(csv(linhas));
  const prop = proporMapeamento(r1.cabecalho.celulas, r1.amostra);
  assert.deepEqual([prop.formato.decimal, prop.formato.datas], ['ponto', 'mes_dia_ano']);
  // Os nomes em inglês não estão nos sinônimos: o analista confirma as colunas à mão.
  const { resumo, titulos } = await aplicar(csv(linhas), { mapa: { contraparte: 0, vencimento: 1, saldo: 2 }, formato: prop.formato });
  assert.equal(resumo.saldo_titulos, '124500');
  assert.deepEqual(titulos.map((t) => t.vencimento), ['2025-03-15', '2025-04-20', '2025-12-31']);
});

test('impressão do cabeçalho: os vetores que a migration 0242 recalcula no banco', () => {
  assert.equal(impressaoDoCabecalho(['Código', 'Cliente', 'CNPJ/CPF', 'Título', 'Parcela', 'Emissão', 'Vencimento', 'Valor Original', 'Valor Pago', 'Saldo', 'Data Pagamento', 'Situação']),
    '85e6f43fb9eed49ea6cc1ed90cab717d711a18b54c14dee3c8a04a667795f72d');
  assert.equal(impressaoDoCabecalho(['  Código ', 'Cli  ente', '', '']), 'b9b00f3fd09b66b137353b69ed211fabfb259bb78b10690a7266e2b6c004188f');
  assert.equal(impressaoDoCabecalho(['Ação']), impressaoDoCabecalho(['Ação']), 'NFD = NFC');
  assert.notEqual(impressaoDoCabecalho(['Saldo']), impressaoDoCabecalho(['saldo']), 'sem minúsculas: o lower() do Postgres depende de locale');
});

test('contraparte com saldo e SEM vencimento, sem palavra de total: rejeitada, nem subtotal nem título', async () => {
  const { resumo, classes } = await aplicar(csv(['Nome;Vencimento;Saldo', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00', 'ACME LTDA;;5,00', 'DELTA SA;a combinar;7,00']));
  assert.deepEqual(classes.slice(4).map((c) => c.motivo), ["vencimento não é data: ''", "vencimento não é data: 'a combinar'"]);
  assert.equal(resumo.subtotal, 0);
  assert.equal(resumo.saldo_titulos, '300');
});

test('campo OPCIONAL inválido não derruba o título: o campo fica ausente e é contado', async () => {
  const { resumo, titulos } = await aplicar(csv(['Cliente;Emissão;Vencimento;Data Pagamento;Valor Pago;Saldo',
    'A;01/01/2025;01/02/2025;;;1,00', 'B;01/01/2025;01/02/2025;;;1,00', 'C;31/02/2025;01/03/2025;00/00/0000;-;1,00']),
  // Mapa explícito, como o analista confirma: nesta amostra as colunas de pagamento só têm valor inválido.
  { mapa: { contraparte: 0, emissao: 1, vencimento: 2, data_pagamento: 3, valor_pago: 4, saldo: 5 } });
  assert.equal(resumo.titulo, 3);
  assert.equal(resumo.saldo_titulos, '300');
  assert.deepEqual(resumo.opcionais_invalidos, { emissao: 1, data_pagamento: 1, valor_pago: 1 });
  assert.ok(!('emissao' in titulos[2]) && !('data_pagamento' in titulos[2]));
});

// ============================== 4. achados da revisão independente (11/11/2026) =====
test('total por data ("Total ACME; 02/01/2025") nunca soma: o aging não sai em dobro nem em triplo', async () => {
  const { resumo } = await aplicar(csv(['Cliente;Vencimento;Saldo', 'ACME;01/01/2025;10,00', 'ACME;01/01/2025;20,00',
    'Total ACME;02/01/2025;30,00', 'BETA;01/01/2025;5,00', 'Total BETA;03/01/2025;5,00', 'TOTAL GERAL;31/12/2025;35,00']));
  assert.equal(resumo.titulo, 3);
  assert.equal(resumo.saldo_titulos, '3500');
  assert.equal(resumo.rejeitada, 3);
});

test('total sem sinal da MB1, só na coluna da contraparte (3ª coluna): subtotal', async () => {
  const { classes } = await aplicar(csv(['Código;Doc;Cliente;Vencimento;Saldo', '1;10;ACME;01/01/2025;1,00', '2;11;BETA;01/01/2025;1,00',
    '3;12;GAMA;01/01/2025;1,00', '99;123;Total ACME;;30,00']));
  assert.equal(classes[4].classe, 'subtotal');
});

test('formato: a data "15.03.25" não vota no decimal; "1.234" (milhar) prova vírgula', async () => {
  const { resumo, prop } = await aplicar(csv(['Cliente;Vencimento;Saldo', 'A;15.03.25;1.234', 'B;16.03.25;2.000', 'C;17.03.25;500']));
  assert.equal(prop.formato.decimal, 'virgula');
  assert.match(prop.formato.evidencia.decimal, /2 valores provam vírgula/);
  assert.equal(resumo.saldo_titulos, '373400', '3.734,00, não 503,23');
});

test('formato: coluna de texto "1.10" não vence a coluna de saldo com vírgula', () => {
  // Duas colunas de texto com ponto (8 votos) contra uma de saldo com vírgula (4): votando em
  // todas as colunas, o texto vencia.
  const p = proporMapeamento(['Cliente', 'Versão', 'Lote', 'Vencimento', 'Saldo'],
    [['A', '1.10', '2.01', '01/01/2025', '1,50'], ['B', '1.11', '2.02', '01/01/2025', '2,50'], ['C', '1.12', '2.03', '01/01/2025', '3,50'], ['D', '1.13', '2.04', '01/01/2025', '4,50']]);
  assert.equal(p.formato.decimal, 'virgula');
});

test('formato: arquivo americano só com inteiros ("1,000") prova ponto; com vírgula, cada valor é marcado', async () => {
  const linhas = ['Cliente;Vencimento;Saldo', 'A;01/01/2025;1,000', 'B;01/01/2025;12,500', 'C;01/01/2025;3,000'];
  const { prop } = await aplicar(csv(linhas));
  assert.equal(prop.formato.decimal, 'ponto');
  const errado = await aplicar(csv(linhas), { formato: { decimal: 'virgula', datas: 'dia_mes_ano' } });
  assert.equal(errado.resumo.saldos_com_mais_de_2_casas, 3, 'o formato trocado não passa sem marca');
});

test('saldo com casas decimais a mais é contado (arredondados), não só arredondado', async () => {
  const { resumo } = await aplicar(csv(['Cliente;Vencimento;Saldo', 'A;01/01/2025;1,005', 'B;01/01/2025;2,00', 'C;01/01/2025;3,00']));
  assert.equal(resumo.saldos_arredondados, 1);
  assert.equal(resumo.saldo_titulos, '601');
});

test('contraparte vazia (relatório agrupado): rejeitada, com o saldo que ficou de fora', async () => {
  const { resumo } = await aplicar(csv(['Cliente;Vencimento;Saldo', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00', ';02/01/2025;4,00']));
  assert.deepEqual(resumo.motivos['contraparte vazia'], { linhas: 1, saldo: '400' });
});

test('o aplicador confere SOZINHO o cabeçalho que passa por ele: coluna inserida pelo ERP é erro, não saldo errado', async () => {
  const conf = { mapa: { contraparte: 0, vencimento: 1, saldo: 2 }, cabecalho: ['Cliente', 'Vencimento', 'Saldo'], formato: { decimal: 'virgula', datas: 'dia_mes_ano' }, ...CONFIRMACAO };
  const ap = aplicadorDeMapeamento(conf);
  await assert.rejects(lerTabela(csv(['Cliente;Vencimento;Valor Original;Saldo', 'A;01/01/2025;5,00;1,00', 'B;01/01/2025;5,00;1,00', 'C;01/01/2025;5,00;1,00']),
    { aoLinha: (l) => ap.linha(l) }), /não é o do mapeamento confirmado/);
  const ap2 = aplicadorDeMapeamento(conf);
  await lerTabela(csv(['Cliente;Vencimento;Saldo', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00']), { aoLinha: (l) => ap2.linha(l) });
  assert.equal(ap2.resumo().cabecalhos_conferidos, 1);
});

test('total geral no TOPO, ou seguido do subtotal do último cliente: confere, não diverge falso', async () => {
  const topo = await aplicar(csv(['Cliente;Vencimento;Saldo', 'TOTAL GERAL;;3,00', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00']));
  assert.equal(topo.resumo.conferencia_com_o_total_do_arquivo.estado, 'confere');
  const fim = await aplicar(csv(['Cliente;Vencimento;Saldo', 'A;01/01/2025;1,00', 'B;01/01/2025;1,00', 'C;01/01/2025;1,00', 'TOTAL GERAL;;3,00', 'Total C;;1,00']));
  assert.equal(fim.resumo.conferencia_com_o_total_do_arquivo.estado, 'confere');
});

test('saldo negativo (adiantamento) entra na soma e é contado à parte, com o efeito', async () => {
  const { resumo } = await aplicar(csv(['Cliente;Vencimento;Saldo', 'A;01/01/2025;10,00', 'B;01/01/2025;10,00', 'D;01/01/2025;-5,00']));
  assert.equal(resumo.saldo_titulos, '1500');
  assert.equal(resumo.titulos_com_saldo_negativo.linhas, 1);
  assert.equal(resumo.titulos_com_saldo_negativo.saldo, '-500');
  assert.match(resumo.titulos_com_saldo_negativo.efeito, /REDUZ/);
});

test('data com hora no CSV e ano de 2 dígitos como o Excel', () => {
  assert.equal(dataIso('31/12/2025 10:00'), '2025-12-31');
  assert.equal(dataIso('2025-12-31 10:00:00'), '2025-12-31');
  assert.equal(dataIso('01/01/29'), '2029-01-01');
  assert.equal(dataIso('01/01/30'), '1930-01-01');
});

test('a proposta não põe código numérico na contraparte', () => {
  const p = proporMapeamento(['Cliente', 'Vencimento', 'Saldo'], [['1001', '01/01/2025', '1,00'], ['1002', '01/01/2025', '2,00']]);
  assert.ok(!('contraparte' in p.mapa));
});
