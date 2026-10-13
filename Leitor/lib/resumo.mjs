// O RESUMO de um arquivo oficial: o que vai para o banco no lugar do arquivo.
//
// A DECISÃO (dono, 13/10/2026, sessão 108): o arquivo é lido no navegador do analista
// e só o resumo sai da máquina. Guardar a linha bruta custaria ~2 GB de banco por ECD
// de 10M de linhas (medido: 1,95 GB de tabela), e nenhuma reconciliação da Espec. 12
// usa o lançamento individual:
//   S1 (DRE enviada × ECD × ECF) usa J150 e L300; S2 (balancete conta a conta) usa
//   I155 com I050; S6 (LALUR) usa M300. O lançamento (I200/I250) é ~75% das linhas.
// Medido numa ECD sintética de 10.000.180 linhas: o resumo tem 3,4 MB (745 KB
// comprimido), com os 7.480.476 I250 somados em 18.000 grupos.
//
// O QUE SE PERDE, e é dito no próprio resumo: o lançamento individual (contrapartida,
// histórico, participante). Uma análise que precise dele exige reenviar o arquivo; o
// hash prova que é o mesmo.
//
// [A CONFIRMAR] As listas de registros abaixo foram escritas pelo Guia Prático de
// memória, como as posições de `leiautes.mjs`. O aceite da onda 1 (3 ECDs reais) é a
// prova. Registro fora da lista que uma reconciliação venha a precisar exige
// reenviar os arquivos já recebidos, e por isso a lista é generosa nos blocos pequenos.

import { centavosBR, dataDDMMAAAA } from './campos.mjs';

export const RESUMO_VERSAO = 'resumo/1';

// Registros guardados NA ÍNTEGRA, com o número da linha (proveniência). São os
// blocos pequenos: plano de contas, saldos, demonstrações, termos.
const INTEGRA = {
  ECD: new Set(['0000', '0007', 'I010', 'I030', 'I050', 'I051', 'I052', 'I150', 'I155', 'I157', 'I350', 'I355',
    'J005', 'J100', 'J150', 'J210', 'J215', 'J900', 'J930']),
  // A ECF inteira costuma ter dezenas de milhares de linhas: os blocos de
  // demonstração e cálculo vão todos.
  ECF: new Set(['0000', '0010', '0020', '0030']),
  ECF_BLOCOS: ['L', 'M', 'N', 'P', 'T', 'U', 'X', 'Y'],
};

const MAX_ACHADOS = 50;

/** O código do registro, extraído do MESMO jeito que o `leitorSped` (`split('|')[1]`, e
 * linha só de espaço ignorada): com outro jeito, uma linha que o envelope conta
 * (indentada, ou o 0000 depois de um BOM UTF-8, medidos pela revisão) sumiria só do
 * resumo. É essa igualdade que deixa `resultado()` conferir uma contagem com a outra. */
function registroDe(texto) {
  return texto.trim() === '' ? null : String(texto.split('|', 3)[1]);
}

/** Cópia que não segura a fatia de origem. `c[2]` e a própria linha são, no V8, recortes
 * (SlicedString) do texto da fatia de ~64 KB em que apareceram: guardar o recorte mantém a
 * fatia inteira viva. Medido pela revisão (Node 22, ECD de ~317 MB, contas de 17
 * caracteres): 38,1 MB retidos no fim, contra 10,1 MB com a cópia. O teto sem ela é
 * min(grupos, fatias) × 64 KB, ou seja, o arquivo inteiro num plano de contas esparso. */
const copia = (s) => JSON.parse(JSON.stringify(s));

/** Resumo da ECD: íntegra dos registros pequenos e o I250 somado por conta, mês e indicador do lançamento. */
function resumidorEcd() {
  const registros = [];
  const grupos = new Map();
  let mes = null, ind = null, lctoLinha = null, lctoValor = null, deb = 0, cred = 0, partidas = 0;
  let i250 = 0, semI200 = 0, fechado = false;
  const porRegistro = {};
  const invalidos = [], desbalanceados = [];
  let nInvalidos = 0, nDesbalanceados = 0;
  const invalido = (linha, registro, campo, valor) => {
    nInvalidos++;
    if (invalidos.length < MAX_ACHADOS) invalidos.push({ linha, registro, campo, valor });
  };
  // Partida dobrada: num lançamento, a soma dos débitos = a soma dos créditos = VL_LCTO.
  // Sai de graça (o leitor já passa por cada partida) e é a única conferência do
  // lançamento individual que sobra depois que ele é descartado.
  const fecharLancamento = () => {
    if (lctoLinha === null) return;
    if (deb !== cred || (lctoValor !== null && deb !== lctoValor)) {
      nDesbalanceados++;
      if (desbalanceados.length < MAX_ACHADOS) desbalanceados.push({ linha: lctoLinha, vl_lcto: lctoValor, debitos: deb, creditos: cred, partidas });
    }
    lctoLinha = null;
  };
  return {
    linha(n, texto) {
      // Depois do 9999 só vem a assinatura digital; um segundo |0000| ali é outro SPED
      // concatenado, que o envelope recusa. Somado aqui, as contas sairiam em dobro.
      if (fechado) return;
      const reg = registroDe(texto);
      if (reg === null) return;
      porRegistro[reg] = (porRegistro[reg] || 0) + 1;
      if (reg === '9999') { fechado = true; return; }
      if (reg === 'I200') {
        fecharLancamento();
        const c = texto.split('|');
        // |I200|NUM_LCTO|DT_LCTO|VL_LCTO|IND_LCTO|DT_LCTO_EXT|
        const data = dataDDMMAAAA(c[3]);
        if (!data) invalido(n, 'I200', 'DT_LCTO', c[3]);
        mes = data ? data.slice(0, 7) : null;
        // N normal, E encerramento, X extemporâneo. O encerramento zera as contas de
        // resultado no fim do exercício: somado junto com o normal, a DRE do mês 12 some.
        ind = (c[5] || '').trim() || null;
        lctoValor = centavosBR(c[4]);
        if (lctoValor === null) invalido(n, 'I200', 'VL_LCTO', c[4]);
        lctoLinha = n; deb = 0; cred = 0; partidas = 0;
        return;
      }
      if (reg === 'I250') {
        i250++;
        const c = texto.split('|');
        // |I250|COD_CTA|COD_CCUS|VL_DC|IND_DC|NUM_ARQ|COD_HIST_PAD|HIST|COD_PART|
        const v = centavosBR(c[4]);
        const dc = c[5];
        if (v === null) invalido(n, 'I250', 'VL_DC', c[4]);
        if (dc !== 'D' && dc !== 'C') invalido(n, 'I250', 'IND_DC', dc);
        // Partida sem I200 antes (ou com data inválida) cai no grupo de mês null: ela
        // é somada e contada, nunca descartada, e o mês null é a marca do problema.
        if (lctoLinha === null) semI200++;
        const chave = `${c[2]}|${mes}|${ind}`;
        let g = grupos.get(chave);
        if (!g) grupos.set(chave, g = { conta: copia(c[2]), mes, ind_lcto: ind, debito: 0, credito: 0, partidas: 0, partidas_sem_valor: 0, primeira_linha: n });
        g.partidas++;
        // Partida sem valor legível não soma ZERO em silêncio (regra 1): o grupo diz
        // quantas ficaram de fora, e quem consome trata o grupo como incompleto.
        if (v === null || (dc !== 'D' && dc !== 'C')) g.partidas_sem_valor++;
        else if (dc === 'D') { g.debito += v; deb += v; }
        else { g.credito += v; cred += v; }
        partidas++;
        return;
      }
      if (INTEGRA.ECD.has(reg)) registros.push([n, copia(texto)]);
    },
    fim() {
      fecharLancamento();
      return {
        registros,
        lancamentos_por_conta_mes: [...grupos.values()],
        por_registro: porRegistro,
        conferencia: {
          i250_lidos: i250,
          i250_sem_i200: semI200,
          grupos_com_partida_sem_valor: [...grupos.values()].filter(g => g.partidas_sem_valor > 0).length,
          valores_invalidos: nInvalidos, valores_invalidos_amostra: invalidos,
          lancamentos_desbalanceados: nDesbalanceados, lancamentos_desbalanceados_amostra: desbalanceados,
        },
        descartado: 'o lançamento individual (I200/I250: contrapartida, histórico, participante e centro de custo) não é guardado; está somado por conta, mês e IND_LCTO, sem o centro de custo. Para vê-lo, reenviar o arquivo (o hash prova que é o mesmo).',
      };
    },
  };
}

function resumidorEcf() {
  const registros = [];
  const porRegistro = {};
  let fechado = false;
  return {
    linha(n, texto) {
      if (fechado) return;
      const reg = registroDe(texto);
      if (reg === null) return;
      porRegistro[reg] = (porRegistro[reg] || 0) + 1;
      if (reg === '9999') { fechado = true; return; }
      if (INTEGRA.ECF.has(reg) || INTEGRA.ECF_BLOCOS.includes(reg[0])) registros.push([n, copia(texto)]);
    },
    fim() {
      return {
        registros,
        por_registro: porRegistro,
        descartado: 'blocos 0 (exceto 0000-0030), C, E, J, K, Q, W e 9 da ECF não são guardados: os dados da ECD (C), saldos recuperados (E/K), plano referencial (J) e o país a país (W).',
      };
    },
  };
}

/**
 * O resumidor de uma família/subtipo: `{ linha(numero, texto), fim() }`, ou null se
 * ainda não há resumo para ela. Null NÃO é resumo vazio: o envelope continua lido e
 * contado, e `resumoAusente` diz por quê (regra 1).
 */
export function resumidorDe(familia, subtipo) {
  if (familia === 'sped' && subtipo === 'ECD') return resumidorEcd();
  if (familia === 'sped' && subtipo === 'ECF') return resumidorEcf();
  return null;
}

/** O motivo de não haver resumo, por família: em que onda da F2T o conteúdo passa a ser lido. */
export function resumoAusente(familia, subtipo) {
  if (familia === 'sped' && (subtipo === 'EFD_ICMS_IPI' || subtipo === 'EFD_CONTRIBUICOES')) return 'conteúdo da EFD é lido na onda 3 da F2T; hoje só o envelope (contagem, período, CNPJ) é registrado';
  if (familia === 'ofx' || (familia && familia.startsWith('cnab'))) return 'conteúdo de extrato e CNAB é lido na onda 2 da F2T; hoje só o envelope é registrado';
  if (familia === 'esocial') return 'conteúdo do eSocial é lido na onda 4 da F2T; hoje só o envelope é registrado';
  if (familia === 'reinf' || familia === 'nfe' || familia === 'nfse') return 'conteúdo é lido na onda 3 da F2T; hoje só o envelope é registrado';
  if (familia === 'cte' || familia === 'mdfe') return 'conteúdo é lido na onda 5 da F2T; hoje só o envelope é registrado';
  return 'família sem resumo definido; só o envelope é registrado';
}
