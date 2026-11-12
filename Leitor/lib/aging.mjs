// O AGING de contas a receber e a pagar (MB3 e MB4 do PLANO_MVP_2026-11.md), em fluxo.
//
// POR QUE EXISTE. A MB2 entrega cada título (contraparte, vencimento, saldo em centavos). O
// aging é a fotografia da carteira numa DATA-BASE: quanto está a vencer e quanto está vencido
// há quanto tempo, por contraparte. É ele que concilia com o balanço (MB3b: Clientes e
// Fornecedores) e que vai ao book.
//
// DECISÕES QUE NÃO SE DESFAZEM SEM O DONO:
//   - Saldo NEGATIVO (adiantamento, crédito) é SEPARADO do positivo (decisão de 12/11/2026): os
//     positivos conciliam com Clientes (ou Fornecedores) e os negativos com Adiantamentos de
//     clientes (ou a fornecedores). Somar os dois só fecharia se o balanço também tivesse
//     compensado. As faixas e a concentração são só dos positivos.
//   - Título com saldo ZERO (liquidado) não entra em faixa nenhuma: é contado à parte.
//   - Título emitido DEPOIS da data-base não deveria estar numa posição naquela data: entra
//     (somar menos esconderia o problema) e é contado à parte, com o saldo. Muitos assim quase
//     sempre querem dizer data-base errada.
//
// A memória não depende do número de linhas: o que cresce é o número de contrapartes COM saldo.

import { textoNormalizado, dataIso } from './mapeamento.mjs';

// Atraso em dias = data-base − vencimento. Vencer NA data-base ainda é "a vencer".
export const FAIXAS = [
  ['a_vencer', null, 0], ['1_30', 1, 30], ['31_60', 31, 60], ['61_90', 61, 90],
  ['91_180', 91, 180], ['181_360', 181, 360], ['acima_360', 361, null],
];
const DIA = 86400000;
const dias = (iso) => Date.parse(`${iso}T00:00:00Z`) / DIA;

export function faixaDoAtraso(atraso) {
  for (const [nome, lo, hi] of FAIXAS) if ((lo === null || atraso >= lo) && (hi === null || atraso <= hi)) return nome;
  throw new Error(`atraso fora das faixas: ${atraso}`);
}

/**
 * A data-base proposta pelo título do relatório ("Posição em 31/12/2025", "Data-base: 31/12/2025",
 * "Vencidos até 31/12/2025"). Recebe as linhas `antes_do_cabecalho` da MB1 e o formato de datas
 * confirmado. É PROPOSTA: o analista confirma. Sem frase reconhecível, devolve `data: null` com o
 * motivo (regra 1), nunca a data de hoje.
 */
const RE_DATA_BASE = /(posi[cç][aã]o|data[\s-]*base|base|at[eé]|em)\s*(?:em|de|:)?\s*(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}|\d{4}-\d{2}-\d{2})/i;
export function dataBaseDoTitulo(linhas, datas = 'dia_mes_ano') {
  for (const l of linhas) {
    for (const c of l.celulas ?? []) {
      const m = RE_DATA_BASE.exec(String(c ?? ''));
      const d = m && dataIso(m[2], datas);
      if (d) return { data: d, evidencia: `linha ${l.n + 1} do arquivo: "${String(c).trim().slice(0, 120)}"` };
    }
  }
  return { data: null, evidencia: 'nenhuma linha antes do cabeçalho diz a data da posição ("Posição em ...", "Data-base ..."): o analista informa' };
}

/**
 * O agregador. `titulo(t)` recebe o `titulo` do aplicador da MB2; `resumo()` devolve o aging.
 * `dataBase` é obrigatória (ISO). `top` é quantas contrapartes vão nominalmente ao resumo; as
 * demais vão somadas em `demais`, com a contagem (nada some).
 */
export function agregadorDeAging({ dataBase, top = 50 } = {}) {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(dataBase ?? '')) || Number.isNaN(dias(dataBase))) {
    throw new Error('aging sem data-base (AAAA-MM-DD): o aging é a posição NUMA data, e ela tem de ser confirmada');
  }
  const base = dias(dataBase);
  const zero = () => Object.fromEntries(FAIXAS.map(([f]) => [f, 0n]));
  const r = {
    titulos: 0, liquidados: 0,
    positivos: { titulos: 0, saldo: 0n, por_faixa: zero(), vencido: 0n },
    negativos: { titulos: 0, saldo: 0n },
    emitidos_depois_da_data_base: { titulos: 0, saldo: 0n },
  };
  const porCp = new Map(); // chave → { contraparte, documento, saldo, vencido, titulos, negativo }

  return {
    titulo(t) {
      r.titulos++;
      if (t.saldo === 0n) { r.liquidados++; return; }
      if (t.emissao && dias(t.emissao) > base) { r.emitidos_depois_da_data_base.titulos++; r.emitidos_depois_da_data_base.saldo += t.saldo; }
      // A contraparte é identificada pelo documento quando ele existe (homônimos não se somam);
      // sem documento, pelo nome normalizado.
      const doc = String(t.documento_contraparte ?? '').replace(/\D/g, '');
      const chave = doc.length === 14 || doc.length === 11 ? `doc:${doc}` : `nome:${textoNormalizado(t.contraparte)}`;
      const cp = porCp.get(chave) ?? { contraparte: textoNormalizado(t.contraparte), documento: doc || null, saldo: 0n, vencido: 0n, titulos: 0, negativo: 0n };
      cp.titulos++;
      if (t.saldo < 0n) {
        r.negativos.titulos++; r.negativos.saldo += t.saldo; cp.negativo += t.saldo;
      } else {
        const faixa = faixaDoAtraso(base - dias(t.vencimento));
        r.positivos.titulos++; r.positivos.saldo += t.saldo; r.positivos.por_faixa[faixa] += t.saldo;
        cp.saldo += t.saldo;
        if (faixa !== 'a_vencer') { r.positivos.vencido += t.saldo; cp.vencido += t.saldo; }
      }
      porCp.set(chave, cp);
    },
    resumo() {
      const s = (x) => x.toString();
      const soma = Object.values(r.positivos.por_faixa).reduce((a, b) => a + b, 0n);
      if (soma !== r.positivos.saldo) throw new Error(`aging inconsistente: Σ faixas ${soma} ≠ Σ positivos ${r.positivos.saldo}`);
      const comSaldo = [...porCp.values()].filter((c) => c.saldo > 0n).sort((a, b) => (b.saldo > a.saldo ? 1 : b.saldo < a.saldo ? -1 : 0));
      const comCredito = [...porCp.values()].filter((c) => c.negativo < 0n).sort((a, b) => (a.negativo > b.negativo ? 1 : -1));
      const top10 = comSaldo.slice(0, 10).reduce((a, c) => a + c.saldo, 0n);
      // % com 4 casas, arredondado meio para cima, em inteiro (truncar dava 95,4026 onde é 95,4027).
      const pct = (a, b) => (b === 0n ? null : Number((a * 2000000n / b + 1n) / 2n) / 10000);
      const nominal = comSaldo.slice(0, top), demais = comSaldo.slice(top);
      const cpOut = (c) => ({ contraparte: c.contraparte, documento: c.documento, saldo: s(c.saldo), vencido: s(c.vencido), titulos: c.titulos });
      return {
        data_base: dataBase,
        titulos: r.titulos, liquidados: r.liquidados,
        positivos: {
          titulos: r.positivos.titulos, saldo: s(r.positivos.saldo), vencido: s(r.positivos.vencido),
          vencido_pct: pct(r.positivos.vencido, r.positivos.saldo),
          por_faixa: Object.fromEntries(Object.entries(r.positivos.por_faixa).map(([k, v]) => [k, s(v)])),
        },
        negativos: {
          titulos: r.negativos.titulos, saldo: s(r.negativos.saldo),
          efeito: 'créditos e adiantamentos: conciliam com Adiantamentos (passivo de quem recebe, ativo de quem paga), não com a carteira',
          maiores: comCredito.slice(0, 10).map((c) => ({ contraparte: c.contraparte, documento: c.documento, saldo: s(c.negativo) })),
        },
        emitidos_depois_da_data_base: {
          titulos: r.emitidos_depois_da_data_base.titulos, saldo: s(r.emitidos_depois_da_data_base.saldo),
          ...(r.emitidos_depois_da_data_base.titulos ? { efeito: 'título emitido depois da data-base está somado; muitos assim quase sempre querem dizer data-base errada' } : {}),
        },
        contrapartes_com_saldo: comSaldo.length,
        concentracao_top10_pct: pct(top10, r.positivos.saldo),
        maiores: nominal.map(cpOut),
        demais: { contrapartes: demais.length, saldo: s(demais.reduce((a, c) => a + c.saldo, 0n)), vencido: s(demais.reduce((a, c) => a + c.vencido, 0n)) },
      };
    },
  };
}
