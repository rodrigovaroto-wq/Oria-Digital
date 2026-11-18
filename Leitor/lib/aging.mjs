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
 *
 * Duas passadas, em ordem de força: primeiro "posição", "data-base" e "até" em TODAS as linhas;
 * só sem nenhuma delas, um "em" solto — e nunca numa frase de impressão, geração ou emissão. A
 * primeira versão aceitava o primeiro "em" de qualquer linha: "Impresso em 12/11/2026" antes de
 * "Posição em 31/12/2025" virava a data-base (revisão de 11/11/2026), com 316 dias a mais de
 * atraso em todo título e nada acusando (a data errada era posterior).
 */
const DATA = String.raw`(\d{1,2}[/.-]\d{1,2}[/.-]\d{2,4}|\d{4}-\d{2}-\d{2})`;
// Limite de palavra com acento: o `\b` do JavaScript só conhece [A-Za-z0-9_], e "até" não fecharia.
const ANTES = String.raw`(?<![\p{L}\d])`, DEPOIS = String.raw`(?![\p{L}\d])`;
const RE_FORTE = new RegExp(`${ANTES}(?:posi[cç][aã]o|data[\\s-]*(?:da\\s+)?base|database|at[eé])${DEPOIS}[^\\d]{0,12}?${DATA}`, 'iu');
const RE_FRACO = new RegExp(`${ANTES}em${DEPOIS}\\s*:?\\s*${DATA}`, 'iu');
const RE_NAO_E_POSICAO = new RegExp(`${ANTES}(?:impress|gerad|emitid|emiss|criad|extra[ií]d|hora|usu[aá]rio|p[aá]gina)`, 'iu');
export function dataBaseDoTitulo(linhas, datas = 'dia_mes_ano') {
  for (const [re, filtro] of [[RE_FORTE, null], [RE_FRACO, RE_NAO_E_POSICAO]]) {
    for (const l of linhas) {
      for (const c of l.celulas ?? []) {
        const texto = String(c ?? '');
        if (filtro && filtro.test(texto)) continue;
        const m = re.exec(texto);
        const d = m && dataIso(m[1], datas);
        if (d) return { data: d, evidencia: `linha ${l.n + 1} do arquivo: "${texto.trim().slice(0, 120)}"` };
      }
    }
  }
  return { data: null, evidencia: 'nenhuma linha antes do cabeçalho diz a data da posição ("Posição em ...", "Data-base ..."): o analista informa' };
}

// ------------------------------------------------------------- documento --
/** CNPJ (14) ou CPF (11) com dígito verificador VÁLIDO, em dígitos; ou null. */
function dvValido(d) {
  const calc = (base, pesos) => { const r = base.split('').reduce((a, x, i) => a + Number(x) * pesos[i], 0) % 11; return r < 2 ? 0 : 11 - r; };
  if (/^(\d)\1+$/.test(d)) return false; // 00.000.000/0000-00, 111.111.111-11: passam na conta e não são ninguém
  if (d.length === 14) {
    const p1 = [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2], p2 = [6, ...p1];
    return calc(d.slice(0, 12), p1) === Number(d[12]) && calc(d.slice(0, 13), p2) === Number(d[13]);
  }
  if (d.length === 11) {
    const p1 = [10, 9, 8, 7, 6, 5, 4, 3, 2], p2 = [11, ...p1];
    return calc(d.slice(0, 9), p1) === Number(d[9]) && calc(d.slice(0, 10), p2) === Number(d[10]);
  }
  return false;
}
/**
 * O documento que IDENTIFICA a contraparte, ou null. Aceita o zero à esquerda perdido pelo XLSX
 * numérico (13 dígitos → CNPJ, 10 → CPF) se o dígito verificador fecha depois de recolocá-lo.
 * Documento de preenchimento (zeros, repetidos, DV errado) não identifica ninguém: a primeira
 * versão juntava ACME e BETA, os dois com 00.000.000/0000-00, numa contraparte só (revisão).
 */
export function documentoValido(texto) {
  const d = String(texto ?? '').replace(/\D/g, '');
  if (!d) return null;
  for (const n of d.length > 11 ? [14] : [11, 14]) {
    if (d.length <= n && d.length >= n - 2) { const x = d.padStart(n, '0'); if (dvValido(x)) return x; }
  }
  return null;
}

/**
 * O agregador. `titulo(t)` recebe o `titulo` do aplicador da MB2; `resumo()` devolve o aging.
 * `dataBase` é obrigatória (ISO, data que existe). `top` é quantas contrapartes vão nominalmente
 * ao resumo, nos positivos e nos créditos; as demais vão somadas em `demais`, com as contagens
 * (nada some, nos dois lados).
 *
 * Identidade da contraparte: pelo documento VÁLIDO; sem ele, pelo nome normalizado. O MESMO nome
 * visto com um documento e sem documento é a MESMA contraparte quando só UM documento usa aquele
 * nome (o ERP às vezes não traz o CNPJ); com dois documentos para o nome (homônimos), a linha sem
 * documento fica à parte e é contada em `sem_documento_ambiguo`.
 */
export function agregadorDeAging({ dataBase, top = 50 } = {}) {
  // `dataIso` recusa 2025-02-30 (o Date.parse o rolaria para 02/03 e deslocaria as faixas).
  if (!/^\d{4}-\d{2}-\d{2}$/.test(String(dataBase ?? '')) || dataIso(dataBase) !== dataBase) {
    throw new Error('aging sem data-base válida (AAAA-MM-DD, data que existe): o aging é a posição NUMA data, e ela tem de ser confirmada');
  }
  const base = dias(dataBase);
  const zero = () => Object.fromEntries(FAIXAS.map(([f]) => [f, 0n]));
  const r = {
    titulos: 0, liquidados: 0,
    positivos: { titulos: 0, saldo: 0n, por_faixa: zero(), vencido: 0n },
    negativos: { titulos: 0, saldo: 0n },
    emitidos_depois_da_data_base: { titulos: 0, saldo_positivos: 0n, saldo_negativos: 0n },
    documentos_invalidos: { titulos: 0 },
  };
  const porCp = new Map(); // chave → { contraparte, documento, saldo, vencido, titulos, negativo, titulos_credito }

  return {
    titulo(t) {
      r.titulos++;
      if (t.saldo === 0n) { r.liquidados++; return; }
      if (t.emissao && dias(t.emissao) > base) {
        r.emitidos_depois_da_data_base.titulos++;
        r.emitidos_depois_da_data_base[t.saldo < 0n ? 'saldo_negativos' : 'saldo_positivos'] += t.saldo;
      }
      const temDoc = String(t.documento_contraparte ?? '').replace(/\D/g, '') !== '';
      const doc = documentoValido(t.documento_contraparte);
      if (temDoc && !doc) r.documentos_invalidos.titulos++;
      const nome = textoNormalizado(t.contraparte);
      const chave = doc ? `doc:${doc}` : `nome:${nome}`;
      const cp = porCp.get(chave) ?? { contraparte: nome, documento: doc, saldo: 0n, vencido: 0n, titulos: 0, negativo: 0n, titulos_credito: 0 };
      if (t.saldo < 0n) {
        r.negativos.titulos++; r.negativos.saldo += t.saldo; cp.negativo += t.saldo; cp.titulos_credito++;
      } else {
        const faixa = faixaDoAtraso(base - dias(t.vencimento));
        r.positivos.titulos++; r.positivos.saldo += t.saldo; r.positivos.por_faixa[faixa] += t.saldo;
        cp.saldo += t.saldo; cp.titulos++;
        if (faixa !== 'a_vencer') { r.positivos.vencido += t.saldo; cp.vencido += t.saldo; }
      }
      porCp.set(chave, cp);
    },
    resumo() {
      const s = (x) => x.toString();
      const soma = Object.values(r.positivos.por_faixa).reduce((a, b) => a + b, 0n);
      if (soma !== r.positivos.saldo) throw new Error(`aging inconsistente: Σ faixas ${soma} ≠ Σ positivos ${r.positivos.saldo}`);
      // O mesmo nome com e sem documento: funde no documento quando ele é o ÚNICO daquele nome.
      const docsDoNome = new Map();
      for (const [k, c] of porCp) if (k.startsWith('doc:')) docsDoNome.set(c.contraparte, [...(docsDoNome.get(c.contraparte) ?? []), k]);
      let semDocAmbiguo = 0;
      for (const [k, c] of [...porCp]) {
        if (!k.startsWith('nome:')) continue;
        const docs = docsDoNome.get(c.contraparte) ?? [];
        if (docs.length === 1) {
          const alvo = porCp.get(docs[0]);
          for (const f of ['saldo', 'vencido', 'titulos', 'negativo', 'titulos_credito']) alvo[f] += c[f];
          porCp.delete(k);
        } else if (docs.length > 1) semDocAmbiguo += c.titulos + c.titulos_credito;
      }
      const ordem = (campo, desc) => (a, b) => (a[campo] === b[campo] ? 0 : (a[campo] > b[campo]) === desc ? -1 : 1);
      const comSaldo = [...porCp.values()].filter((c) => c.saldo > 0n).sort(ordem('saldo', true));
      const comCredito = [...porCp.values()].filter((c) => c.negativo < 0n).sort(ordem('negativo', false));
      const top10 = comSaldo.slice(0, 10).reduce((a, c) => a + c.saldo, 0n);
      // % com 4 casas, arredondado meio para cima, em inteiro (truncar dava 95,4026 onde é 95,4027).
      const pct = (a, b) => (b === 0n ? null : Number((a * 2000000n / b + 1n) / 2n) / 10000);
      const nominal = comSaldo.slice(0, top), demais = comSaldo.slice(top);
      const credNominal = comCredito.slice(0, top), credDemais = comCredito.slice(top);
      const somaDe = (lista, f) => lista.reduce((a, c) => a + c[f], f.startsWith('titulos') ? 0 : 0n);
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
          maiores: credNominal.map((c) => ({ contraparte: c.contraparte, documento: c.documento, saldo: s(c.negativo), titulos: c.titulos_credito })),
          demais: { contrapartes: credDemais.length, saldo: s(somaDe(credDemais, 'negativo')), titulos: somaDe(credDemais, 'titulos_credito') },
        },
        emitidos_depois_da_data_base: {
          titulos: r.emitidos_depois_da_data_base.titulos,
          saldo_positivos: s(r.emitidos_depois_da_data_base.saldo_positivos), saldo_negativos: s(r.emitidos_depois_da_data_base.saldo_negativos),
          ...(r.emitidos_depois_da_data_base.titulos ? { efeito: 'título emitido depois da data-base está somado; muitos assim quase sempre querem dizer data-base errada' } : {}),
        },
        documentos_invalidos: {
          titulos: r.documentos_invalidos.titulos,
          ...(r.documentos_invalidos.titulos ? { efeito: 'CNPJ/CPF com dígito verificador inválido (ou de preenchimento, como 00.000.000/0000-00) não identifica a contraparte: esses títulos foram agrupados pelo nome' } : {}),
        },
        sem_documento_ambiguo: { titulos: semDocAmbiguo },
        contrapartes_com_saldo: comSaldo.length,
        concentracao_top10_pct: pct(top10, r.positivos.saldo),
        maiores: nominal.map(cpOut),
        demais: { contrapartes: demais.length, saldo: s(somaDe(demais, 'saldo')), vencido: s(somaDe(demais, 'vencido')), titulos: somaDe(demais, 'titulos') },
      };
    },
  };
}
