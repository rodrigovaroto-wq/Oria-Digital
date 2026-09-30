// Confere se o NÚMERO que a IA extraiu é aritmeticamente consistente consigo
// mesmo — hoje o pipeline garante que o TEXTO chegou (cobertura.mjs: linha
// perdida, bloco perdido, truncamento); não garante que o número está certo.
//
// ACHADO EM PRODUÇÃO (12/09/2026, documentos reais do dono):
//   • `01_Relatorio_de_Faturamento_OMNIBEAUTY_2025`: colunas
//     "Saídas | Serviços | Outros | Total" — a identidade Saídas+Serviços+
//     Outros=Total FALHA em 6 dos 12 meses. Janeiro: Saídas 2.371.829,89,
//     Total 2.311.829,89 — diferem em 60 mil. E o rodapé "Totais
//     51.271.444,92" não fecha com NENHUMA leitura plausível dos 12 meses (a
//     mais próxima erra em R$ 660,00).
//   • Balanços fecham quando o texto está limpo: ATIVO=PASSIVO=64.126.203,52
//     (AMOBELEZA) e CIRCULANTE 10.035.063,87 + NÃO-CIRCULANTE 2.295.330,92 =
//     ATIVO 12.330.394,79 (GENERAL TABACO).
//
// ONDE ISTO NÃO DUPLICA O QUE JÁ EXISTE. `ATIVO = PASSIVO + PL` e `subtotal =
// soma dos filhos diretos` (secao como ponteiro do pai, ver campo_extraido.
// secao) já têm checagem própria e mais sofisticada no Postgres —
// `fn_reconciliar_ativo_passivo_pl` (Supabase/migrations/0009→0034) e
// `fn_reconciliar_arvore` (0133/0151), as duas rodando por documento no nó
// `Reconciliar (Classe A)`, já wired no grafo. Reimplementá-las aqui, com um
// dicionário de rótulos mais pobre que o de lá (`fn_valor_conceito` trata
// sinônimo, termo excludente, desempate por confiança — nada disso existe
// neste arquivo), arriscaria DIVERGIR da checagem que já é a autoridade — a
// mesma doença que este repositório já pagou duas vezes com cópia à mão
// (prompt de extração, lista de apelidos da taxonomia).
//
// O que NÃO tinha checagem nenhuma, em lugar nenhum, é a identidade (c):
// "total declarado = soma das parcelas" DENTRO do próprio documento, em duas
// formas — a de LINHA (colunas de categoria somando para uma coluna "Total"
// na MESMA linha) e a de SÉRIE (uma linha "Totais" somando as outras linhas
// da mesma coluna). Nenhuma reconciliação existente cobre isto: o mais perto
// é `fn_reconciliar_receita_dre_vs_faturamento` (Classe B, 0015), que compara
// a Receita da DRE com a soma do faturamento — ENTRE DOIS DOCUMENTOS, não
// dentro do próprio relatório de faturamento. É essa lacuna que este arquivo
// fecha, e só ela — sem tocar SQL nenhum (migration é fatia de outro agente).
//
// AS DUAS FUNÇÕES SÃO AUTO-CONTIDAS (nó Code do n8n não importa arquivo, e
// `toString()` não leva escopo de módulo): cada uma declara seu próprio
// normalizador de rótulo por dentro, para poder ser embutida sozinha sem
// `ReferenceError`.
//
// AUSÊNCIA NÃO É ZERO (regra 1 do CLAUDE.md), em toda parte deste arquivo: uma
// parcela ausente (valor_num null) ABORTA a conferência daquele grupo — nunca
// vira zero na soma. "Não dá para conferir" e "não confere" são vereditos
// diferentes, e só o segundo vira pendência.
//
// TOLERÂNCIA: a mesma fórmula da 0133 (`greatest(1, ceil(0.5*(n+1)))`, n =
// número de parcelas), na unidade em que o documento já está — não é um
// número novo inventado aqui, é o precedente já medido nesta casa: "0,5% de
// um total grande deixaria passar a conta inteira que a checagem existe para
// pegar" (comentário da 0133). Medido neste arquivo (aritmetica.test.mjs):
// com esta fórmula, a divergência de R$ 60.000,00 da OMNIBEAUTY estoura a
// tolerância por ~30.000×, e uma diferença de 1 centavo de arredondamento
// fica dentro dela.

/**
 * Identidade (c), forma de LINHA: numa mesma linha do documento (mesma conta,
 * várias COLUNAS — ex.: "Saídas | Serviços | Outros | Total" do relatório de
 * faturamento), a soma das colunas que NÃO são a coluna "Total" tem de bater
 * com a coluna "Total" daquela linha.
 *
 * Entrada: `campos` já JUNTADOS (saída de `juntarBlocos`) — usa o campo
 * `ordem`, que `juntarBlocos` já garante ser o MESMO para todo par
 * (conta×coluna) que veio da mesma linha original do documento, mesmo depois
 * de juntar blocos de chamadas diferentes.
 *
 * Devolve uma lista de strings (uma por linha que NÃO fecha) — vazia quando
 * tudo confere ou quando não há o que conferir (regra 1: célula ausente não
 * vira zero, e sai da conta em vez de fabricar divergência).
 */
export function conferirIdentidadeDeLinha(campos) {
  const problemas = [];
  if (!Array.isArray(campos)) return problemas;
  const normRotulo = (s) => String(s ?? '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/\s+/g, ' ');
  // Bem ESTREITA de propósito: só "total"/"totais", opcionalmente com "geral"
  // ou "do período/exercício/ano/mês". "Total do Ativo" NÃO casa (sobra
  // "ativo") — esse rótulo é conceito específico e já tem dono no Postgres
  // (fn_reconciliar_ativo_passivo_pl via fn_valor_conceito); casar aqui
  // também seria abrir DUAS pendências para o mesmo defeito.
  const ehTotal = (s) => /^(total|totais)(\s+(geral|gerais|do\s+(periodo|exercicio|ano|mes)))?$/.test(normRotulo(s));

  const grupos = new Map();
  for (const c of campos) {
    if (!c || typeof c !== 'object' || !Number.isFinite(Number(c.ordem))) continue;
    const chave = Number(c.ordem);
    if (!grupos.has(chave)) grupos.set(chave, []);
    grupos.get(chave).push(c);
  }

  for (const linha of grupos.values()) {
    if (linha.length < 2) continue; // uma coluna só: não há "parte" para somar
    const rotuladasTotal = linha.filter((c) => ehTotal(c.periodo_coluna) || ehTotal(c.entidade_coluna));
    // Zero ou mais de uma coluna "Total": ambíguo, não dá para conferir.
    if (rotuladasTotal.length !== 1) continue;
    const total = rotuladasTotal[0];
    const partes = linha.filter((c) => c !== total);
    if (partes.length === 0) continue;
    if (typeof total.valor_num !== 'number') continue; // total ausente: nada a conferir
    if (partes.some((p) => typeof p.valor_num !== 'number')) continue; // parcela ausente: idem
    // Unidade/moeda mista não se soma (mesma guarda da 0133): pré-condição não
    // satisfeita, não se descarta a parcela em silêncio para forçar uma conta.
    const unidades = new Set([total.unidade ?? null, ...partes.map((p) => p.unidade ?? null)]);
    const moedas = new Set([total.moeda ?? null, ...partes.map((p) => p.moeda ?? null)]);
    if (unidades.size > 1 || moedas.size > 1) continue;

    const soma = partes.reduce((acc, p) => acc + p.valor_num, 0);
    const tolerancia = Math.max(1, Math.ceil(0.5 * (partes.length + 1)));
    const diff = Math.abs(soma - total.valor_num);
    if (diff <= tolerancia) continue;

    const rotuloLinha = linha[0]?.chave ?? '(sem rótulo)';
    const nomeColTotal = total.periodo_coluna ?? total.entidade_coluna ?? 'Total';
    const parcelasTexto = partes
      .map((p) => `${p.periodo_coluna ?? p.entidade_coluna ?? '?'}=${p.valor_num}`)
      .join(' + ');
    problemas.push(
      `identidade de linha não fecha em "${rotuloLinha}": ${parcelasTexto} = ${soma}, mas a coluna `
      + `"${nomeColTotal}" declara ${total.valor_num} — diferença de ${diff.toFixed(2)} (tolerância de `
      + `arredondamento: ${tolerancia}). Um dos dois valores está errado, e o book vai sair com essa `
      + 'diferença nesta linha.',
    );
  }
  return problemas;
}

/**
 * Identidade (c), forma de SÉRIE: uma linha "Totais"/"Total geral" declara,
 * numa coluna, o total da SÉRIE — e esse total tem de bater com a soma das
 * outras linhas naquela MESMA coluna (ex.: o "Totais" do rodapé do
 * faturamento contra os 12 meses; o total de uma coluna do mapa de dívida
 * contra suas linhas).
 *
 * Agrupa por COLUNA (periodo_coluna + entidade_coluna), não por `ordem`: a
 * série é entre LINHAS diferentes que compartilham a mesma coluna, o oposto
 * da checagem de linha acima.
 *
 * Devolve lista de strings; vazia quando fecha ou quando falta dado para
 * concluir (uma parcela da série ausente NÃO vira zero — a checagem se cala
 * em vez de acusar uma divergência que pode ser só extração incompleta;
 * `linhasComNumero`/`avaliarCobertura`, em cobertura.mjs, já é quem mede
 * extração incompleta).
 */
export function conferirTotalDaSerie(campos) {
  const problemas = [];
  if (!Array.isArray(campos)) return problemas;
  const normRotulo = (s) => String(s ?? '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/\s+/g, ' ');
  const ehTotal = (s) => /^(total|totais)(\s+(geral|gerais|do\s+(periodo|exercicio|ano|mes)))?$/.test(normRotulo(s));

  const porColuna = new Map();
  for (const c of campos) {
    if (!c || typeof c !== 'object') continue;
    const colKey = `${c.periodo_coluna ?? ''}\u0000${c.entidade_coluna ?? ''}`;
    if (!porColuna.has(colKey)) porColuna.set(colKey, []);
    porColuna.get(colKey).push(c);
  }

  for (const [colKey, linhas] of porColuna) {
    const totais = linhas.filter((c) => ehTotal(c.chave));
    // Zero ou mais de uma linha "Totais" na mesma coluna: ambíguo.
    if (totais.length !== 1) continue;
    const total = totais[0];
    if (typeof total.valor_num !== 'number') continue;
    const [pcCol, ecCol] = colKey.split('\u0000');
    // COLUNA NÃO ADITIVA NÃO É SÉRIE. "Variação %" do faturamento tem uma
    // variação por mês e a do ano na linha de total: somar doze variações nunca
    // dá a anual, e a checagem acusava diferença de 293,6 num documento certo
    // (medido em 30/09/2026, mandato de teste em produção, caso bb37f726).
    // PALAVRA INTEIRA, não substring: "Intermediação" contém "media" e "Receita
    // variável" contém "varia", e são colunas de R$ que têm série. "Taxas" (plural)
    // fica de fora de propósito: "Taxas de serviço" é R$; "Taxa" e "Taxa anual" não.
    if (/%|\b(variacao|variacoes|var|margem|margens|media|medias|medio|ticket|indice|taxa)\b/.test(normRotulo(pcCol || ecCol))) continue;
    // A SÉRIE É O QUE VEM ANTES DO TOTAL, na ordem do documento. As linhas
    // DEPOIS dele são memória ("Média mensal", "Ticket médio por pedido"), não
    // parcela. Somá-las acusou "soma das 14 linhas 198.808,2 contra 183.480"
    // quando os 12 meses fecham EXATOS em 183.480: 183.480 + 15.290 + 38,2 é o
    // número da pendência falsa (mesmo caso bb37f726). Sem `ordem` em alguma
    // linha, fica a regra antiga, porque não há como saber o que veio antes.
    // MAS o modelo às vezes devolve o total ANTES dos meses (doc 63a36efe,
    // FATURAMENTO OMNIBEAUTY PR 202606.pdf: "Totais" na ordem 0, 12 meses
    // depois). Com menos de duas parcelas antes do total, a série é o que vem
    // DEPOIS — senão a checagem se pula em silêncio (6 grupos no campo_extraido
    // de produção, 4 colunas do AMO e 2 do Teste v40). Linha de memória pelo
    // rótulo (média, ticket, índice) nunca é parcela, esteja onde estiver.
    const ehMemoria = (c) => /\b(media|medias|medio|ticket|indice)\b/.test(normRotulo(c.chave));
    const temOrdem = linhas.every((c) => Number.isFinite(c.ordem));
    const candidatas = linhas.filter((c) => c !== total && !ehTotal(c.chave) && !ehMemoria(c));
    const antes = temOrdem ? candidatas.filter((c) => c.ordem < total.ordem) : candidatas;
    const partes = antes.length >= 2 || !temOrdem
      ? antes
      : candidatas.filter((c) => c.ordem > total.ordem);
    // Precisa de pelo menos DUAS parcelas para ser série (uma parcela só não
    // é série, é a mesma conta repetida) — abaixo disso não dá para concluir.
    if (partes.length < 2) continue;
    if (partes.some((p) => typeof p.valor_num !== 'number')) continue;
    const unidades = new Set([total.unidade ?? null, ...partes.map((p) => p.unidade ?? null)]);
    const moedas = new Set([total.moeda ?? null, ...partes.map((p) => p.moeda ?? null)]);
    if (unidades.size > 1 || moedas.size > 1) continue;

    const soma = partes.reduce((acc, p) => acc + p.valor_num, 0);
    const tolerancia = Math.max(1, Math.ceil(0.5 * (partes.length + 1)));
    const diff = Math.abs(soma - total.valor_num);
    if (diff <= tolerancia) continue;

    const rotuloCol = pcCol || ecCol || '(coluna única)';
    problemas.push(
      `total da série não fecha em "${total.chave}" (coluna "${rotuloCol}"): total declarado `
      + `${total.valor_num}, soma das ${partes.length} linha(s) da série ${soma} — diferença de `
      + `${diff.toFixed(2)} (tolerância de arredondamento: ${tolerancia}). Um dos dois números está `
      + 'errado, ou a extração perdeu uma linha da série — nos dois casos o book sai com essa '
      + 'diferença.',
    );
  }
  return problemas;
}

/**
 * Papel de uma coluna de balancete pelo rótulo normalizado (sem acento, minúsculo):
 * 'SA' (saldo anterior/inicial), 'D', 'C', 'SAt' (saldo atual/final) ou null.
 * AUTO-CONTIDA; helper de `conferirBalanceteLinhaALinha`, embutida junto com ela
 * (FONTE_ARITMETICA) — extraída do corpo dela pelo Sonar S3776 (complexidade 31).
 */
export function papelDeColunaDeBalancete(pc) {
  const r = String(pc ?? '')
    .normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLowerCase().trim().replace(/\s+/g, ' ');
  if (/^saldo (anterior|inicial)\b/.test(r)) return 'SA';
  if (/^debitos?\b/.test(r)) return 'D';
  if (/^creditos?\b/.test(r)) return 'C';
  if (/^saldo (atual|final)\b/.test(r)) return 'SAt';
  return null;
}

/**
 * Agrupa os campos em contas ({chave, pagina, SA, D, C, SAt}) e devolve também o
 * conjunto de papéis vistos. A mesma chave repetida na mesma seção e página (o
 * balancete real repete CHEQUES A COMPENSAR, duas vezes idêntica) é OUTRA conta,
 * não a mesma com a coluna em dobro: abre-se um novo grupo quando o papel já está
 * preenchido. AUTO-CONTIDA, embutida por toString().
 */
export function agruparContasDeBalancete(campos) {
  const contas = [];
  const abertas = new Map();
  const papeis = new Set();
  for (const c of campos) {
    const p = c && typeof c === 'object' ? papelDeColunaDeBalancete(c.periodo_coluna) : null;
    if (!p) continue;
    papeis.add(p);
    const k = [c.chave, c.secao ?? '', c.origem_pagina ?? '', c.entidade_coluna ?? ''].join('\u0000');
    let conta = abertas.get(k);
    if (!conta || p in conta) {
      conta = { chave: c.chave, pagina: c.origem_pagina ?? null };
      abertas.set(k, conta);
      contas.push(conta);
    }
    conta[p] = Number.isFinite(c.valor_num) ? c.valor_num : null;
  }
  return { contas, papeis };
}

/**
 * Para cada conta com as quatro colunas e movimento, diz se fecha como rotulada
 * (SAt = SA + D - C, ou SA - D + C), só com a troca de colunas (D gravado = SA
 * +/- C gravado +/- SAt gravado) ou de nenhum jeito; guarda o 1º exemplo de cada
 * um dos dois últimos. Tolerância 1 na unidade do documento. Conta de movimento
 * zero (D e C dentro da tolerância) fecha de qualquer jeito e não conta.
 * AUTO-CONTIDA, embutida por toString().
 */
export function classificarContasDeBalancete(contas) {
  const TOL = 1;
  const perto = (a, b) => Math.abs(a - b) <= TOL;
  const r = { rotulada: 0, trocada: 0, nenhuma: 0, exTroca: null, exNenhuma: null };
  for (const v of contas) {
    const completa = ['SA', 'D', 'C', 'SAt'].every((p) => typeof v[p] === 'number');
    if (!completa || (Math.abs(v.D) <= TOL && Math.abs(v.C) <= TOL)) continue;
    if (perto(v.SAt, v.SA + v.D - v.C) || perto(v.SAt, v.SA - v.D + v.C)) {
      r.rotulada += 1;
    } else if ([1, -1].some((s1) => [1, -1].some((s2) => perto(v.D, v.SA + s1 * v.C + s2 * v.SAt)))) {
      r.trocada += 1;
      r.exTroca = r.exTroca ?? v;
    } else {
      r.nenhuma += 1;
      r.exNenhuma = r.exNenhuma ?? v;
    }
  }
  return r;
}

/** O texto do problema único do balancete (contagens + exemplo). AUTO-CONTIDA. */
export function mensagemDoBalancete(naoTriviais, r) {
  const ex = r.exTroca ?? r.exNenhuma;
  const pagina = ex.pagina ? ' (p. ' + ex.pagina + ')' : '';
  const exemplo = '"' + ex.chave + '"' + pagina + ': saldo anterior ' + ex.SA + ', débito ' + ex.D
    + ', crédito ' + ex.C + ', saldo atual ' + ex.SAt;
  return 'balancete não fecha linha a linha (saldo atual = saldo anterior +/- débito -/+ crédito, tolerância 1): '
    + `das ${naoTriviais} conta(s) com movimento, ${r.rotulada} fecham como rotuladas, ${r.trocada} fecham só com a `
    + 'troca de colunas (a gravada como "Débito" é o saldo atual, a "Crédito" é o débito e a "Saldo atual" é o '
    + `crédito) e ${r.nenhuma} não fecham de jeito nenhum. Exemplo${r.exTroca ? ' com a troca' : ''}: ${exemplo}. `
    + 'O número NÃO foi corrigido: com as colunas trocadas, ler "Saldo atual" como saldo dá o crédito do período.';
}

/**
 * Identidade de BALANCETE, linha a linha: para cada conta com as quatro colunas
 * "Saldo anterior | Débito | Crédito | Saldo atual" (rótulos normalizados;
 * "Saldo inicial/final", "Débitos", "Créditos" valem), o saldo atual tem de ser
 * o anterior mais o movimento, na natureza da conta:
 *   devedora: SAt = SA + D - C        credora: SAt = SA - D + C
 *
 * POR QUÊ EXISTE. No balancete_janaago26.pdf do mandato real Krauspenhar (320
 * contas, 288 com as quatro colunas; medido em produção, 30/09/2026) só 111
 * contas fecham como rotuladas, e 90 delas são triviais (movimento zero). 196
 * fecham se a coluna gravada como "Débito" for o saldo atual real, a "Crédito"
 * o débito real e a "Saldo atual" o crédito real (com sinal): ESTOQUES grava
 * 43.569.482,33 | 47.956.795,90 | 65.971.485,41 | -61.584.171,84, e o saldo real
 * é 47,96 mi (43,57 + 65,97 - 61,58). A troca muda POR PÁGINA. Nenhuma pendência
 * nomeava isto, e uma análise leu o crédito do período como saldo ("estoque
 * subiu para 61,6 mi"; o real é 47,96). NÃO corrige o número: o dado do cliente
 * não é reescrito por palpite — só NOMEIA a troca.
 *
 * FORMA DE FECHAR. Como rotulada: acima, nas duas naturezas. Com a troca:
 * D_gravado = SA +/- C_gravado +/- SAt_gravado (os dois sinais livres, porque
 * o saldo real vem com sinal e a natureza muda de conta para conta). Tolerância
 * de 1 na unidade do documento, a do precedente desta casa para identidade de 3
 * parcelas sem ser 0,5% do total (ver TOLERÂNCIA no topo do arquivo).
 *
 * LIMIAR: UM problema por documento quando mais de 20% das contas NÃO triviais
 * (D ou C diferente de zero) não fecham como rotuladas, com no mínimo 10 contas
 * não triviais. 20% porque um balancete certo só perde conta por extração
 * isolada (o exemplo Adiantamentos, que não fecha de jeito nenhum, é 1 de 198)
 * e a troca por página do documento medido deixou ~89% sem fechar; entre 1% e
 * 20% é ruído de extração que o dono vê conta a conta, acima disso a coluna está
 * sistematicamente errada. O mínimo de 10 evita acusar documento de 3 contas.
 *
 * UMA CONTA = (chave, seção, página, entidade); se a mesma coluna aparece de
 * novo para essa chave, é outra conta (o balancete real repete uma conta
 * idêntica), contada à parte. Coluna com valor ausente (null) tira a conta:
 * ausência não é zero.
 * AUTO-CONTIDA, embutida por toString() no nó Code (ver FONTE_ARITMETICA) JUNTO com os 4
 * helpers acima: toString() não leva o escopo do módulo (bc439fa, PR #246).
 */
export function conferirBalanceteLinhaALinha(campos) {
  const problemas = [];
  if (!Array.isArray(campos)) return problemas;
  const { contas, papeis } = agruparContasDeBalancete(campos);
  if (papeis.size < 4) return problemas;
  const r = classificarContasDeBalancete(contas);
  const naoTriviais = r.rotulada + r.trocada + r.nenhuma;
  if (naoTriviais < 10 || (r.trocada + r.nenhuma) / naoTriviais <= 0.2) return problemas;
  problemas.push(mensagemDoBalancete(naoTriviais, r));
  return problemas;
}
