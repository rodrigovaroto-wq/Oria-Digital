import type { LinhaModelo } from "./modelo-institucional";

// A IDENTIDADE DE UMA LINHA DE MODELAGEM — e por que ela não é só o rótulo.
//
// O DEFEITO QUE ISTO CORRIGE (relatado pelo dono no teste da tela): ele escolhia
// a premissa de UMA linha, não mexia em nenhuma outra, salvava — e outra linha,
// que ele nunca tocou, aparecia preenchida com a mesma premissa.
//
// A causa não estava no salvamento, estava na LEITURA. No banco, a identidade da
// linha é o par (`secao_canonica`, `rotulo_norm`) — o índice único de
// `caso_linha_premissa` inclui a seção, e `fn_linhas_para_modelagem` agrupa por
// `group by o.secao_canonica, o.rotulo_norm`. O portal, nos dois lugares em que
// casava vínculo com linha, usava só o `rotulo_norm`:
//
//   const vinculoPorRotulo = new Map(vinculos.map((v) => [v.rotulo_norm, v]));
//
// e demonstração real repete rótulo entre seções o tempo todo. No caso do teste
// v35 são TREZE: `Empréstimos e Financiamentos` e `Arrendamentos` estão no
// passivo circulante E no não circulante; `Capital social`, `Reserva legal` e
// `Prejuízos acumulados` estão no patrimônio líquido E na DMPL; `Provisão para
// contingências` está no passivo não circulante E nas despesas operacionais.
//
// O efeito era em cadeia, e o primeiro passo é o que o dono viu:
//
//   1. a tela mostrava a premissa da linha do circulante na linha homônima do NÃO
//      circulante — "completou sozinho";
//   2. esse valor virava o `orig` daquela seção, então na próxima vez que ele
//      salvasse aquela seção por qualquer outro motivo, a linha ia ao banco DE
//      VERDADE com uma premissa que ninguém escolheu ali;
//   3. no export, `valorBase` e o rótulo exibido vinham do último homônimo do
//      mapa — podia ser o saldo da OUTRA seção, e a projeção partia dele.
//
// Nada disso dava erro. O arquivo saía com um número plausível e errado.
//
// A chave usa `\u0000` (byte zero) como separador porque é o único caractere que não pode
// aparecer num rótulo vindo do banco (texto Postgres não guarda byte zero) —
// separador visível como `|` ou `::` casaria dois pares diferentes se algum
// rótulo o contivesse.

/** Identidade de uma linha de modelagem: o par (seção canônica, rótulo normalizado). */
export function chaveDaLinha(
  secaoCanonica: string | null | undefined,
  rotuloNorm: string,
): string {
  return `${secaoCanonica ?? ""}\u0000${rotuloNorm}`;
}

/** O que `fn_linhas_para_modelagem` devolve, no que interessa ao casamento. */
export interface LinhaParaCasar {
  secao_canonica: string | null;
  rotulo_norm: string;
  chave: string;
  valor_ultimo: number | null;
}

/** O que `caso_linha_premissa` guarda. */
export interface VinculoParaCasar {
  secao_canonica: string | null;
  rotulo_norm: string;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

export interface LinhaDeConfig {
  rotulo: string;
  secaoCanonica: string | null;
  premissaCodigo: string | null;
  sazonalidadeCodigo: string | null;
  valorBase: number | null;
}

/**
 * Casa cada vínculo com a linha do caso, PELO PAR (seção, rótulo).
 *
 * Vínculo sem linha correspondente (o documento não chegou, ou foi reextraído com
 * outro rótulo) mantém o `rotulo_norm` como rótulo exibido e `valorBase` nulo —
 * é o mesmo comportamento de antes, e `fn_conferir_modelagem` já o denuncia como
 * `vinculos_orfaos`. Descartá-lo aqui esconderia a configuração órfã do arquivo.
 */
export function casarVinculosComLinhas(
  vinculos: VinculoParaCasar[],
  linhas: LinhaParaCasar[],
): LinhaDeConfig[] {
  const porChave = new Map(linhas.map((l) => [chaveDaLinha(l.secao_canonica, l.rotulo_norm), l]));
  return vinculos.map((v) => {
    const l = porChave.get(chaveDaLinha(v.secao_canonica, v.rotulo_norm));
    return {
      rotulo: l?.chave ?? v.rotulo_norm,
      secaoCanonica: v.secao_canonica,
      premissaCodigo: v.premissa_codigo,
      sazonalidadeCodigo: v.sazonalidade_codigo,
      valorBase: l?.valor_ultimo ?? null,
    };
  });
}

/**
 * O vínculo de cada linha, para a TELA — indexado pela mesma identidade.
 *
 * A tela pergunta por (seção, rótulo) e recebe o que está gravado para aquela
 * linha, e só para ela.
 */
export function vinculoPorLinha(
  vinculos: VinculoParaCasar[],
): Map<string, VinculoParaCasar> {
  return new Map(vinculos.map((v) => [chaveDaLinha(v.secao_canonica, v.rotulo_norm), v]));
}

/** Uma linha de `fn_valores_por_ano`: o valor de um ano para uma linha do caso. */
export interface ValorPorAno {
  rotulo_norm: string;
  secao_canonica: string | null;
  ano: number;
  valor: number | string;
  /**
   * A PROVENIÊNCIA DAQUELA CÉLULA (0125): de que arquivo, de que página, com que
   * confiança e com que aceite veio ESTE valor NESTE ano.
   *
   * Por ANO, e isto não é detalhe: a `fn_linhas_para_modelagem` também sabe dizer
   * de onde veio uma linha, mas a resposta dela é da ocorrência de maior módulo
   * ENTRE OS EXERCÍCIOS. Usada na nota de uma célula de 2023, ela descreveria com
   * toda a convicção a célula de 2025 — e rastreabilidade que aponta para o lugar
   * errado é pior que rastreabilidade nenhuma, porque convida a conferir e engana.
   *
   * Opcionais porque a extração pode não ter dito: PDF sem página identificada,
   * campo sem confiança. `null` é "não sei", e a nota escreve isso em vez de
   * inventar um número.
   */
  arquivo?: string | null;
  origem_pagina?: number | null;
  confianca?: number | string | null;
  status_aceite?: string | null;
  aceito_por?: string | null;
}

/** A proveniência de uma célula, como a nota do Excel a consome. */
export interface ProvenienciaCelula {
  arquivo: string | null;
  pagina: number | null;
  confianca: number | null;
  statusAceite: string | null;
  aceitoPor: string | null;
}

/**
 * A SÉRIE HISTÓRICA DE CADA LINHA, indexada pela MESMA identidade das outras
 * duas funções deste arquivo: o par (seção canônica, rótulo normalizado).
 *
 * POR QUE ELA VIVE AQUI, e não solta na rota do export: era o terceiro lugar do
 * portal que casava linha por rótulo, e foi o único que ficou de fora quando a
 * `chaveDaLinha` corrigiu os outros dois — justamente o que decide os NÚMEROS do
 * modelo. `fn_valores_por_ano` agrupa por (rotulo_norm, secao_canonica, ano) e
 * devolve a seção; indexando só pelo rótulo, a última seção lida sobrescrevia as
 * anteriores e todas as linhas homônimas recebiam a mesma série.
 *
 * MEDIDO no caso v35: treze rótulos aparecem em duas seções com valores
 * diferentes — `Empréstimos e Financiamentos` (37.379 no circulante × 44.474 no
 * não circulante), `Obrigações Tributárias` (13.549 × 7.895), `Financiamentos
 * FINAME/BNDES` (11.393 × 3.618), `Arrendamentos` (3.118 × 908), `Provisão para
 * contingências` (−1.900 na despesa × 2.567 no passivo), `Capital social`
 * (43.000 na DMPL × 45.000 no PL). Cada um entrava no modelo com o número da
 * OUTRA seção, e o arquivo saía plausível e falso.
 *
 * Só os anos de `anosHistoricos` entram: um balancete do ano corrente não é
 * exercício fechado, e tratá-lo como tal faria a projeção partir de meio ano.
 */
export function seriesPorLinha(
  valores: ValorPorAno[],
  anosHistoricos: number[],
): Map<string, Record<string, number>> {
  const anos = new Set(anosHistoricos);
  const series = new Map<string, Record<string, number>>();
  for (const v of valores) {
    if (!anos.has(v.ano)) continue;
    const k = chaveDaLinha(v.secao_canonica, v.rotulo_norm);
    let serie = series.get(k);
    if (!serie) { serie = {}; series.set(k, serie); }
    serie[String(v.ano)] = Number(v.valor);
  }
  return series;
}

/**
 * A série de UMA linha. Linha sem série devolve objeto vazio — é o que acontece
 * com a conta de outra empresa do grupo (a consulta de valores filtra pela
 * entidade modelada) e é o comportamento certo: zero explícito, não o número da
 * empresa ao lado.
 */
export function serieDaLinha(
  series: Map<string, Record<string, number>>,
  secaoCanonica: string | null,
  rotuloNorm: string,
): Record<string, number> {
  return series.get(chaveDaLinha(secaoCanonica, rotuloNorm)) ?? {};
}

/**
 * A PROVENIÊNCIA POR ANO de cada linha, na MESMA identidade das outras funções
 * deste arquivo — o par (seção canônica, rótulo normalizado).
 *
 * Separada de `seriesPorLinha` de propósito, e não é gosto: aquela função decide
 * NÚMERO e é lida por quem confere número. Misturar dez campos de metadado no
 * mesmo `Record<string, number>` obrigaria a mudar o tipo dela — e o tipo estreito
 * é o que faz um `serie[ano] = "aceito"` não compilar.
 */
export function provenienciaPorLinha(
  valores: ValorPorAno[],
  anosHistoricos: number[],
): Map<string, Record<string, ProvenienciaCelula>> {
  const anos = new Set(anosHistoricos);
  const mapa = new Map<string, Record<string, ProvenienciaCelula>>();
  for (const v of valores) {
    if (!anos.has(v.ano)) continue;
    const k = chaveDaLinha(v.secao_canonica, v.rotulo_norm);
    let porAno = mapa.get(k);
    if (!porAno) { porAno = {}; mapa.set(k, porAno); }
    const conf = v.confianca == null ? null : Number(v.confianca);
    porAno[String(v.ano)] = {
      arquivo: v.arquivo ?? null,
      pagina: v.origem_pagina ?? null,
      confianca: conf === null || Number.isNaN(conf) ? null : conf,
      statusAceite: v.status_aceite ?? null,
      aceitoPor: v.aceito_por ?? null,
    };
  }
  return mapa;
}

/** A proveniência de UMA linha, por ano. Linha sem série devolve objeto vazio. */
export function provenienciaDaLinha(
  mapa: Map<string, Record<string, ProvenienciaCelula>>,
  secaoCanonica: string | null,
  rotuloNorm: string,
): Record<string, ProvenienciaCelula> {
  return mapa.get(chaveDaLinha(secaoCanonica, rotuloNorm)) ?? {};
}

/**
 * O HISTÓRICO DO MODELO: as linhas do caso com a série de cada uma, os exercícios que contam e
 * a unidade — o miolo que o export e a tela de Modelagem compartilham.
 *
 * Existe para que as sugestões do realizado saiam do MESMO caminho de dados do arquivo que vai
 * a comitê. Antes, a tela somava `fn_linhas_do_realizado` por seção e errava em silêncio onde o
 * documento imprime o total do grupo ao lado das filhas (Fw Valtra, 2025: PMR 120 dias contra
 * ~40 do documento). Duas leituras do mesmo histórico divergem sem erro nenhum.
 *
 * Só exercícios ATÉ `ultimoReal` são histórico: um balancete do ano corrente não é exercício
 * fechado (ver `seriesPorLinha`).
 */
export function historicoDoModelo(
  linhasDoBanco: Array<{
    secao_canonica: string | null; chave: string; rotulo_norm: string;
    papel: LinhaModelo["papel"]; unidade: string | null; moeda: string | null;
    documentos: string[] | null;
  }>,
  valores: ValorPorAno[],
  ultimoReal: number,
): { linhas: LinhaModelo[]; anosHistoricos: number[]; unidade: string } {
  const anosHistoricos = [...new Set(valores.map((v) => v.ano))]
    .filter((a) => a <= ultimoReal).sort((a, b) => a - b);
  const series = seriesPorLinha(valores, anosHistoricos);
  const proveniencias = provenienciaPorLinha(valores, anosHistoricos);
  const linhas: LinhaModelo[] = linhasDoBanco.map((l) => ({
    secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
    papel: l.papel, unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
    valores: serieDaLinha(series, l.secao_canonica, l.rotulo_norm),
    proveniencia: provenienciaDaLinha(proveniencias, l.secao_canonica, l.rotulo_norm),
  }));
  // Unidade dominante: a das linhas, não um palpite. Se o caso mistura milhar e unidade, a
  // dominante entra no cabeçalho e a divergência aparece por linha.
  const contagemUnidade = new Map<string, number>();
  for (const l of linhas) {
    if (!l.unidade) continue;
    contagemUnidade.set(l.unidade, (contagemUnidade.get(l.unidade) ?? 0) + 1);
  }
  const dominante = [...contagemUnidade.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  const ROTULO_DA_UNIDADE: Record<string, string> = { milhar: "R$ mil", unidade: "R$" };
  const unidade = ROTULO_DA_UNIDADE[dominante ?? "unidade"] ?? dominante ?? "R$";
  return { linhas, anosHistoricos, unidade };
}

