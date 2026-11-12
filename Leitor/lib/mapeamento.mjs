// O MAPEAMENTO DE COLUNAS de contas a receber e a pagar (MB2 do PLANO_MVP_2026-11.md).
//
// POR QUE EXISTE. O leitor tabular (`tabela.mjs`, MB1) entrega linhas e células, mas não sabe
// o que cada coluna significa. Sem isso, decidir se uma linha é título, subtotal ou lixo é
// palpite: a revisão de 11/11/2026 mostrou o palpite errando nos dois sentidos (título em
// aberto descartado, subtotal somado como título). Aqui a decisão é feita COM o significado
// das colunas, e a regra é uma só: um título tem contraparte, vencimento que É data e saldo
// que É número. O que não é isso não some: vira subtotal ou rejeitada, contada, com o motivo.
//
// O CICLO:
//   1. `proporMapeamento(cabecalho, amostra, tipoBase)` propõe, coluna a coluna, por sinônimo
//      do nome E pelo tipo dos valores da amostra. É proposta: o analista confirma.
//   2. O analista confirma; o banco guarda o mapeamento com autor e data, pela impressão do
//      cabeçalho (`impressaoDoCabecalho`), e o reaproveita no próximo arquivo do mesmo ERP.
//   3. `aplicadorDeMapeamento(mapeamentoConfirmado)` recebe cada linha do `aoLinha` da MB1 e
//      devolve o título já em centavos e datas ISO, ou o motivo de não ser título.
// SEM mapeamento confirmado (autor e data) o aplicador RECUSA: arquivo sem confirmação não
// vira dado (critério de pronto da MB2).
//
// A IA NÃO ENTRA AQUI, de propósito, por ora (escada, degraus 1 e 2): o plano previa a IA
// propondo o mapeamento a partir de 30 linhas. Para cabeçalhos de ERP ("Vencimento",
// "Saldo", "Cliente") sinônimo + tipo da amostra resolve, sem custo e sem rede; o analista
// confirma de qualquer jeito. A IA volta se arquivos reais (DM7) mostrarem cabeçalhos que os
// sinônimos não alcançam: a proposta diz `confianca` por campo para isso ser medido.

import { sha256Hex } from './sha256.mjs';

// ------------------------------------------------------------------- os campos --
// `efeito` é o que vai na nota quando o campo falta (regra 1: ausência com o efeito).
export const CAMPOS = {
  contraparte: { tipo: 'texto', obrigatorio: true, efeito: 'sem contraparte não há aging por cliente ou fornecedor nem concentração' },
  documento_contraparte: { tipo: 'documento', efeito: 'sem CNPJ/CPF a contraparte é identificada só pelo nome; homônimos se somam' },
  titulo: { tipo: 'texto', efeito: 'sem número do título as parcelas não são agrupadas' },
  parcela: { tipo: 'texto', efeito: 'sem parcela, título repetido não se distingue de parcela' },
  emissao: { tipo: 'data', efeito: 'sem emissão não há prazo médio de recebimento ou pagamento' },
  vencimento: { tipo: 'data', obrigatorio: true, efeito: 'sem vencimento o aging não pode ser calculado' },
  valor_original: { tipo: 'valor', efeito: 'sem valor original não se confere original = pago + saldo' },
  valor_pago: { tipo: 'valor', efeito: 'sem valor pago o título parcial não se distingue do aberto' },
  saldo: { tipo: 'valor', obrigatorio: true, efeito: 'sem saldo não há aging nem conciliação com o balanço' },
  data_pagamento: { tipo: 'data', efeito: 'sem data de pagamento não há prazo efetivo' },
  situacao: { tipo: 'texto', efeito: 'sem situação o título liquidado só se reconhece pelo saldo zero' },
};
export const TIPOS_DE_BASE = ['contas_a_receber', 'contas_a_pagar'];

const sem = (s) => String(s ?? '').normalize('NFD').replace(/[̀-ͯ]/g, '').toLowerCase().replace(/[^a-z0-9]+/g, ' ').trim();

// Sinônimos de nome de coluna, já sem acento e em minúsculas. A ordem importa só entre
// campos que disputam a mesma coluna; o desempate final é o tipo dos valores da amostra.
const SINONIMOS = {
  contraparte: [/^(cliente|fornecedor|sacado|cedente|razao social|nome|favorecido|devedor|credor|parceiro)( .*)?$/, /^nome (do )?(cliente|fornecedor)/],
  documento_contraparte: [/^(cnpj|cpf|cnpj cpf|cpf cnpj|documento do cliente|doc cliente|cnpj do cliente|cnpj fornecedor)$/],
  titulo: [/^(titulo|n titulo|numero|numero do titulo|documento|doc|nota|nf|nota fiscal|duplicata|n documento)$/],
  parcela: [/^(parcela|parc|prestacao)$/],
  emissao: [/^(emissao|data de emissao|dt emissao|data emissao|emitido em)$/],
  vencimento: [/^(vencimento|data de vencimento|dt vencto|dt vencimento|vencto|venc|data vencimento|vencimento real)$/],
  valor_original: [/^(valor original|valor|vl original|valor do titulo|valor nominal|valor bruto|vl titulo)$/],
  valor_pago: [/^(valor pago|vl pago|valor recebido|vl recebido|pago|recebido|valor baixado)$/],
  saldo: [/^(saldo|saldo em aberto|em aberto|valor em aberto|saldo devedor|valor a receber|valor a pagar|vl saldo|aberto)$/],
  data_pagamento: [/^(data pagamento|data de pagamento|dt pagamento|data recebimento|data de recebimento|dt baixa|data baixa|pago em|recebido em)$/],
  situacao: [/^(situacao|status|posicao|estado)$/],
};

// ---------------------------------------------------------- a impressão digital --
// O MESMO texto tem de sair aqui e no banco (que recalcula a impressão do cabeçalho que
// recebe, em vez de confiar na que o navegador manda). Por isso a normalização é a menor
// possível e sem nada que dependa de locale: NFC, espaços nas pontas fora, espaços
// internos colapsados, células vazias do FIM fora, junção por U+001F. NÃO há minúsculas:
// o `lower()` do Postgres depende do LC_CTYPE do banco, e um ERP exporta o mesmo
// cabeçalho sempre com a mesma caixa.
const ESPACOS = /[ \t\n\r\u00a0]+/g;
/**
 * Uma célula normalizada: NFC, sequências de [espaço \t \n \r U+00A0] viram um espaço, pontas
 * aparadas desses MESMOS caracteres. Não `.trim()`: ele apara qualquer espaço Unicode (U+2003...)
 * e o banco (0272, 0273) apara só esses cinco; as duas impressões divergiriam.
 */
export function textoNormalizado(x) {
  return String(x ?? '').normalize('NFC').replace(ESPACOS, ' ').replace(/^ | $/g, '');
}
export function cabecalhoNormalizado(celulas) {
  const c = celulas.map(textoNormalizado);
  while (c.length && c[c.length - 1] === '') c.pop();
  return c;
}
export function impressaoDoCabecalho(celulas) {
  return sha256Hex(new TextEncoder().encode(cabecalhoNormalizado(celulas).join('\u001f')));
}

// ------------------------------------------------------------ valores e datas --
// O FORMATO é do arquivo, não do valor: "1.250" é mil duzentos e cinquenta com vírgula
// decimal e um e vinte e cinco com ponto; "03/04/2025" é 3 de abril ou 4 de março. Decidir
// valor a valor erra sem erro. Por isso o formato é proposto pela amostra
// (`formatoDaAmostra`) e CONFIRMADO pelo analista junto com as colunas.
export const FORMATO_PADRAO = { decimal: 'virgula', datas: 'dia_mes_ano' };

/**
 * Texto de valor → { centavos (BigInt), arredondado, casas_extras }, ou null. `decimal` é o do
 * arquivo: 'virgula' ("1.234,56", "1234,56") ou 'ponto' ("1,234.56", "1234.56"). Aceita UM
 * sinal: na frente, no fim ("1.234,56-") ou parênteses, antes ou depois de "R$" ("-R$ 1,00",
 * "(R$ 1,00)", "R$-1,00"). Dois sinais ("(-1,00)", "-1,00-") são null: virariam positivo sem
 * erro (revisão de 11/11/2026). Número do XLSX (`tipo` 'n') é sempre ponto, talvez em notação
 * científica ("1.5E-2") ou com o ruído de 17 dígitos do Excel ("1234.5599999999999"),
 * expandido em TEXTO (por float o centavo de valor grande some).
 *   arredondado   havia mais de 2 casas com dígito não-zero que NÃO era ruído de float
 *   casas_extras  havia mais de 2 casas, mesmo zeros ("1,000" lido com vírgula decimal): quase
 *                 sempre é o formato trocado, e a revisão mediu 16.500,00 virando 16,50 sem marca
 */
export function valorEmCentavos(texto, tipo = '', decimal = 'virgula') {
  let t = String(texto ?? '').trim();
  if (t === '') return null;
  let sinais = 0;
  const tirarMoeda = () => { t = t.replace(/^R\$\s*/i, '').trim(); };
  tirarMoeda();
  if (/^\(.*\)$/.test(t)) { sinais++; t = t.slice(1, -1).trim(); tirarMoeda(); }
  if (t.endsWith('-')) { sinais++; t = t.slice(0, -1).trim(); }
  if (t.startsWith('-')) { sinais++; t = t.slice(1).trim(); tirarMoeda(); }
  if (sinais > 1 || t.startsWith('-') || t.startsWith('(')) return null;
  let inteiro, frac;
  if (tipo === 'n') {
    // Número do XML (ponto decimal, talvez notação científica). Expandido em TEXTO: passar
    // por float perderia o centavo de valores grandes.
    const m = /^(\d+)(?:\.(\d+))?(?:e([+-]?\d+))?$/i.exec(t);
    if (!m) return null;
    let dig = m[1] + (m[2] ?? ''), pos = m[1].length + Number(m[3] ?? 0);
    if (pos < 0) { dig = '0'.repeat(-pos) + dig; pos = 0; }
    if (pos > dig.length) dig += '0'.repeat(pos - dig.length);
    inteiro = dig.slice(0, pos) || '0'; frac = dig.slice(pos);
  } else if (decimal === 'ponto') {
    if (!/^\d{1,3}(,\d{3})+(\.\d+)?$|^\d+(\.\d+)?$/.test(t)) return null;
    [inteiro, frac = ''] = t.replace(/,/g, '').split('.');
  } else {
    if (!/^\d{1,3}(\.\d{3})+(,\d+)?$|^\d+(,\d+)?$/.test(t)) return null;
    [inteiro, frac = ''] = t.replace(/\./g, '').split(',');
  }
  const dois = (frac + '00').slice(0, 2), resto = frac.slice(2);
  let c = BigInt(inteiro) * 100n + BigInt(dois);
  // Ruído de float: "99999999…" ou "0000000…1" a partir da 3ª casa (o Excel grava 17 dígitos).
  const ruido = /^9{6,}\d*$/.test(resto) || /^0{6,}\d*$/.test(resto);
  if (resto && resto[0] >= '5') c += 1n;
  const arredondado = !!resto && /[1-9]/.test(resto) && !ruido;
  const casasExtras = !!resto && !ruido;
  return { centavos: sinais ? -c : c, arredondado, casas_extras: casasExtras };
}

/**
 * Texto de data → "AAAA-MM-DD", ou null. ISO ("2025-12-31", a data do XLSX) vale sempre;
 * "31/12/2025" e "31/12/25" seguem `datas` do arquivo ('dia_mes_ano' ou 'mes_dia_ano'). Hora no
 * fim ("31/12/2025 10:00", "2025-12-31 10:00:00") é aceita e descartada. Ano de 2 dígitos segue
 * o Excel: 00–29 é 20xx, 30–99 é 19xx. Data impossível (31/02) é null: o `Date` a normalizaria
 * para março sem erro.
 */
const DATAS_JA_VISTAS = new Map(); // um AR de 1M de linhas tem poucas centenas de datas distintas
const HORA = '(?:[ T]\\d{1,2}:\\d{2}(?::\\d{2}(?:\\.\\d+)?)?)?';
const RE_ISO = new RegExp(`^(\\d{4})-(\\d{2})-(\\d{2})${HORA}$`);
const RE_BR = new RegExp(`^(\\d{1,2})[/.-](\\d{1,2})[/.-](\\d{2}|\\d{4})${HORA}$`);
export function dataIso(texto, datas = 'dia_mes_ano') {
  const t = String(texto ?? '').trim();
  const chave = datas + t;
  if (DATAS_JA_VISTAS.has(chave)) return DATAS_JA_VISTAS.get(chave);
  let a, m, d;
  let x = RE_ISO.exec(t);
  if (x) [a, m, d] = [Number(x[1]), Number(x[2]), Number(x[3])];
  else if ((x = RE_BR.exec(t))) {
    [d, m, a] = datas === 'mes_dia_ano' ? [Number(x[2]), Number(x[1]), Number(x[3])] : [Number(x[1]), Number(x[2]), Number(x[3])];
    if (x[3].length === 2) a += a < 30 ? 2000 : 1900;
  } else return null;
  const dt = new Date(Date.UTC(a, m - 1, d));
  const r = a < 1 || dt.getUTCFullYear() !== a || dt.getUTCMonth() !== m - 1 || dt.getUTCDate() !== d ? null : dt.toISOString().slice(0, 10);
  if (DATAS_JA_VISTAS.size > 50000) DATAS_JA_VISTAS.clear();
  DATAS_JA_VISTAS.set(chave, r);
  return r;
}

/**
 * O formato proposto pela amostra, com a evidência, contado SÓ nas colunas que importam:
 * `colunas.valores` (as de saldo, valor original e valor pago) para o decimal, e
 * `colunas.datas` para a ordem das datas. Medido na revisão de 11/11/2026: votando em todas
 * as colunas, uma data "15.03.25" contava como "ponto decimal" e "1.234" virava 12,34 com a
 * evidência dizendo que havia prova.
 * Decimal: "1.234,56" prova vírgula; "1,234.56" prova ponto; "1.234" (milhar sem decimal) prova
 * que o ponto é milhar, logo vírgula; "1,000" prova que a vírgula é milhar, logo ponto.
 * Datas: um primeiro número > 12 prova dia/mês; um segundo > 12 prova mês/dia. Sem prova,
 * fica o padrão brasileiro e a `evidencia` DIZ que não houve prova.
 */
export function formatoDaAmostra(amostra, tipos = [], colunas = {}) {
  let virgula = 0, ponto = 0, dmy = 0, mdy = 0;
  const conta = (lista, i) => !lista || lista.includes(i);
  amostra.forEach((linha, k) => linha.forEach((c, i) => {
    const tipo = tipos[k]?.[i];
    if (tipo && tipo !== 's') return; // número e data do XLSX não dizem nada do formato do texto
    const t = String(c ?? '').trim().replace(/^[-(]*\s*(R\$)?\s*-?/i, '').replace(/[)-]+$/, '').trim();
    if (conta(colunas.valores, i)) {
      if (/^\d{1,3}(\.\d{3})*,\d{1,2}$|^\d+,\d{1,2}$/.test(t)) virgula++;
      else if (/^\d{1,3}(,\d{3})*\.\d{1,2}$|^\d+\.\d{1,2}$/.test(t)) ponto++;
      else if (/^\d{1,3}(\.\d{3})+$/.test(t)) virgula++; // ponto como milhar
      else if (/^\d{1,3}(,\d{3})+$/.test(t)) ponto++;    // vírgula como milhar
    }
    if (conta(colunas.datas, i)) {
      const x = RE_BR.exec(t);
      if (x) { if (Number(x[1]) > 12) dmy++; if (Number(x[2]) > 12) mdy++; }
    }
  }));
  const decimal = ponto > virgula ? 'ponto' : 'virgula';
  const datas = mdy > dmy ? 'mes_dia_ano' : 'dia_mes_ano';
  return {
    decimal, datas,
    evidencia: {
      decimal: virgula + ponto === 0 ? 'nenhum valor com casas decimais ou milhar nas colunas de valor da amostra: padrão vírgula, SEM prova' : `nas colunas de valor: ${virgula} valores provam vírgula decimal, ${ponto} provam ponto`,
      datas: dmy + mdy === 0 ? 'nenhuma data com dia acima de 12 nas colunas de data da amostra: ordem dia/mês SEM prova' : `nas colunas de data: ${dmy} datas provam dia/mês, ${mdy} provam mês/dia`,
    },
  };
}

/** O tipo de um valor, SEM depender do formato (que só se decide depois de saber quais colunas são de valor). */
function tipoDoValor(texto, tipo) {
  if (String(texto ?? '').trim() === '') return 'vazio';
  if (tipo === 'd' || (tipo !== 'n' && (dataIso(texto, 'dia_mes_ano') || dataIso(texto, 'mes_dia_ano')))) return 'data';
  const t = String(texto).trim();
  const digitos = t.replace(/\D/g, '');
  if (/^\d{2}\.?\d{3}\.?\d{3}\/?\d{4}-?\d{2}$|^\d{3}\.?\d{3}\.?\d{3}-?\d{2}$/.test(t) && (digitos.length === 14 || digitos.length === 11)) return 'documento';
  if (valorEmCentavos(texto, tipo, 'virgula') || valorEmCentavos(texto, tipo, 'ponto')) return 'valor';
  return 'texto';
}

// -------------------------------------------------------------------- proposta --
/**
 * Proposta de mapeamento: { mapa: {campo: índice}, formato, faltando: [{campo, obrigatorio,
 * efeito}], ambiguos: [...] }. `amostra` e `tipos` são o `amostra` e o `amostra_tipos` do
 * resumo da MB1 (até 30 linhas do corpo; `tipos` só no XLSX). Primeiro as colunas (pelo nome
 * e pelo tipo), DEPOIS o formato, contado só nas colunas de valor e de data escolhidas. É
 * PROPOSTA: o analista confirma colunas e formato.
 */
export function proporMapeamento(cabecalho, amostra, { tipos = [] } = {}) {
  const n = cabecalho.length;
  // Tipo dominante de cada coluna na amostra.
  const dominante = [];
  for (let i = 0; i < n; i++) {
    const cont = {};
    amostra.forEach((l, k) => { const t = tipoDoValor(l[i], tipos[k]?.[i]); if (t !== 'vazio') cont[t] = (cont[t] ?? 0) + 1; });
    const [t] = Object.entries(cont).sort((a, b) => b[1] - a[1])[0] ?? ['vazio'];
    dominante.push(t);
  }
  const compativel = (campo, i) => {
    const t = dominante[i], esperado = CAMPOS[campo].tipo;
    if (t === 'vazio') return true; // coluna vazia na amostra (ex.: data de pagamento de quem não pagou)
    // Contraparte nunca é número: um código de cliente numérico não é a razão social.
    if (esperado === 'texto') return t === 'texto' || t === 'documento' || (campo !== 'contraparte' && t === 'valor');
    return t === esperado;
  };
  const mapa = {}, usadas = new Set(), ambiguos = [];
  for (const campo of Object.keys(CAMPOS)) {
    const candidatas = [];
    for (let i = 0; i < n; i++) {
      if (usadas.has(i)) continue;
      if (SINONIMOS[campo].some((re) => re.test(sem(cabecalho[i]))) && compativel(campo, i)) candidatas.push(i);
    }
    if (candidatas.length > 1) ambiguos.push({ campo, colunas: candidatas.map((i) => cabecalho[i]) });
    if (candidatas.length) { mapa[campo] = candidatas[0]; usadas.add(candidatas[0]); }
  }
  // Sem coluna de valor (ou de data) reconhecida pelo nome — cabeçalho fora dos sinônimos, o
  // analista vai mapear à mão —, o voto conta nas colunas cujo tipo dominante é valor (ou data):
  // nunca em todas, que é o que deixava uma data "15.03.25" votar no decimal.
  const de = (lista, tipo) => {
    const mapeadas = lista.filter((c) => c in mapa).map((c) => mapa[c]);
    return mapeadas.length ? mapeadas : dominante.flatMap((t, i) => (t === tipo ? [i] : []));
  };
  const formato = formatoDaAmostra(amostra, tipos, {
    valores: de(['saldo', 'valor_original', 'valor_pago'], 'valor'), datas: de(['vencimento', 'emissao', 'data_pagamento'], 'data'),
  });
  const faltando = Object.entries(CAMPOS).filter(([c]) => !(c in mapa))
    .map(([campo, d]) => ({ campo, obrigatorio: !!d.obrigatorio, efeito: d.efeito }));
  return { mapa, formato, faltando, ambiguos, tipo_dominante: dominante };
}

/** O mapeamento é aplicável? Obrigatórios presentes, índices válidos, coluna usada uma vez só. */
export function validarMapeamento(mapa, cabecalho) {
  const erros = [];
  const usadas = new Map();
  for (const [campo, i] of Object.entries(mapa ?? {})) {
    if (!(campo in CAMPOS)) { erros.push(`campo desconhecido: ${campo}`); continue; }
    if (!Number.isInteger(i) || i < 0 || i >= cabecalho.length) { erros.push(`${campo}: coluna ${i} fora do cabeçalho (${cabecalho.length} colunas)`); continue; }
    if (usadas.has(i)) erros.push(`a coluna "${cabecalho[i]}" está em ${usadas.get(i)} e em ${campo}`);
    usadas.set(i, campo);
  }
  for (const [campo, d] of Object.entries(CAMPOS)) if (d.obrigatorio && !(campo in (mapa ?? {}))) erros.push(`falta o campo obrigatório ${campo}: ${d.efeito}`);
  return { ok: erros.length === 0, erros };
}

// -------------------------------------------------------------------- aplicação --
const RE_TOTAL = /^\W*(sub[\s-]?)?tota(l|is)\b|^\W*soma\b|^\W*saldo\s+geral\b/i;
// O nome que é SÓ o rótulo de total, sem nada que identifique alguém: nunca contraparte real.
const RE_SO_ROTULO = /^\W*((sub[\s-]?)?tota(l|is)(\s+gera(l|is))?|soma|saldo\s+geral)\W*$/i;
const MAX_SUBTOTAIS_GUARDADOS = 10000;

/**
 * O aplicador: recebe CADA linha do `aoLinha` da MB1 e a classifica. Devolve um objeto com
 * `linha(l)` → { classe, titulo?, motivo? } e `resumo()`. Classes, uma por linha do corpo:
 *   titulo     contraparte preenchida, vencimento que é data, saldo que é número, e NENHUM
 *              sinal de total
 *   subtotal   saldo é número, vencimento vazio ou não-data, e a linha tem o SINAL de total
 *              (da MB1 ou na contraparte) ou nenhuma contraparte: nunca somada de novo
 *   rejeitada  qualquer outra, contada por motivo com o saldo que ficou de fora. Inclui a
 *              linha com sinal de total E vencimento data: "Total ACME; 02/01/2025; 30,00"
 *              (total por data) e "TOTAL DISTRIBUIDORA LTDA" (cliente chamado Total) não se
 *              distinguem sem o analista. Somar a primeira triplicava o aging (revisão de
 *              11/11/2026); deixar a segunda de fora é VISÍVEL, com o saldo, no resumo.
 * As linhas fora do corpo passam contadas como `fora_do_corpo`. A linha de CABEÇALHO (inclusive
 * a repetida) é conferida contra o cabeçalho confirmado: se o ERP mudou uma coluna de lugar, o
 * aplicador ERRA em vez de ler o saldo da coluna errada.
 *
 * `contrapartesReais` são as contrapartes que o analista CONFIRMOU, no mandato, como cliente ou
 * fornecedor de verdade apesar do nome de total ("TOTAL DISTRIBUIDORA LTDA", "SOMA ENGENHARIA"):
 * a linha delas com vencimento data volta a ser título, contada em
 * `titulos_de_contraparte_confirmada`. As que ainda não foram confirmadas aparecem em
 * `candidatas_a_contraparte_real` (nome, linhas e saldo), que é o que a tela oferece para confirmar.
 * Comparação pelo nome normalizado (`textoNormalizado`), o mesmo que o banco grava (0273).
 *
 * Campo OPCIONAL inválido (data de pagamento "00/00/0000", valor pago "-") não derruba o
 * título: o campo fica ausente e é contado em `opcionais_invalidos` (regra 1: a ausência
 * aparece). Só os obrigatórios rejeitam.
 *
 * `confirmado` é o mapeamento CONFIRMADO: { mapa, formato, cabecalho, confirmado_por,
 * confirmado_em }. Sem autor e data, ou sem o formato, o aplicador recusa: arquivo sem
 * confirmação não vira dado.
 */
export function aplicadorDeMapeamento(confirmado, { cabecalhoDoArquivo, contrapartesReais = [] } = {}) {
  if (!confirmado?.confirmado_por || !confirmado?.confirmado_em) {
    throw new Error('mapeamento sem confirmação (autor e data): o arquivo não vira dado sem um analista confirmar as colunas');
  }
  const { mapa, cabecalho, formato } = confirmado;
  if (!['virgula', 'ponto'].includes(formato?.decimal) || !['dia_mes_ano', 'mes_dia_ano'].includes(formato?.datas)) {
    throw new Error('mapeamento sem o formato confirmado (decimal: vírgula ou ponto; datas: dia/mês ou mês/dia)');
  }
  const v = validarMapeamento(mapa, cabecalho);
  if (!v.ok) throw new Error(`mapeamento inválido: ${v.erros.join('; ')}`);
  const impressao = impressaoDoCabecalho(cabecalho);
  const conferirCabecalho = (celulas) => {
    if (impressaoDoCabecalho(celulas) !== impressao) {
      throw new Error('o cabeçalho do arquivo não é o do mapeamento confirmado: as colunas podem ter mudado de lugar');
    }
  };
  if (cabecalhoDoArquivo) conferirCabecalho(cabecalhoDoArquivo);
  const r = {
    linhas: 0, fora_do_corpo: 0, cabecalhos_conferidos: 0, titulo: 0, subtotal: 0, rejeitada: 0,
    motivos: {}, primeira_rejeitada: null, opcionais_invalidos: {},
    saldos_arredondados: 0, saldos_com_mais_de_2_casas: 0,
    titulos_com_saldo_negativo: { linhas: 0, saldo: 0n }, titulos_de_contraparte_confirmada: 0,
    saldo_titulos: 0n,
    campos_ausentes: Object.entries(CAMPOS).filter(([c]) => !(c in mapa)).map(([campo, d]) => ({ campo, efeito: d.efeito })),
  };
  const reais = new Set(contrapartesReais.map(textoNormalizado));
  const candidatas = new Map();
  const MAX_CANDIDATAS = 200;
  let candidatasTruncadas = false;
  // O sinal da linha veio SÓ do nome? A MB1 marca rotulo_de_total olhando as duas primeiras
  // células preenchidas; se alguma delas, que não seja a contraparte, fala em total, o total é da
  // linha, não do nome.
  const sinalSoDoNome = (l, contraparte) => {
    const iCp = mapa.contraparte;
    const primeiras = l.celulas.map((c, i) => [i, String(c ?? '').trim()]).filter(([, c]) => c !== '').slice(0, 2);
    return !primeiras.some(([i, c]) => i !== iCp && RE_TOTAL.test(c)) && RE_TOTAL.test(contraparte);
  };
  const subtotais = new Set();
  let maiorSubtotal = null;
  const cel = (l, campo) => (campo in mapa ? l.celulas[mapa[campo]] : undefined);
  const tip = (l, campo) => (campo in mapa ? l.tipos?.[mapa[campo]] : undefined);
  const valor = (l, campo) => valorEmCentavos(cel(l, campo), tip(l, campo), formato.decimal);
  const data = (l, campo) => dataIso(cel(l, campo), formato.datas);
  const abs = (x) => (x < 0n ? -x : x);

  function rejeitar(l, motivo, saldo) {
    r.rejeitada++;
    const chave = motivo.replace(/: '.*'$/, '');
    const m = (r.motivos[chave] ??= { linhas: 0, saldo: 0n });
    m.linhas++;
    if (saldo) m.saldo += saldo.centavos;
    if (!r.primeira_rejeitada) r.primeira_rejeitada = { n: l.n, motivo };
    return { classe: 'rejeitada', motivo };
  }

  return {
    linha(l) {
      r.linhas++;
      if (l.destino === 'cabecalho') { conferirCabecalho(l.celulas); r.cabecalhos_conferidos++; }
      if (l.destino !== 'corpo') { r.fora_do_corpo++; return { classe: 'fora_do_corpo' }; }
      const saldo = valor(l, 'saldo');
      const vencTexto = cel(l, 'vencimento');
      const venc = data(l, 'vencimento');
      const contraparte = String(cel(l, 'contraparte') ?? '').trim();
      const temSinal = (l.sinais ?? []).includes('rotulo_de_total') || RE_TOTAL.test(contraparte);
      if (saldo && !venc && (temSinal || contraparte === '')) {
        r.subtotal++;
        if (subtotais.size < MAX_SUBTOTAIS_GUARDADOS) subtotais.add(saldo.centavos);
        if (!maiorSubtotal || abs(saldo.centavos) > abs(maiorSubtotal.saldo)) maiorSubtotal = { n: l.n, saldo: saldo.centavos };
        return { classe: 'subtotal', saldo: saldo.centavos };
      }
      if (!saldo) return rejeitar(l, `saldo não é número: '${cel(l, 'saldo') ?? ''}'`);
      if (!venc) return rejeitar(l, `vencimento não é data: '${vencTexto ?? ''}'`, saldo);
      if (contraparte === '') return rejeitar(l, 'contraparte vazia', saldo);
      // A confirmação do analista só vale quando é o NOME que parece total ("TOTAL DISTRIBUIDORA
      // LTDA"). Se quem acusou foi outra célula da linha ("Total;ACME LTDA;02/01/2025;30,00"), a
      // linha é um total e ACME é cliente comum: oferecê-la para confirmar e aceitar a confirmação
      // somava o total de ACME como título (revisão de 12/11/2026: ACME em dobro, em todo arquivo
      // seguinte do mandato). Nome que é SÓ o rótulo ("Total", "Total geral") nunca é candidato.
      const nomeDeTotal = RE_TOTAL.test(contraparte) && !RE_SO_ROTULO.test(contraparte);
      const soDoNome = nomeDeTotal && sinalSoDoNome(l, contraparte);
      const confirmada = temSinal && soDoNome && reais.has(textoNormalizado(contraparte));
      if (temSinal && !confirmada) {
        const k = textoNormalizado(contraparte);
        if (soDoNome) {
          if (candidatas.has(k) || candidatas.size < MAX_CANDIDATAS) {
            const x = candidatas.get(k) ?? { contraparte: k, linhas: 0, saldo: 0n };
            x.linhas++; x.saldo += saldo.centavos;
            candidatas.set(k, x);
          } else candidatasTruncadas = true;
        }
        return rejeitar(l, `rótulo de total com vencimento (total por data, ou contraparte chamada Total?): '${contraparte}'`, saldo);
      }
      if (confirmada) r.titulos_de_contraparte_confirmada++;
      const titulo = { n: l.n, contraparte, vencimento: venc, saldo: saldo.centavos };
      if (saldo.arredondado) r.saldos_arredondados++;
      if (saldo.casas_extras) r.saldos_com_mais_de_2_casas++;
      if (saldo.centavos < 0n) { r.titulos_com_saldo_negativo.linhas++; r.titulos_com_saldo_negativo.saldo += saldo.centavos; }
      for (const campo of ['documento_contraparte', 'titulo', 'parcela', 'situacao']) {
        if (campo in mapa) titulo[campo] = String(cel(l, campo) ?? '').trim();
      }
      const invalido = (campo) => { r.opcionais_invalidos[campo] = (r.opcionais_invalidos[campo] ?? 0) + 1; };
      for (const campo of ['emissao', 'data_pagamento']) {
        if (!(campo in mapa) || String(cel(l, campo) ?? '').trim() === '') continue;
        const d = data(l, campo);
        if (d) titulo[campo] = d; else invalido(campo);
      }
      for (const campo of ['valor_original', 'valor_pago']) {
        if (!(campo in mapa) || String(cel(l, campo) ?? '').trim() === '') continue;
        const x = valor(l, campo);
        if (x) titulo[campo] = x.centavos; else invalido(campo);
      }
      r.titulo++;
      r.saldo_titulos += titulo.saldo;
      return { classe: 'titulo', titulo };
    },
    /**
     * O resumo, com a conferência positiva contra os totais do próprio arquivo: `confere` se
     * ALGUM subtotal é igual à soma dos títulos (o total geral pode estar no topo, no fim, ou
     * ser seguido do subtotal do último cliente); senão `diverge`, mostrando o maior subtotal.
     */
    resumo() {
      const conferencia = subtotais.size === 0
        ? { estado: 'sem_total_no_arquivo', efeito: 'o arquivo não traz linha de total: a soma lida não tem com o que ser conferida dentro do próprio arquivo' }
        : subtotais.has(r.saldo_titulos)
          ? { estado: 'confere', soma_lida: r.saldo_titulos.toString() }
          : { estado: 'diverge', maior_total_do_arquivo: maiorSubtotal.saldo.toString(), soma_lida: r.saldo_titulos.toString(),
            linha_do_maior_total: maiorSubtotal.n };
      const motivos = Object.fromEntries(Object.entries(r.motivos).map(([k, m]) => [k, { linhas: m.linhas, saldo: m.saldo.toString() }]));
      return {
        ...r, motivos, saldo_titulos: r.saldo_titulos.toString(),
        candidatas_a_contraparte_real: [...candidatas.values()].map((c) => ({ ...c, saldo: c.saldo.toString() })),
        candidatas_truncadas: candidatasTruncadas,
        titulos_com_saldo_negativo: { linhas: r.titulos_com_saldo_negativo.linhas, saldo: r.titulos_com_saldo_negativo.saldo.toString(),
          efeito: 'saldo negativo (adiantamento ou crédito) entra na soma e a REDUZ: a soma é a carteira menos os créditos' },
        conferencia_com_o_total_do_arquivo: conferencia,
      };
    },
  };
}
