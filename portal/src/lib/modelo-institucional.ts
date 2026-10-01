import ExcelJS from "exceljs";
import { comoNota, THIN_TOP_BORDER } from "./export-estilo";
import {
  FILL_ANO_PROJETADO, FILL_ANO_REALIZADO, FILL_ENTRADA, FILL_ERRO, FILL_OK, FILL_SECAO,
  FILL_SUBTOTAL, FMT, FONTE_COR, fonte, LEGENDA_CORES, ORIA,
  TAM_CAPA_TITULO, TAM_TITULO_ABA,
} from "./oria-marca";
import { normalizar } from "./statement-templates";
import type { EspecGrafico } from "./xlsx-graficos";

// =============================================================================
// O MODELO INSTITUCIONAL — reconstrução do "Modelo Base" do dono, integrada aos
// dados e às premissas deste sistema.
//
// O QUE É O MODELO BASE. Um modelo de projeção de três demonstrações, de 14 abas,
// com switch de cenário, cascata de receita, capital de giro por dias de giro,
// cronograma de dívida com revolver, capex com depreciação por safra, fluxo de
// caixa indireto e um Output de métricas de crédito. É o formato que a casa usa,
// e é o alvo de fidelidade: MESMOS nomes de aba, MESMA semântica de linha, MESMO
// mecanismo de cenário.
//
// O QUE MUDA EM RELAÇÃO AO ARQUIVO DE REFERÊNCIA, e por quê:
//
//   1. OS NÚMEROS HISTÓRICOS SAEM DO BANCO, não são digitados. A aba `Premissas`
//      é montada com as linhas EXTRAÍDAS do caso (`fn_linhas_para_modelagem`),
//      com proveniência por célula. No arquivo de referência elas eram valores
//      colados — que é justamente o que este sistema existe para eliminar.
//   2. A aba `Anual` (base macro) sai de `indice_macro_obs` + Focus, versionados,
//      em vez de uma planilha de consultoria de 1994 a 2014.
//   3. A CIRCULARIDADE FOI QUEBRADA DE PROPÓSITO — ver `NOTA_CIRCULARIDADE`.
//   4. Nenhuma linha é projetada sem premissa vinculada. Onde o referência tinha
//      "Item 2/Item 3" como espaço reservado, aqui aparecem as linhas REAIS do
//      caso; linha sem premissa fica no arquivo dizendo que não é projetada.
//
// POR QUE FÓRMULA E NÃO VALOR: o arquivo é entregue para o cliente e para o
// credor mexerem. Um modelo com valores calculados fora do Excel é um relatório;
// um modelo com fórmula é um modelo. Toda projeção aqui é fórmula que aponta para
// a célula de premissa — mudar a premissa move o modelo inteiro.
// =============================================================================

// -----------------------------------------------------------------------------
// A DECISÃO DE ENGENHARIA MAIS IMPORTANTE DESTE ARQUIVO.
//
// O modelo de referência é CIRCULAR: despesa financeira → lucro → caixa →
// revolver → despesa financeira. Ele depende do cálculo iterativo do Excel
// (Arquivo → Opções → Fórmulas → Habilitar cálculo iterativo). Isso tem três
// consequências ruins para um entregável institucional:
//
//   • fora do Excel (LibreOffice, Google Sheets, visualizador do navegador) a
//     referência circular resolve para ZERO ou #VALUE! sem avisar — e quem abre
//     não sabe que está lendo um modelo que não convergiu;
//   • nenhum teste automático consegue verificar o arquivo: não há como avaliar
//     uma referência circular sem reimplementar o motor iterativo;
//   • duas pessoas com configurações diferentes de Excel leem NÚMEROS diferentes
//     do MESMO arquivo, e nada na tela denuncia.
//
// Então aqui o laço é cortado no ponto onde ele custa menos precisão: juros e
// rendimentos incidem sobre o saldo de ABERTURA do período (o que o próprio
// modelo de referência já faz na linha do revolver: `=J58*I51`, margem do período
// × revolver do período ANTERIOR). O arquivo declara isso na aba `Considerações`
// e em nota na célula, porque é uma divergência de método e quem audita precisa
// saber. Não é aproximação escondida: é escolha registrada.
// -----------------------------------------------------------------------------
// O que o LEITOR do arquivo precisa saber sobre a convenção de juros. A
// justificativa da escolha (referência circular, cálculo iterativo, o que o
// modelo de referência faz) está no cabeçalho deste arquivo — é assunto de quem
// mantém o gerador, não de quem lê o entregável.
const NOTA_CIRCULARIDADE =
  "Juros e rendimentos financeiros incidem sobre o saldo de ABERTURA do período, não sobre a "
  + "média do período — a diferença é de cerca de meio período de juros.";

export const ABAS_MODELO = [
  "Considerações", "Capa", "Output", "Revenues, COGS & SG&A", "Premissas",
  "Income Statement", "Balance Sheet", "Working Capital", "ST Inv. & Debt",
  "Fixed Assets & CAPEX", "Cash Flow", "Goodwill, Taxes & Div.", "Anual",
  "Tributos a Recolher",
] as const;

// Colunas. B = sinal, C = rótulo, D = premissa/unidade, E em diante = períodos.
//
// UMA GRADE, TODAS AS ABAS — divergência DELIBERADA do Modelo Base, e é uma das
// correções que ele mais pede. Lá cada aba tem seu próprio deslocamento: a coluna
// de rótulo é B, C ou nenhuma, o eixo do tempo começa em D, E ou G, e a mesma
// referência entre abas carrega um deslocamento fixo diferente em cada par
// (`Income Statement` = `Revenues` +1 coluna, `Fixed Assets` = −1, `Working
// Capital` = 0). O mapa chama isso de "a armadilha estrutural do arquivo"
// (§2.2), e é a fonte natural do erro de espelhar a linha certa na coluna
// errada. Aqui a grade é a MESMA nas 14 abas, e nenhuma fórmula precisa saber de
// deslocamento nenhum.
const COL_SINAL = 2;
const COL_ROTULO = 3;
const COL_NOTA = 4;
const COL_PRIMEIRO_ANO = 5;

const CENARIOS = ["Base Case", "Cliente Case", "Stress Case"] as const;

// Os três cenários pelo sufixo com que vivem nas chaves da grade. A ORDEM é a do
// `CHOOSE` (1=Base, 2=Cliente, 3=Stress) e não é decorativa: o `CHECK_SOMBRA` e o
// bloco do Output indexam por ela, e trocá-la faria o arquivo comparar o Stress
// contra a coluna do Cliente sem nada denunciar.
const CENARIOS_SUF = [
  ["base", "Base Case"],
  ["cli", "Cliente Case"],
  ["str", "Stress Case"],
] as const;
type CenSuf = (typeof CENARIOS_SUF)[number][0];

// Estilo: vem de `oria-marca.ts`, que é onde a identidade visual do entregável
// mora e onde está escrito o que cada cor SIGNIFICA. Os aliases abaixo são só
// para o corpo deste arquivo continuar legível.
const FONTE_BLOCO: Partial<ExcelJS.Font> = fonte({ bold: true });
const FILL_BLOCO = FILL_SECAO;
const FONTE_BLOCO_INV: Partial<ExcelJS.Font> = fonte({ bold: true, color: { argb: ORIA.branco } });
const FILL_INPUT = FILL_ENTRADA;
const FILL_HIST = FILL_SUBTOTAL;
const FILL_CHECK_OK = FILL_OK;
const FILL_CHECK_ERRO = FILL_ERRO;
const NUM = FMT.valor;
const NUM2 = FMT.valor2;
const PCT = FMT.pct;
const MULT = FMT.mult;
const DIAS = FMT.dias;
const PCT2 = FMT.pct2;

// A gramática de cor de FONTE (azul = digitado, preto = calculado, verde = vem de
// outra aba) é aplicada dentro de `Grade.set`, que classifica a célula pela
// PROCEDÊNCIA do valor. Copiada do Modelo Base, que a usa com rigor, mais o
// verde, que é acréscimo nosso — num arquivo de 29 abas, saber num relance que a
// célula é espelho de outra aba economiza a auditoria de abrir a nota.
// A constante abaixo é para as células escritas FORA da grade (a raiz do eixo do
// tempo e a chave S/N por tranche).
const FONTE_ENTRADA: Partial<ExcelJS.Font> = fonte({ color: { argb: FONTE_COR.entrada } });
const preencherArgb = (argb: string): ExcelJS.Fill =>
  ({ type: "pattern", pattern: "solid", fgColor: { argb } });

// -----------------------------------------------------------------------------
// Entrada
// -----------------------------------------------------------------------------
export interface LinhaModelo {
  secao_canonica: string | null;
  chave: string;
  rotulo_norm: string;
  papel: "conta" | "subtotal" | "derivado" | "serie_mensal";
  unidade: string | null;
  moeda: string | null;
  documentos: string[] | null;
  /** valor por ano, do histórico extraído */
  valores: Record<string, number>;
  /**
   * Marcado por `contexto()`, NUNCA por quem chama: o bloco desta linha vinha do
   * documento na convenção "despesa negativa" e foi normalizado para a convenção
   * do modelo ("despesa positiva, subtraída na cascata"). Serve para a nota da
   * célula dizer o número do documento — sem isso a normalização seria silenciosa,
   * e valor que muda de sinal sem dizer por quê é exatamente o tipo de coisa que
   * ninguém confere.
   */
  sinalNormalizado?: boolean;
  /**
   * Marcado por `contexto()`: os exercícios em que a prova de cabeçalho de grupo TIROU o valor
   * desta linha da soma (ano -> motivo e efeito, em texto de nota). A célula fica em branco, e
   * branco sem explicação é ausência apresentada como dado (regra 1).
   */
  semValorPorCabecalho?: Record<string, string>;
  /**
   * A PROVENIÊNCIA DE CADA CÉLULA HISTÓRICA, por ano: arquivo, página, confiança e
   * aceite (`0125`).
   *
   * POR QUE POR ANO, e não por linha. `documentos` (acima) é da LINHA e é o que a
   * nota mostrava até aqui — e ele é a lista de TIPOS de documento
   * (`array_agg(distinct tipo_taxonomia)`), não de arquivos: a nota dizia "Extraído
   * de BALANCO, DF_AUDITADA", que num mandato com oito balanços não localiza nada.
   * A proveniência que serve para conferir é da CÉLULA, e a célula é (linha, ano).
   *
   * Ausente quando a rota não a carregou (é opcional de propósito, para o
   * verificador do export poder montar `LinhaModelo` à mão sem ela) — e aí a nota
   * volta a dizer só o que sabe.
   */
  proveniencia?: Record<string, {
    arquivo: string | null;
    pagina: number | null;
    confianca: number | null;
    statusAceite: string | null;
    aceitoPor: string | null;
  }>;
}

export interface PremissaModelo {
  codigo: string;
  nome: string;
  natureza: string;
  formula: string;
  unidade: string | null;
  valores: Record<string, number>;
  origem: string | null;
}

export interface VinculoModelo {
  rotulo_norm: string;
  premissa_codigo: string | null;
  sazonalidade_codigo: string | null;
}

export interface EntradaModeloInstitucional {
  caso: { nome: string; produto: string };
  agora: Date;
  entidade: string | null;
  setor: string | null;
  anosHistoricos: number[];
  anosProjetados: number[];
  /** haircut do cenário Stress sobre as premissas do Base (0.20 = -20%) */
  stressPct: number;
  /** caixa mínimo operacional; abaixo dele o revolver é acionado */
  caixaMinimo: number;
  aliquotaTributos: number;
  linhas: LinhaModelo[];
  premissas: PremissaModelo[];
  vinculos: VinculoModelo[];
  /**
   * `natureza` distingue série de TAXA (variação % do ano) de série de NÍVEL
   * (R$/US$ de fechamento). Sem ela o modelo publicava o RETORNO de uma série de
   * nível numa linha rotulada "R$/US$ — final de período": o arquivo entregue
   * trazia 24,5 em 2024 e **−10,6** em 2025 (câmbio negativo) ao lado de 5,2 do
   * Focus, que é nível. Duas grandezas na mesma linha é dado mentiroso, e a linha
   * alimenta a conversão de dívida em moeda estrangeira.
   */
  /**
   * `meses` = quantos meses o REALIZADO cobre (`fn_indice_macro_anual`). Expectativa do
   * Focus não tem (é projeção do ano inteiro). Ausente = tratado como ano completo, que é
   * o que as fixtures sem o campo sempre assumiram; a rota do export sempre o manda.
   */
  macro: {
    serie: string; ano: number; valor: number; fonte: string; natureza?: "taxa" | "nivel"; meses?: number;
    /**
     * De onde o número vem, em campo ESTRUTURADO — `fonte` é só texto de exibição. "focus" =
     * expectativa de mercado (para a Selic, a META de fim de ano); "realizado" = observação
     * do BCB/IBGE. A aba Anual decide a fórmula do CDI por este campo: decidir pelo texto de
     * `fonte` fazia a troca do rótulo na rota reverter o CDI para a cópia da meta, sem erro.
     * AUSENTE = "realizado": as fixtures antigas sem o campo são realizado de 12 meses ou
     * série de nível, e tratar um número de origem desconhecida como meta (compor/fazer média)
     * inventaria uma aproximação; tratá-lo como realizado só mantém a igualdade medida.
     */
    origem?: "focus" | "realizado";
  }[];
  /**
   * Rótulos normalizados que a detecção ESTRUTURAL do export (`export.ts`,
   * `detectarSubtotaisInformados` + `detectarSubtotaisPorOrdem`) reconheceu como
   * SUBTOTAL impresso pelo próprio documento.
   *
   * POR QUE ISTO VEM DE FORA E NÃO DO `papel` DA LINHA. `fn_papel_linha` (0042)
   * classifica por LISTA FECHADA de rótulos — pega "TOTAL DO ATIVO" e "Lucro
   * Bruto", e não tem como pegar "Obrigações Tributárias", "Provisões", "Capital
   * Social", "Reservas", "Disponível" ou "Contas a Receber", que são nomes de
   * agrupamento comuns e chegam como `papel = 'conta'`. A hierarquia não está no
   * rótulo, está na ORDEM em que o documento imprime — e isso só o export vê.
   *
   * MEDIDO NO ARQUIVO ENTREGUE (v35, VERTENTES METALÚRGICA, 06/08/2026): sem esta
   * lista o balanço do modelo somava o subtotal E os componentes dele, e o
   * `ATIVO TOTAL` saía **195.090 contra 95.780 informados** — 2,04x. As mesmas
   * linhas, na aba analítica `Balanço` do MESMO arquivo, apareciam corretamente
   * marcadas como "↳ subtotal informado" e fora da soma.
   */
  subtotaisInformados?: string[];
  /** unidade dominante das linhas (milhar/unidade), para o cabeçalho das abas */
  unidade: string;
}

// -----------------------------------------------------------------------------
// Infra de escrita. Um `Grade` por aba: escreve linha a linha, guarda a âncora de
// cada linha por chave, e sabe converter (linha, ano) em referência A1.
//
// POR QUE ÂNCORA E NÃO NÚMERO LITERAL: no export-modelagem, escrever `getRow(189)`
// no meio da montagem já criou linha fantasma e empurrou o modelo 90 linhas (duas
// vezes, em duas sessões). Aqui nenhum número de linha aparece em fórmula: só
// `g.ref("EBITDA", ano)`.
// -----------------------------------------------------------------------------
function colLetra(n: number): string {
  let s = "";
  while (n > 0) {
    const r = (n - 1) % 26;
    s = String.fromCharCode(65 + r) + s;
    n = Math.floor((n - 1) / 26);
  }
  return s;
}

class Grade {
  readonly ws: ExcelJS.Worksheet;
  private anchors = new Map<string, number>();
  private cursor = 0;
  readonly anos: number[];
  readonly nHist: number;

  constructor(wb: ExcelJS.Workbook, nome: string, anos: number[], nHist: number) {
    this.ws = wb.addWorksheet(nome);
    this.anos = anos;
    this.nHist = nHist;
    this.ws.getColumn(COL_ROTULO).width = 46;
    this.ws.getColumn(COL_NOTA).width = 22;
    for (let i = 0; i < anos.length; i++) this.ws.getColumn(COL_PRIMEIRO_ANO + i).width = 13;
    this.ws.getColumn(COL_SINAL).width = 4;
    this.ws.getColumn(1).width = 2;
  }

  /** Coluna (índice) do ano. Lança se o ano não existe — erro de programação. */
  colDoAno(ano: number): number {
    const i = this.anos.indexOf(ano);
    if (i < 0) throw new Error(`modelo-institucional: ano ${ano} fora do horizonte`);
    return COL_PRIMEIRO_ANO + i;
  }

  letraDoAno(ano: number): string { return colLetra(this.colDoAno(ano)); }
  ehProjetado(ano: number): boolean { return this.anos.indexOf(ano) >= this.nHist; }
  anoAnterior(ano: number): number | null {
    const i = this.anos.indexOf(ano);
    return i > 0 ? this.anos[i - 1] : null;
  }

  proximaLinha(): number { return this.cursor + 1; }
  pular(n = 1): void { this.cursor += n; }

  /** Registra uma linha e devolve o seu número. */
  linha(chave: string | null, opts: {
    rotulo?: string; sinal?: string; nota?: string; bloco?: boolean;
    negrito?: boolean; topo?: boolean; fmt?: string;
  } = {}): number {
    const r = ++this.cursor;
    if (chave) {
      if (this.anchors.has(chave)) {
        // Chave duplicada silenciosa faria toda fórmula apontar para a PRIMEIRA
        // linha com aquele nome — e o modelo somaria a conta errada, sem avisar.
        throw new Error(`modelo-institucional: âncora duplicada "${chave}" em ${this.ws.name}`);
      }
      this.anchors.set(chave, r);
    }
    const row = this.ws.getRow(r);
    if (opts.sinal) row.getCell(COL_SINAL).value = opts.sinal;
    if (opts.rotulo !== undefined) row.getCell(COL_ROTULO).value = opts.rotulo;
    if (opts.nota !== undefined) row.getCell(COL_NOTA).value = opts.nota;
    if (opts.bloco) {
      for (let c = COL_SINAL; c < COL_PRIMEIRO_ANO + this.anos.length; c++) {
        row.getCell(c).fill = FILL_BLOCO;
        row.getCell(c).font = FONTE_BLOCO_INV;
      }
    } else if (opts.negrito) {
      row.getCell(COL_ROTULO).font = FONTE_BLOCO;
    }
    if (opts.topo) {
      for (let c = COL_ROTULO; c < COL_PRIMEIRO_ANO + this.anos.length; c++) {
        row.getCell(c).border = THIN_TOP_BORDER;
      }
    }
    if (opts.fmt) {
      for (let i = 0; i < this.anos.length; i++) {
        row.getCell(COL_PRIMEIRO_ANO + i).numFmt = opts.fmt;
      }
    }
    return r;
  }

  tem(chave: string): boolean { return this.anchors.has(chave); }

  /** As chaves registradas, na ordem em que as linhas foram criadas. */
  chaves(): string[] { return [...this.anchors.keys()]; }

  n(chave: string): number {
    const r = this.anchors.get(chave);
    if (r === undefined) throw new Error(`modelo-institucional: âncora "${chave}" não existe em ${this.ws.name}`);
    return r;
  }

  /** Referência A1 local: `ref("EBITDA", 2027)` → "J42". */
  ref(chave: string, ano: number, fixo: "" | "$" = ""): string {
    return `${fixo}${this.letraDoAno(ano)}${fixo}${this.n(chave)}`;
  }

  /** Referência para outra aba. O nome vai entre apóstrofos: há abas com "&". */
  static refExterna(aba: string, coluna: string, linha: number): string {
    return `'${aba.replace(/'/g, "''")}'!${coluna}${linha}`;
  }

  externa(aba: string, g: Grade, chave: string, ano: number): string {
    return Grade.refExterna(aba, g.letraDoAno(ano), g.n(chave));
  }

  /**
   * Escreve valor/fórmula na célula (linha por chave, coluna por ano) e pinta a
   * fonte pela PROCEDÊNCIA do número — azul digitado, preto calculado, verde
   * vindo de outra aba. A classificação é automática justamente para não
   * depender de alguém lembrar: fórmula com `'Aba'!` é externa, fórmula sem é
   * cálculo local, e literal é entrada. Onde a heurística erraria (histórico
   * EXTRAÍDO, que é literal mas não é premissa), quem chama passa `tipo`.
   */
  set(chave: string, ano: number, v: number | string | null, opts: {
    fmt?: string; fill?: ExcelJS.Fill; nota?: string; negrito?: boolean;
    tipo?: "entrada" | "calc" | "externa";
  } = {}): ExcelJS.Cell {
    const cell = this.ws.getRow(this.n(chave)).getCell(this.colDoAno(ano));
    const ehFormula = typeof v === "string" && v.startsWith("=");
    if (ehFormula) cell.value = { formula: (v as string).slice(1) };
    else if (v !== null) cell.value = v;
    if (opts.fmt) cell.numFmt = opts.fmt;
    if (opts.fill) cell.fill = opts.fill;
    const tipo = opts.tipo ?? (ehFormula
      ? (/'[^']+'!/.test(v as string) ? "externa" : "calc")
      : (opts.fill === FILL_HIST ? "calc" : "entrada"));
    const cor = tipo === "entrada" ? FONTE_COR.entrada : tipo === "externa" ? FONTE_COR.externo : FONTE_COR.calculado;
    cell.font = fonte({ bold: opts.negrito === true, color: { argb: cor } });
    if (opts.nota) cell.note = comoNota(opts.nota);
    return cell;
  }

  /** Célula avulsa (fora da grade de anos), por endereço absoluto. */
  celula(linha: number, col: number): ExcelJS.Cell {
    return this.ws.getRow(linha).getCell(col);
  }

  /**
   * O cabeçalho da aba: título, a linha de anos e a unidade.
   *
   * `refAno` é o EIXO DO TEMPO (`P01`/`P02` do mapa). Quando informado, a célula
   * do ano é FÓRMULA — e é isso que faz o arquivo inteiro ter uma única raiz de
   * calendário, como no Modelo Base: lá as 26 colunas de 9 abas saem de UMA
   * célula (`'Revenues, COGS & SG&A'!C5`) por duas recorrências de `EOMONTH`.
   * Sem isso, "2026" está escrito 14 vezes no arquivo e mudar o exercício-base é
   * reescrever tudo.
   */
  cabecalho(titulo: string, unidade: string, refAno?: (ano: number) => string, fmtAno: string = FMT.ano): void {
    const rTit = this.linha("__titulo", { rotulo: titulo, negrito: true });
    this.ws.getRow(rTit).getCell(COL_ROTULO).font = fonte({ bold: true, size: TAM_TITULO_ABA });
    this.ws.getRow(rTit).getCell(COL_ROTULO).border = { bottom: { style: "double" } };
    for (const ano of this.anos) {
      const cell = this.ws.getRow(rTit).getCell(this.colDoAno(ano));
      const f = refAno?.(ano);
      if (f !== undefined && f.startsWith("=")) {
        cell.value = { formula: f.slice(1) };
        cell.numFmt = fmtAno;
      } else if (f !== undefined) {
        cell.value = Number(f);
        cell.numFmt = fmtAno;
      } else {
        cell.value = ano;
      }
      cell.font = fonte({ bold: true, color: { argb: this.ehProjetado(ano) ? ORIA.branco : FONTE_COR.calculado } });
      cell.alignment = { horizontal: "center" };
      cell.fill = this.ehProjetado(ano) ? FILL_ANO_PROJETADO : FILL_ANO_REALIZADO;
      cell.border = { bottom: { style: "double" } };
      if (refAno && fmtAno === FMT.ano) {
        cell.note = comoNota(
          "O ano é FÓRMULA, não número digitado. Todo o calendário do modelo sai de uma única "
          + "célula — o último exercício realizado, na aba 'Revenues, COGS & SG&A' —, e daí para "
          + "trás e para frente por EOMONTH(±12 meses). Mudar aquela célula move as 14 abas. "
          + "É o mecanismo do Modelo Base (uma raiz, duas recorrências).",
        );
      }
    }
    this.linha("__unidade", { rotulo: unidade });
    this.ws.getRow(this.n("__unidade")).getCell(COL_ROTULO).font = fonte({ italic: true });
    this.pular();
  }

  /**
   * `P01` — a RAIZ do calendário, escrita uma vez, na aba de receita.
   * Devolve o endereço absoluto da célula-raiz para as outras abas herdarem.
   */
  eixoRaiz(ultimoHist: number): string {
    const r = this.linha("__eixoRaiz", {
      rotulo: "Último exercício realizado (a raiz do calendário do modelo)",
      nota: "entrada — move o modelo inteiro",
    });
    const cell = this.celula(r, COL_PRIMEIRO_ANO);
    // 31 de dezembro do último exercício realizado. Data FIXA derivada do caso,
    // nunca `new Date()`: gerador com data do sistema muda o arquivo sozinho na
    // virada do mês (regra do CLAUDE.md, e já aconteceu neste repositório).
    cell.value = new Date(Date.UTC(ultimoHist, 11, 31));
    cell.numFmt = "dd/mm/yyyy";
    cell.fill = FILL_INPUT;
    cell.font = FONTE_ENTRADA;
    cell.note = comoNota(
      "A ÚNICA data digitada do modelo. Todas as colunas de todas as abas saem daqui por "
      + "EOMONTH(±12): o histórico para trás, a projeção para frente. Trocar 2025 por 2026 aqui "
      + "reescreve o cabeçalho das 14 abas sem tocar em mais nada.",
    );
    this.celula(r, COL_ROTULO).font = fonte({ bold: true });
    this.pular();
    return `$${colLetra(COL_PRIMEIRO_ANO)}$${r}`;
  }

  /**
   * A fórmula do cabeçalho de ano DESTA aba, montada como cadeia a partir da
   * raiz — igual ao Modelo Base: a coluna do último realizado aponta para a
   * raiz, as anteriores voltam 12 meses, as posteriores avançam 12.
   */
  formulaEixo(ano: number, raiz: string, ultimoHist: number): string {
    if (ano === ultimoHist) return `=${raiz}`;
    const i = this.anos.indexOf(ano);
    const iUlt = this.anos.indexOf(ultimoHist);
    if (i < 0) throw new Error(`modelo-institucional: ano ${ano} fora do horizonte`);
    if (iUlt < 0) {
      // Caso sem histórico: a raiz é o ano anterior ao primeiro projetado.
      return i === 0 ? `=+EOMONTH(${raiz},12)` : `=+EOMONTH(${this.letraDoAno(this.anos[i - 1])}${this.n("__titulo")},12)`;
    }
    return i < iUlt
      ? `=+EOMONTH(${this.letraDoAno(this.anos[i + 1])}${this.n("__titulo")},-12)`
      : `=+EOMONTH(${this.letraDoAno(this.anos[i - 1])}${this.n("__titulo")},12)`;
  }

  /**
   * `P18 ESPELHO-DA-CONTA` — os três blocos que toda aba de driver do Modelo
   * Base publica no topo (`BALANCE SHEET ACCOUNTS`, `INCOME STATEMENT ACCOUNTS`,
   * `CASH FLOW ACCOUNTS`) e de onde as demonstrações leem.
   *
   * POR QUE ISTO IMPORTA e não é decoração: sem o espelho, `Balance Sheet` lê a
   * linha de MIOLO do cálculo do giro, e trocar o motor de uma conta obriga a
   * mexer na demonstração. Com o espelho, a interface de cada driver é
   * declarada, e é a única coisa que as demonstrações conhecem.
   */
  espelho(titulo: string, itens: { chave: string; rotulo: string; fmt?: string }[]): void {
    this.linha(null, { rotulo: titulo, bloco: true });
    for (const it of itens) {
      this.linha(it.chave, { rotulo: it.rotulo, fmt: it.fmt ?? NUM });
    }
    this.pular();
  }

  /** A célula do cenário: toda aba lê `Output` para não haver dois interruptores. */
  ancoraCenario(): void {
    const c = this.ws.getRow(1).getCell(COL_NOTA + 1);
    c.value = { formula: `Output!$G$2` };
    c.font = { bold: true };
    this.ws.getRow(1).getCell(COL_ROTULO).value = "Cenário ativo (1=Base, 2=Cliente, 3=Stress) →";
    this.cursor = Math.max(this.cursor, 2);
  }

  /** Endereço absoluto da célula de cenário desta aba, para usar em CHOOSE. */
  get celulaCenario(): string { return `$${colLetra(COL_NOTA + 1)}$1`; }

  /**
   * Painel congelado. O Modela Base congela até a ÚLTIMA COLUNA DE HISTÓRICO e
   * até a linha do cabeçalho (`ySplit=7` nas 10 abas congeladas dele, medido no
   * §17.5 do mapa) — e o motivo é operacional: quem rola a projeção para a
   * direita precisa continuar vendo o realizado ao lado do rótulo, senão compara
   * de memória. Congelar só as colunas de rótulo, como fazíamos, perde isso.
   */
  congelar(chaveLinha?: string): void {
    const ultimaHist = this.nHist > 0 ? this.colDoAno(this.anos[this.nHist - 1]) : COL_NOTA;
    this.ws.views = [{
      state: "frozen",
      xSplit: Math.max(COL_NOTA, ultimaHist),
      ySplit: chaveLinha ? this.n(chaveLinha) : (this.tem("__unidade") ? this.n("__unidade") : 3),
      // Sem linhas de grade e a 85% — é como o Modelo Base abre em 11 das 14 abas
      // (§2.8 do mapa). Grade ligada num modelo de 30 colunas compete com a
      // borda que separa subtotal de conta, que é a borda que carrega informação.
      showGridLines: false,
      zoomScale: 85,
    }];
  }

  /**
   * Área de impressão. O Modelo Base declara `Print_Area` em 5 das 14 abas — os
   * únicos 5 nomes definidos dele que têm valor, entre 1.044 (§17.1 do mapa).
   * Aqui todas declaram: sem isso, imprimir uma aba de 30 colunas leva a
   * planilha para 6 páginas em pedaços, e é assim que o comitê recebe o papel.
   */
  imprimir(): void {
    const ultima = colLetra(COL_PRIMEIRO_ANO + this.anos.length - 1);
    const ultimaLinha = Math.max(this.cursor, 1);
    this.ws.pageSetup = {
      ...(this.ws.pageSetup ?? {}),
      orientation: "landscape",
      fitToPage: true,
      fitToWidth: 1,
      fitToHeight: 0,
      printArea: `B1:${ultima}${ultimaLinha}`,
      margins: { left: 0.4, right: 0.4, top: 0.6, bottom: 0.6, header: 0.3, footer: 0.3 },
    };
    this.ws.headerFooter = {
      oddFooter: "&L&\"Arial,Italic\"&8Oria Partners — documento de trabalho&C&8&A&R&8&P/&N",
    };
  }

  /** Fecha a aba: congela, define área de impressão e devolve a última linha. */
  finalizar(chaveLinha?: string): void {
    this.congelar(chaveLinha);
    this.imprimir();
  }

  /**
   * Estende a área de impressão até uma linha ABAIXO da última escrita — é o que o
   * `Output` precisa para os gráficos entrarem no papel (eles são ancorados depois
   * de `finalizar()`, e a âncora não move a área de impressão sozinha).
   */
  estenderImpressao(ultimaLinha: number): void {
    if (ultimaLinha <= this.cursor) return;
    const ultima = colLetra(COL_PRIMEIRO_ANO + this.anos.length - 1);
    this.ws.pageSetup = {
      ...(this.ws.pageSetup ?? {}),
      printArea: `B1:${ultima}${ultimaLinha}`,
    };
  }
}


// -----------------------------------------------------------------------------
// ESCALA. O caso mistura unidades de verdade: o balanço vem em `milhar` e o mapa
// da dívida em `unidade` (reais). Medido no book: o passivo do modelo saiu com
// 51.300.000 ao lado de um ativo de 1.000 — a dívida em reais somada a um balanço
// em milhares, e o "modelo" mostrando alavancagem de 51 mil vezes.
//
// Então TODO valor histórico é convertido para a unidade do modelo antes de
// entrar, e a célula diz que foi convertida. Unidade desconhecida NÃO é convertida
// nem chutada: a linha entra com aviso, porque adivinhar fator de mil é a forma
// mais rápida de errar por três ordens de grandeza.
// -----------------------------------------------------------------------------
const FATOR_PARA_MILHAR: Record<string, number> = {
  milhar: 1, mil: 1, "r$ mil": 1,
  unidade: 0.001, reais: 0.001, "r$": 0.001,
  milhao: 1000, milhoes: 1000, "milhão": 1000, "milhões": 1000,
};

function fatorDeEscala(unidadeLinha: string | null, unidadeModelo: string): number | null {
  const alvo = /mil/i.test(unidadeModelo) && !/milh(a|ã)o/i.test(unidadeModelo) ? 1 : 0.001;
  if (!unidadeLinha) return null;
  const f = FATOR_PARA_MILHAR[unidadeLinha.toLowerCase().trim()];
  if (f === undefined) return null;
  return alvo === 1 ? f : f * 1000;
}

/**
 * A PROVENIÊNCIA DA CÉLULA, escrita para quem vai conferir o número no documento.
 *
 * O QUE ELA CONSERTA (§2.3 do diagnóstico de 11/08). Antes do PR #109 o arquivo de
 * modelagem carregava as abas de dado, e cada célula delas trazia documento,
 * PÁGINA, CONFIANÇA e STATUS DE ACEITE. O #109 separou os dois exports — decisão
 * certa e medida — e com as abas de dado saiu essa camada. O que restou nas células
 * históricas foi `Extraído de ${documentos}`.
 *
 * E ESSE RESTO ERA MENOS DO QUE PARECIA: `documentos` é
 * `array_agg(distinct tipo_taxonomia)`, ou seja o TIPO do documento. A nota dizia
 * "Extraído de BALANCO, DF_AUDITADA" — num mandato com oito balanços, isso é a
 * categoria, não a peça. Para responder "de onde veio o 106.580" faltava tudo o que
 * localiza: o arquivo, a página, e se alguém já olhou aquilo.
 *
 * A ORDEM DAS FRASES É A DA CONFERÊNCIA: primeiro onde procurar (arquivo, página),
 * depois o quanto confiar (confiança, aceite). E cada pedaço só aparece se
 * EXISTIR — `null` é "a extração não disse", e escrever "página null" seria pior
 * que calar. Sem proveniência carregada, a nota volta ao texto antigo, com os tipos.
 */
function frasesDeProveniencia(l: LinhaModelo, ano: number): string {
  const p = l.proveniencia?.[String(ano)];
  if (!p) return `Extraído de ${(l.documentos ?? ["?"]).join(", ")}`;
  const partes: string[] = [
    `Extraído de ${p.arquivo ?? (l.documentos ?? ["?"]).join(", ")}`,
  ];
  if (p.pagina != null) partes.push(`página ${p.pagina}`);
  if (p.confianca != null) partes.push(`confiança da extração ${Math.round(p.confianca * 100)}%`);
  if (p.statusAceite) {
    // ACEITE É O QUE SEPARA "o modelo leu" de "um humano conferiu", e é a única
    // frase daqui que muda o peso do número numa conversa com credor.
    partes.push(p.statusAceite === "aceito"
      ? `ACEITO${p.aceitoPor ? ` por ${p.aceitoPor}` : ""}`
      : `aceite: ${p.statusAceite} — este número ainda NÃO foi conferido por ninguém`);
  }
  return partes.join(" · ");
}

/** Valor histórico já na escala do modelo, com o aviso quando houve conversão. */
function valorNaEscala(l: LinhaModelo, ano: number, unidadeModelo: string):
  { valor: number; nota: string } | null {
  const bruto = l.valores[String(ano)];
  if (bruto === undefined) return null;
  const f = fatorDeEscala(l.unidade, unidadeModelo);
  // A NORMALIZAÇÃO DE SINAL É DITA NA CÉLULA. Sem esta frase o número da planilha
  // aparece com sinal diferente do número do PDF e não há como saber se foi
  // conversão de convenção ou erro de extração — que é a diferença entre um
  // arquivo auditável e um que só parece certo.
  const sinal = l.sinalNormalizado
    ? ` · SINAL NORMALIZADO: o documento traz ${(-bruto).toLocaleString("pt-BR")} (despesa negativa) `
      + "e o modelo usa magnitude positiva, subtraída na cascata — ver a coluna de sinal \"(-)\"."
    : "";
  const proveniencia = `${frasesDeProveniencia(l, ano)}${sinal}`;
  if (f === null) {
    return {
      valor: bruto,
      nota: `${proveniencia}. ATENÇÃO: unidade "${l.unidade ?? "(não informada)"}" não reconhecida, `
        + `valor entrou SEM conversão de escala. Se esta conta estiver em reais e o modelo em `
        + `${unidadeModelo}, ela está mil vezes maior — confira antes de usar o arquivo.`,
    };
  }
  if (f === 1) return { valor: bruto, nota: `${proveniencia} · unidade ${l.unidade}.` };
  return {
    valor: bruto * f,
    nota: `${proveniencia} · CONVERTIDO de "${l.unidade}" para ${unidadeModelo} (fator ${f}). `
      // Com sinal normalizado, o número do documento é o oposto do que está aqui:
      // dizer `bruto` seria repetir a magnitude e contradizer a frase acima.
      + "O valor no documento é "
      + (l.sinalNormalizado ? -bruto : bruto).toLocaleString("pt-BR") + ".",
  };
}

// -----------------------------------------------------------------------------
// Classificação das linhas do caso nos blocos do modelo.
//
// O modelo tem blocos fixos (receita, dedução, custo, SG&A, e as contas de
// balanço). A `secao_canonica` da extração já resolve a maior parte; o que ela não
// resolve é DEDUÇÃO dentro de `receita_bruta` — ICMS/PIS/COFINS/IPI/devoluções
// vêm marcados como receita porque é onde eles aparecem na DRE.
//
// A lista é FECHADA e casa por palavra, não por substring solta: `"ICMS a
// recuperar"` é conta do ativo e não pode virar dedução de receita só por conter
// "ICMS". A `secao_canonica` já separa as duas, e este filtro só age DENTRO de
// `receita_bruta`.
// -----------------------------------------------------------------------------
const PADROES_DEDUCAO = [
  /\bdevolu/i, /\babatimento/i, /\bdescontos? concedidos?\b/i,
  /\bicms sobre\b/i, /\bipi sobre\b/i, /\bpis e cofins sobre\b/i, /\bpis\/cofins sobre\b/i,
  /\biss sobre\b/i, /\bimpostos? sobre vendas?\b/i, /\bdedu(ç|c)(õ|o)es\b/i,
  /\btributos sobre vendas?\b/i, /\bcancelad/i,
];

export type BlocoModelo =
  | "receita" | "deducao" | "custo" | "sga" | "resultado_financeiro" | "tributos"
  | "ativo_circulante" | "ativo_nao_circulante" | "passivo_circulante"
  | "passivo_nao_circulante" | "patrimonio_liquido" | "divida" | "capex" | "fora";

export function blocoDaLinha(l: LinhaModelo): BlocoModelo {
  const docs = l.documentos ?? [];
  if (docs.includes("MAPA_DIVIDA")) return "divida";
  switch (l.secao_canonica) {
    case "receita_bruta":
      return PADROES_DEDUCAO.some((re) => re.test(l.chave)) ? "deducao" : "receita";
    case "custos": return "custo";
    case "despesas_operacionais": return "sga";
    case "resultado_financeiro": return "resultado_financeiro";
    case "impostos_lucro": return "tributos";
    case "ativo_circulante": return "ativo_circulante";
    case "ativo_nao_circulante": return "ativo_nao_circulante";
    case "passivo_circulante": return "passivo_circulante";
    case "passivo_nao_circulante": return "passivo_nao_circulante";
    case "patrimonio_liquido": return "patrimonio_liquido";
    default: return "fora";
  }
}

// Linhas de imobilizado dentro do ANC viram classes de capex — é o que o
// `Fixed Assets & CAPEX` projeta. Lista fechada, mesma razão de sempre.
const PADROES_IMOBILIZADO = [
  /\bimobilizado\b/i, /\bedifica/i, /\bterreno/i, /\bve(í|i)culo/i, /\bm(á|a)quina/i,
  /\bequipamento/i, /\binstala(ç|c)/i, /\bm(ó|o)veis?\b/i, /\butens(í|i)lio/i,
  /\bferramenta/i, /\bfrota\b/i, /\bempilhadeira/i, /\bintang(í|i)vel/i, /\bsoftware/i,
  /\bmarcas? e patentes?\b/i,
];
const ehImobilizado = (chave: string) => PADROES_IMOBILIZADO.some((re) => re.test(chave));

// -----------------------------------------------------------------------------
// CAIXA E EQUIVALENTES — a lista que corrige a DUPLA CONTAGEM aberta desde a
// sessão 32, e a resposta veio do próprio Modelo Base.
//
// O QUE ESTAVA ERRADO. `Working Capital` projetava TODAS as contas de
// `ativo_circulante` por dias de giro — inclusive caixa, bancos e aplicações. As
// mesmas contas voltavam pelo `Cash Flow` em `CAIXA_FIM`, e o `Balance Sheet`
// fazia `AC = CAIXA + AC_OPER`. Resultado: o caixa entrava DUAS VEZES no ativo, o
// `CHECK` do balanço acusava em vermelho, e a alavancagem saía otimista porque a
// dívida líquida descontava um caixa inflado.
//
// O QUE O MODELO BASE FAZ (medido, §10 do MAPA_MODELO_BASE.md): as seis contas de
// giro do ativo dele são `Aplicações de liquidez imediata`, `Reserva Técnica`,
// `Créd. operações`, `Despesas de comercialização diferidas`, `Títulos e créditos
// a receber` e `Outros valores e bens` — e `Cash & Short Term Inv.` **está fora
// da lista**. O caixa é projetado só pelo `Cash Flow`
// (`Balance Sheet!J13 = 'Cash Flow'!H59`) e a dívida só pelo `ST Inv. & Debt`.
// A regra é UMA CONTA, UMA ORIGEM.
//
// A lista é fechada e casa por palavra inteira, pelo mesmo motivo das outras: a
// conta "Aplicações em coligadas" é investimento permanente e não pode virar
// caixa só por conter "aplicações".
const PADROES_CAIXA = [
  /\bcaixa\b/i, /\bcaixa e equivalentes?\b/i, /\bdisponibilidades?\b/i, /\bdispon(í|i)vel\b/i,
  /\bbancos?\b/i, /\bconta movimento\b/i, /\bequivalentes? de caixa\b/i,
  /\baplica(ç|c)(õ|o)es financeiras\b/i, /\baplica(ç|c)(õ|o)es de liquidez\b/i,
  /\bt(í|i)tulos e valores mobili(á|a)rios\b/i, /\bnumer(á|a)rio\b/i,
];
const ehCaixa = (chave: string) => PADROES_CAIXA.some((re) => re.test(chave));

// -----------------------------------------------------------------------------
// DÍVIDA FINANCEIRA — o vocabulário ÚNICO, e por que ele passou a existir.
//
// Seis lugares deste arquivo faziam a MESMA pergunta — "esta linha é dívida, que
// vive na aba de dívida, e portanto NÃO é giro?" — com TRÊS regexes diferentes:
//
//   A. `abaCapitalGiro` (giro) e a repartição CP/LP …… empréstimo|financiamento|
//                                                      debênture|arrendamento
//   B. `Cash Flow` e o passivo não circulante ………… A + leasing
//   C. a origem da dívida do `ST Inv. & Debt` ……… B + nota promissória|
//                                                      cédula de crédito
//
// As diferenças não eram deliberadas: os três sítios dão o MESMO motivo no
// comentário ("contaria duas vezes"). E o efeito era uma classificação que muda
// de aba para aba dentro do mesmo arquivo: "Leasing operacional a pagar" é dívida
// no Cash Flow e no balanço (B) e é GIRO no Working Capital (A); "Nota
// promissória" é dívida só em C. Duas réguas sobre a mesma quantidade é a forma
// de defeito que esta casa já pagou três vezes.
//
// E AS TRÊS DEIXAVAM PASSAR DÍVIDA BANCÁRIA COM NOME BRASILEIRO, medido no book:
// "Conta garantida" (1.550) e "Duplicatas descontadas e antecipação de
// recebíveis" (5.277) — 6.827, ou 9,6% do passivo circulante informado — ficavam
// no passivo OPERACIONAL e eram projetadas por DIAS DE GIRO CONTRA RECEITA. É
// exatamente o que o comentário do `abaCapitalGiro` proíbe em voz alta: "o
// passivo operacional carregaria dívida, e a NCG passaria a MELHORAR quando a
// empresa se endivida mais".
//
// O QUE FICOU DE FORA, DE PROPÓSITO: risco sacado, confirming, forfait e vendor.
// São supplier finance, e se eles são dívida ou fornecedor é julgamento contábil
// em aberto (depende de quem assume o risco e do prazo original). Classificá-los
// aqui mudaria resultado financeiro por decisão nossa — e isso é decisão do dono,
// não de um regex.
// -----------------------------------------------------------------------------
const PADROES_DIVIDA_FINANCEIRA = [
  /empr(é|e)stimo/i, /financiamento/i, /deb(ê|e)nture/i, /arrendamento/i, /leasing/i,
  /nota promiss(ó|o)ria/i, /c(é|e)dula de cr(é|e)dito/i,
  // Instrumentos bancários de curto prazo com nome próprio no Brasil. Nenhum
  // deles traz a palavra "empréstimo", e todos são dívida com banco.
  /conta garantida/i, /cheque especial/i,
  /duplicatas? descontadas?/i, /desconto de (duplicatas?|receb(í|i)veis|t(í|i)tulos)/i,
  /antecipa(ç|c)(ã|a)o de receb(í|i)veis/i,
  /adiantamento de contrato de c(â|a)mbio/i, /\bACC\b/, /\bACE\b/,
];
export const ehDividaFinanceira = (chave: string) =>
  PADROES_DIVIDA_FINANCEIRA.some((re) => re.test(chave));

// AS TRÊS CONTAS DO CICLO DE CAIXA, isoladas por nome.
//
// Elas moravam dentro da aba `Working Capital` como filtros locais. Subiram para
// cá quando a tela de Modelagem passou a sugerir premissa a partir do realizado
// (`premissas-do-realizado.ts`): as duas precisam responder "o que é cliente,
// estoque e fornecedor" com a MESMA lista, senão o dia sugerido na tela não é o
// dia que o modelo aplica, e a diferença aparece como saldo que não reproduz o
// balanço de onde saiu.
export const ehCliente = (chave: string) =>
  /\bclientes?\b/i.test(chave) || /\bcontas? a receber\b/i.test(chave)
  || /\bduplicatas? a receber\b/i.test(chave)
  || /\bt(í|i)tulos? a receber\b/i.test(chave) || /\btitulos? a receber\b/i.test(chave);

export const ehEstoque = (chave: string) =>
  /\bestoque/i.test(chave) || /\bmercadoria/i.test(chave)
  || /\bprodutos? (acabados?|em (elabora|processo))/i.test(chave)
  || /\bmat(é|e)ria.prima/i.test(chave);

export const ehFornecedor = (chave: string) =>
  /\bfornecedor/i.test(chave) || /\bcontas? a pagar\b/i.test(chave)
  || /\bduplicatas? a pagar\b/i.test(chave);

// LUCROS RETIDOS, dentro do patrimônio líquido. Existe para o X2 do Altman, e é
// lista fechada pelo mesmo motivo dos outros: `reserva de capital` e `ajuste de
// avaliação patrimonial` também são PL e NÃO são lucro retido — somá-los infla o
// índice justamente na empresa que capitalizou para cobrir prejuízo.
// DESPESA FINANCEIRA, dentro do resultado financeiro. Existe porque a taxa média
// da dívida se mede com o que a dívida CUSTA, e o bloco `resultado_financeiro`
// traz as duas pontas: o juro pago e o rendimento da aplicação. Somar as duas em
// módulo — que é o que a magnitude faz — INFLA a taxa implícita pelo rendimento,
// e o número volta como premissa de custo de dívida.
//
// Lista fechada pela mesma razão dos outros classificadores desta seção, e o
// sinal NÃO serve de critério: o documento publica despesa ora positiva, ora
// negativa, conforme a convenção de quem o emitiu.
export const ehDespesaFinanceira = (chave: string) =>
  /\bdespesas? financeiras?\b/i.test(chave)
  || /\bjuros\b/i.test(chave)
  || /\bencargos? financeiros?\b/i.test(chave)
  || /\bvaria(ç|c)(ã|a)o cambial passiva\b/i.test(chave)
  || /\b(iof|cpmf)\b/i.test(chave)
  || /\bdescontos? concedidos?\b/i.test(chave)
  || /\bcomiss(õ|o)es? e taxas? banc(á|a)rias?\b/i.test(chave);

export const ehLucrosRetidos = (chave: string) =>
  /\blucros? (ou preju(í|i)zos? )?acumulados?\b/i.test(chave)
  || /\bpreju(í|i)zos? acumulados?\b/i.test(chave)
  || /\breservas? de lucros?\b/i.test(chave)
  || /\breserva legal\b/i.test(chave)
  || /\breservas? de reten(ç|c)(ã|a)o de lucros?\b/i.test(chave);


// -----------------------------------------------------------------------------
// A CONVENÇÃO DE SINAL DO MODELO, e por que ela precisa ser imposta na fronteira.
//
// Toda a cascata deste modelo SUBTRAI despesa: `RECEITA_LIQUIDA = GROSS −
// DEDUÇÕES`, `GROSS_PROFIT = NET − CUSTOS`, `EBITDA = GROSS_PROFIT − SG&A + D&A`.
// Isso quer dizer que dedução, custo e SG&A entram como MAGNITUDE POSITIVA, com o
// "(-)" na coluna de sinal — é a convenção do Modelo Base e a que as projeções por
// `% da receita` (`pct × receita`, positivo) já produziam.
//
// O DOCUMENTO usa a convenção oposta: a DRE publicada traz `(-) ICMS sobre vendas
// −18.900`. E o histórico entra no modelo direto da extração, sem passar por
// conversão nenhuma. Subtrair um número negativo SOMA.
//
// MEDIDO NO ARQUIVO ENTREGUE (v35, VERTENTES METALÚRGICA, 06/08/2026), contra os
// totais que o próprio documento informa e que a aba analítica `DRE` do MESMO
// arquivo mostra corretos:
//
//   | 2025                | documento | modelo institucional |
//   | Receita líquida     |   106.580 |              170.220 |
//   | Lucro bruto         |     5.280 |              271.520 |
//   | EBIT                |    −4.571 |             +281.371 |
//   | Resultado líquido   |   −17.901 |             +268.041 |
//
// Uma empresa que perdeu 17,9 milhões apareceu ganhando 268 — e as projeções de
// 2026 a 2030 cresceram a partir dessa base. Pior: dentro da MESMA coluna as
// linhas projetadas por crescimento seguiam negativas e as projetadas por
// percentual saíam positivas, então `CUSTOS 2026` somava sinais opostos.
//
// A NORMALIZAÇÃO É POR BLOCO E POR MULTIPLICAÇÃO POR −1, nunca por `Math.abs`:
// `abs` transformaria "Outras receitas (despesas) operacionais, líquidas +11.549"
// — um CRÉDITO dentro do bloco de despesa — em despesa de 11.549, invertendo um
// fato do documento. Multiplicar o bloco inteiro por −1 preserva o crédito como
// crédito (ele vira −11.549 na convenção do modelo e a cascata o soma de volta).
//
// A DECISÃO É DO BLOCO, não da linha, e é medida no próprio caso: se a soma do
// bloco no histórico é negativa, o documento está na convenção "despesa negativa"
// e o bloco é invertido; se é positiva, já está em magnitude e nada é feito. Assim
// um documento que publique custo positivo também sai certo, sem chave manual.
// -----------------------------------------------------------------------------
const BLOCOS_DE_DESPESA: readonly BlocoModelo[] = ["deducao", "custo", "sga"];

// Casamento de rótulo com âncora: a `normalizar` de statement-templates (UMA
// definição de "sem acento, minúscula, espaço único" no projeto) mais a pontuação
// de apresentação. "Resultado Operacional (EBIT)" e "Resultado operacional -
// EBIT" são o mesmo rótulo para quem lê, e um documento escreve de cada jeito.
// CÓDIGO DE CONTA CONTÁBIL NO COMEÇO DO RÓTULO — "1.1.01.002 Caixa e bancos".
//
// É como quase todo balancete de ERP brasileiro chega, e ele quebrava a ÂNCORA:
// `chaveDeAncora` troca ponto por espaço, então "1.1.01.002 TOTAL DO ATIVO" virava
// "1 1 01 002 total do ativo" e não casava com "total do ativo" da lista fechada.
// Sem âncora não há linha de reconciliação, e sem reconciliação o balanço não
// fecha: medido no arnês de variações, resíduo de −36.116 com os mesmos números.
//
// Dois dígitos-grupo no mínimo (`\d+(\.\d+){2,}`), que é a mesma definição de
// código de conta que `N8N/lib/cobertura.mjs` já usa — "identidade sem uma letra
// sequer". Exigir três grupos evita comer um "2.500" que seja parte do nome.
// O código não se perde: ele continua no rótulo que o arquivo imprime; o que muda
// é só o que a âncora COMPARA.
const CODIGO_DE_CONTA_NO_INICIO = /^\s*\d+(?:\.\d+){2,}\s*[-–—.)]?\s*/;
const chaveDeAncora = (s: string) =>
  normalizar(String(s ?? "").replace(CODIGO_DE_CONTA_NO_INICIO, ""))
    .replace(/[()[\].,;:/–—-]+/g, " ").replace(/\s+/g, " ").trim();

// AS ÂNCORAS DO DOCUMENTO — o que permite PROVAR que o modelo não mente.
//
// As linhas de resultado da DRE e os totais do balanço chegam com
// `papel = 'subtotal'` (lista fechada da `fn_papel_linha`) e por isso ficam FORA
// das somas do modelo, como devem. Mas elas são o número que o documento informa,
// e até agora eram simplesmente descartadas.
//
// Aqui elas passam a ser guardadas para a CONFERÊNCIA: o modelo publica, no
// realizado, o número dele ao lado do número do documento e a diferença. É o
// invariante nº 9 do `verificar-export` ("nosso número == o número do documento")
// trazido para dentro do modelo institucional, que era a única parte do arquivo
// sem ele — e é o que faz um erro de sinal ou de dupla contagem aparecer NA CARA
// em vez de virar um EBITDA de 281 milhões que ninguém questiona.
//
// DUAS ARMADILHAS QUE ESTA LISTA TEM DE TRATAR, as duas medidas contra o book:
//
//   • O MESMO RÓTULO VEM DE VÁRIOS DOCUMENTOS. "Lucro líquido do exercício" aparece
//     na DRE, na DMPL e no fluxo — e na DMPL costuma ser uma COLUNA DE MOVIMENTO,
//     com o prejuízo escrito positivo. Sem preferir o documento de origem certo, a
//     conferência da DRE comparava contra o número da DMPL e acusava divergência
//     onde o modelo estava certo. Daí o campo `doc`.
//   • "PREJUÍZO LÍQUIDO DO EXERCÍCIO 17.901" É −17.901. O rótulo já carrega o sinal
//     em português contábil, e o valor vem positivo. Comparar cru inverteria o
//     resultado (erro de 35.802 num caso de 17.901).
const ANCORAS_DOC: ReadonlyArray<{ chave: string; doc: string; rotulos: readonly string[] }> = [
  { chave: "DOC_RECEITA_LIQUIDA", doc: "DRE", rotulos: [
    "receita liquida", "receita operacional liquida", "receita liquida de vendas",
    "receita liquida de vendas e servicos"] },
  { chave: "DOC_LUCRO_BRUTO", doc: "DRE", rotulos: ["lucro bruto", "prejuizo bruto", "resultado bruto"] },
  { chave: "DOC_EBIT", doc: "DRE", rotulos: [
    "resultado operacional antes do resultado financeiro", "resultado operacional",
    "resultado operacional ebit", "ebit", "lucro operacional"] },
  { chave: "DOC_EBT", doc: "DRE", rotulos: [
    "resultado antes dos tributos sobre o lucro", "resultado antes dos tributos",
    "lucro antes do imposto de renda", "resultado antes do ir e csll"] },
  { chave: "DOC_LUCRO_LIQUIDO", doc: "DRE", rotulos: [
    "lucro liquido do exercicio", "prejuizo liquido do exercicio",
    "lucro prejuizo liquido do exercicio", "lucro liquido prejuizo do exercicio",
    "lucro liquido", "prejuizo liquido", "resultado do exercicio", "resultado liquido"] },
  { chave: "DOC_ATIVO", doc: "BALANCO", rotulos: ["ativo", "ativo total", "total do ativo", "total ativo"] },
  { chave: "DOC_PASSIVO_PL", doc: "BALANCO", rotulos: [
    "passivo e patrimonio liquido", "total do passivo e patrimonio liquido",
    "passivo + patrimonio liquido", "total do passivo e do patrimonio liquido"] },
  // OS TOTAIS DE GRUPO — o insumo da reconciliação (ver `RECONC_` em `abaBalanco`).
  { chave: "DOC_AC", doc: "BALANCO", rotulos: [
    "ativo circulante", "total do ativo circulante", "total ativo circulante"] },
  { chave: "DOC_ANC", doc: "BALANCO", rotulos: [
    "ativo nao circulante", "total do ativo nao circulante", "total ativo nao circulante"] },
  { chave: "DOC_PC", doc: "BALANCO", rotulos: [
    "passivo circulante", "total do passivo circulante", "total passivo circulante"] },
  { chave: "DOC_PNC", doc: "BALANCO", rotulos: [
    "passivo nao circulante", "total do passivo nao circulante", "total passivo nao circulante"] },
  { chave: "DOC_PL", doc: "BALANCO", rotulos: [
    "patrimonio liquido", "total do patrimonio liquido", "patrimonio liquido consolidado"] },
];

// -----------------------------------------------------------------------------
// Premissa por linha: como a projeção de cada conta é escrita.
// -----------------------------------------------------------------------------
interface Ctx {
  ent: EntradaModeloInstitucional;
  anos: number[];
  nHist: number;
  premissaPorLinha: Map<string, PremissaModelo>;
  premissaPorCodigo: Map<string, PremissaModelo>;
  linhasPorBloco: Map<BlocoModelo, LinhaModelo[]>;
  /** anos com histórico, em ordem */
  hist: number[];
  proj: number[];
  ultimoHist: number;
  /** blocos cuja convenção de sinal foi invertida para a do modelo */
  blocosInvertidos: Set<BlocoModelo>;
  /** âncora do documento (`DOC_*`) → a linha extraída que a informa */
  ancoras: Map<string, LinhaModelo>;
}

function contexto(ent: EntradaModeloInstitucional): Ctx {
  const premissaPorCodigo = new Map(ent.premissas.map((p) => [p.codigo, p]));
  const premissaPorLinha = new Map<string, PremissaModelo>();
  for (const v of ent.vinculos) {
    const p = v.premissa_codigo ? premissaPorCodigo.get(v.premissa_codigo) : undefined;
    if (p) premissaPorLinha.set(v.rotulo_norm, p);
  }
  // Os subtotais que a estrutura do documento denuncia (ver
  // `subtotaisInformados`). Casa pelo rótulo normalizado E pelo `rotulo_norm` da
  // linha, porque os dois caminhos normalizam de formas ligeiramente diferentes e
  // um subtotal que escapa volta a dobrar o balanço.
  // A chave é o PAR (seção, rótulo) — ver o comentário de
  // `rotulosDeSubtotalInformado`: casar só pelo rótulo tirava da DRE uma despesa
  // que tem o mesmo nome de um subtotal do balanço.
  // `seção||rótulo` = subtotal em todos os exercícios (regra antiga, período ilegível);
  // `seção||rótulo||ano` = subtotal SÓ naquele exercício — nos outros a linha é conta e soma.
  const subtotaisEstruturais = new Set<string>();
  const subtotaisPorAno = new Map<string, Set<string>>(); // seção||rótulo → anos
  for (const r of ent.subtotaisInformados ?? []) {
    const [secao, rotulo, ano] = r.split("||");
    const k = `${chaveDeAncora(secao ?? "")}||${chaveDeAncora(rotulo ?? "")}`;
    if (ano === undefined) { subtotaisEstruturais.add(k); continue; }
    if (!subtotaisPorAno.has(k)) subtotaisPorAno.set(k, new Set());
    subtotaisPorAno.get(k)!.add(ano);
  }
  const chavesDaLinha = (l: LinhaModelo) => {
    const secao = chaveDeAncora(l.secao_canonica ?? "");
    return [`${secao}||${chaveDeAncora(l.rotulo_norm)}`, `${secao}||${chaveDeAncora(l.chave)}`];
  };
  const ehSubtotalEstrutural = (l: LinhaModelo) => chavesDaLinha(l).some((k) => subtotaisEstruturais.has(k));
  /** A linha SEM os exercícios em que ela é subtotal; `null` se não sobrou nenhum. */
  const semOsAnosDeSubtotal = (l: LinhaModelo): LinhaModelo | null => {
    const anos = new Set(chavesDaLinha(l).flatMap((k) => [...(subtotaisPorAno.get(k) ?? [])]));
    if (anos.size === 0) return l;
    const valores = Object.fromEntries(Object.entries(l.valores).filter(([a]) => !anos.has(a)));
    return Object.keys(valores).length > 0 ? { ...l, valores } : null;
  };

  // As âncoras vêm das linhas que NÃO são conta (subtotais do documento). Quando o
  // mesmo rótulo aparece em mais de um documento, os anos se completam em vez de um
  // sobrescrever o outro — o balanço de 2024 e o de 2025 costumam ser dois PDFs.
  const ancoras = new Map<string, LinhaModelo>();
  // Duas passadas: primeiro só as linhas que vêm do DOCUMENTO da âncora (a DRE para
  // as linhas de resultado, o balanço para os totais), depois as demais para
  // completar ano que faltou. Sem a ordem, "Lucro líquido do exercício" da DMPL
  // sobrescrevia o da DRE e a conferência comparava contra a coluna de movimento.
  for (const preferindoODoc of [true, false]) {
    for (const l of ent.linhas) {
      const alvo = ANCORAS_DOC.find((a) => a.rotulos.includes(chaveDeAncora(l.chave))
        || a.rotulos.includes(chaveDeAncora(l.rotulo_norm)));
      if (!alvo) continue;
      const doDoc = (l.documentos ?? []).some((d) => d.toUpperCase().includes(alvo.doc));
      if (preferindoODoc !== doDoc) continue;
      // "PREJUÍZO ..." escrito com valor positivo é resultado NEGATIVO — o rótulo
      // carrega o sinal, e é assim que a DRE brasileira publica.
      const ehPrejuizo = /preju[íi]zo/i.test(l.chave) && !/lucro/i.test(l.chave);
      const valores = Object.fromEntries(Object.entries(l.valores)
        .map(([ano, v]) => [ano, ehPrejuizo ? -Math.abs(v) : v]));
      const atual = ancoras.get(alvo.chave);
      if (!atual) {
        ancoras.set(alvo.chave, { ...l, valores });
        continue;
      }
      // DOIS RÓTULOS DIFERENTES PARA A MESMA ÂNCORA: ganha o que DIZ "TOTAL".
      //
      // O documento imprime o cabeçalho do grupo e o total do grupo, e os dois
      // casam com a mesma âncora. Medido no v35: `PASSIVO E PATRIMÔNIO LÍQUIDO`
      // vale 121.198 (é o cabeçalho da metade direita, sem o passivo circulante
      // inteiro) e `TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO` vale 158.801 — o
      // fechamento de verdade, igual ao `TOTAL DO ATIVO`. Antes vencia o primeiro
      // que a iteração encontrasse: ordem de banco decidindo qual número o modelo
      // chama de "informado no documento".
      //
      // "Total" no rótulo é declaração do próprio documento, não heurística
      // nossa — e é o critério que a contabilidade usa para distinguir cabeçalho
      // de fechamento. Quando nenhum dos dois diz "total", o primeiro continua
      // valendo (é o comportamento anterior, e não há sinal para desempatar).
      const dizTotal = (x: LinhaModelo) => /\btotal\b/i.test(x.chave) || /\btotal\b/i.test(x.rotulo_norm);
      if (dizTotal(l) && !dizTotal(atual)) {
        const anosDoAntigo = atual.valores;
        const novo: LinhaModelo = { ...l, valores };
        for (const [ano, v] of Object.entries(anosDoAntigo)) {
          if (novo.valores[ano] === undefined) novo.valores[ano] = v;
        }
        ancoras.set(alvo.chave, novo);
        continue;
      }
      for (const [ano, v] of Object.entries(valores)) {
        if (atual.valores[ano] === undefined) atual.valores[ano] = v;
      }
    }
  }

  const linhasPorBloco = new Map<BlocoModelo, LinhaModelo[]>();
  for (const l of ent.linhas) {
    if (l.papel !== "conta") continue;
    // SUBTOTAL FORA DA SOMA. Ele continua no arquivo (a aba analítica o mostra
    // marcado) e continua servindo de âncora acima — só não entra como conta.
    if (ehSubtotalEstrutural(l)) continue;
    const lSoma = semOsAnosDeSubtotal(l);
    if (lSoma === null) continue;
    const b = blocoDaLinha(lSoma);
    if (!linhasPorBloco.has(b)) linhasPorBloco.set(b, []);
    linhasPorBloco.get(b)!.push(lSoma);
  }

  // ---- CABEÇALHO DE GRUPO IMPRESSO: fora da soma, e só COM PROVA ----------
  //
  // O PROBLEMA. Um balanço brasileiro imprime, dentro de cada seção, o nome do
  // grupo com o total dele e as contas embaixo: `Contas a Receber 30.020`,
  // depois `Duplicatas a receber…`, `Clientes…`. Para a extração as duas coisas
  // são linhas iguais, e `fn_papel_linha` (lista fechada) não reconhece esses
  // nomes como subtotal — o comentário de `rotulosDeSubtotalInformado` já nomeia
  // os seis mais comuns. Somando tudo, o grupo entra DUAS VEZES no modelo.
  //
  // O detector estrutural do export resolve isso quando a `ordem` das linhas é a
  // ordem impressa. Quando ela não é — extração antiga sem `ordem`, documento
  // recomposto, captura por rótulo — não há sequência para ler, e o modelo ficava
  // sem defesa nenhuma: no v35 o ativo circulante operacional saía 155.939 contra
  // 67.878 informados, e a linha de reconciliação absorvia 99 mil, ou seja, mais
  // do que o próprio grupo.
  //
  // A REGRA AQUI EXIGE PROVA ARITMÉTICA, e é isso que a torna segura:
  //
  //   1. o rótulo tem de ser EXATAMENTE um nome de grupo (lista fechada abaixo) —
  //      "Estoques" entra, "Estoques de matéria-prima" não;
  //   2. o documento tem de informar o total DAQUELE grupo (a âncora DOC_*);
  //   3. a soma das contas extraídas tem de EXCEDER esse total — sem excesso não
  //      há dupla contagem para explicar, e nada é removido;
  //   4. remover a linha tem de APROXIMAR a soma do informado, nunca ultrapassá-lo.
  //
  // Com isso, o documento simples — que imprime "Estoques" como conta-folha, sem
  // abertura — nunca perde a conta: lá a soma não excede o informado, e a
  // condição 3 já barra. A remoção é do MODELO; a linha continua no arquivo, na
  // aba de dados, com o valor que a extração trouxe.
  const CABECALHOS_DE_GRUPO = new Set([
    // ativo circulante
    "disponivel", "disponibilidades", "caixa e equivalentes", "caixa e equivalentes de caixa",
    "contas a receber", "clientes", "estoques", "tributos a recuperar", "impostos a recuperar",
    "outros creditos", "despesas antecipadas", "adiantamentos", "aplicacoes financeiras",
    "titulos e valores mobiliarios",
    // ativo não circulante
    "realizavel a longo prazo", "investimentos", "imobilizado", "intangivel", "ativo permanente",
    // passivo
    "fornecedores", "emprestimos e financiamentos", "financiamentos", "obrigacoes tributarias",
    "obrigacoes fiscais", "obrigacoes trabalhistas", "obrigacoes trabalhistas e sociais",
    "obrigacoes sociais e trabalhistas", "tributos a recolher", "impostos a recolher",
    "outras obrigacoes", "outras contas a pagar", "partes relacionadas", "provisoes",
    "arrendamentos", "adiantamentos de clientes",
    // patrimônio líquido
    "capital social", "reservas", "reservas de lucros", "reservas de capital",
    "ajustes de avaliacao patrimonial",
  ]);
  const ANCORA_DO_BLOCO: Partial<Record<BlocoModelo, string>> = {
    ativo_circulante: "DOC_AC", ativo_nao_circulante: "DOC_ANC",
    passivo_circulante: "DOC_PC", passivo_nao_circulante: "DOC_PNC",
    patrimonio_liquido: "DOC_PL",
  };
  // A PROVA É POR EXERCÍCIO, e a remoção também. Antes ela rodava só no último exercício
  // histórico e tirava a LINHA INTEIRA (todos os anos): "Estoques" é cabeçalho sintético no
  // balancete de 2026 (soma das contas > total informado) e FOLHA nos Balanços de 2024 e 2025
  // — a prova do último ano apagava a conta dos três. Medido no Krauspenhar (caso 33b58a89):
  // resíduo de 53.924.564,46 (2024) e 43.569.482,33 (2025), 43% do ativo, e `Working Capital`
  // sem linha de Estoques. Agora cada exercício histórico prova o seu e a linha perde SÓ o
  // valor daquele ano; sem excesso naquele ano, nada sai dele.
  const chaveDaLinha = (l: LinhaModelo) => `${l.secao_canonica ?? ""}||${l.chave}`;
  const tirarAno = (bloco: BlocoModelo, quais: (l: LinhaModelo) => string | null, anoS: string) => {
    const lista = linhasPorBloco.get(bloco) ?? [];
    linhasPorBloco.set(bloco, lista.flatMap((l) => {
      const motivo = quais(l);
      if (motivo === null) return [l];
      const valores = Object.fromEntries(Object.entries(l.valores).filter(([a]) => a !== anoS));
      if (Object.keys(valores).length === 0) return [];
      return [{ ...l, valores, semValorPorCabecalho: { ...l.semValorPorCabecalho, [anoS]: motivo } }];
    }));
  };
  // Linhas que a prova aritmética JÁ provou cabeçalho de grupo em algum exercício, por bloco, e
  // os exercícios históricos sem total informado (sem âncora não há prova possível).
  const provadas = new Map<BlocoModelo, Set<string>>();
  const semAncora: Array<[BlocoModelo, string]> = [];
  for (const ano of [...ent.anosHistoricos].sort((a, b) => b - a)) {
    const anoS = String(ano);
    for (const [bloco, chaveAncora] of Object.entries(ANCORA_DO_BLOCO) as Array<[BlocoModelo, string]>) {
      const lista = linhasPorBloco.get(bloco);
      const ancora = ancoras.get(chaveAncora);
      if (!lista || lista.length === 0) continue;
      const informado = ancora?.valores[anoS];
      if (typeof informado !== "number" || informado === 0) { semAncora.push([bloco, anoS]); continue; }
      const valorDe = (l: LinhaModelo) => l.valores[anoS] ?? 0;
      let soma = lista.reduce((s, l) => s + valorDe(l), 0);
      // TOLERÂNCIA EM MÓDULO, e não `informado * 1.005`. O total informado pode
      // ser NEGATIVO — patrimônio líquido a descoberto é o caso normal num
      // mandato de reestruturação (a Canastra Indústria do book tem PL −4.221) —
      // e multiplicar um número negativo por 1,005 afrouxa o limiar para o lado
      // errado. Nos cenários que medi as duas formas decidem igual (a segunda
      // guarda segura o caso), mas "meio por cento do tamanho" é o que a regra
      // quer dizer, e é o que ela passa a dizer.
      const tolerancia = Math.abs(informado) * 0.005;
      if (soma - informado <= tolerancia) continue;
      const somaAntes = soma;
      const candidatos = lista
        .filter((l) => CABECALHOS_DE_GRUPO.has(chaveDeAncora(l.chave))
          || CABECALHOS_DE_GRUPO.has(chaveDeAncora(l.rotulo_norm)))
        .sort((a, b) => Math.abs(valorDe(b)) - Math.abs(valorDe(a)));
      const remover = new Set<LinhaModelo>();
      for (const c of candidatos) {
        const v = valorDe(c);
        if (v === 0) continue;
        // VALOR IGUAL AO DE OUTRA LINHA DO BLOCO NÃO É CABEÇALHO — é a MESMA
        // CONTA TRANSPOSTA COM DOIS RÓTULOS, e a doutrina desta casa (invariante
        // nº 6, teste 0106h) é explícita: não se apaga conta, segue-se o total
        // informado e DECLARA-SE o resíduo. "Reservas de lucros 5.000" ao lado de
        // "Reserva de lucros acumulados 5.000" são duas grafias do mesmo saldo;
        // um cabeçalho de grupo é a SOMA de vários componentes, e coincidir no
        // centavo com um deles é assinatura de transposição, não de agrupamento.
        if (lista.some((o) => o !== c && Math.abs(valorDe(o) - v) < 0.5)) continue;
        const depois = soma - v;
        // Só remove o que APROXIMA do informado sem passar do ponto — as duas
        // comparações em MÓDULO, pelo mesmo motivo da tolerância acima.
        if (depois - informado < -tolerancia) continue;
        if (Math.abs(depois - informado) >= Math.abs(soma - informado)) continue;
        remover.add(c);
        soma = depois;
      }
      // TUDO OU NADA. Tirar uma conta que só "aproxima" e deixa o excesso de pé é compensar o
      // erro de OUTRA linha com uma conta de verdade: medido num arranjo em que um sintético de
      // 50.000 fora da lista de nomes dobrava o circulante, a prova tirava "Clientes" (28.000,
      // folha) e o modelo ficava 100.000 contra 78.000 informados — o erro trocado de lugar e
      // com cara de tratado. Se a remoção não fecha o grupo no informado (dentro da tolerância),
      // nada sai e o excesso fica à vista na linha de reconciliação.
      if (remover.size > 0 && soma - informado > tolerancia) continue;
      if (remover.size > 0) {
        const nomes = new Set([...remover].map(chaveDaLinha));
        if (!provadas.has(bloco)) provadas.set(bloco, new Set());
        for (const n of nomes) provadas.get(bloco)!.add(n);
        tirarAno(bloco, (l) => nomes.has(chaveDaLinha(l))
          ? `Cabeçalho de grupo: em ${anoS} a soma das contas do bloco excedia o total informado `
            + `no documento (${informado.toLocaleString("pt-BR")}) em ${(somaAntes - informado).toLocaleString("pt-BR")}, `
            + `e este valor (${valorDe(l).toLocaleString("pt-BR")}) é o do grupo, não de uma conta. Quem carrega o `
            + "saldo são as filhas. Efeito: o valor sai da soma do modelo neste exercício; deixá-lo dobraria o grupo."
          : null, anoS);
      }
    }
  }
  // EXERCÍCIO SEM TOTAL INFORMADO: não há como provar, e somar de volta o grupo que a prova
  // tirou noutro exercício dobraria o bloco calado (antes de 3f40571 a prova do último ano
  // tirava a linha de todos os anos; aqui o ano sem âncora herda a decisão, e DIZ que herdou).
  // Teto: se a conta for folha neste ano, ela sai por herança — por isso a nota da célula.
  for (const [bloco, anoS] of semAncora) {
    const nomes = provadas.get(bloco);
    if (!nomes) continue;
    tirarAno(bloco, (l) => nomes.has(chaveDaLinha(l)) && l.valores[anoS] !== undefined
      ? `Cabeçalho de grupo por herança: o documento não informa o total do bloco em ${anoS}, então `
        + "não há prova aritmética neste exercício; a linha foi provada cabeçalho de grupo em outro "
        + "exercício (a soma das contas excedia o total informado) e seu valor "
        + `(${(l.valores[anoS] ?? 0).toLocaleString("pt-BR")}) fica fora da soma. Efeito: se aqui ela for uma conta `
        + "(e não o grupo), o bloco fica menor que o real por este valor."
      : null, anoS);
  }

  // ---- normalização de sinal, bloco a bloco --------------------------------
  const blocosInvertidos = new Set<BlocoModelo>();
  const anosHist = new Set(ent.anosHistoricos.map(String));
  for (const bloco of BLOCOS_DE_DESPESA) {
    const lista = linhasPorBloco.get(bloco);
    if (!lista || lista.length === 0) continue;
    let soma = 0;
    for (const l of lista) {
      for (const [ano, v] of Object.entries(l.valores)) {
        if (anosHist.has(ano)) soma += v;
      }
    }
    if (soma >= 0) continue; // já está em magnitude: nada a fazer
    blocosInvertidos.add(bloco);
    linhasPorBloco.set(bloco, lista.map((l) => ({
      ...l,
      sinalNormalizado: true,
      valores: Object.fromEntries(Object.entries(l.valores).map(([ano, v]) => [ano, -v])),
    })));
  }

  // Ordem estável e legível: pelo rótulo. Sem isso, a ordem vem do banco e o
  // arquivo muda de forma entre duas gerações sem nada ter mudado.
  for (const lista of linhasPorBloco.values()) lista.sort((a, b) => a.chave.localeCompare(b.chave, "pt-BR"));

  const hist = [...ent.anosHistoricos].sort((a, b) => a - b);
  const proj = [...ent.anosProjetados].sort((a, b) => a - b);
  return {
    ent, anos: [...hist, ...proj], nHist: hist.length,
    premissaPorLinha, premissaPorCodigo, linhasPorBloco, hist, proj,
    ultimoHist: hist[hist.length - 1] ?? proj[0] - 1,
    blocosInvertidos, ancoras,
  };
}

// =============================================================================
// PREMISSA LIGADA A K CONTAS: o valor é do GRUPO, não de cada conta.
//
// O DEFEITO (medido no Excel do mandato Krauspenhar, caso 33b58a89): a premissa
// PME (150 dias) estava ligada em lote a 40 contas de estoque, e cada conta virava
// `dias/360 × RECEITA_LÍQUIDA`. O "Ativo circulante operacional" foi de 36,10 mi
// (2025) para 340,32 mi (2026), a dívida de curto prazo de 18,00 para 333,11 mi e
// o ativo total de 113,86 para 413,15 mi — sem célula vermelha, e o CHECK fechava
// (o patrimônio absorve). O mesmo vale para `pct_de_linha` em custo/SG&A (47 contas
// × 88% da receita) e para o capex por classe.
//
// A LEITURA: a premissa tem UM valor por (caso, código) em `caso_premissa.valores`.
// Ligada a K contas, o único sentido possível é "o GRUPO vale isto". O total do
// grupo é `dias/360 × base` (ou `taxa × base`) e cada conta recebe a PARCELA
// HISTÓRICA dela: saldo da conta ÷ soma do grupo, no último exercício realizado,
// em fórmula visível (linha `#part`). Grupo = contas do MESMO bloco, ligadas ao
// MESMO código, com a MESMA base (fornecedor gira contra custo, o resto contra
// receita — misturar as duas bases no mesmo grupo não teria total único).
//
// K = 1 NÃO MUDA NADA: sem linha `#part`, sem rateio, mesma fórmula de antes.
// SEM SALDO para ratear (soma do grupo zero ou ausente) NÃO se divide igualmente
// em silêncio: as contas ficam em BRANCO com nota de motivo e efeito (regra 1).
// =============================================================================
interface GrupoRateado {
  /** as contas do grupo (inclui a própria) */
  membros: LinhaModelo[];
  /** soma dos saldos do último exercício realizado, na escala do modelo */
  somaHist: number;
  /** não há saldo realizado para ratear: as contas não projetam */
  semSaldo: boolean;
}

function gruposRateados(
  ctx: Ctx, lista: LinhaModelo[], chaveDe: (l: LinhaModelo) => string,
  formula: PremissaModelo["formula"], saldo: (l: LinhaModelo) => number,
  mesmaBase: (a: LinhaModelo, b: LinhaModelo) => boolean = () => true,
): Map<string, GrupoRateado> {
  const out = new Map<string, GrupoRateado>();
  for (const l of lista) {
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    if (!p || p.formula !== formula) continue;
    const membros = lista.filter((o) => {
      const po = ctx.premissaPorLinha.get(o.rotulo_norm);
      return po !== undefined && po.codigo === p.codigo && po.formula === formula && mesmaBase(l, o);
    });
    if (membros.length <= 1) continue;
    const somaHist = membros.reduce((s, o) => s + saldo(o), 0);
    out.set(chaveDe(l), { membros, somaHist, semSaldo: !(Math.abs(somaHist) > 1e-9) });
  }
  return out;
}

/** `saldo da conta ÷ soma do grupo` no último exercício realizado (fórmula, não valor). */
function formulaParcela(g: Grade, ch: string, chavesDoGrupo: string[], ultimoHist: number): string {
  return `=${g.ref(ch, ultimoHist)}/(${chavesDoGrupo.map((k) => g.ref(k, ultimoHist)).join("+")})`;
}

function notaParcela(p: PremissaModelo, gr: GrupoRateado, ultimoHist: number, total: string): string {
  return `Premissa "${p.nome}" está ligada a ${gr.membros.length} contas (do mesmo bloco, ou de custo e SG&A, que têm a mesma base): o valor dela é do `
    + `GRUPO (${total}) e esta conta recebe a parcela que tinha no grupo em ${ultimoHist} (saldo ÷ `
    + "soma dos saldos). Aplicar o valor inteiro a cada conta multiplicaria o bloco por "
    + `${gr.membros.length}.`;
}

function notaGrupoSemSaldo(p: PremissaModelo, gr: GrupoRateado, ultimoHist: number, efeito: string): string {
  return `Premissa "${p.nome}" está ligada a ${gr.membros.length} contas do mesmo grupo, mas o grupo não tem `
    + `saldo realizado em ${ultimoHist} para ratear o valor entre elas (soma ${gr.somaHist}). Esta conta `
    + `NÃO é projetada: fica em branco e os subtotais a leem como zero — ${efeito} `
    + "Para projetar, ligue a premissa a uma conta com saldo realizado.";
}

/** A nota da célula em branco cujo valor a prova de cabeçalho de grupo tirou (ver `contexto`). */
function notaSemValor(l: LinhaModelo, ano: number): string | undefined {
  return l.semValorPorCabecalho?.[String(ano)];
}

/** O valor da âncora do documento naquele ano, na escala do modelo. */
function valorDaAncora(ctx: Ctx, chave: string, ano: number): { valor: number; nota: string } | null {
  const l = ctx.ancoras.get(chave);
  if (!l) return null;
  return valorNaEscala(l, ano, ctx.ent.unidade);
}

// A ÂNCORA DA LINHA INCLUI A SEÇÃO, e não só o rótulo.
//
// O DEFEITO QUE ISTO CORRIGE derrubou o export inteiro com HTTP 500 na primeira
// vez que o modelo institucional rodou sobre conteúdo real:
//
//   Error: modelo-institucional: âncora duplicada "trib:obrigacoes tributarias"
//          em Tributos a Recolher
//
// `Obrigações Tributárias` existe DUAS vezes no caso do v35 — 7.895 no passivo
// circulante e 13.549 no não circulante —, e `fn_linhas_para_modelagem` devolve
// as duas porque a identidade dela é o par (seção, rótulo). Enquanto cada aba
// consumia UM bloco, o rótulo sozinho bastava: dentro de um bloco ele é único.
// `abaTributos` é a única que junta dois blocos (circulante + não circulante) sob
// o mesmo prefixo — e ali as duas linhas viram a mesma âncora.
//
// A guarda da `Grade` fez o que devia: preferiu explodir a somar a conta errada
// em silêncio (é o que o comentário dela diz, e é a escolha certa). O que estava
// errado era a chave.
//
// Vale para as demais abas como prevenção do mesmo acidente: `Working Capital`
// junta ativo e passivo circulante, `Balance Sheet` junta quatro blocos, e hoje
// nenhum rótulo colide ali por acaso — não por construção.
const chaveLinha = (prefixo: string, l: LinhaModelo) =>
  `${prefixo}:${l.secao_canonica ?? ""}:${l.rotulo_norm}`;

// =============================================================================
// ABA Anual — a base macro. Séries nas linhas, anos nas colunas, como no
// referência; a diferença é que aqui o dado é o `indice_macro_obs` versionado
// mais o Focus, com a FONTE de cada célula na nota.
// =============================================================================
const SERIES_MACRO: ReadonlyArray<{ codigo: string; rotulo: string }> = [
  { codigo: "PIB", rotulo: "PIB — crescimento real (% a.a.)" },
  { codigo: "IPCA", rotulo: "IPCA — IBGE (% a.a.)" },
  { codigo: "IGPM", rotulo: "IGP-M — FGV (% a.a.)" },
  { codigo: "INPC", rotulo: "INPC — IBGE (% a.a.)" },
  { codigo: "SELIC", rotulo: "Selic acumulada (% a.a.)" },
  { codigo: "CDI", rotulo: "CDI (% a.a.)" },
  { codigo: "CAMBIO_USD", rotulo: "R$/US$ — final de período" },
];

/**
 * Séries de NÍVEL (preço/estoque), não de taxa. É a mesma classificação que a
 * `indice_macro_serie.natureza` guarda no banco (0025) — aqui em lista fechada,
 * porque a linha do modelo é rotulada em nível ("R$/US$ — final de período") e
 * publicar variação nela é dado mentiroso, não formatação.
 */
const SERIES_DE_NIVEL = new Set(["CAMBIO_USD"]);

function abaAnual(wb: ExcelJS.Workbook, ctx: Ctx): Grade {
  const g = new Grade(wb, "Anual", ctx.anos, ctx.nHist);
  // Cadeia de ano própria (esta aba é construída ANTES da de receita, que é a raiz
  // do calendário) — mesma solução da `Premissas`, e o mesmo padrão do Modelo Base.
  g.cabecalho("BASE MACROECONÔMICA", "Séries anuais — realizado (BCB/IBGE) e expectativa (Focus)",
    (ano) => {
      const i = ctx.anos.indexOf(ano);
      return i <= 0 ? String(ano) : `=${g.letraDoAno(ctx.anos[i - 1])}1+1`;
    }, "0");

  const porSerieAno = new Map<string, { valor: number; fonte: string; natureza?: "taxa" | "nivel"; meses?: number; origem?: "focus" | "realizado" }>();
  for (const m of ctx.ent.macro) {
    porSerieAno.set(`${m.serie}|${m.ano}`, { valor: m.valor, fonte: m.fonte, natureza: m.natureza, meses: m.meses, origem: m.origem });
  }
  /** Realizado de menos de 12 meses numa série de TAXA: acumulado parcial, não taxa anual. */
  const parcial = (v: { natureza?: "taxa" | "nivel"; meses?: number } | undefined, codigo: string) =>
    v !== undefined && v.meses !== undefined && v.meses < 12
    && v.natureza !== "nivel" && !SERIES_DE_NIVEL.has(codigo);

  for (const s of SERIES_MACRO) {
    g.linha(`macro:${s.codigo}`, { rotulo: s.rotulo, nota: s.codigo, fmt: NUM2 });
    for (const ano of ctx.anos) {
      const v = porSerieAno.get(`${s.codigo}|${ano}`);
      // SÉRIE DE NÍVEL NÃO ACEITA VARIAÇÃO, e vice-versa.
      //
      // DEFEITO MEDIDO NO ARQUIVO ENTREGUE (v35): a linha "R$/US$ — final de período"
      // saiu com 24,5 em 2024 e **−10,6** em 2025 ao lado de 5,2 do Focus. Câmbio
      // negativo não existe: o que chegou ali foi o RETORNO do ano
      // (`fn_indice_macro_anual` devolve, para série de nível, a variação entre o
      // primeiro e o último fechamento) publicado numa linha de NÍVEL, junto com
      // expectativas que são nível. Duas grandezas na mesma linha, e ela alimenta a
      // conversão de dívida em moeda estrangeira.
      //
      // A recusa é deliberada: célula VAZIA com o motivo escrito é auditável;
      // número na unidade errada não é. Quem produz o dado (a rota do export) manda
      // `natureza`, e o que não casa com a natureza da série não entra.
      if (v && SERIES_DE_NIVEL.has(s.codigo) && v.natureza === "taxa") {
        g.set(`macro:${s.codigo}`, ano, null, {
          nota: `A fonte entregou ${s.codigo} de ${ano} como VARIAÇÃO (${v.valor.toLocaleString("pt-BR")}%), `
            + "e esta linha é de NÍVEL (R$/US$ de fechamento). A célula fica VAZIA: publicar a "
            + "variação aqui produziria câmbio negativo ao lado de câmbio em reais — foi o que o "
            + "arquivo de 06/08/2026 fez. Origem: " + v.fonte,
        });
        continue;
      }
      // ANO CORRENTE PARCIAL NÃO É TAXA ANUAL. Medido em 01/10/2026 no export do caso de
      // teste 72d9210a: a linha "CDI (% a.a.)" saía com 10,888 / 14,333 (12 meses) e
      // **9,713 em 2026, que é o acumulado de 9 meses**, e VAZIA de 2027 a 2030 — o Focus
      // não publica CDI (só CAMBIO_USD, IGPM, IPCA, PIB, SELIC). Nove meses de CDI numa
      // linha "% a.a." subestima o ano e vira a curva da dívida; para IPCA e Selic o
      // Focus sobrescrevia o parcial por acaso (as expectativas entram depois), para CDI
      // e INPC nada sobrescrevia. Vale para toda série de taxa, não só o CDI.
      if (parcial(v, s.codigo) && s.codigo !== "CDI") {
        g.set(`macro:${s.codigo}`, ano, null, {
          nota: `O realizado de ${ano} cobre ${v!.meses} meses: realizado de ${v!.meses} meses não é taxa `
            + `anual e não é publicado numa linha "% a.a.". A célula fica VAZIA (e o que a lê cai em `
            + `zero por N()) até ${s.codigo === "INPC" ? "o ano fechar (o Focus não publica INPC)" : "haver Focus ou o ano fechar"}. `
            + `Origem: ${v!.fonte}`,
        });
        continue;
      }
      // CDI: o Focus NÃO publica CDI, então ano projetado sem CDI realizado de 12 meses
      // ficava vazio e a curva da dívida (ST Inv. & Debt) lia zero: "Custo efetivo do
      // revolver" 10,89% | 14,33% | 9,71% | 0 | 0 | 0 | 0 no export medido. A proxy vem da
      // Selic, por FÓRMULA (uma revisão do Focus move o CDI junto). Base medida em
      // produção: CDI e Selic REALIZADOS (SGS 4390, acumulado do ano) são IDÊNTICOS em todo
      // ano fechado de 2022 a 2025 (12,380 / 13,028 / 10,888 / 14,333).
      //
      // MAS A SELIC DO FOCUS NÃO É ESSA GRANDEZA: é a META NO FIM DO ANO. Copiá-la como
      // CDI do ano subestima o custo num ciclo de corte (meta 13,75 no fim de 2026 e 12 no
      // fim de 2027: acumulado de 2027 ≈ 12,9, a célula diria 12,0) e, em 2026, jogaria
      // fora os 9 meses já realizados (9,713). Por isso, com Selic do Focus:
      //   • ano corrente com realizado parcial: realizado de m meses composto com os
      //     (12−m) restantes à meta do fim do ano;
      //   • ano seguinte com meta no ano anterior: média das duas metas (trajetória linear
      //     da meta ao longo do ano);
      //   • primeiro ano projetado sem nada disso: a meta do próprio ano.
      // Só a Selic REALIZADA de 12 meses entra como igualdade (a base medida acima).
      if (s.codigo === "CDI" && (!v || parcial(v, s.codigo))) {
        const selic = porSerieAno.get(`SELIC|${ano}`);
        const ehMeta = (x: { origem?: "focus" | "realizado" } | undefined) => x?.origem === "focus";
        if (selic && !parcial(selic, "SELIC")) {
          const refSelic = g.ref("macro:SELIC", ano);
          const antAno = g.anoAnterior(ano);
          const selicAnt = antAno === null ? undefined : porSerieAno.get(`SELIC|${antAno}`);
          const limite = "Aproximação a partir da META de fim de ano (o Focus não publica a taxa acumulada nem o CDI), "
            + "NÃO é o CDI realizado.";
          let formula = `=${refSelic}`;
          let nota: string;
          if (!ehMeta(selic)) {
            nota = `CDI de ${ano} = Selic realizada de ${ano} (célula acima, por fórmula): o CDI realizado ficou `
              + "IDÊNTICO à Selic em todo ano fechado de 2022 a 2025 (12,380 / 13,028 / 10,888 / 14,333). "
              + (v ? `O realizado de ${ano} cobre só ${v.meses} meses e não é taxa anual (${v.fonte}). ` : "")
              + `Selic: ${selic.fonte}`;
          } else if (v && v.meses !== undefined && ehMeta(selic)) {
            formula = `=((1+${v.valor}/100)*(1+${refSelic}/100)^((12-${v.meses})/12)-1)*100`;
            nota = `CDI de ${ano} = realizado de ${v.meses} meses (${v.valor.toLocaleString("pt-BR")}%, ${v.fonte}) `
              + `composto com os ${12 - v.meses} meses restantes à meta de Selic do fim de ${ano} (célula acima, Focus): `
              + `(1+realizado)×(1+meta)^((12−${v.meses})/12)−1. ${limite} Limite: os meses restantes usam a meta `
              + "do fim do ano, não a trajetória mês a mês.";
          } else if (ehMeta(selicAnt)) {
            formula = `=(${g.ref("macro:SELIC", antAno!)}+${refSelic})/2`;
            nota = `CDI de ${ano} = média das metas de Selic de fim de ${antAno} e ${ano} (Focus, células acima): `
              + `trajetória linear da meta ao longo do ano. ${limite} Limite: curva não linear de juros desvia dela.`;
          } else {
            nota = `CDI de ${ano} = meta de Selic do fim de ${ano} (Focus, célula acima), sem meta do ano anterior `
              + `para compor. ${limite} Limite: a meta de fim de ano fica ABAIXO do acumulado num ciclo de corte (SUBESTIMA o custo) e ACIMA num de alta (superestima). `
              + `Selic: ${selic.fonte}`;
          }
          g.set("macro:CDI", ano, formula, { fmt: NUM2, nota });
          continue;
        }
        if (v) {
          g.set("macro:CDI", ano, null, {
            nota: `O realizado de ${ano} cobre ${v.meses} meses (não é taxa anual) e não há Selic de ${ano} `
              + "completa nem Focus para usar de proxy. A célula fica VAZIA: a curva da dívida lê ZERO neste ano. "
              + `Origem: ${v.fonte}`,
          });
          continue;
        }
      }
      if (!v) {
        // AUSÊNCIA É AUSÊNCIA: célula vazia, e a nota diz o que falta. Repetir a
        // última observação conhecida projetaria uma expectativa que ninguém
        // publicou — e o modelo inteiro penduraria nela.
        g.set(`macro:${s.codigo}`, ano, null, {
          nota: `Sem observação nem expectativa publicada para ${s.codigo} em ${ano}. `
            + "A célula fica VAZIA de propósito: repetir o último valor conhecido seria "
            + "inventar expectativa.",
        });
        continue;
      }
      g.set(`macro:${s.codigo}`, ano, v.valor, {
        fmt: NUM2,
        nota: `Fonte: ${v.fonte}`
          + (s.codigo === "SELIC" && v.origem === "focus"
            ? ". ATENÇÃO: o valor projetado é a META de Selic no fim do ano (Focus), NÃO a taxa acumulada no ano "
              + "como o rótulo da linha sugere; o realizado é o acumulado."
            : ""),
      });
    }
  }
  g.pular();

  // ---- SÉRIES DERIVADAS, por FÓRMULA ---------------------------------------
  //
  // O Modelo Base tem 64 fórmulas nesta aba (índice de PIB base 1998=100,
  // crescimento nominal, correlações); a nossa tinha ZERO — só valor colado. O
  // índice acumulado abaixo é o que um modelo usa para trazer valor nominal a
  // real e vice-versa, e por ser fórmula ele acompanha qualquer revisão do Focus
  // sem ninguém recalcular à mão.
  //
  // A GUARDA `N()` É DELIBERADA e corrige o defeito mais caro da referência: lá a
  // série da Libor carrega o TEXTO "nd" a partir de 2021, e `=Anual!AC86/100`
  // virou #VALUE! que propagou por cinco tranches em moeda estrangeira até
  // apagar o NET PROFIT e o CHECK do balanço de 11 exercícios (§20.1 do mapa).
  // Aqui ano sem publicação fica VAZIO — nunca texto — e todo consumo tem N().
  if (porSerieAno.size > 0 && g.tem("macro:IPCA")) {
    g.linha("IPCA_INDICE", { rotulo: "IPCA — índice acumulado (base 100 no primeiro exercício)", fmt: NUM2 });
    g.linha("IPCA_FATOR", { rotulo: "IPCA — fator acumulado desde o primeiro exercício", fmt: NUM2 });
    for (const ano of ctx.anos) {
      const ant = g.anoAnterior(ano);
      const refIPCA = g.ref("macro:IPCA", ano);
      g.set("IPCA_INDICE", ano, ant === null ? 100 : `=${g.ref("IPCA_INDICE", ant)}*(1+N(${refIPCA})/100)`, {
        fmt: NUM2,
        nota: ant === null
          ? "Base 100 no primeiro exercício do horizonte."
          : "Índice do ano anterior corrigido pelo IPCA do ano. O N() trata ano sem publicação como "
            + "zero em vez de propagar erro — é a guarda que falta no Modelo Base.",
      });
      g.set("IPCA_FATOR", ano, `=${g.ref("IPCA_INDICE", ano)}/100`, { fmt: NUM2 });
    }
    g.pular();
  }

  const rNota = g.linha(null, {
    rotulo: "Realizado: BCB/IBGE (Supabase/seed/macro_carga_inicial.sql). Projetado: mediana do Focus, "
      + "coleta mais recente. Célula vazia = sem publicação para o ano — NUNCA texto como 'nd', "
      + "que é o que quebrou 11 exercícios do modelo de referência.",
  });
  g.celula(rNota, COL_ROTULO).font = { italic: true, size: 9 };
  g.finalizar();
  return g;
}

// =============================================================================
// ABA Premissas — o HISTÓRICO extraído, por bloco da DRE, com proveniência.
// É a aba que substitui os valores colados do referência.
// =============================================================================
/**
 * As premissas de CRESCIMENTO do caso, deduplicadas por código. Usada em dois
 * lugares — o painel da aba `Revenues` e o cockpit da aba `Premissas` — e por isso
 * mora aqui: as duas listas TÊM de ser a mesma, senão o cockpit publica endereço de
 * uma linha que não existe.
 */
function premissasDeCrescimentoDe(ctx: Ctx) {
  return [...new Map(
    [...ctx.premissaPorLinha.values()]
      .filter((p) => p.formula === "crescimento_composto" || p.formula === "indice_macro")
      .map((p) => [p.codigo, p] as const),
  ).values()].sort((a, b) => a.codigo.localeCompare(b.codigo));
}

/**
 * UM BOTÃO DO MODELO: uma célula que o analista pode mexer dentro do Excel e que
 * reprojeta o arquivo. O cockpit da aba `Premissas` publica um por linha.
 */
interface BotaoDoModelo {
  /** âncora da linha no cockpit */
  chave: string;
  rotulo: string;
  /** aba onde a célula editável mora */
  aba: string;
  /** âncora da linha naquela aba */
  alvo: string;
  fmt: string;
  /** o editável é a célula da COLUNA DE NOTA (dropdown de série macro), não a do ano */
  naNota?: boolean;
  /** texto curto de o que acontece ao mexer */
  efeito: string;
}

/**
 * A LISTA DE BOTÕES, decidida a partir do caso. Fica fora das abas porque o cockpit
 * precisa RESERVAR as linhas antes das abas de origem existirem (a `Premissas` é
 * construída em segundo lugar) — os endereços são preenchidos na costura de volta,
 * quando todas as grades já existem.
 */
function botoesDoModelo(ctx: Ctx): BotaoDoModelo[] {
  const b: BotaoDoModelo[] = [];
  for (const p of premissasDeCrescimentoDe(ctx)) {
    b.push({
      chave: `cock:serie:${p.codigo}`, rotulo: `${p.nome} — índice macro escolhido`,
      aba: "Revenues, COGS & SG&A", alvo: `pnl:${p.codigo}#serie`, fmt: PCT2, naNota: true,
      efeito: "troca a série que serve de base (dropdown: PIB, IPCA, IGPM, INPC, SELIC, CDI, câmbio ou nenhum)",
    });
    b.push({
      chave: `cock:spread:${p.codigo}`, rotulo: `${p.nome} — spread real sobre o índice`,
      aba: "Revenues, COGS & SG&A", alvo: `pnl:${p.codigo}#spread`, fmt: PCT2,
      efeito: "compõe com o índice: (1+índice)×(1+spread)−1, nunca soma",
    });
  }
  b.push(
    { chave: "cock:caixa", rotulo: "Caixa mínimo operacional", aba: "ST Inv. & Debt",
      alvo: "CAIXA_MIN", fmt: NUM,
      efeito: "piso de caixa; abaixo dele o revolver saca automaticamente" },
    { chave: "cock:spread_div", rotulo: "Spread da dívida existente", aba: "ST Inv. & Debt",
      alvo: "SPREAD_DIVIDA", fmt: PCT2, efeito: "compõe com o CDI da aba Anual e vira o custo efetivo" },
    { chave: "cock:spread_rev", rotulo: "Spread do revolver", aba: "ST Inv. & Debt",
      alvo: "SPREAD_REVOLVER", fmt: PCT2, efeito: "custo da dívida de emergência, que cobre o furo de caixa" },
    { chave: "cock:aplic", rotulo: "% do CDI recebido na aplicação", aba: "ST Inv. & Debt",
      alvo: "SPREAD_APLIC", fmt: PCT2, efeito: "rendimento do caixa excedente" },
    { chave: "cock:prazo_novo", rotulo: "Prazo da captação nova (anos)", aba: "ST Inv. & Debt",
      alvo: "EMISSAO_PRAZO", fmt: NUM2, efeito: "cada safra nova amortiza em parcelas iguais nesse prazo" },
    { chave: "cock:prazo_tranche", rotulo: "Prazo de amortização das tranches existentes (anos)",
      aba: "ST Inv. & Debt", alvo: "#prazo", fmt: NUM2,
      efeito: "SAC até o vencimento; nasce do prazo implícito no balanço, uma célula por tranche" },
    { chave: "cock:efeito_caixa", rotulo: "Efeito caixa da amortização (S/N), por tranche existente",
      aba: "ST Inv. & Debt", alvo: "#amort", fmt: NUM, naNota: true,
      efeito: "S = a amortização sai do caixa. N = o saldo cai SEM pagamento (reperfilamento) — a "
        + "alavanca de haircut/conversão em equity" },
    { chave: "cock:classe_reperfil", rotulo: "    …e o destino do que cai sem caixa (Equity/Haircut)",
      aba: "ST Inv. & Debt", alvo: "#classe", fmt: NUM, naNota: true,
      efeito: "só importa com Efeito caixa = N. Equity = vira capital, direto. Haircut = vira ganho no "
        + "resultado, fora do EBITDA" },
    { chave: "cock:nm_valor", rotulo: "New money — principal captado no fechamento",
      aba: "ST Inv. & Debt", alvo: "NM_VALOR", fmt: NUM,
      efeito: "captação do 1º ano projetado, com termo e prioridade próprios (não é refinanciamento)" },
    { chave: "cock:nm_prazo", rotulo: "New money — prazo de amortização (anos)",
      aba: "ST Inv. & Debt", alvo: "NM_PRAZO", fmt: NUM2, efeito: "SAC a partir do fim da carência" },
    { chave: "cock:nm_carencia", rotulo: "New money — carência (anos sem amortizar)",
      aba: "ST Inv. & Debt", alvo: "NM_CARENCIA", fmt: NUM2,
      efeito: "anos sem amortização antes do SAC do new money começar" },
    { chave: "cock:nm_spread", rotulo: "New money — spread negociado",
      aba: "ST Inv. & Debt", alvo: "NM_SPREAD", fmt: PCT2,
      efeito: "compõe com o CDI da aba Anual e vira o custo efetivo do new money" },
    { chave: "cock:nm_pik", rotulo: "New money — PIK (S/N)",
      aba: "ST Inv. & Debt", alvo: "NM_JUROS", fmt: NUM, naNota: true,
      efeito: "S = o juro capitaliza no saldo em vez de sair do caixa (mas ainda reduz o lucro "
        + "tributável). N = juro pago normalmente" },
    { chave: "cock:nm_prioridade", rotulo: "New money — prioridade frente à dívida existente",
      aba: "ST Inv. & Debt", alvo: "NM_VALOR", fmt: NUM, naNota: true,
      efeito: "informativo: Super sênior, Sênior, Pari passu ou Júnior" },
    { chave: "cock:vida_util", rotulo: "Vida útil média do imobilizado (anos)",
      aba: "Fixed Assets & CAPEX", alvo: "VIDA_UTIL", fmt: NUM2,
      efeito: "define a depreciação das safras de capex" },
    { chave: "cock:cov_alav", rotulo: "Covenant — Dívida Líquida / EBITDA (teto)", aba: "Output",
      alvo: "C_ND_EBITDA", fmt: MULT, efeito: "o teste de ROMPE/ok do ano lê esta célula" },
    { chave: "cock:cov_dscr", rotulo: "Covenant — DSCR (piso)", aba: "Output",
      alvo: "C_COBERTURA", fmt: MULT, efeito: "o teste de ROMPE/ok do ano lê esta célula" },
    { chave: "cock:cov_liq", rotulo: "Covenant — liquidez corrente (piso)", aba: "Output",
      alvo: "C_LIQ_CORR", fmt: MULT, efeito: "o teste de ROMPE/ok do ano lê esta célula" },
  );
  return b;
}

function abaPremissas(wb: ExcelJS.Workbook, ctx: Ctx): Grade {
  // A GRADE COBRE TODOS OS ANOS, não só os realizados. Os blocos de base histórica
  // continuam escrevendo apenas no realizado (as colunas projetadas ficam vazias, que
  // é a verdade sobre eles), mas o cockpit publica premissa de exercício PROJETADO —
  // e uma premissa de 2027 numa aba que só tem colunas de 2024 e 2025 ou não cabe ou
  // sai na coluna errada. Alinhar as colunas com as demais abas também deixa a leitura
  // lado a lado possível.
  const g = new Grade(wb, "Premissas", ctx.anos, ctx.nHist);
  // Cadeia de ano própria (`=<ano anterior>+1`), que é exatamente o que o Modelo
  // Base faz nesta aba (`Premissas!D4 = C4+1`). Ela não herda a raiz de data
  // porque é construída ANTES da aba de receita — e inverter a ordem faria a
  // receita referenciar uma aba que ainda não existe. A linha do título é sempre
  // a 1 desta aba (nada é escrito antes do cabeçalho).
  g.cabecalho("PREMISSAS — BASE HISTÓRICA EXTRAÍDA", `Valores em ${ctx.ent.unidade}`,
    (ano) => {
      const i = ctx.hist.indexOf(ano);
      return i <= 0 ? String(ano) : `=${g.letraDoAno(ctx.hist[i - 1])}1+1`;
    }, "0");

  // ===========================================================================
  // COCKPIT — TODO BOTÃO DO MODELO EM UMA TELA SÓ.
  //
  // POR QUE ELE EXISTE. O mecanismo de modelar dentro do Excel já funcionava — o
  // painel de índice × spread na aba de receita reprojeta a cascata inteira, e cada
  // aba tem suas células azuis. Só que ele estava ESPALHADO por sete abas de até 135
  // linhas, e uma alavanca que ninguém acha não é uma alavanca. Quem abre o arquivo
  // procurando "as premissas" abre a aba `Premissas` — que até aqui só trazia a base
  // histórica extraída, ou seja, o oposto do que o nome promete.
  //
  // O QUE ELE É. Uma linha por botão: o que é, quanto vale HOJE (por referência viva
  // à célula de origem — não é cópia, muda junto), em que ABA E CÉLULA se edita, e o
  // que acontece ao mexer. Não é documentação: os valores são fórmula, então um
  // cockpit desatualizado é impossível por construção.
  //
  // POR QUE NÃO SE EDITA AQUI. Excel não tem célula de mão dupla: ou o valor mora
  // aqui e as abas leem daqui, ou mora lá e este painel espelha. Mover as premissas
  // para cá quebraria a leitura de cada aba em pé (a de dívida deixaria de ser
  // legível sozinha) e é uma mudança de arquitetura que merece decisão própria. O
  // espelho com endereço entrega o essencial — achar a alavanca em cinco segundos —
  // sem esse custo.
  // ===========================================================================
  const botoes = botoesDoModelo(ctx);
  g.linha(null, {
    rotulo: "PAINEL DE MODELAGEM — as alavancas do arquivo, e onde fica cada uma",
    bloco: true, nota: "editar em",
  });
  g.linha("cock:ajuda", {
    rotulo: "Edite na ABA/CÉLULA indicada ao lado; o modelo reprojeta sozinho. Depois confira o "
      + "CHECK do balanço no topo das abas de driver: tem de continuar ZERO.",
  });
  for (const b of botoes) g.linha(b.chave, { rotulo: b.rotulo, fmt: b.fmt });
  g.pular();

  const bloco = (titulo: string, b: BlocoModelo, chaveTotal: string) => {
    // A CONVENÇÃO DE SINAL DO BLOCO FICA ESCRITA NO CABEÇALHO DELE. O leitor que
    // abre a planilha ao lado do PDF vê 67.000 aqui e −67.000 lá; sem a frase, a
    // única leitura possível é "a planilha está errada".
    g.linha(null, {
      rotulo: titulo, bloco: true,
      nota: ctx.blocosInvertidos.has(b)
        ? "magnitude positiva (documento: negativa)"
        : undefined,
    });
    const lista = ctx.linhasPorBloco.get(b) ?? [];
    for (const l of lista) {
      g.linha(chaveLinha(b, l), { rotulo: l.chave, nota: (l.documentos ?? []).join(" · "), fmt: NUM });
      for (const ano of ctx.hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (!e) {
          const n = notaSemValor(l, ano);
          if (n) g.set(chaveLinha(b, l), ano, null, { fmt: NUM, fill: FILL_HIST, nota: n });
          continue;
        }
        g.set(chaveLinha(b, l), ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota });
      }
    }
    g.linha(chaveTotal, { rotulo: `Total ${titulo.toLowerCase()}`, negrito: true, topo: true, fmt: NUM });
    for (const ano of ctx.hist) {
      if (lista.length === 0) { g.set(chaveTotal, ano, 0, { fmt: NUM, negrito: true }); continue; }
      // Soma CÉLULA A CÉLULA e não por intervalo: intervalo pegaria qualquer linha
      // que alguém insira no meio do bloco depois. Aqui a soma é dos rótulos que
      // o sistema classificou naquele bloco, e só deles.
      const termos = lista.map((l) => g.ref(chaveLinha(b, l), ano));
      g.set(chaveTotal, ano, `=${termos.join("+")}`, { fmt: NUM, negrito: true });
    }
    g.pular();
  };

  bloco("RECEITA BRUTA", "receita", "total:receita");
  bloco("DEDUÇÕES", "deducao", "total:deducao");
  bloco("CUSTOS", "custo", "total:custo");
  bloco("DESPESAS OPERACIONAIS (SG&A)", "sga", "total:sga");
  bloco("RESULTADO FINANCEIRO", "resultado_financeiro", "total:resultado_financeiro");
  bloco("TRIBUTOS SOBRE O LUCRO", "tributos", "total:tributos");
  g.finalizar();
  return g;
}

// =============================================================================
// ABA Revenues, COGS & SG&A — a cascata de receita e a formação de custo.
// Mesma mecânica do referência: cada bloco tem TRÊS linhas de premissa (Base,
// Cliente, Stress) e a linha ativa é `CHOOSE(cenário, base, cliente, stress)`.
// =============================================================================
function abaReceita(wb: ExcelJS.Workbook, ctx: Ctx, gPrem: Grade, gAnual: Grade): Grade {
  const g = new Grade(wb, "Revenues, COGS & SG&A", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  // `P01` — esta aba é a RAIZ do calendário do modelo, como no Modelo Base.
  const raiz = g.eixoRaiz(ctx.ultimoHist);
  g.cabecalho("RECEITA, CUSTOS E DESPESAS", `Valores em ${ctx.ent.unidade}`,
    (ano) => g.formulaEixo(ano, raiz, ctx.ultimoHist));
  // `CHECK` DO BALANÇO NO TOPO DO DRIVER (§5.3 do CONFORMIDADE.md).
  //
  // O Modelo Base publica a conferência do balanço no alto de cada aba de driver, e
  // o motivo é operacional: quem está mexendo na premissa de giro, de dívida ou de
  // capex está OLHANDO ESTA ABA — e é aqui que ele precisa saber se o modelo
  // continua fechando. Ter o CHECK só no `Balance Sheet` significa que a pessoa
  // muda um número, o balanço abre, e ela descobre isso quando (e se) trocar de aba.
  //
  // A célula é preenchida na costura de volta (`construirModeloInstitucional`),
  // porque o `Balance Sheet` é construído DEPOIS dos drivers — a linha existe aqui,
  // apontando para lá, e não o contrário: driver que soubesse calcular o balanço
  // seria o acoplamento que o espelho existe para evitar.
  g.linha("CHECK_MODELO", { rotulo: "CHECK do balanço (0 = fecha)", fmt: NUM2 });
  g.pular();
  const cen = g.celulaCenario;

  // ===========================================================================
  // PAINEL DE PREMISSAS — a modelagem passa a ser EDITÁVEL DENTRO DO EXCEL, com
  // os índices macro como base.
  //
  // O QUE MUDA. Até aqui, cada conta projetada por crescimento tinha o percentual
  // do portal DIGITADO na linha dela: para trocar a premissa era preciso voltar ao
  // portal, remodelar e exportar de novo. Os índices macro estavam na aba `Anual`,
  // versionados e certos, e nenhuma linha de crescimento os REFERENCIAVA — só a
  // correção por `indice_macro` fazia isso, e sem passar pelo dial de cenário.
  //
  // COMO FUNCIONA. Uma linha por premissa de crescimento, com três partes:
  //   • ÍNDICE BASE — célula de escolha (validação de lista com as séries da aba
  //     `Anual` mais "(nenhum)"). A linha mostra, ano a ano, o valor da série
  //     escolhida, por `INDEX/MATCH` sobre a `Anual`.
  //   • SPREAD REAL — premissa digitada, por ano (azul).
  //   • CRESCIMENTO NOMINAL — `(1+índice)×(1+spread)−1`, o mesmo `P15` do custo da
  //     dívida. Composição, não soma: somar erra por índice×spread, que a 5% e 4%
  //     já são 20 pontos-base.
  // As contas apontam para o resultado — mudar o índice na `Anual`, trocar a série
  // no dropdown ou mexer no spread reprojeta o modelo inteiro sem sair do arquivo.
  //
  // CALIBRAÇÃO QUE NÃO INVENTA NÚMERO: o spread nasce com o valor que REPRODUZ
  // exatamente a premissa escolhida no portal (índice "(nenhum)" → spread = a
  // própria premissa; premissa que já era macro → série dela e spread zero). Ou
  // seja, o arquivo abre com os mesmos números de antes e ganha o mecanismo. É a
  // mesma escolha do spread da dívida, que é derivado do custo medido em vez de
  // arbitrado.
  // ===========================================================================
  const premissasDeCrescimento = [...new Map(
    [...ctx.premissaPorLinha.values()]
      .filter((p) => p.formula === "crescimento_composto" || p.formula === "indice_macro")
      .map((p) => [p.codigo, p] as const),
  ).values()].sort((a, b) => a.codigo.localeCompare(b.codigo));

  const codigosMacro = SERIES_MACRO.map((s) => s.codigo).filter((c) => gAnual.tem(`macro:${c}`));
  const linhasMacro = codigosMacro.map((c) => gAnual.n(`macro:${c}`));
  const colCodigo = colLetra(COL_NOTA);
  const painel = new Map<string, string>(); // código da premissa → chave da linha de total

  if (premissasDeCrescimento.length > 0 && linhasMacro.length > 0) {
    g.linha(null, {
      rotulo: "PAINEL DE PREMISSAS — ÍNDICE MACRO × SPREAD (edite aqui e o modelo inteiro reprojeta)",
      bloco: true, nota: "escolha o índice",
    });
    for (const p of premissasDeCrescimento) {
      const base = `pnl:${p.codigo}`;
      const ehMacro = p.formula === "indice_macro" && codigosMacro.includes(p.codigo);
      const rSerie = g.linha(`${base}#serie`, {
        rotulo: `${p.nome} — índice base (da aba Anual)`, fmt: NUM2,
      });
      g.linha(`${base}#spread`, { rotulo: "    spread real sobre o índice", nota: "premissa", fmt: PCT });
      g.linha(`${base}#total`, { rotulo: "    = crescimento nominal aplicado", fmt: PCT });
      painel.set(p.codigo, `${base}#total`);

      // A célula de escolha da série, com validação de lista. Vive na coluna de
      // nota, ao lado do rótulo, pelo mesmo desenho da chave S/N por tranche.
      const cel = g.celula(rSerie, COL_NOTA);
      cel.value = ehMacro ? p.codigo : "(nenhum)";
      cel.fill = FILL_INPUT;
      cel.font = FONTE_ENTRADA;
      cel.alignment = { horizontal: "center" };
      cel.dataValidation = {
        type: "list", allowBlank: false,
        formulae: [`"(nenhum),${codigosMacro.join(",")}"`],
        showErrorMessage: true, errorTitle: "Índice base",
        error: `Escolha uma série da aba Anual (${codigosMacro.join(", ")}) ou "(nenhum)" para `
          + "esta premissa não seguir índice nenhum.",
      };
      cel.note = comoNota(
        "ÍNDICE BASE desta premissa. Escolhendo uma série, o crescimento passa a ser "
        + "(1+índice do ano)×(1+spread)−1 e acompanha qualquer revisão do Focus na aba Anual. "
        + "Com \"(nenhum)\", o índice vale zero e o spread carrega o crescimento inteiro — que é "
        + "como o arquivo nasce, reproduzindo exatamente a premissa escolhida no portal.",
      );

      for (const ano of ctx.anos) {
        // A ESCOLHA VIRA REFERÊNCIA POR `IF` ENCADEADO, e não por `INDEX/MATCH`.
        //
        // Duas razões, e a segunda é a que decide. (1) `INDEX/MATCH` sobre intervalo
        // de OUTRA aba é a forma idiomática, mas esconde a dependência: quem audita
        // não vê quais séries a célula pode ler. (2) O avaliador das suítes
        // (`avaliar-formula.mts`) segue referência entre abas mas NÃO intervalo entre
        // abas — com `INDEX/MATCH` ele devolvia "não sei", o `IFERROR` virava zero e o
        // teste da edição passava verde sem edição nenhuma. Fórmula que o teste não
        // consegue avaliar é fórmula sem prova, e este painel é justamente a promessa
        // que precisa de prova.
        //
        // O `0` do fim é o caso "(nenhum)": índice zero, spread carrega tudo.
        const expr = codigosMacro.reduceRight(
          (acc, cod) => `IF($${colCodigo}$${rSerie}="${cod}",`
            + `${Grade.refExterna("Anual", gAnual.letraDoAno(ano), gAnual.n(`macro:${cod}`))},${acc})`,
          "0",
        );
        g.set(`${base}#serie`, ano, `=${expr}`, {
          fmt: NUM2,
          nota: "Valor da série escolhida na célula ao lado, lido da aba Anual (realizado BCB/IBGE, "
            + "projetado Focus). Zero quando a escolha é \"(nenhum)\" ou o ano não tem publicação — "
            + "nunca erro, que propagaria para o modelo inteiro.",
        });
        const doPortal = p.valores[String(ano)];
        // O spread que reproduz a premissa do portal: com índice zero ele É a
        // premissa; com premissa macro, zero (o índice já é o crescimento).
        const spread = ehMacro ? 0 : (doPortal === undefined ? null : doPortal / 100);
        g.set(`${base}#spread`, ano, spread, {
          fmt: PCT, fill: FILL_INPUT,
          nota: ehMacro
            ? `Zero: esta premissa É a série ${p.codigo}, e o crescimento vem inteiro do índice. `
              + "Subir aqui é dizer que este caso cresce acima do índice."
            : doPortal === undefined
              ? `Premissa "${p.nome}" sem valor para ${ano} no portal — sem crescimento neste ano, `
                + "e o arquivo diz isso em vez de inventar."
              : `Calibrado para reproduzir a premissa "${p.nome}" (${doPortal}% em ${ano}) escolhida `
                + "no portal, com índice \"(nenhum)\". Escolhendo um índice, este número passa a ser o "
                + "ganho REAL sobre ele.",
        });
        g.set(`${base}#total`, ano,
          `=(1+N(${g.ref(`${base}#serie`, ano)})/100)*(1+${g.ref(`${base}#spread`, ano)})-1`, {
          fmt: PCT,
          nota: "Composição, não soma: (1+índice)×(1+spread)−1. É o mesmo P15 do custo da dívida — "
            + "somar as duas pontas subestima o crescimento em índice×spread.",
        });
      }
    }
    g.pular();
  }

  // ---- GROSS REVENUES ------------------------------------------------------
  g.linha("GROSS_REVENUES", { sinal: "+", rotulo: "GROSS REVENUES", bloco: true, fmt: NUM });
  const receitas = ctx.linhasPorBloco.get("receita") ?? [];
  for (const l of receitas) {
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    const ch = chaveLinha("receita", l);
    g.linha(ch, { rotulo: l.chave, nota: p ? p.nome : "(sem premissa — não projetada)", fmt: NUM });
    // três linhas de cenário por conta, como no referência
    g.linha(`${ch}#base`, { rotulo: "    Base Case", fmt: PCT });
    g.linha(`${ch}#cli`, { rotulo: "    Cliente Case", fmt: PCT });
    g.linha(`${ch}#str`, { rotulo: "    Stress Case", fmt: PCT });
  }
  g.linha("RECEITA_SEM_PREMISSA", {
    rotulo: "    (contas de receita sem premissa: mantidas constantes e sinalizadas)",
  });
  g.pular();

  // ---- DEDUÇÕES ------------------------------------------------------------
  g.linha("DEDUCOES", { sinal: "(-)", rotulo: "DEDUÇÕES", bloco: true, fmt: NUM });
  const deducoes = ctx.linhasPorBloco.get("deducao") ?? [];
  for (const l of deducoes) {
    const ch = chaveLinha("deducao", l);
    g.linha(ch, { rotulo: l.chave, nota: "% da receita bruta", fmt: NUM });
    g.linha(`${ch}#pct`, { rotulo: "    % Gross", fmt: PCT });
  }
  g.pular();

  g.linha("RECEITA_LIQUIDA", { sinal: "=", rotulo: "RECEITA LÍQUIDA", negrito: true, topo: true, fmt: NUM });
  g.linha("RECEITA_LIQUIDA_PCT", { rotulo: "    % da receita bruta", fmt: PCT });
  g.pular();

  // ---- CUSTOS --------------------------------------------------------------
  g.linha("CUSTOS", { sinal: "(-)", rotulo: "CUSTOS", bloco: true, fmt: NUM });
  const custos = ctx.linhasPorBloco.get("custo") ?? [];
  // `% da receita líquida` ligada a K contas do MESMO bloco é taxa do GRUPO (ver
  // `gruposRateados`); cada conta recebe a parcela histórica dela em `#part`.
  const saldoHistRec = (l: LinhaModelo) => valorNaEscala(l, ctx.ultimoHist, ctx.ent.unidade)?.valor ?? 0;
  // UM GRUPO POR CÓDIGO ENTRE CUSTO E SG&A: os dois blocos são medidos contra a MESMA base
  // (receita líquida), então o mesmo código ligado a contas de custo E de SG&A é UMA taxa de
  // UM grupo. Dois grupos (um por bloco) somavam 1 cada e o total saía 2× a premissa, sem
  // nota (em produção: MARKDOWN 2% em 7 contas de custo + 6 de SG&A projetava 4%).
  const sgaDoCaso = ctx.linhasPorBloco.get("sga") ?? [];
  const blocoCS = (l: LinhaModelo) => (custos.includes(l) ? "custo" : "sga");
  const rateioCS = gruposRateados(ctx, [...custos, ...sgaDoCaso], (l) => chaveLinha(blocoCS(l), l),
    "pct_de_linha", saldoHistRec);
  // Custo e SG&A declaram as MESMAS linhas por conta (valor, três cenários e, se a
  // conta está num grupo de rateio com saldo, a parcela) — um ponto só, para os dois
  // blocos não divergirem (e o Sonar reprovou a cópia: 12 linhas duplicadas).
  const declararContaCS = (bloco: "custo" | "sga", l: LinhaModelo) => {
    const ch = chaveLinha(bloco, l);
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    g.linha(ch, { rotulo: l.chave, nota: p ? p.nome : "(sem premissa)", fmt: NUM });
    g.linha(`${ch}#base`, { rotulo: "    Base Case", fmt: PCT });
    g.linha(`${ch}#cli`, { rotulo: "    Cliente Case", fmt: PCT });
    g.linha(`${ch}#str`, { rotulo: "    Stress Case", fmt: PCT });
    if (rateioCS.get(ch) && !rateioCS.get(ch)!.semSaldo) {
      g.linha(`${ch}#part`, { rotulo: "    Parcela da conta no grupo da premissa", fmt: PCT });
    }
  };
  for (const l of custos) declararContaCS("custo", l);
  g.linha("CUSTOS_PCT", { rotulo: "    % da receita líquida", fmt: PCT });
  g.pular();

  // ---- SG&A ----------------------------------------------------------------
  g.linha("SGA", { sinal: "(-)", rotulo: "SG&A", bloco: true, fmt: NUM });
  const sga = ctx.linhasPorBloco.get("sga") ?? [];
  for (const l of sga) declararContaCS("sga", l);
  g.linha("SGA_PCT", { rotulo: "    % da receita líquida", fmt: PCT });
  g.pular();

  g.linha("DEPRECIACAO", { sinal: "(+)", rotulo: "Depreciação (de Fixed Assets & CAPEX)", fmt: NUM });
  g.linha("EBITDA", { sinal: "=", rotulo: "EBITDA", negrito: true, topo: true, fmt: NUM });
  g.linha("EBITDA_MARGEM", { rotulo: "    Margem EBITDA (% receita líquida)", fmt: PCT });

  // ===========================================================================
  // AS TRÊS CASCATAS EM PARALELO — o bloco que faz os cenários serem comparáveis.
  //
  // O DEFEITO QUE ISTO FECHA (`Arquitetura do Sistema/4 Análises e Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md`, §2.2): o
  // arquivo tem UM interruptor de cenário (`Output!$G$2`) e todas as abas leem
  // dele por `CHOOSE`. Ter um interruptor só é a decisão certa — dois produziriam
  // um arquivo em dois cenários ao mesmo tempo, sem nada denunciar. A consequência
  // é que o arquivo mostra **um cenário por vez**, e a comparação base × cliente ×
  // stress — que é o motivo de existirem três — não estava em lugar nenhum.
  //
  // O QUE ENTRA AQUI, e a fronteira é a da CASCATA. Estas linhas recalculam, em
  // paralelo e sem olhar o interruptor, exatamente o que esta aba já sabe
  // calcular: receita, deduções, custos, SG&A e EBITDA. Ficam de fora ND/EBITDA,
  // DSCR e pico de caixa — eles exigiriam replicar a cascata de dívida e o fluxo
  // de caixa por cenário, isto é, três modelos paralelos dentro do arquivo, e cada
  // linha nova é uma chance de o arquivo que vai a comitê passar a mentir. O que
  // ficou fora está DITO na aba Output, ao lado do bloco, em vez de silenciado.
  //
  // POR QUE ESTAS LINHAS NÃO DUPLICAM A LÓGICA DA CASCATA ATIVA. Elas não são um
  // segundo cálculo: são o MESMO código emitindo fórmula quatro vezes, com o
  // cenário como parâmetro (`preencherConta` abaixo). Uma sombra escrita à parte
  // divergiria da linha ativa no primeiro dia em que alguém mexesse numa das duas
  // — e divergiria em silêncio, porque as duas continuariam produzindo números
  // plausíveis. Além disso o próprio arquivo confere: `CHECK_SOMBRA` mede a
  // distância entre a sombra do cenário ATIVO e a linha ativa, e ela é zero por
  // construção. Se aparecer diferente de zero, as duas se separaram.
  // ===========================================================================
  g.pular();
  g.linha("__sombra_titulo", {
    rotulo: "OS TRÊS CENÁRIOS EM NÚMERO (cascata paralela, não olha o interruptor)",
    bloco: true,
  });
  g.linha("CHECK_SOMBRA", {
    rotulo: "    CHECK: sombra do cenário ATIVO − linha ativa (0 = as duas concordam)",
    fmt: NUM,
    nota: "Se este número não for zero, a cascata paralela se separou da cascata ativa e o "
      + "bloco de comparação dos cenários deixou de descrever este modelo. Ele é zero por "
      + "construção: as duas saem do mesmo código, com o cenário como parâmetro.",
  });
  for (const [suf, nome] of CENARIOS_SUF) {
    g.pular();
    g.linha(`__sombra_${suf}`, { rotulo: `— ${nome} —`, bloco: true });
    for (const [bloco, lista] of [["receita", receitas], ["deducao", deducoes],
                                  ["custo", custos], ["sga", sga]] as const) {
      for (const l of lista) {
        g.linha(`${chaveLinha(bloco, l)}#v_${suf}`, { rotulo: `    ${l.chave}`, fmt: NUM });
      }
    }
    g.linha(`GROSS_REVENUES#v_${suf}`, { rotulo: "    Receita bruta", fmt: NUM });
    g.linha(`DEDUCOES#v_${suf}`, { rotulo: "    Deduções", fmt: NUM });
    g.linha(`RECEITA_LIQUIDA#v_${suf}`, { rotulo: "    Receita líquida", negrito: true, fmt: NUM });
    g.linha(`CUSTOS#v_${suf}`, { rotulo: "    Custos", fmt: NUM });
    g.linha(`SGA#v_${suf}`, { rotulo: "    SG&A", fmt: NUM });
    g.linha(`EBITDA#v_${suf}`, { rotulo: "    EBITDA", negrito: true, fmt: NUM });
    g.linha(`EBITDA_MARGEM#v_${suf}`, { rotulo: "    Margem EBITDA", fmt: PCT });
  }

  // ---------------------------------------------------------------- preencher
  const fmtCel = { fmt: NUM };

  // A FÓRMULA DE VALOR DE UMA CONTA, E ELA É UMA SÓ.
  //
  // Tanto a linha ATIVA (que decide por `CHOOSE` no interruptor) quanto as três
  // sombras do bloco de comparação saem desta função, com o cenário como
  // parâmetro. Escrever a sombra à parte seria o defeito clássico de duas
  // verdades: as duas divergiriam no primeiro dia em que alguém mexesse numa
  // delas, e divergiriam em SILÊNCIO, porque as duas continuariam produzindo
  // números plausíveis. O que fica fora daqui é só nota, cor e formato — que são
  // da linha ativa, a que a pessoa lê.
  //
  // `cenS === null` significa "a linha ativa".
  const alvoCen = (ch: string, cenS: CenSuf | null) => (cenS === null ? ch : `${ch}#v_${cenS}`);
  const taxaCen = (ch: string, ano: number, cenS: CenSuf | null) =>
    cenS === null
      ? `CHOOSE(${cen},${g.ref(`${ch}#base`, ano)},${g.ref(`${ch}#cli`, ano)},`
        + `${g.ref(`${ch}#str`, ano)})`
      : g.ref(`${ch}#${cenS}`, ano);

  const formulaConta = (
    bloco: "receita" | "custo" | "sga",
    l: LinhaModelo,
    ano: number,
    ant: number,
    cenS: CenSuf | null,
  ): string | null => {
    const ch = chaveLinha(bloco, l);
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    // A RAIZ DA SOMBRA É A LINHA ATIVA, e este detalhe é a diferença entre o bloco
    // funcionar e ele sair todo zero. As sombras existem só na projeção (o passado
    // é um), então no PRIMEIRO ano projetado o "ano anterior" da sombra é uma
    // célula que não existe — e uma referência a célula vazia vale zero em Excel,
    // silenciosamente: as três cascatas partiriam de zero e o comitê leria três
    // cenários de receita nula sem uma única célula vermelha. O ano anterior
    // histórico é lido da linha ATIVA, que é onde o realizado mora, e é o mesmo
    // número para os três cenários por definição.
    const anterior = g.ref(
      cenS !== null && !g.ehProjetado(ant) ? ch : alvoCen(ch, cenS), ant);
    // Conta sem premissa: constante. Vale para os três cenários igualmente — não
    // projetar é não projetar em cenário nenhum.
    if (!p) return `=${anterior}`;

    if (bloco !== "receita" && p.formula === "pct_de_linha") {
      // Taxa ligada a K contas é do GRUPO: a conta leva a parcela dela (`#part`).
      // Sem saldo para ratear a conta NÃO projeta (branco + nota na linha ativa) —
      // nunca divisão igual em silêncio.
      const gr = rateioCS.get(ch);
      if (gr?.semSaldo) return null;
      const parte = gr ? `*${g.ref(`${ch}#part`, ano)}` : "";
      return `=${taxaCen(ch, ano, cenS)}*${g.ref(alvoCen("RECEITA_LIQUIDA", cenS), ano)}${parte}`;
    }

    if (bloco !== "receita" && p.formula === "indice_macro" && !painel.get(p.codigo)) {
      // Caminho sem painel: a conta segue a série macro e é IMÓVEL entre cenários.
      // A sombra reproduz isso em vez de "consertar" — o bloco de comparação existe
      // para mostrar o modelo como ele é, e uma conta que não responde ao cenário é
      // exatamente o tipo de coisa que a comparação tem de deixar ver.
      const refMacro = gAnual.tem(`macro:${p.codigo}`)
        ? Grade.refExterna("Anual", gAnual.letraDoAno(ano), gAnual.n(`macro:${p.codigo}`))
        : null;
      return `=${anterior}*(1+${refMacro ? `N(${refMacro})/100` : g.ref(`${ch}#base`, ano)})`;
    }

    return `=${anterior}*(1+${taxaCen(ch, ano, cenS)})`;
  };

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);

    // --- receita por conta
    for (const l of receitas) {
      const ch = chaveLinha("receita", l);
      const p = ctx.premissaPorLinha.get(l.rotulo_norm);
      if (hist) {
        // Histórico aponta para a aba Premissas: UM lugar guarda o número
        // extraído, e o resto do modelo o referencia. Copiar o valor para cá
        // criaria uma segunda verdade sobre o mesmo fato.
        if (l.valores[String(ano)] !== undefined) {
          g.set(ch, ano, `=${g.externa("Premissas", gPrem, ch, ano)}`, { fmt: NUM, fill: FILL_HIST });
        }
        continue;
      }
      if (!p) {
        g.set(ch, ano, `=${g.ref(ch, ant!)}`, {
          fmt: NUM,
          nota: "Conta SEM premissa vinculada: mantida constante e listada na conferência. "
            + "O sistema não projeta o que ninguém escolheu projetar.",
        });
        continue;
      }
      const vBase = p.valores[String(ano)];
      // Premissa por ano: Base é o valor escolhido; Cliente ESPELHA o Base
      // (como no referência, `=J11`); Stress aplica o haircut declarado.
      //
      // COM PAINEL, o Base é FÓRMULA apontando para ele — é isso que faz o modelo
      // reprojetar quando alguém troca o índice ou o spread dentro do Excel. Sem
      // painel (premissa que não é de crescimento), continua sendo o número do
      // portal, digitado e azul.
      const doPainel = painel.get(p.codigo);
      g.set(`${ch}#base`, ano,
        doPainel ? `=${g.ref(doPainel, ano)}` : (vBase === undefined ? null : vBase / 100), {
        fmt: PCT, fill: doPainel ? undefined : FILL_INPUT,
        nota: doPainel
          ? `Vem do PAINEL DE PREMISSAS, no topo desta aba (premissa "${p.nome}"): índice macro × `
            + "spread. Para mudar a projeção, mexa lá — não aqui, senão a conta passa a discordar "
            + "das outras que usam a mesma premissa."
          : vBase === undefined
            ? `Premissa "${p.nome}" sem valor para ${ano} — a projeção deste ano fica sem crescimento `
              + "e o arquivo diz isso. Preencher no portal (Modelagem)."
            : `Premissa "${p.nome}" (${p.origem ?? "digitado"}) — ${vBase}% em ${ano}.`,
      });
      g.set(`${ch}#cli`, ano, `=${g.ref(`${ch}#base`, ano)}`, { fmt: PCT });
      g.set(`${ch}#str`, ano, `=${g.ref(`${ch}#base`, ano)}*(1-${refStress()})`, { fmt: PCT });
      g.set(ch, ano, formulaConta("receita", l, ano, ant!, null), fmtCel);
    }
    somaOuZero(g, "GROSS_REVENUES", ano, receitas.map((l) => g.ref(chaveLinha("receita", l), ano)), true);

    // --- deduções: % da receita bruta, travado no último histórico
    for (const l of deducoes) {
      const ch = chaveLinha("deducao", l);
      if (hist) {
        if (l.valores[String(ano)] !== undefined) {
          g.set(ch, ano, `=${g.externa("Premissas", gPrem, ch, ano)}`, { fmt: NUM, fill: FILL_HIST });
        }
        g.set(`${ch}#pct`, ano, `=IF(${g.ref("GROSS_REVENUES", ano)}<>0,${g.ref(ch, ano)}/${g.ref("GROSS_REVENUES", ano)},0)`, { fmt: PCT });
        continue;
      }
      // % do último histórico, mantido. É a convenção do referência (`=I24`) e é
      // a única honesta sem premissa própria: a carga tributária sobre venda não
      // se projeta por crescimento de receita.
      g.set(`${ch}#pct`, ano, `=${g.ref(`${ch}#pct`, ant!)}`, {
        fmt: PCT, fill: FILL_INPUT,
        nota: "Percentual da receita bruta mantido no nível do último exercício realizado. "
          + "Alterar aqui é premissa de carga tributária/devolução.",
      });
      g.set(ch, ano, `=${g.ref(`${ch}#pct`, ano)}*${g.ref("GROSS_REVENUES", ano)}`, fmtCel);
    }
    somaOuZero(g, "DEDUCOES", ano, deducoes.map((l) => g.ref(chaveLinha("deducao", l), ano)), true);

    g.set("RECEITA_LIQUIDA", ano, `=${g.ref("GROSS_REVENUES", ano)}-${g.ref("DEDUCOES", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("RECEITA_LIQUIDA_PCT", ano,
      `=IF(${g.ref("GROSS_REVENUES", ano)}<>0,${g.ref("RECEITA_LIQUIDA", ano)}/${g.ref("GROSS_REVENUES", ano)},0)`,
      { fmt: PCT });

    // --- custos e SG&A: % da receita líquida (variável) ou inflação (fixo)
    for (const [bloco, lista] of [["custo", custos], ["sga", sga]] as const) {
      for (const l of lista) {
        const ch = chaveLinha(bloco, l);
        const p = ctx.premissaPorLinha.get(l.rotulo_norm);
        if (hist) {
          if (l.valores[String(ano)] !== undefined) {
            g.set(ch, ano, `=${g.externa("Premissas", gPrem, ch, ano)}`, { fmt: NUM, fill: FILL_HIST });
          }
          continue;
        }
        if (!p) {
          g.set(ch, ano, `=${g.ref(ch, ant!)}`, {
            fmt: NUM, nota: "Conta sem premissa: mantida constante e sinalizada na conferência.",
          });
          continue;
        }
        const v = p.valores[String(ano)];
        const doPainel = painel.get(p.codigo);
        const notaP = doPainel
          ? `Vem do PAINEL DE PREMISSAS no topo desta aba (premissa "${p.nome}"): índice macro × `
            + "spread. Mexer lá reprojeta todas as contas que usam esta premissa; mexer aqui faria "
            + "esta conta discordar das outras."
          : v === undefined
            ? `Premissa "${p.nome}" sem valor para ${ano}.`
            : `Premissa "${p.nome}" (${p.origem ?? "digitado"}).`;
        const gr = rateioCS.get(ch);
        if (gr && p.formula === "pct_de_linha" && !gr.semSaldo) {
          g.set(`${ch}#part`, ano, formulaParcela(g, ch, gr.membros.map((o) => chaveLinha(blocoCS(o), o)), ctx.ultimoHist), {
            fmt: PCT, nota: notaParcela(p, gr, ctx.ultimoHist, "taxa × receita líquida"),
          });
        }
        if (p.formula === "pct_de_linha" || p.formula === "indice_macro" || p.formula === "crescimento_composto") {
          g.set(`${ch}#base`, ano,
            doPainel ? `=${g.ref(doPainel, ano)}` : (v === undefined ? null : v / 100),
            { fmt: PCT, fill: doPainel ? undefined : FILL_INPUT, nota: notaP });
          g.set(`${ch}#cli`, ano, `=${g.ref(`${ch}#base`, ano)}`, { fmt: PCT });
          // No STRESS, custo e despesa pioram: o haircut entra com sinal
          // invertido em relação à receita. Aplicar -20% num custo produziria um
          // cenário de estresse mais LUCRATIVO que o base, que é o erro clássico
          // de modelo de estresse feito por multiplicação cega.
          g.set(`${ch}#str`, ano, `=${g.ref(`${ch}#base`, ano)}*(1+${refStress()})`, {
            fmt: PCT,
            nota: "No Stress o custo PIORA: o haircut entra somando. Multiplicar custo por "
              + "(1-stress) faria o cenário ruim parecer melhor que o base.",
          });
        }
        // As três saídas saem do MESMO `formulaConta` que faz as sombras — a nota
        // do caminho macro continua aqui porque nota é da linha que a pessoa lê.
        if (p.formula === "indice_macro" && !doPainel) {
          g.set(ch, ano, formulaConta(bloco, l, ano, ant!, null), {
            fmt: NUM,
            nota: `Corrigido pela série ${p.codigo} da aba Anual (dado versionado, não digitado). `
              + "Sem painel de premissas, esta conta é IMÓVEL entre cenários — o bloco de "
              + "comparação dos três cenários mostra isso em vez de esconder.",
          });
        } else if (gr && p.formula === "pct_de_linha") {
          g.set(ch, ano, formulaConta(bloco, l, ano, ant!, null), {
            fmt: NUM,
            nota: gr.semSaldo
              ? notaGrupoSemSaldo(p, gr, ctx.ultimoHist,
                `o bloco de ${bloco === "custo" ? "custos" : "SG&A"} projeta MENOS do que a premissa indica `
                + "(taxa × receita líquida), pela parte inteira deste grupo.")
              : "Taxa do GRUPO × receita líquida × parcela histórica desta conta (linha #part).",
          });
        } else {
          g.set(ch, ano, formulaConta(bloco, l, ano, ant!, null), fmtCel);
        }
      }
    }
    somaOuZero(g, "CUSTOS", ano, custos.map((l) => g.ref(chaveLinha("custo", l), ano)), true);
    somaOuZero(g, "SGA", ano, sga.map((l) => g.ref(chaveLinha("sga", l), ano)), true);
    g.set("CUSTOS_PCT", ano, `=IF(${g.ref("RECEITA_LIQUIDA", ano)}<>0,${g.ref("CUSTOS", ano)}/${g.ref("RECEITA_LIQUIDA", ano)},0)`, { fmt: PCT });
    g.set("SGA_PCT", ano, `=IF(${g.ref("RECEITA_LIQUIDA", ano)}<>0,${g.ref("SGA", ano)}/${g.ref("RECEITA_LIQUIDA", ano)},0)`, { fmt: PCT });

    // ---- AS TRÊS SOMBRAS, e SÓ NA PROJEÇÃO.
    //
    // Histórico não tem cenário: o passado é um. Preencher as três colunas
    // históricas com o mesmo número três vezes convidaria a pessoa a procurar uma
    // diferença que não existe, e pior — no realizado o EBITDA reconcilia com o
    // documento, então a sombra e a linha ativa poderiam divergir por um motivo
    // legítimo e o CHECK acusaria um defeito que não há.
    if (!hist) {
      for (const [suf] of CENARIOS_SUF) {
        for (const [bl, lista] of [["receita", receitas], ["custo", custos], ["sga", sga]] as const) {
          for (const l of lista) {
            g.set(`${chaveLinha(bl, l)}#v_${suf}`, ano,
              formulaConta(bl, l, ano, ant!, suf), { fmt: NUM });
          }
        }
        somaOuZero(g, `GROSS_REVENUES#v_${suf}`, ano,
          receitas.map((l) => g.ref(`${chaveLinha("receita", l)}#v_${suf}`, ano)));

        // As deduções são % da receita BRUTA, e o percentual não depende de
        // cenário (é o último histórico, mantido) — o que muda é a base.
        for (const l of deducoes) {
          const chD = chaveLinha("deducao", l);
          g.set(`${chD}#v_${suf}`, ano,
            `=${g.ref(`${chD}#pct`, ano)}*${g.ref(`GROSS_REVENUES#v_${suf}`, ano)}`, { fmt: NUM });
        }
        somaOuZero(g, `DEDUCOES#v_${suf}`, ano,
          deducoes.map((l) => g.ref(`${chaveLinha("deducao", l)}#v_${suf}`, ano)));

        g.set(`RECEITA_LIQUIDA#v_${suf}`, ano,
          `=${g.ref(`GROSS_REVENUES#v_${suf}`, ano)}-${g.ref(`DEDUCOES#v_${suf}`, ano)}`,
          { fmt: NUM, negrito: true });
        somaOuZero(g, `CUSTOS#v_${suf}`, ano,
          custos.map((l) => g.ref(`${chaveLinha("custo", l)}#v_${suf}`, ano)));
        somaOuZero(g, `SGA#v_${suf}`, ano,
          sga.map((l) => g.ref(`${chaveLinha("sga", l)}#v_${suf}`, ano)));

        // EBITDA da sombra: na PROJEÇÃO o Income Statement calcula exatamente isto
        // (NET_REV − COGS − SG&A + D&A, com NET_REV = bruta − deduções e sem termo
        // de reconciliação, que só existe no realizado). A depreciação vem da aba
        // de ativo fixo e não depende de cenário.
        g.set(`EBITDA#v_${suf}`, ano,
          `=${g.ref(`RECEITA_LIQUIDA#v_${suf}`, ano)}-${g.ref(`CUSTOS#v_${suf}`, ano)}`
          + `-${g.ref(`SGA#v_${suf}`, ano)}+${g.ref("DEPRECIACAO", ano)}`,
          { fmt: NUM, negrito: true });
        g.set(`EBITDA_MARGEM#v_${suf}`, ano,
          `=IF(${g.ref(`RECEITA_LIQUIDA#v_${suf}`, ano)}<>0,`
          + `${g.ref(`EBITDA#v_${suf}`, ano)}/${g.ref(`RECEITA_LIQUIDA#v_${suf}`, ano)},0)`,
          { fmt: PCT });
      }

      // O CHECK: a sombra do cenário ATIVO menos a linha ativa, nas três
      // agregadas desta aba. Zero por construção — as quatro saem do mesmo
      // `formulaConta`. Diferente de zero significa que alguém separou as duas, e
      // aí o bloco de comparação dos cenários deixou de descrever este modelo.
      const dist = (chv: string) =>
        `ABS(CHOOSE(${cen},${CENARIOS_SUF.map(([su]) => g.ref(`${chv}#v_${su}`, ano)).join(",")})`
        + `-${g.ref(chv, ano)})`;
      g.set("CHECK_SOMBRA", ano,
        `=${["RECEITA_LIQUIDA", "CUSTOS", "SGA"].map(dist).join("+")}`,
        { fmt: NUM });
    }
  }

  // ===========================================================================
  // O CENÁRIO É DIFERENTE DO BASE? — a pergunta que o arquivo não respondia.
  //
  // O QUE ISTO DENUNCIA, e é um defeito de PRODUTO, não de código: o `Cliente
  // Case` nasce como `=<Base Case>` em TODA conta deste modelo (é a convenção do
  // Modelo Base, e está certa como ponto de partida). A consequência é que, num
  // arquivo recém-exportado, girar o dial de 1 para 2 não muda NADA — e nada no
  // arquivo diz isso. Um analista pode levar a um comitê um "Cliente Case" que é,
  // número por número, o Base Case, e a planilha não o contradiz.
  //
  // O Stress tem o problema espelhado: ele é o Base multiplicado por um haircut
  // único (`Considerações!$F$8`). Se alguém zerar aquela célula, o Stress vira o
  // Base e, de novo, o arquivo continua mostrando três cenários no dropdown.
  //
  // A MEDIDA É EXATA, não é heurística: para cada conta e cada exercício
  // projetado, `ABS(cenário − base)`. Zero em tudo significa premissas idênticas,
  // e nada mais pode significar. Somar as premissas (em vez das diferenças em
  // módulo) seria mais curto e ERRADO: dois conjuntos diferentes podem ter a
  // mesma soma, e aí o indicador diria "diferenciado" sobre um cenário que não é.
  //
  // A linha é por ANO porque a fórmula de todos os anos junta não caberia: são
  // uma conta por termo, e um caso com centenas de contas estoura o limite de
  // 8.192 caracteres de fórmula do Excel.
  // ===========================================================================
  const comCenario = g.chaves()
    .filter((k) => k.endsWith("#cli"))
    .map((k) => k.slice(0, -"#cli".length));
  g.pular();
  g.linha("DIF_CENARIO", {
    rotulo: "O CENÁRIO ESTÁ DIFERENCIADO DO BASE?", bloco: true,
  });
  g.linha("DIF_CENARIO#cli", {
    rotulo: "    Cliente Case — distância das premissas ao Base", fmt: PCT2,
    nota: "0 = idêntico ao Base",
  });
  g.linha("DIF_CENARIO#str", {
    rotulo: "    Stress Case — distância das premissas ao Base", fmt: PCT2,
    nota: "0 = idêntico ao Base",
  });
  for (const ano of ctx.anos) {
    if (!g.ehProjetado(ano)) continue;
    for (const [alvo, sufixo] of [["DIF_CENARIO#cli", "#cli"], ["DIF_CENARIO#str", "#str"]] as const) {
      const termos = comCenario.map(
        (ch) => `ABS(N(${g.ref(`${ch}${sufixo}`, ano)})-N(${g.ref(`${ch}#base`, ano)}))`,
      );
      // `N()` em cada ponta: célula VAZIA (conta sem premissa) vale zero aqui, e
      // sem ele a subtração de duas vazias ainda é 0 — mas a de uma vazia com um
      // texto seria `#VALUE!`, e um erro nesta linha apagaria o indicador inteiro.
      g.set(alvo, ano, termos.length > 0 ? `=${termos.join("+")}` : "=0", { fmt: PCT2 });
    }
  }

  // Esta aba nunca congelava nem tinha área de impressão — medido no arquivo
  // gerado (`congelado=False` na única aba que é a RAIZ do modelo).
  g.finalizar("__unidade");
  return g;
}

// O texto que explica a linha de reconciliação, na célula onde ela aparece. Fica
// aqui (e não inline) porque é a MESMA explicação nas cinco linhas de grupo, e
// cinco cópias divergiriam na primeira revisão.
const NOTA_RECONC = "Diferença entre o total que o DOCUMENTO informa para este grupo e a soma das "
  + "contas extraídas dele. Existe porque a extração pode traspor a mesma conta com dois rótulos "
  + "(medido no v35: 'Prejuízos acumulados' e 'Resultados Acumulados', ambos −39.150), deixar conta "
  + "fora de classificação, ou arredondar. É DADO A RECONCILIAR, não premissa: o número do grupo "
  + "segue o documento, e o tamanho do que não se explica fica escrito aqui. Mantida constante na "
  + "projeção — reprojetá-la seria projetar um erro de extração como se fosse conta.";

/**
 * Escreve a linha de reconciliação de um grupo do balanço (ver o comentário longo em
 * `abaBalanco`): no realizado, `informado − nossa soma`; no projetado, o valor do
 * último realizado, constante.
 *
 * O realizado é uma FÓRMULA (`informado − termos`), não um literal, para a linha
 * acompanhar qualquer correção nas contas: se amanhã a extração deixar de duplicar
 * "Resultados Acumulados", esta linha vai a zero sozinha e ninguém precisa lembrar
 * de mexer aqui. É o mesmo motivo pelo qual todo subtotal deste modelo é fórmula.
 */
function escreverReconc(
  g: Grade, ctx: Ctx, r: { chave: string; ancora: string } | null,
  ano: number, hist: boolean, ant: number | null, termos: string[],
): void {
  if (!r) return;
  if (!hist) {
    g.set(r.chave, ano, ant === null ? 0 : `=${g.ref(r.chave, ant)}`, {
      fmt: NUM2,
      nota: "Mantida constante: é o resíduo do REALIZADO. Reprojetá-la seria projetar um erro de "
        + "extração como se fosse conta; zerá-la na virada criaria um salto artificial no balanço.",
    });
    return;
  }
  const e = valorDaAncora(ctx, r.ancora, ano);
  if (!e) {
    g.set(r.chave, ano, 0, {
      fmt: NUM2,
      nota: "O documento deste exercício não informa o total deste grupo: nada a reconciliar, e o "
        + "grupo fica com a soma das contas extraídas.",
    });
    return;
  }
  const soma = termos.length > 0 ? termos.join("+") : "0";
  g.set(r.chave, ano, `=${e.valor}-(${soma})`, {
    fmt: NUM2,
    nota: `Total informado no documento para este grupo: ${e.valor.toLocaleString("pt-BR")}. `
      + `${e.nota}\n\n${NOTA_RECONC}`,
  });
}

/**
 * A reconciliação com o TOTAL GERAL do balanço (ativo / passivo+PL).
 *
 * Difere da de grupo em UMA coisa, e é a que a torna segura: ela exige que o
 * documento informe os DOIS totais gerais e que eles concordem entre si. É o
 * único caso em que "o documento fecha em X" é fato dele, e não escolha nossa —
 * `TOTAL DO ATIVO` e `TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO` são duas linhas
 * independentes dizendo o mesmo número. Faltando uma delas, ou discordando as
 * duas, o ajuste NÃO entra e o CHECK continua acusando: sem evidência dupla, o
 * modelo não tem como saber qual lado está certo, e escolher um seria inventar.
 */
function escreverReconcTotal(
  g: Grade, ctx: Ctx, r: { chave: string; ancora: string } | null,
  outraAncora: string, ano: number, hist: boolean, ant: number | null, termos: string[],
): void {
  if (!r) return;
  if (!hist) {
    g.set(r.chave, ano, ant === null ? 0 : `=${g.ref(r.chave, ant)}`, {
      fmt: NUM2,
      nota: "Mantida constante: é o resíduo do REALIZADO (ver a nota do exercício realizado).",
    });
    return;
  }
  const e = valorDaAncora(ctx, r.ancora, ano);
  const o = valorDaAncora(ctx, outraAncora, ano);
  if (!e || !o) {
    g.set(r.chave, ano, 0, {
      fmt: NUM2,
      nota: "O documento deste exercício não informa OS DOIS totais gerais (ativo e passivo+PL). "
        + "Sem as duas pontas não há evidência de quanto o balanço fecha, e nada é ajustado — o "
        + "CHECK abaixo mostra a diferença que sobra.",
    });
    return;
  }
  if (Math.abs(e.valor - o.valor) > 0.5) {
    g.set(r.chave, ano, 0, {
      fmt: NUM2,
      nota: `Os dois totais gerais informados DISCORDAM entre si (${e.valor.toLocaleString("pt-BR")} `
        + `× ${o.valor.toLocaleString("pt-BR")}): o próprio documento não fecha, ou a extração leu `
        + "um deles errado. Nada é ajustado — escolher um lado seria inventar o fechamento.",
    });
    return;
  }
  const soma = termos.length > 0 ? termos.join("+") : "0";
  g.set(r.chave, ano, `=${e.valor}-(${soma})`, {
    fmt: NUM2,
    nota: `Total geral informado no documento: ${e.valor.toLocaleString("pt-BR")}, confirmado pela `
      + `outra metade do balanço. ${e.nota}\n\n`
      + "Este resíduo é a diferença entre os totais de GRUPO informados e o total GERAL informado — "
      + "os dois vêm do mesmo documento e não somam entre si. É dado a reconciliar com quem "
      + "produziu o documento, não premissa.",
  });
}

/** Soma célula a célula, ou zero explícito quando o bloco está vazio. */
function somaOuZero(g: Grade, chave: string, ano: number, termos: string[], negrito = false) {
  if (termos.length === 0) {
    g.set(chave, ano, 0, {
      fmt: NUM, negrito,
      nota: "Nenhuma linha do caso caiu neste bloco. Zero EXPLÍCITO: célula vazia num "
        + "subtotal pareceria dado faltando, e num modelo de crédito as duas coisas têm "
        + "consequências diferentes.",
    });
    return;
  }
  // Soma por termos, não por intervalo: as linhas do bloco não são
  // necessariamente contíguas (cada conta tem 3 linhas de cenário embaixo dela),
  // e SUM de intervalo somaria os percentuais junto dos valores.
  g.set(chave, ano, `=${termos.join("+")}`, { fmt: NUM, negrito });
}

/** Referência absoluta à célula do haircut de stress (mora em Considerações). */
function refStress(): string { return `Considerações!$F$8`; }

/**
 * `P02 CABEÇALHO-HERDADO` — o eixo do tempo de qualquer aba que não seja a raiz.
 * Aponta para a linha de título da aba de receita, que é onde o calendário nasce.
 *
 * No Modelo Base cada par de abas carrega um DESLOCAMENTO de coluna diferente
 * (§2.2 do mapa), e é dali que sai o erro de ler o ano errado. Aqui a coluna é a
 * mesma nas 14 abas, então a herança é sempre "mesma coluna, linha do título".
 */
function eixoHerdado(gRec: Grade): (ano: number) => string {
  return (ano) => `=${Grade.refExterna("Revenues, COGS & SG&A", gRec.letraDoAno(ano), gRec.n("__titulo"))}`;
}

// =============================================================================
// ABA Income Statement — a DRE completa. Todo subtotal é FÓRMULA: é o que faz o
// modelo se mover quando a premissa muda, e é o que impede o subtotal de
// discordar das partes (o defeito que a Fase 8 fechou na tela de Modelagem).
// =============================================================================
function abaDRE(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade, gPrem: Grade, gDiv: Grade): Grade {
  const g = new Grade(wb, "Income Statement", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("INCOME STATEMENT", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));

  // MODELO SEM DRE NÃO PASSA POR MODELO COM DRE ZERADA.
  //
  // Se nenhuma linha do caso cai nos blocos de resultado — acontece quando a
  // extração não trouxe `secao_canonica` (medido na cadeia do book: 767 campos,
  // todos sem seção canônica) — esta aba sai inteira em zero. Zero em toda a
  // cascata parece "empresa sem operação", que é uma afirmação sobre o negócio;
  // o fato é "o modelo não recebeu a DRE". As duas coisas não podem ter a mesma
  // aparência num arquivo que vai a comitê.
  const semResultado = ["receita", "custo", "sga"]
    .every((b) => (ctx.linhasPorBloco.get(b as BlocoModelo) ?? []).length === 0);
  if (semResultado) {
    const rAviso = g.linha(null, {
      rotulo: "SEM DRE: nenhuma linha deste caso caiu nos blocos de receita, custo ou despesa — "
        + "a cascata abaixo sai TODA em zero. Isso NÃO significa empresa sem operação: significa "
        + "que a extração não classificou as linhas de resultado (secao_canonica ausente). "
        + "Confira a aba 'Dados (linha a linha)' e a de revisão antes de usar qualquer número daqui.",
    });
    g.celula(rAviso, COL_ROTULO).fill = FILL_CHECK_ERRO;
    g.celula(rAviso, COL_ROTULO).font = fonte({ bold: true });
    g.pular();
  }

  g.linha("GROSS", { sinal: "+", rotulo: "GROSS REVENUES", negrito: true, fmt: NUM });
  g.linha("DEDUC", { sinal: "(-)", rotulo: "Deductions", fmt: NUM });
  // AS RECONCILIAÇÕES DA DRE — o mesmo desenho do balanço, pelo mesmo motivo.
  //
  // O QUE ACONTECIA: a cascata soma as CONTAS extraídas e o documento imprime os
  // SUBTOTAIS dele; extração real repete conta com dois rótulos, perde conta e
  // classifica conta de resultado fora dos blocos, então os dois nunca batem. No
  // v35 a DRE do modelo saía com EBIT 7.509 acima e resultado líquido 18.460
  // acima do que o próprio documento informa — e a linha de conferência acusava,
  // sem que nada no modelo fosse corrigido. Modelo que não reproduz o realizado
  // do documento não serve para projetar a partir dele: a base já está errada.
  //
  // Cada nível que o documento informa ganha um resíduo DECLARADO, e o total
  // daquele nível passa a ser o do documento por construção. O resíduo é
  // constante na projeção (mesma doutrina do balanço: zerá-lo na virada criaria
  // um salto artificial), e o seu tamanho é o que diz se a extração está boa —
  // é por isso que ele é uma LINHA, e não um ajuste escondido na fórmula.
  const recDRE = (chave: string, ancora: string) => ctx.ancoras.has(ancora)
    ? { chave: `RECONC_${chave}`, ancora } : null;
  const rNetRev = recDRE("NET_REV", "DOC_RECEITA_LIQUIDA");
  const rGrossProfit = recDRE("GROSS_PROFIT", "DOC_LUCRO_BRUTO");
  const rEbit = recDRE("EBIT", "DOC_EBIT");
  const rNetProfit = recDRE("NET_PROFIT", "DOC_LUCRO_LIQUIDO");
  const linhaRecDRE = (r: { chave: string; ancora: string } | null, oQue: string) => {
    if (!r) return;
    g.linha(r.chave, {
      rotulo: `    reconciliação com ${oQue} informado no documento`, fmt: NUM2,
      nota: "dado a reconciliar",
    });
  };

  linhaRecDRE(rNetRev, "a receita líquida");
  g.linha("NET_REV", { sinal: "=", rotulo: "NET REVENUES", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("COGS", { sinal: "(-)", rotulo: "COGS", fmt: NUM });
  linhaRecDRE(rGrossProfit, "o lucro bruto");
  g.linha("GROSS_PROFIT", { sinal: "=", rotulo: "GROSS PROFIT", negrito: true, topo: true, fmt: NUM });
  g.linha("GROSS_MARGIN", { rotulo: "    % margem bruta", fmt: PCT });
  g.pular();
  g.linha("SGA", { sinal: "(-)", rotulo: "SG&A", fmt: NUM });
  g.linha("EBITDA", { sinal: "=", rotulo: "EBITDA", negrito: true, topo: true, fmt: NUM });
  g.linha("EBITDA_MARGIN", { rotulo: "    % margem EBITDA", fmt: PCT });
  g.pular();
  g.linha("DA", { sinal: "(-)", rotulo: "Depreciation and Amortization", fmt: NUM });
  linhaRecDRE(rEbit, "o EBIT");
  g.linha("EBIT", { sinal: "=", rotulo: "EBIT", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("FIN_RESULT", { sinal: "+", rotulo: "Financial Result", fmt: NUM });
  g.linha("FIN_EXP", { rotulo: "    Financial Expenses (juros da dívida)", fmt: NUM });
  g.linha("FIN_INC", { rotulo: "    Financial Income (rendimento do caixa)", fmt: NUM });
  g.linha("FIN_OUTROS", { rotulo: "    Outros resultados financeiros (histórico)", fmt: NUM });
  g.pular();
  // GANHO COM HAIRCUT — a chave "#classe = Haircut" de uma tranche da aba de
  // dívida (junto com "Efeito caixa? = N") faz o saldo cair sem contrapartida
  // em equity. Contabilmente é o que um perdão/redução negociada de dívida é:
  // ganho no resultado, abaixo do EBITDA porque não é desempenho operacional
  // — é reestruturação financeira. Fica em linha própria, não escondida dentro
  // do "Financial Result", porque um ganho não-recorrente de renegociação e um
  // resultado financeiro recorrente são leituras diferentes para o comitê.
  g.linha("GANHO_HAIRCUT", {
    rotulo: "Ganho com redução negociada de dívida (haircut, não-caixa, fora do EBITDA)", fmt: NUM,
  });
  g.pular();
  g.linha("EBT", { sinal: "=", rotulo: "EBT", negrito: true, topo: true, fmt: NUM });
  g.linha("TAX", { sinal: "(-)", rotulo: "Income tax", fmt: NUM });
  g.linha("TAX_RATE", { rotulo: "    Alíquota efetiva aplicada", fmt: PCT });
  g.pular();
  linhaRecDRE(rNetProfit, "o resultado líquido");
  g.linha("NET_PROFIT", { sinal: "=", rotulo: "NET PROFIT", negrito: true, topo: true, fmt: NUM });
  g.linha("NET_MARGIN", { rotulo: "    % margem líquida", fmt: PCT });

  // ---- CONFERÊNCIA CONTRA O DOCUMENTO --------------------------------------
  //
  // O invariante nº 9 do `verificar-export` ("nosso número == o número do
  // documento") vale para as abas analíticas desde o teste v25. O modelo
  // institucional era a única parte do arquivo sem ele — e foi exatamente ali que
  // um erro de convenção de sinal transformou, no arquivo entregue ao dono,
  // prejuízo de 17.901 em lucro de 268.041 sem uma única célula vermelha.
  //
  // As quatro linhas de resultado que TODA DRE publica são conferidas no
  // realizado, contra as âncoras extraídas do próprio documento (`ANCORAS_DOC`).
  // Onde o documento não informa a linha, a conferência DIZ que não informa em vez
  // de sair verde por ausência de comparação — "não sei" e "confere" não podem ter
  // a mesma cor.
  const CONFERIR: ReadonlyArray<{ chave: string; ancora: string; rotulo: string }> = [
    { chave: "NET_REV", ancora: "DOC_RECEITA_LIQUIDA", rotulo: "Receita líquida" },
    { chave: "GROSS_PROFIT", ancora: "DOC_LUCRO_BRUTO", rotulo: "Lucro bruto" },
    { chave: "EBIT", ancora: "DOC_EBIT", rotulo: "EBIT" },
    { chave: "NET_PROFIT", ancora: "DOC_LUCRO_LIQUIDO", rotulo: "Resultado líquido" },
  ];
  const conferiveis = CONFERIR.filter((c) => ctx.ancoras.has(c.ancora));
  g.pular();
  g.linha(null, {
    rotulo: "CONFERÊNCIA CONTRA O DOCUMENTO (exercícios realizados)", bloco: true,
    nota: conferiveis.length > 0 ? "diferença tem de ser ZERO" : "documento não informa totais",
  });
  for (const c of conferiveis) {
    g.linha(`DOC_${c.chave}`, { rotulo: `    ${c.rotulo} — informado no documento`, fmt: NUM });
    g.linha(`DIF_${c.chave}`, { rotulo: `    diferença (modelo − documento)`, fmt: NUM2 });
  }
  const rSemAncora = conferiveis.length === 0
    ? g.linha("CONF_SEM_ANCORA", {
      rotulo: "    O documento extraído não traz nenhuma linha de resultado (Receita Líquida, "
        + "Lucro Bruto, EBIT, Resultado do Exercício): NÃO HÁ contra o que conferir a DRE deste "
        + "modelo. Isto é ausência de conferência, não conferência bem-sucedida.",
    })
    : null;
  const rConfTxt = conferiveis.length > 0 ? g.linha("CONF_TXT", { rotulo: "    diagnóstico" }) : null;

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("GROSS", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "GROSS_REVENUES", ano)}`, { fmt: NUM, negrito: true });
    g.set("DEDUC", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "DEDUCOES", ano)}`, { fmt: NUM });
    escreverReconc(g, ctx, rNetRev, ano, hist, ant,
      [`${g.ref("GROSS", ano)}-${g.ref("DEDUC", ano)}`]);
    g.set("NET_REV", ano,
      `=${[`${g.ref("GROSS", ano)}-${g.ref("DEDUC", ano)}`,
           ...(rNetRev ? [g.ref(rNetRev.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });
    g.set("COGS", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "CUSTOS", ano)}`, { fmt: NUM });
    escreverReconc(g, ctx, rGrossProfit, ano, hist, ant,
      [`${g.ref("NET_REV", ano)}-${g.ref("COGS", ano)}`]);
    g.set("GROSS_PROFIT", ano,
      `=${[`${g.ref("NET_REV", ano)}-${g.ref("COGS", ano)}`,
           ...(rGrossProfit ? [g.ref(rGrossProfit.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });
    g.set("GROSS_MARGIN", ano, `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref("GROSS_PROFIT", ano)}/${g.ref("NET_REV", ano)},0)`, { fmt: PCT });
    g.set("SGA", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "SGA", ano)}`, { fmt: NUM });
    // EBITDA = lucro bruto - SG&A + depreciação que está DENTRO de custo/despesa.
    // Somar a depreciação de volta é o passo que a maioria dos modelos erra: sem
    // ele, "EBITDA" é EBIT com outro nome, e a alavancagem sai otimista.
    g.set("EBITDA", ano,
      `=${g.ref("GROSS_PROFIT", ano)}-${g.ref("SGA", ano)}+${g.externa("Revenues, COGS & SG&A", gRec, "DEPRECIACAO", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("EBITDA_MARGIN", ano, `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref("EBITDA", ano)}/${g.ref("NET_REV", ano)},0)`, { fmt: PCT });
    g.set("DA", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "DEPRECIACAO", ano)}`, { fmt: NUM });
    escreverReconc(g, ctx, rEbit, ano, hist, ant,
      [`${g.ref("EBITDA", ano)}-${g.ref("DA", ano)}`]);
    g.set("EBIT", ano,
      `=${[`${g.ref("EBITDA", ano)}-${g.ref("DA", ano)}`,
           ...(rEbit ? [g.ref(rEbit.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });
    g.set("FIN_RESULT", ano, `=${g.ref("FIN_EXP", ano)}+${g.ref("FIN_INC", ano)}+${g.ref("FIN_OUTROS", ano)}`, { fmt: NUM });
    g.set("GANHO_HAIRCUT", ano, hist ? 0 : `=${g.externa("ST Inv. & Debt", gDiv, "TOTAL_AMORT_HAIRCUT", ano)}`, {
      fmt: NUM,
      nota: hist
        ? "Zero no realizado: haircut é alavanca de negociação, não fato do balanço histórico."
        : "Soma da amortização SEM caixa das tranches marcadas \"Efeito caixa? = N\" e "
          + "\"classificação = Haircut\" na aba de dívida. Fora do EBITDA porque não é operação — é "
          + "renegociação financeira —, mas sujeito a imposto como qualquer outro resultado.",
    });
    g.set("EBT", ano, `=${g.ref("EBIT", ano)}+${g.ref("FIN_RESULT", ano)}+${g.ref("GANHO_HAIRCUT", ano)}`,
      { fmt: NUM, negrito: true });
    // TRIBUTO SÓ SOBRE LUCRO POSITIVO. Aplicar a alíquota sobre prejuízo geraria
    // "crédito" de imposto entrando como caixa — num mandato de reestruturação,
    // que é o caso de uso deste modelo, isso é o erro mais provável e o mais
    // otimista possível. Prejuízo fiscal a compensar é decisão tributária, não
    // subproduto de uma fórmula.
    g.set("TAX_RATE", ano, hist ? null : ctx.ent.aliquotaTributos, {
      fmt: PCT, fill: hist ? undefined : FILL_INPUT,
      nota: hist ? undefined
        : "Alíquota efetiva sobre o EBT POSITIVO. Prejuízo não gera crédito automático: "
          + "compensação de prejuízo fiscal é decisão tributária e entra como premissa própria.",
    });
    // RESULTADO FINANCEIRO. No realizado vem da extração (aba Premissas); no
    // projetado, da aba de dívida — juros e rendimento calculados, não repetidos.
    if (hist) {
      g.set("FIN_EXP", ano, 0, { fmt: NUM });
      g.set("FIN_INC", ano, 0, { fmt: NUM });
      g.set("FIN_OUTROS", ano, `=${g.externa("Premissas", gPrem, "total:resultado_financeiro", ano)}`, {
        fmt: NUM,
        nota: "Resultado financeiro REALIZADO, como extraído. Não é decomposto em juros e "
          + "rendimento porque o documento não decompõe — e inventar a divisão daria dois "
          + "números que não estão em documento nenhum.",
      });
      g.set("TAX", ano, `=${g.externa("Premissas", gPrem, "total:tributos", ano)}`, {
        fmt: NUM, nota: "Tributo REALIZADO, extraído da DRE.",
      });
    } else {
      g.set("FIN_EXP", ano, `=${g.externa("ST Inv. & Debt", gDiv, "DESP_FIN", ano)}`, { fmt: NUM });
      g.set("FIN_INC", ano, `=${g.externa("ST Inv. & Debt", gDiv, "REC_FIN", ano)}`, { fmt: NUM });
      g.set("FIN_OUTROS", ano, 0, {
        fmt: NUM,
        nota: "Zero no projetado: juros e rendimento já estão nas duas linhas acima. Repetir "
          + "aqui o 'outros' do histórico contaria despesa financeira duas vezes.",
      });
      g.set("TAX", ano, `=-MAX(0,${g.ref("EBT", ano)})*${g.ref("TAX_RATE", ano)}`, { fmt: NUM });
    }
    escreverReconc(g, ctx, rNetProfit, ano, hist, ant,
      [`${g.ref("EBT", ano)}+${g.ref("TAX", ano)}`]);
    g.set("NET_PROFIT", ano,
      `=${[`${g.ref("EBT", ano)}+${g.ref("TAX", ano)}`,
           ...(rNetProfit ? [g.ref(rNetProfit.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });
    g.set("NET_MARGIN", ano, `=IF(${g.ref("NET_REV", ano)}<>0,${g.ref("NET_PROFIT", ano)}/${g.ref("NET_REV", ano)},0)`, { fmt: PCT });

    // ---- a conferência, ano a ano -------------------------------------------
    for (const c of conferiveis) {
      const e = hist ? valorDaAncora(ctx, c.ancora, ano) : null;
      if (!hist) {
        g.set(`DOC_${c.chave}`, ano, null, {
          nota: "Exercício projetado: não há documento contra o que conferir.",
        });
        g.set(`DIF_${c.chave}`, ano, null, {});
        continue;
      }
      if (!e) {
        g.set(`DOC_${c.chave}`, ano, null, {
          nota: `O documento deste exercício não informa "${c.rotulo}". Sem informado não há `
            + "diferença a calcular, e a célula fica vazia em vez de fingir conferência.",
        });
        g.set(`DIF_${c.chave}`, ano, null, {});
        continue;
      }
      g.set(`DOC_${c.chave}`, ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota, tipo: "calc" });
      g.set(`DIF_${c.chave}`, ano, `=${g.ref(c.chave, ano)}-${g.ref(`DOC_${c.chave}`, ano)}`, {
        fmt: NUM2,
        nota: "Modelo menos documento. Qualquer coisa diferente de zero significa que a cascata "
          + "desta aba não reproduz a DRE extraída — convenção de sinal, conta fora do bloco ou "
          + "dupla contagem. É o teste que pega o erro antes do comitê.",
      });
    }
    if (rConfTxt !== null) {
      const termos = conferiveis.map((c) => `ABS(${g.ref(`DIF_${c.chave}`, ano)})`).join("+");
      g.set("CONF_TXT", ano,
        hist
          ? `=IF(COUNT(${conferiveis.map((c) => g.ref(`DOC_${c.chave}`, ano)).join(",")})=0,`
            + `"documento não informa",IF(${termos}<0.5,"confere com o documento",`
            + `"DIVERGE do documento em "&TEXT(${termos},"#,##0")))`
          : "=\"projetado — sem documento\"",
        {});
    }
  }

  // Verde só quando a diferença é zero; vermelho quando não; e a linha de "sem
  // âncora" fica CINZA-AVISO, porque ausência de conferência não é aprovação.
  if (conferiveis.length > 0) {
    const colIni = colLetra(COL_PRIMEIRO_ANO);
    const colFim = colLetra(COL_PRIMEIRO_ANO + ctx.anos.length - 1);
    for (const c of conferiveis) {
      const linha = g.n(`DIF_${c.chave}`);
      g.ws.addConditionalFormatting({
        ref: `${colIni}${linha}:${colFim}${linha}`,
        rules: [
          { type: "expression", formulae: [`ABS(${colIni}${linha})>0.5`], style: { fill: FILL_CHECK_ERRO }, priority: 1 },
          { type: "expression", formulae: [`ISNUMBER(${colIni}${linha})`], style: { fill: FILL_CHECK_OK }, priority: 2 },
        ],
      });
    }
    if (rConfTxt !== null) {
      g.ws.addConditionalFormatting({
        ref: `${colIni}${rConfTxt}:${colFim}${rConfTxt}`,
        rules: [
          { type: "containsText", operator: "containsText", text: "DIVERGE", style: { fill: FILL_CHECK_ERRO }, priority: 1 },
          { type: "containsText", operator: "containsText", text: "confere", style: { fill: FILL_CHECK_OK }, priority: 2 },
        ],
      });
    }
  } else if (rSemAncora !== null) {
    g.celula(rSemAncora, COL_ROTULO).fill = FILL_CHECK_ERRO;
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Working Capital — cada conta de giro é `dias / 360 × receita líquida`.
// 360 e não 365: é o ano comercial, que é o que os contratos e os covenants usam.
// =============================================================================
function abaCapitalGiro(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade): Grade {
  const g = new Grade(wb, "Working Capital", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("WORKING CAPITAL", `Valores em ${ctx.ent.unidade} · dias de giro sobre a linha de DRE correspondente`, eixoHerdado(gRec));
  g.linha("CHECK_MODELO", { rotulo: "CHECK do balanço (0 = fecha)", fmt: NUM2 });
  g.pular();
  const cen = g.celulaCenario;

  // O CAIXA NÃO ENTRA NO GIRO — ver `PADROES_CAIXA`. É a correção da dupla
  // contagem aberta desde a sessão 32, e é o que o Modelo Base faz.
  const ativos = (ctx.linhasPorBloco.get("ativo_circulante") ?? [])
    .filter((l) => !ehImobilizado(l.chave) && !ehCaixa(l.chave));
  const caixaFora = (ctx.linhasPorBloco.get("ativo_circulante") ?? []).filter((l) => ehCaixa(l.chave));
  // O estoque é giro (fica aqui), mas é identificado à parte porque a LIQUIDEZ
  // SECA do Output precisa dele: num mandato de reestruturação o estoque é o
  // ativo circulante que menos vira caixa.
  const estoques = ativos.filter((l) => ehEstoque(l.chave));
  // CLIENTES, pela mesma razão e para o mesmo destino: o CICLO DE CAIXA do
  // `Output` precisa do recebível isolado. `Arquitetura do Sistema/2 Especificação/f0/08` lista PMR/PME/PMP como
  // faseados "até a extração isolar as linhas-conceito" — e o giro já as isola
  // aqui para aplicar dias, então o que faltava era publicar o espelho.
  const clientes = ativos.filter((l) => ehCliente(l.chave));
  // A dívida bancária de curto prazo também não é giro: ela vive no
  // `ST Inv. & Debt`. Deixá-la aqui faria o passivo operacional carregar dívida,
  // e a NCG passaria a "melhorar" quando a empresa se endivida mais.
  // TRIBUTO A RECOLHER SAI DO GIRO, pelo mesmo motivo da dívida bancária: ele não
  // gira contra receita. Parcelamento tributário é cronograma de pagamento — projetá-lo
  // por dias de giro fazia o saldo do acordo CRESCER quando a empresa vende mais, o que
  // é o contrário do que acontece. Quem o projeta é a aba `Tributos a Recolher`, e o
  // balanço lê o espelho dela.
  const passivos = (ctx.linhasPorBloco.get("passivo_circulante") ?? [])
    .filter((l) => !ehDividaFinanceira(l.chave))
    .filter((l) => !ehTributoARecolher(l.chave));
  const tributoFora = (ctx.linhasPorBloco.get("passivo_circulante") ?? [])
    .filter((l) => ehTributoARecolher(l.chave));
  const dividaFora = (ctx.linhasPorBloco.get("passivo_circulante") ?? [])
    .filter((l) => ehDividaFinanceira(l.chave));

  // `P18` — o espelho: é DAQUI que o `Balance Sheet` e o `Cash Flow` leem.
  g.espelho("BALANCE SHEET ACCOUNTS", [
    { chave: "ESP_AC", rotulo: "Ativo circulante operacional (para o Balance Sheet)" },
    { chave: "ESP_PC", rotulo: "Passivo circulante operacional (para o Balance Sheet)" },
    { chave: "ESP_ESTOQUE", rotulo: "    do qual ESTOQUE (para a liquidez seca do Output)" },
    { chave: "ESP_CLIENTES", rotulo: "    do qual CLIENTES (para o ciclo de caixa do Output)" },
    { chave: "ESP_FORNEC", rotulo: "    do qual FORNECEDORES (para o ciclo de caixa do Output)" },
  ]);
  g.espelho("CASH FLOW ACCOUNTS", [
    { chave: "ESP_VAR_NCG", rotulo: "Variação da NCG (para o Cash Flow)" },
  ]);
  g.espelho("INCOME STATEMENT ACCOUNTS", [
    { chave: "NET_REV", rotulo: "Receita líquida (base dos dias de giro do ativo)" },
    { chave: "BASE_COGS", rotulo: "Custos (base dos dias de giro do passivo de fornecedor)" },
  ]);

  const fora = [...caixaFora, ...dividaFora, ...tributoFora];
  const rExcl = g.linha(null, {
    rotulo: fora.length === 0
      ? "Nenhuma conta de caixa, de dívida bancária ou de tributo a recolher foi encontrada no circulante deste caso."
      : `FORA do giro de propósito (uma conta, uma origem): ${fora.map((l) => l.chave).join(" · ")}`,
  });
  g.celula(rExcl, COL_ROTULO).font = fonte({ italic: true, size: 9, color: { argb: FONTE_COR.auxiliar } });
  g.celula(rExcl, COL_ROTULO).note = comoNota(
    "Caixa, bancos e aplicações são projetados SÓ pelo Cash Flow; empréstimos e financiamentos, "
    + "SÓ pelo ST Inv. & Debt; tributo a recolher e parcelamento, SÓ pela aba Tributos a Recolher. "
    + "Projetá-los aqui por dias de giro os contaria duas vezes (o defeito aberto desde a sessão 32) "
    + "e, no caso do parcelamento, faria o saldo do acordo CRESCER quando a empresa vende mais. "
    + "É a mesma separação do Modelo Base.",
  );
  g.pular();
  // A base de cada conta (ver o comentário longo mais abaixo). Sobe para cá porque o
  // GRUPO de uma premissa compartilhada só vale entre contas de MESMA base.
  const nomeBase = (pref: "wc_a" | "wc_p", l: LinhaModelo) =>
    pref === "wc_p" && ehFornecedor(l.chave) ? "custos" : "receita líquida";
  // `dias_de_giro` ligada a K contas é prazo do GRUPO (ver `gruposRateados`): o
  // grupo vale `dias/360 × base` e cada conta recebe a parcela histórica dela.
  const saldoGiro = (pref: "wc_a" | "wc_p") => (l: LinhaModelo) => {
    const v = valorNaEscala(l, ctx.ultimoHist, ctx.ent.unidade)?.valor ?? 0;
    return pref === "wc_a" ? v : Math.abs(v);
  };
  const rateioWC = new Map<string, GrupoRateado>([
    ...gruposRateados(ctx, ativos, (l) => chaveLinha("wc_a", l), "dias_de_giro", saldoGiro("wc_a"),
      (a, b) => nomeBase("wc_a", a) === nomeBase("wc_a", b)),
    ...gruposRateados(ctx, passivos, (l) => chaveLinha("wc_p", l), "dias_de_giro", saldoGiro("wc_p"),
      (a, b) => nomeBase("wc_p", a) === nomeBase("wc_p", b)),
  ]);
  // O MESMO CÓDIGO EM BASES DIFERENTES (ativo × passivo, fornecedor contra custo × resto contra
  // receita): somar os grupos não tem sentido e rateá-los entre si seria regra inventada. Ficam
  // separados e CADA UM projeta os dias inteiros — então o agregado leva N× a premissa. Isso é
  // dito na célula, com motivo e efeito (regra 1), em vez de passar calado (em produção: PMR em
  // 16 contas do ativo + 2 do passivo; PMP em 5 do ativo + 59 do passivo).
  const gruposDoCodigo = new Map<string, Set<string>>();
  const rotuloGrupoWC = (pref: "wc_a" | "wc_p", l: LinhaModelo) =>
    `${pref === "wc_a" ? "ativo" : "passivo"}/${nomeBase(pref, l)}`;
  for (const [pref, lista] of [["wc_a", ativos], ["wc_p", passivos]] as const) {
    for (const l of lista) {
      const p = ctx.premissaPorLinha.get(l.rotulo_norm);
      if (!p || p.formula !== "dias_de_giro") continue;
      if (!gruposDoCodigo.has(p.codigo)) gruposDoCodigo.set(p.codigo, new Set());
      gruposDoCodigo.get(p.codigo)!.add(rotuloGrupoWC(pref, l));
    }
  }
  const avisoBases = (pref: "wc_a" | "wc_p", l: LinhaModelo): string => {
    const p = ctx.premissaPorLinha.get(l.rotulo_norm);
    const gs = p && p.formula === "dias_de_giro" ? gruposDoCodigo.get(p.codigo) : undefined;
    if (!p || !gs || gs.size < 2) return "";
    return `\n\nATENÇÃO: a premissa ${p.codigo} está aplicada a ${gs.size} grupos com bases diferentes `
      + `(${[...gs].join(" e ")}); cada grupo projeta os dias INTEIROS, então o circulante projetado `
      + `carrega ${gs.size}× a premissa — revise o vínculo. Esta conta pertence ao grupo `
      + `${rotuloGrupoWC(pref, l)}.`;
  };
  // As linhas extras só existem para conta de grupo COM saldo; sem saldo a conta fica em branco.
  const linhasDoGrupo = (ch: string) => {
    const gr = rateioWC.get(ch);
    if (!gr || gr.semSaldo) return;
    g.linha(`${ch}#grupo`, { rotulo: "    dias do GRUPO (premissa)", fmt: NUM2 });
    g.linha(`${ch}#part`, { rotulo: "    parcela da conta no grupo", fmt: PCT });
  };
  g.linha(null, { rotulo: "ATIVO CIRCULANTE OPERACIONAL", bloco: true });
  for (const l of ativos) {
    const ch = chaveLinha("wc_a", l);
    g.linha(ch, { rotulo: l.chave, fmt: NUM });
    linhasDoGrupo(ch);
    g.linha(`${ch}#dias`, { rotulo: "    dias de giro (base)", fmt: NUM2 });
    g.linha(`${ch}#diasStr`, { rotulo: "    dias de giro (stress)", fmt: NUM2 });
    // A SOMBRA POR CENÁRIO, no mesmo desenho do `CHECK_SOMBRA` da aba de receita
    // (P34/sessão 54): mesma fórmula, mesmos dias, só troca a base (receita ou
    // custo) pela sombra `#v_${suf}` daquela conta na aba de receita. É o que
    // falta para a NCG deixar de estar presa ao cenário ATIVO — ver "réplica
    // completa dos 3 cenários" no cabeçalho do arquivo.
    for (const [suf] of CENARIOS_SUF) g.linha(`${ch}#v_${suf}`, { rotulo: `    sombra — ${suf}`, fmt: NUM });
  }
  g.linha("TOTAL_AC", { rotulo: "Total ativo circulante operacional", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "PASSIVO CIRCULANTE OPERACIONAL", bloco: true });
  for (const l of passivos) {
    const ch = chaveLinha("wc_p", l);
    g.linha(ch, { rotulo: l.chave, fmt: NUM });
    linhasDoGrupo(ch);
    g.linha(`${ch}#dias`, { rotulo: "    dias de giro (base)", fmt: NUM2 });
    g.linha(`${ch}#diasStr`, { rotulo: "    dias de giro (stress)", fmt: NUM2 });
    for (const [suf] of CENARIOS_SUF) g.linha(`${ch}#v_${suf}`, { rotulo: `    sombra — ${suf}`, fmt: NUM });
  }
  g.linha("TOTAL_PC", { rotulo: "Total passivo circulante operacional", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("NCG", { rotulo: "NECESSIDADE DE CAPITAL DE GIRO (AC − PC)", negrito: true, topo: true, fmt: NUM });
  g.linha("VAR_NCG", { rotulo: "Variação da NCG (efeito no caixa, sinal invertido)", fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "NCG POR CENÁRIO (sombra, não olha o interruptor)", bloco: true });
  for (const [suf, nome] of CENARIOS_SUF) {
    g.linha(`NCG#v_${suf}`, { rotulo: `    ${nome}`, fmt: NUM });
    g.linha(`VAR_NCG#v_${suf}`, { rotulo: `        variação`, fmt: NUM });
  }
  g.linha("CHECK_SOMBRA_WC", {
    rotulo: "    CHECK: a sombra do cenário ATIVO bate com a NCG ativa (0 = bate)", fmt: NUM2,
  });

  // ---- A GUARDA DO GIRO AGREGADO ------------------------------------------
  //
  // O DEFEITO QUE ELA EXISTE PARA DENUNCIAR, e ele não tem sintoma nenhum hoje.
  // Cada conta de giro é projetada por `dias ÷ 360 × base`, e nada olha o
  // AGREGADO. Vincular a MESMA premissa de prazo a N contas — que é um clique
  // por linha na tela de Modelagem, e o caminho natural de quem está com pressa —
  // produz N × dias de receita presos em capital de giro. Vinte contas a 60 dias
  // são 1.200 dias, e o balanço CONTINUA FECHANDO, porque o patrimônio líquido
  // absorve a diferença. O arquivo vai ao comitê com um passivo circulante que
  // cresce oitenta vezes em cinco anos e nenhuma célula vermelha.
  //
  // A RÉGUA NÃO JULGA O NEGÓCIO — compara a HIPÓTESE com o FATO. Não há limiar
  // absoluto de "quantos dias de giro são demais": depende do setor, do ciclo, do
  // mandato. O que não depende de opinião é a razão entre o giro PROJETADO e o
  // giro que a própria empresa teve no último exercício REALIZADO. Uma projeção
  // que multiplica por cinco o giro histórico não é uma tese agressiva, é um erro
  // de configuração — e é isso, e só isso, que esta linha acusa.
  //
  // O DENOMINADOR É A RECEITA LÍQUIDA nos dois lados, inclusive no passivo, e
  // isso é DELIBERADO: aqui a régua é de ORDEM DE GRANDEZA, e trocar a base do
  // passivo para custo faria a razão do passivo e a do ativo não serem
  // comparáveis entre si. Cada CONTA continua girando contra a base contábil
  // certa dela — o que muda é só o denominador desta leitura agregada, e a nota
  // da célula diz isso.
  g.pular();
  g.linha(null, { rotulo: "GUARDA DO GIRO AGREGADO (hipótese × fato)", bloco: true });
  g.linha("DIAS_AC_TOT", { rotulo: "Ativo de giro, em dias de receita", fmt: DIAS });
  g.linha("DIAS_PC_TOT", { rotulo: "Passivo de giro, em dias de receita", fmt: DIAS });
  g.linha("CHECK_GIRO", {
    rotulo: "CHECK — giro projetado ÷ último realizado (>2× é erro de configuração)",
    fmt: MULT, negrito: true,
  });

  // A BASE DE CADA CONTA — e uma incoerência do Modelo Base que NÃO se replica.
  //
  // Lá o prazo médio HISTÓRICO de uma conta de fornecedor é medido contra o CUSTO
  // (`Working Capital!D46 = IF(D32>0, D21/D32*360, )`), mas o saldo PROJETADO é
  // aplicado sobre a RECEITA LÍQUIDA (`I21 = I46/360*I31`). Medir num
  // denominador e aplicar noutro infla o passivo projetado na razão
  // receita/custo — no caso da referência, ~1,27×. É defeito, não convenção.
  //
  // Aqui a base é a MESMA nas duas pontas, e é a base contábil correta de cada
  // conta: fornecedor gira contra CUSTO (é o PMP de manual), o resto gira contra
  // RECEITA LÍQUIDA.
  const baseDe = (pref: "wc_a" | "wc_p", l: LinhaModelo, ano: number) =>
    pref === "wc_p" && ehFornecedor(l.chave) ? g.ref("BASE_COGS", ano) : g.ref("NET_REV", ano);

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("NET_REV", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)}`, { fmt: NUM, negrito: true });
    g.set("BASE_COGS", ano, `=${g.externa("Revenues, COGS & SG&A", gRec, "CUSTOS", ano)}`, { fmt: NUM });

    for (const [pref, lista] of [["wc_a", ativos], ["wc_p", passivos]] as const) {
      for (const l of lista) {
        const ch = chaveLinha(pref, l);
        const base = baseDe(pref, l, ano);
        if (hist) {
          const e = valorNaEscala(l, ano, ctx.ent.unidade);
          // O ATIVO ENTRA COM O SINAL DO DOCUMENTO; o PASSIVO, em magnitude.
          //
          // `Math.abs` valia para os dois lados e era erro aritmético no ativo:
          // conta REDUTORA é negativa por natureza — "(-) Perdas estimadas em
          // créditos de liquidação duvidosa" (−3.850) e "(-) Provisão para
          // obsolescência de estoques" (−2.350) reduzem o circulante. Em módulo
          // elas passavam a SOMAR, e o erro é o DOBRO do valor delas: medido no
          // book, +12.400 num ativo circulante de 45.440 (27%), absorvido em
          // silêncio pela linha de reconciliação.
          //
          // Os blocos de BALANÇO não passam pela normalização de sinal (ela só
          // toca `BLOCOS_DE_DESPESA`, da DRE), então aqui o sinal do documento é
          // a verdade e não há convenção a impor.
          //
          // No PASSIVO a magnitude FICA: lá o documento às vezes publica o saldo
          // negativo por convenção de partida dobrada, e a cascata do modelo
          // soma passivo como número positivo. Trocar os dois de uma vez faria o
          // balanço deixar de fechar por motivo diferente do que se está
          // corrigindo — e o lado do ativo é o que tem conta redutora de verdade.
          if (e) g.set(ch, ano, pref === "wc_a" ? e.valor : Math.abs(e.valor),
            { fmt: NUM, fill: FILL_HIST, nota: e.nota, tipo: "calc" });
          else if (notaSemValor(l, ano)) g.set(ch, ano, null, { fmt: NUM, fill: FILL_HIST, nota: notaSemValor(l, ano), tipo: "calc" });
          // Dias IMPLÍCITOS do histórico: saldo ÷ base × 360, com a guarda
          // `IF(base>0)` do Modelo Base (`P27`). É o número que o analista precisa
          // ver antes de escolher o dia projetado — sem ele, a premissa é palpite.
          g.set(`${ch}#dias`, ano,
            `=IF(${base}>0,${g.ref(ch, ano)}/${base}*360,0)`,
            { fmt: DIAS, nota: `Dias implícitos no realizado: saldo ÷ ${nomeBase(pref, l)} × 360. `
              + "Base 360 (ano comercial), que é a dos contratos e dos covenants." });
          continue;
        }
        const p = ctx.premissaPorLinha.get(l.rotulo_norm);
        const usaPremissa = p && p.formula === "dias_de_giro" && p.valores[String(ano)] !== undefined;
        const gr = rateioWC.get(ch);
        const aviso = avisoBases(pref, l);
        if (gr?.semSaldo && p) {
          // Sem saldo realizado no grupo não há como ratear: BRANCO + nota (motivo e
          // efeito), nunca zero medido nem divisão igual em silêncio.
          const nota = notaGrupoSemSaldo(p, gr, ctx.ultimoHist,
            `o capital de giro projetado fica MENOR que o da premissa (dias/360 × ${nomeBase(pref, l)}), `
            + "pela parte inteira deste grupo." + aviso);
          g.set(`${ch}#dias`, ano, null, { fmt: DIAS, fill: FILL_INPUT, nota });
          g.set(ch, ano, null, { fmt: NUM, nota });
          continue;
        }
        if (gr && p && usaPremissa) {
          // Os dias da conta = dias do GRUPO × parcela dela; a fórmula de `ch`, o Stress
          // e as sombras seguem lendo `#dias` como antes (um ponto só).
          g.set(`${ch}#grupo`, ano, p.valores[String(ano)], {
            fmt: NUM2, fill: FILL_INPUT,
            nota: `Premissa "${p.nome}" (${p.origem ?? "digitado"}): dias do GRUPO de ${gr.membros.length} `
              + `contas, aplicados sobre ${nomeBase(pref, l)} UMA vez.${aviso}`,
          });
          g.set(`${ch}#part`, ano, formulaParcela(g, ch,
            gr.membros.map((o) => chaveLinha(pref, o)), ctx.ultimoHist), {
            fmt: PCT, nota: notaParcela(p, gr, ctx.ultimoHist, `dias/360 × ${nomeBase(pref, l)}`),
          });
          g.set(`${ch}#dias`, ano, `=${g.ref(`${ch}#grupo`, ano)}*${g.ref(`${ch}#part`, ano)}`, {
            fmt: DIAS,
            nota: "Dias do grupo × parcela histórica desta conta. A soma das contas do grupo dá os "
              + "dias do grupo." + aviso,
          });
        } else {
          g.set(`${ch}#dias`, ano, usaPremissa ? p!.valores[String(ano)] : `=${g.ref(`${ch}#dias`, ant!)}`, {
            fmt: DIAS, fill: FILL_INPUT,
            nota: usaPremissa
              ? `Premissa "${p!.nome}" (${p!.origem ?? "digitado"}). Aplicada sobre ${nomeBase(pref, l)}.${aviso}`
              : "Sem premissa de dias de giro para esta conta: mantém os dias do período anterior. "
                + `É a hipótese conservadora — o giro não melhora sozinho.${aviso}`,
          });
        }
        g.set(`${ch}#diasStr`, ano, `=${g.ref(`${ch}#dias`, ano)}*(1+${refStress()}*${pref === "wc_a" ? "1" : "-1"})`, {
          fmt: DIAS,
          nota: pref === "wc_a"
            ? "No Stress o ATIVO gira MAIS DEVAGAR (recebe pior): dias sobem."
            : "No Stress o PASSIVO gira MAIS RÁPIDO (fornecedor aperta o prazo): dias caem. "
              + "Aumentar os dias do passivo no stress daria caixa de graça no cenário ruim.",
        });
        g.set(ch, ano,
          `=CHOOSE(${cen},${g.ref(`${ch}#dias`, ano)},${g.ref(`${ch}#dias`, ano)},${g.ref(`${ch}#diasStr`, ano)})`
          + `/360*${base}`, { fmt: NUM, nota: `Prazo ÷ 360 × ${nomeBase(pref, l)} do mesmo exercício.` });

        // A SOMBRA: MESMOS dias (Base e Cliente compartilham `#dias`; Stress usa
        // `#diasStr`, exatamente como o `CHOOSE` acima), mas a BASE muda para a
        // receita/custo daquele cenário — a sombra de `RECEITA_LIQUIDA`/`CUSTOS`
        // que a aba de receita já publica (`#v_${suf}`, sessão 54). É o mesmo
        // desenho do `CHECK_SOMBRA`: fórmula idêntica, insumo trocado.
        const baseFonte = pref === "wc_p" && ehFornecedor(l.chave) ? "CUSTOS" : "RECEITA_LIQUIDA";
        for (const [suf] of CENARIOS_SUF) {
          const diasSuf = suf === "str" ? `${ch}#diasStr` : `${ch}#dias`;
          const baseSombra = g.externa("Revenues, COGS & SG&A", gRec, `${baseFonte}#v_${suf}`, ano);
          g.set(`${ch}#v_${suf}`, ano, `=${g.ref(diasSuf, ano)}/360*${baseSombra}`, { fmt: NUM });
        }
      }
    }
    somaOuZero(g, "TOTAL_AC", ano, ativos.map((l) => g.ref(chaveLinha("wc_a", l), ano)), true);
    somaOuZero(g, "TOTAL_PC", ano, passivos.map((l) => g.ref(chaveLinha("wc_p", l), ano)), true);
    g.set("NCG", ano, `=${g.ref("TOTAL_AC", ano)}-${g.ref("TOTAL_PC", ano)}`, { fmt: NUM, negrito: true });
    g.set("VAR_NCG", ano, ant === null ? 0 : `=-(${g.ref("NCG", ano)}-${g.ref("NCG", ant)})`, {
      fmt: NUM,
      nota: "Giro que CRESCE consome caixa — por isso o sinal aqui é o inverso do saldo.",
    });

    // NCG POR CENÁRIO — só na projeção, mesma regra do `CHECK_SOMBRA` da receita.
    //
    // `kv(chave, s)` existe para tirar o gabarito literal aninhado
    // (`` `${chaveLinha(...)}#v_${suf}` `` dentro doutro template literal) —
    // achado de revisão (SonarCloud `typescript:S4624`), não só estilo: um
    // gabarito aninhado é mais fácil de errar a interpolação sem notar.
    const kv = (chave: string, s: string) => `${chave}#v_${s}`;
    if (!hist) {
      for (const [suf] of CENARIOS_SUF) {
        const kNcg = kv("NCG", suf);
        // NCG é AC − PC: soma os ativos e SUBTRAI os passivos — `somaOuZero` só
        // soma, então aqui a soma é escrita direto, com o passivo negado.
        g.set(kNcg, ano,
          `=${ativos.map((l) => g.ref(kv(chaveLinha("wc_a", l), suf), ano)).join("+") || "0"}`
          + `-(${passivos.map((l) => g.ref(kv(chaveLinha("wc_p", l), suf), ano)).join("+") || "0"})`,
          { fmt: NUM });
        // O ANO ANTERIOR pode ser histórico (primeiro ano projetado): aí a sombra
        // ainda não existe, e a NCG ativa daquele ano — comum aos três cenários —
        // é a base correta. O mesmo desenho do `baseAnterior` no resumo do Output.
        // Sem ternário aninhado (achado de revisão, SonarCloud `typescript:S3358`):
        // três casos viram três `if`, não um ternário dentro doutro.
        let ncgAnterior: string | null;
        if (ant === null) {
          ncgAnterior = null;
        } else if (g.ehProjetado(ant)) {
          ncgAnterior = g.ref(kNcg, ant);
        } else {
          ncgAnterior = g.ref("NCG", ant);
        }
        g.set(kv("VAR_NCG", suf), ano, ncgAnterior === null ? 0
          : `=-(${g.ref(kNcg, ano)}-${ncgAnterior})`, { fmt: NUM });
      }
      // CHOOSE, não `#v_base` fixo — a NCG ativa segue o CENÁRIO LIGADO, e um
      // Working Capital cujo CHECK só bate com Base mentiria "divergiu" toda
      // vez que o dial estivesse em Cliente ou Stress, que é o estado normal
      // de um arquivo de reestruturação. É o mesmo desenho do `CHECK_SOMBRA`
      // da aba de receita (linha ~2090), que já usa `CHOOSE(cen, ...)`.
      const opcoesNcg = CENARIOS_SUF.map(([su]) => g.ref(kv("NCG", su), ano)).join(",");
      const escolheNcg = `CHOOSE(${cen},${opcoesNcg})`;
      g.set("CHECK_SOMBRA_WC", ano, `=ABS(${escolheNcg}-${g.ref("NCG", ano)})`, {
        fmt: NUM2,
        nota: "Distância entre a sombra do cenário ATIVO e a NCG ativa. Zero por construção: os "
          + "dois leem os mesmos dias e a mesma base (a sombra RECEITA_LIQUIDA#v/CUSTOS#v da aba "
          + "de receita é, por sua vez, igual à linha ativa NO CENÁRIO ATIVO). Diferente de zero é "
          + "a NCG por cenário tendo se separado do que o modelo realmente cobra.",
      });
    } else {
      g.set("CHECK_SOMBRA_WC", ano, "", { fmt: NUM2 });
    }

    // A GUARDA DO GIRO AGREGADO, por exercício. Ver o comentário longo acima.
    const notaBase = "Denominador é a receita líquida nos DOIS lados, de propósito: aqui a régua é "
      + "de ordem de grandeza, e bases diferentes tornariam ativo e passivo incomparáveis entre si. "
      + "Cada conta continua girando contra a base contábil correta dela.";
    g.set("DIAS_AC_TOT", ano,
      `=IF(${g.ref("NET_REV", ano)}>0,${g.ref("TOTAL_AC", ano)}/${g.ref("NET_REV", ano)}*360,"")`,
      { fmt: DIAS, nota: notaBase });
    g.set("DIAS_PC_TOT", ano,
      `=IF(${g.ref("NET_REV", ano)}>0,${g.ref("TOTAL_PC", ano)}/${g.ref("NET_REV", ano)}*360,"")`,
      { fmt: DIAS, nota: notaBase });
    // No REALIZADO a razão é 1 por construção contra o próprio último ano, então
    // ela só é publicada na PROJEÇÃO — é lá que a hipótese existe para ser
    // conferida. Publicar 1,00 nas colunas históricas encheria a linha de um
    // número que não decide nada, e número que não decide nada é o que ensina o
    // leitor a ignorar a linha inteira.
    if (hist) {
      g.set("CHECK_GIRO", ano, "", { fmt: MULT });
    } else {
      const ref = `(${g.ref("DIAS_AC_TOT", ctx.ultimoHist)}+${g.ref("DIAS_PC_TOT", ctx.ultimoHist)})`;
      const proj = `(${g.ref("DIAS_AC_TOT", ano)}+${g.ref("DIAS_PC_TOT", ano)})`;
      g.set("CHECK_GIRO", ano, `=IF(${ref}>0,${proj}/${ref},"")`, {
        fmt: MULT,
        nota: "Giro agregado projetado dividido pelo do último exercício realizado. A régua não "
          + "julga o negócio: ela compara a HIPÓTESE com o FATO da própria empresa. Acima de 2× "
          + "quase sempre é a MESMA premissa de prazo vinculada a várias contas — cada uma passa a "
          + "prender os mesmos dias de receita, e o balanço continua fechando porque o patrimônio "
          + "líquido absorve. Soma ativo E passivo para que um giro que cresce dos dois lados, sem "
          + "mexer na NCG líquida, também apareça.",
      });
    }
    // `P18` — o espelho, que é o que as demonstrações leem.
    g.set("ESP_AC", ano, `=${g.ref("TOTAL_AC", ano)}`, { fmt: NUM, negrito: true });
    somaOuZero(g, "ESP_ESTOQUE", ano, estoques.map((l) => g.ref(chaveLinha("wc_a", l), ano)));
    somaOuZero(g, "ESP_CLIENTES", ano, clientes.map((l) => g.ref(chaveLinha("wc_a", l), ano)));
    somaOuZero(g, "ESP_FORNEC", ano,
      passivos.filter((l) => ehFornecedor(l.chave)).map((l) => g.ref(chaveLinha("wc_p", l), ano)));
    g.set("ESP_PC", ano, `=${g.ref("TOTAL_PC", ano)}`, { fmt: NUM, negrito: true });
    g.set("ESP_VAR_NCG", ano, `=${g.ref("VAR_NCG", ano)}`, { fmt: NUM });
  }
  // O VERMELHO É O QUE FAZ A LINHA SER VISTA. Sem ele a razão fica publicada e
  // some entre trinta outras — o mesmo motivo pelo qual o CHECK do balanço tem
  // realce desde a 0101. Acima de 2× é erro de configuração; abaixo de 0,5× é a
  // hipótese oposta (giro que MELHORA sozinho), que também não se sustenta sem
  // alguém ter dito por quê.
  {
    const linhaCheck = g.n("CHECK_GIRO");
    if (linhaCheck) {
      const colIni = colLetra(COL_PRIMEIRO_ANO);
      const colFim = colLetra(COL_PRIMEIRO_ANO + ctx.anos.length - 1);
      g.ws.addConditionalFormatting({
        ref: `${colIni}${linhaCheck}:${colFim}${linhaCheck}`,
        rules: [
          { type: "expression", formulae: [`AND(ISNUMBER(${colIni}${linhaCheck}),OR(${colIni}${linhaCheck}>2,${colIni}${linhaCheck}<0.5))`],
            style: { fill: FILL_CHECK_ERRO }, priority: 1 },
          { type: "expression", formulae: [`ISNUMBER(${colIni}${linhaCheck})`],
            style: { fill: FILL_CHECK_OK }, priority: 2 },
        ],
      });
    }
  }

  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Fixed Assets & CAPEX — imobilizado por classe, capex por premissa e
// depreciação linear por safra.
//
// DIVERGÊNCIA DELIBERADA DO REFERÊNCIA: ele deprecia com
// `SUM(OFFSET(...))*(...)`, que é ilegível e quebra silenciosamente se alguém
// inserir uma coluna. Aqui a depreciação de cada ano é a soma das safras de capex
// dentro da vida útil, escrita como intervalo explícito — mesmo resultado,
// auditável a olho.
// =============================================================================
const VIDA_UTIL_PADRAO = 10;

// Prazo de amortização da dívida NOVA, em anos. É default de modelo, não dado do
// caso — e por isso vira célula de premissa (azul) na aba, não número escondido
// na fórmula.
const PRAZO_EMISSAO_PADRAO = 5;

// CORTES DE COVENANT SUGERIDOS. São PREMISSA DE NEGOCIAÇÃO, não dado do caso, e
// por isso entram como célula azul editável ao lado do índice — que é o desenho
// do Modelo Base (as linhas `Corte Sugerido` / `Covenant Sugerido` das tabelas
// laterais do `Output` dele). Os números abaixo são os patamares usuais de term
// sheet de crédito no Brasil; o valor certo é o do contrato, e é por isso que a
// célula existe em vez de a fórmula ter o número dentro.
const COVENANT_ND_EBITDA = 3;
const COVENANT_DSCR = 1.2;
const COVENANT_LIQUIDEZ = 1;

function abaImobilizado(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade): Grade {
  const g = new Grade(wb, "Fixed Assets & CAPEX", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("FIXED ASSETS & CAPEX", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));
  g.linha("CHECK_MODELO", { rotulo: "CHECK do balanço (0 = fecha)", fmt: NUM2 });
  g.pular();
  const cen = g.celulaCenario;

  const classes = (ctx.linhasPorBloco.get("ativo_nao_circulante") ?? []).filter((l) => ehImobilizado(l.chave));

  // `P18` — o espelho desta aba. É daqui que `Balance Sheet`, `Income Statement`
  // e `Cash Flow` leem; nenhum deles conhece o miolo do cálculo de depreciação.
  g.espelho("BALANCE SHEET ACCOUNTS", [
    { chave: "ESP_IMOB", rotulo: "Imobilizado e intangível líquido (para o Balance Sheet)" },
  ]);
  g.espelho("INCOME STATEMENT ACCOUNTS", [
    { chave: "ESP_DEPREC", rotulo: "Depreciação e amortização do período (para a DRE)" },
  ]);
  g.espelho("CASH FLOW ACCOUNTS", [
    { chave: "ESP_CAPEX", rotulo: "CAPEX do período (para o Cash Flow)" },
    { chave: "ESP_DEPREC_CF", rotulo: "Depreciação (volta ao caixa no método indireto)" },
  ]);

  g.linha("VIDA_UTIL", { rotulo: "Vida útil média adotada (anos)", nota: "premissa", fmt: NUM2 });
  g.pular();
  g.linha(null, { rotulo: "SALDO DO IMOBILIZADO POR CLASSE", bloco: true });
  for (const l of classes) {
    g.linha(chaveLinha("fa", l), { rotulo: l.chave, fmt: NUM });
    g.linha(`${chaveLinha("fa", l)}#dep`, { rotulo: "    depreciação rateada à classe", fmt: NUM });
  }
  g.linha("TOTAL_FA", { rotulo: "Imobilizado líquido total", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "CAPEX", bloco: true });
  // `% da receita líquida` ligada a K classes é taxa do GRUPO de classes (ver
  // `gruposRateados`): cada classe leva a parcela dela no imobilizado realizado.
  const rateioCapex = gruposRateados(ctx, classes, (l) => chaveLinha("capex", l), "pct_de_linha",
    (l) => valorNaEscala(l, ctx.ultimoHist, ctx.ent.unidade)?.valor ?? 0);
  for (const l of classes) {
    const ch = chaveLinha("capex", l);
    g.linha(ch, { rotulo: `Capex — ${l.chave}`, fmt: NUM });
    g.linha(`${ch}#pct`, { rotulo: "    % da receita líquida (base)", fmt: PCT });
    if (rateioCapex.get(ch) && !rateioCapex.get(ch)!.semSaldo) {
      g.linha(`${ch}#part`, { rotulo: "    parcela da classe no grupo da premissa", fmt: PCT });
    }
  }
  g.linha("TOTAL_CAPEX", { rotulo: "CAPEX total", negrito: true, topo: true, fmt: NUM });
  g.linha("CAPEX_PCT", { rotulo: "    % da receita líquida", fmt: PCT });
  g.pular();
  g.linha("DEPREC", { rotulo: "DEPRECIAÇÃO DO PERÍODO", negrito: true, fmt: NUM });
  g.linha("DEPREC_NOTA", { rotulo: "    (linear, sobre as safras de capex dentro da vida útil)" });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("VIDA_UTIL", ano, VIDA_UTIL_PADRAO, {
      fmt: NUM2, fill: FILL_INPUT,
      nota: "Vida útil média. Um único número por caso: abrir por classe exige laudo de vida "
        + "útil, que não existe nos documentos do Kit Básico — e inventar uma taxa por classe "
        + "daria falsa precisão.",
    });

    for (const l of classes) {
      const chFa = chaveLinha("fa", l);
      const chCx = chaveLinha("capex", l);
      if (hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (e) g.set(chFa, ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota, tipo: "calc" });
        else if (notaSemValor(l, ano)) g.set(chFa, ano, null, { fmt: NUM, fill: FILL_HIST, nota: notaSemValor(l, ano), tipo: "calc" });
        g.set(`${chFa}#dep`, ano, 0, { fmt: NUM, tipo: "calc" });
        g.set(chCx, ano, 0, { fmt: NUM, tipo: "calc", nota: "Capex histórico não é extraível do balanço (só a variação do saldo). Zero explícito." });
        continue;
      }
      const p = ctx.premissaPorLinha.get(l.rotulo_norm);
      const pct = p && p.formula === "pct_de_linha" ? p.valores[String(ano)] : undefined;
      g.set(`${chCx}#pct`, ano, pct === undefined ? 0 : pct / 100, {
        fmt: PCT, fill: FILL_INPUT,
        nota: pct === undefined
          ? "Sem premissa de capex para esta classe: ZERO. Capex inventado é o jeito mais "
            + "rápido de fazer um modelo fechar bonito e não acontecer."
          : `Premissa "${p!.nome}".`,
      });
      const grCx = rateioCapex.get(chCx);
      if (grCx && p && !grCx.semSaldo) {
        g.set(`${chCx}#part`, ano,
          formulaParcela(g, chFa, grCx.membros.map((o) => chaveLinha("fa", o)), ctx.ultimoHist),
          { fmt: PCT, nota: notaParcela(p, grCx, ctx.ultimoHist, "taxa × receita líquida") });
      }
      g.set(chCx, ano,
        grCx?.semSaldo ? null
          : `=CHOOSE(${cen},${g.ref(`${chCx}#pct`, ano)},${g.ref(`${chCx}#pct`, ano)},`
            + `${g.ref(`${chCx}#pct`, ano)}*(1-${refStress()}))*${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)}`
            + (grCx ? `*${g.ref(`${chCx}#part`, ano)}` : ""),
        {
          fmt: NUM,
          nota: grCx?.semSaldo && p
            ? notaGrupoSemSaldo(p, grCx, ctx.ultimoHist,
              "o CAPEX projeta MENOS do que a premissa indica (taxa × receita líquida), pela parte inteira "
              + "deste grupo de classes.")
            : "No Stress o capex é CORTADO (é a primeira coisa que se corta numa crise de caixa).",
        });
      // RATEIO EXAUSTIVO DA DEPRECIAÇÃO — e é uma correção que a álgebra do
      // balanço exige, não estética.
      //
      // O rateio anterior era `IF(total anterior<>0, participação × depreciação, 0)`
      // por classe. Quando o saldo anterior total era ZERO (primeiro ano com
      // capex, ou caso sem imobilizado extraído), TODOS os rateios davam zero e a
      // depreciação do período não saía de classe nenhuma: o imobilizado crescia
      // pelo capex inteiro, a DRE debitava a depreciação, e o balanço abria
      // exatamente no valor dela. Aqui a ÚLTIMA classe recebe o resíduo, então a
      // soma dos rateios é sempre igual à depreciação do período — por
      // construção, não por sorte.
      const iClasse = classes.indexOf(l);
      const ehUltima = iClasse === classes.length - 1;
      g.set(`${chFa}#dep`, ano,
        ehUltima
          ? `=${g.ref("DEPREC", ano)}-(${classes.slice(0, -1).map((o) => g.ref(`${chaveLinha("fa", o)}#dep`, ano)).join("+") || "0"})`
          : `=IF(${g.ref("TOTAL_FA", ant!)}<>0,${g.ref(chFa, ant!)}/${g.ref("TOTAL_FA", ant!)}*${g.ref("DEPREC", ano)},0)`,
        {
          fmt: NUM,
          nota: ehUltima
            ? "Última classe: recebe o RESÍDUO, para a soma dos rateios ser exatamente a "
              + "depreciação do período. Sem isso, quando o saldo anterior é zero nenhuma classe "
              + "recebe depreciação e o balanço abre no valor dela."
            : "Rateio pela participação da classe no imobilizado de abertura.",
        });
      // Saldo: abertura + capex − depreciação rateada à classe.
      g.set(chFa, ano,
        `=${g.ref(chFa, ant!)}+${g.ref(chCx, ano)}-${g.ref(`${chFa}#dep`, ano)}`, { fmt: NUM });
    }
    somaOuZero(g, "TOTAL_FA", ano, classes.map((l) => g.ref(chaveLinha("fa", l), ano)), true);
    somaOuZero(g, "TOTAL_CAPEX", ano, classes.map((l) => g.ref(chaveLinha("capex", l), ano)), true);
    g.set("CAPEX_PCT", ano,
      `=IF(${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)}<>0,`
      + `${g.ref("TOTAL_CAPEX", ano)}/${g.externa("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ano)},0)`, { fmt: PCT });

    if (hist) {
      // Depreciação histórica não é extraível do balanço de forma confiável (ela
      // está na DRE, e o rateio por classe não está em documento nenhum).
      g.set("DEPREC", ano, 0, { fmt: NUM, negrito: true, nota: "Período realizado: a depreciação vem da DRE extraída, não é reprojetada aqui." });
      continue;
    }
    // Depreciação = saldo de abertura ÷ vida útil + capex do ano ÷ vida útil ÷ 2
    // (meia safra no ano de entrada, convenção de meio-ano). Fórmula explícita.
    g.set("DEPREC", ano,
      `=IF(${g.ref("VIDA_UTIL", ano)}<=0,0,${g.ref("TOTAL_FA", ant!)}/${g.ref("VIDA_UTIL", ano)}`
      + `+${g.ref("TOTAL_CAPEX", ano)}/${g.ref("VIDA_UTIL", ano)}/2)`, {
      fmt: NUM, negrito: true,
      nota: "Linear sobre o saldo de abertura, mais meia safra do capex do ano (convenção de "
        + "meio-ano). Guarda contra vida útil zero: divisão por zero num modelo entregue vira "
        + "#DIV/0! em cascata por 12 abas.",
    });
  }
  // `P18` — o espelho, preenchido depois que TOTAL_FA/TOTAL_CAPEX/DEPREC existem
  // em todos os anos. Fazê-lo dentro do laço acima daria o mesmo resultado, mas
  // separado deixa explícito que o espelho é interface, não cálculo.
  for (const ano of ctx.anos) {
    g.set("ESP_IMOB", ano, `=${g.ref("TOTAL_FA", ano)}`, { fmt: NUM, negrito: true });
    g.set("ESP_DEPREC", ano, `=${g.ref("DEPREC", ano)}`, { fmt: NUM });
    g.set("ESP_CAPEX", ano, `=${g.ref("TOTAL_CAPEX", ano)}`, { fmt: NUM });
    g.set("ESP_DEPREC_CF", ano, `=${g.ref("DEPREC", ano)}`, { fmt: NUM });
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA ST Inv. & Debt — o cronograma da dívida, uma tranche por linha do mapa.
// =============================================================================
function abaDivida(wb: ExcelJS.Workbook, ctx: Ctx, gAnual: Grade, gRec: Grade): Grade {
  const g = new Grade(wb, "ST Inv. & Debt", ctx.anos, ctx.nHist);
  g.ancoraCenario();
  g.cabecalho("ST INVESTMENTS & DEBT", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));
  g.linha("CHECK_MODELO", { rotulo: "CHECK do balanço (0 = fecha)", fmt: NUM2 });
  g.pular();

  // DE ONDE SAEM AS TRANCHES — e este parágrafo corrige o defeito mais grave que
  // esta rodada encontrou no nosso lado, achado por um teste que somou o balanço.
  //
  // Antes, as tranches vinham SÓ do mapa de dívida (`documentos` com
  // `MAPA_DIVIDA`, linhas de "saldo"/"principal"). Como esta mesma rodada tirou a
  // dívida bancária do capital de giro — corretamente, ela não é giro —, um caso
  // SEM mapa de dívida ficava com a dívida em lugar NENHUM: fora do giro e fora
  // desta aba. Medido no teste (0105a): o balanço abria em exatamente 50.000, que
  // era a soma dos empréstimos de curto e longo prazo do caso.
  //
  // A regra agora tem duas fontes, nesta ordem de qualidade:
  //   1. o MAPA DE DÍVIDA, quando existe — é o detalhe por contrato, com juros;
  //   2. as LINHAS DE DÍVIDA BANCÁRIA DO BALANÇO, sempre que o mapa não traz —
  //      é o número auditado da demonstração, e ele nunca falta.
  // Nunca as duas juntas: somar mapa e balanço contaria a mesma dívida duas vezes.
  const doMapa = (ctx.linhasPorBloco.get("divida") ?? []).filter((l) => /saldo|principal/i.test(l.chave));
  const doBalanco = [
    ...(ctx.linhasPorBloco.get("passivo_circulante") ?? []),
    ...(ctx.linhasPorBloco.get("passivo_nao_circulante") ?? []),
  ].filter((l) => ehDividaFinanceira(l.chave));
  const iProjDoAno = (ano: number) => ctx.anos.indexOf(ano) - ctx.hist.length;
  const dividas = doMapa.length > 0 ? doMapa : doBalanco;

  // A ÚLTIMA COLUNA HISTÓRICA EM QUE CADA TRANCHE TEM VALOR — e por que isto
  // precisou existir.
  //
  // O DEFEITO, achado rodando o arnês de variações: `#fim` do histórico só é
  // escrito quando a tranche TEM valor naquele ano (`if (e)` abaixo). Quando ela
  // não tem valor no ÚLTIMO exercício realizado, a célula fica vazia — e a
  // abertura do primeiro ano projetado, que é `=<#fim do ano anterior>`, referencia
  // vazio e vale ZERO. A tranche some da projeção SEM AMORTIZAÇÃO NENHUMA.
  //
  // Medido: uma variação em que as colunas de período vêm trocadas levou a dívida
  // de curto prazo de 23.462 e a de longo de 14.257 para ZERO no primeiro ano
  // projetado, com `Amortização de dívida no período` = 0. Dívida não paga que
  // desaparece é a mentira mais lisonjeira que este arquivo pode contar num
  // mandato de reestruturação, e o único a reclamar era o CHECK do balanço, 37.719
  // colunas adiante.
  //
  // É REALISTA fora do arnês: basta o mapa de dívida não trazer uma tranche na
  // coluna do último exercício — extração que perdeu a célula, tranche que o
  // documento reporta só até o ano anterior, coluna em branco no PDF.
  //
  // A REGRA: a projeção abre no ÚLTIMO SALDO CONHECIDO, e a célula diz de que ano
  // ele veio. Carregar o último saldo é conservador; zerar afirma que a dívida foi
  // quitada, e o documento não disse isso.
  const ultimoAnoComSaldo = new Map<LinhaModelo, number>();
  for (const l of dividas) {
    for (const ano of ctx.hist) {
      if (valorNaEscala(l, ano, ctx.ent.unidade)) ultimoAnoComSaldo.set(l, ano);
    }
  }
  const origemDaDivida = doMapa.length > 0 ? "mapa de dívida" : "linhas de dívida bancária do balanço";
  const jurosDoMapa = (ctx.linhasPorBloco.get("divida") ?? []).filter((l) => /juros/i.test(l.chave));

  // A REPARTIÇÃO CURTO/LONGO PRAZO MORA AQUI, não no balanço. Ela é medida no
  // último exercício realizado do próprio caso (dívida bancária no circulante ÷
  // dívida bancária total). Antes vivia em `abaBalanco`, e o balanço acabava
  // sabendo de dívida — o que é exatamente o acoplamento que o espelho (`P18`)
  // existe para evitar. Sem base para medir, 30% declarado na nota.
  const somaBancaria = (bloco: BlocoModelo, ano: number) =>
    (ctx.linhasPorBloco.get(bloco) ?? [])
      .filter((l) => ehDividaFinanceira(l.chave))
      .reduce((acc, l) => acc + Math.abs(valorNaEscala(l, ano, ctx.ent.unidade)?.valor ?? 0), 0);
  const saldoCP = somaBancaria("passivo_circulante", ctx.ultimoHist);
  const saldoLP = somaBancaria("passivo_nao_circulante", ctx.ultimoHist);
  const fracCPMedida = saldoCP + saldoLP > 0;
  const fracCP = fracCPMedida ? saldoCP / (saldoCP + saldoLP) : 0.3;

  // PRAZO DE AMORTIZAÇÃO IMPLÍCITO NO PRÓPRIO BALANÇO.
  //
  // A decisão do dono (07/08/2026) é amortizar LINEARMENTE (SAC) até o vencimento
  // quando o documento não traz cronograma — e o documento quase nunca traz. Falta
  // então o prazo, e a saída fácil seria cravar um número: é exatamente o tipo de
  // premissa inventada que este repositório já pagou caro para não ter.
  //
  // Só que o prazo NÃO precisa ser inventado: a repartição curto/longo prazo do
  // balanço já É uma declaração de vencimento. Sob amortização linear em `n` anos, a
  // parcela que vence nos próximos 12 meses é `1/n` do saldo — logo `n = 1 ÷ fração
  // no circulante`, medido no último exercício realizado do próprio caso. Uma dívida
  // 40% circulante amortiza em 2,5 anos, e quem disse isso foi a demonstração.
  //
  // O limite superior de 10 anos existe porque dívida 100% de longo prazo levaria
  // `n → ∞` (fração zero), e um prazo infinito é dívida que nunca é paga — o defeito
  // que esta mudança veio corrigir. O inferior de 1 ano impede prazo fracionário
  // gerar amortização acima de 100% do saldo.
  const prazoImplicito = fracCP > 0
    ? Math.min(10, Math.max(1, Math.round((1 / fracCP) * 10) / 10))
    : 10;

  // A DÍVIDA DO BALANÇO, POR EXERCÍCIO REALIZADO — a origem de segunda instância.
  //
  // DEFEITO MEDIDO NO ARQUIVO ENTREGUE (v35): o mapa de dívida do caso tem UMA data
  // de referência (2025). Como `dividas` escolhe o mapa para todos os exercícios, o
  // balanço de 2024 saiu com dívida ZERO nas duas linhas — enquanto o documento
  // informa 22.972 no circulante e 11.393 no não circulante. O `CHECK` acusou 60.609
  // em 2024, e a maior parte disso era a dívida que desapareceu.
  //
  // A escolha de origem passa a ser POR EXERCÍCIO, não do modelo inteiro: onde o
  // mapa cobre, vale o mapa (é o detalhe por contrato); onde não cobre, vale a
  // dívida bancária do balanço daquele ano (é o número auditado, e ele nunca falta).
  // Nunca as duas no mesmo ano — somar as duas contaria a mesma dívida duas vezes —
  // e a nota da célula diz qual das duas foi usada naquele exercício.
  const dividaBalancoNoAno = (ano: number) =>
    somaBancaria("passivo_circulante", ano) + somaBancaria("passivo_nao_circulante", ano);
  const somaMapaNoAno = (ano: number) =>
    dividas.reduce((s, l) => s + Math.abs(valorNaEscala(l, ano, ctx.ent.unidade)?.valor ?? 0), 0);
  const anosSemMapa = ctx.hist.filter((ano) => somaMapaNoAno(ano) === 0 && dividaBalancoNoAno(ano) > 0);
  // Fração de curto prazo do PRÓPRIO exercício quando ele é conhecido: no realizado
  // a repartição não precisa ser estimada, ela está no balanço.
  const fracCPdoAno = (ano: number) => {
    const cp = somaBancaria("passivo_circulante", ano);
    const lp = somaBancaria("passivo_nao_circulante", ano);
    return cp + lp > 0 ? cp / (cp + lp) : fracCP;
  };

  // `P18` — o espelho desta aba, na ordem do Modelo Base: o que o balanço, a DRE
  // e o fluxo leem. As demonstrações NÃO conhecem as tranches.
  // NOTA DE DESENHO: as aplicações financeiras NÃO entram neste espelho de
  // propósito. No Modelo Base `Cash` e `ST Investments` são duas linhas do ativo;
  // aqui o caixa é UMA linha (`Balance Sheet!Caixa e equivalentes`) e a aplicação
  // é uma DECOMPOSIÇÃO dela — o excedente ao caixa mínimo. Publicá-la como conta
  // de balanço convidaria a somá-la ao caixa, que é exatamente a dupla contagem
  // que esta rodada corrigiu no giro. Ela vive no bloco `SHORT TERM INVESTMENTS`,
  // com a nota dizendo isso.
  g.espelho("BALANCE SHEET ACCOUNTS", [
    { chave: "ESP_REVOLVER", rotulo: "Revolver (fim do período)" },
    { chave: "ESP_DIVIDA_CP", rotulo: "Dívida de curto prazo (fim do período)" },
    { chave: "ESP_DIVIDA_LP", rotulo: "Dívida de longo prazo (fim do período)" },
  ]);
  g.espelho("INCOME STATEMENT ACCOUNTS", [
    { chave: "DESP_FIN", rotulo: "Despesa financeira total (juros e encargos)" },
    { chave: "REC_FIN", rotulo: "Receita financeira (rendimento das aplicações)" },
  ]);
  g.espelho("CASH FLOW ACCOUNTS", [
    { chave: "ESP_CAPTACAO", rotulo: "Captação de dívida no período" },
    { chave: "ESP_AMORT", rotulo: "Amortização de dívida no período" },
    { chave: "ESP_REVOLVER_MOV", rotulo: "Saque/(amortização) do revolver" },
    { chave: "ESP_JUROS_PIK", rotulo: "Juros do new money capitalizados (PIK, não-caixa)" },
  ]);

  // ---- premissas do instrumento, todas em coluna própria (como no Modelo Base,
  // que concentra margem, fee e % de amortização na coluna F) ------------------
  g.linha(null, { rotulo: "PREMISSAS DO ENDIVIDAMENTO", bloco: true });
  g.linha("CAIXA_MIN", { rotulo: "Caixa mínimo operacional", nota: "premissa", fmt: NUM });
  g.linha("CURVA_CDI", { rotulo: "Curva de juros de referência (CDI, da aba Anual)", fmt: PCT2 });
  g.linha("SPREAD_DIVIDA", { rotulo: "Spread sobre a curva (dívida existente)", nota: "premissa", fmt: PCT2 });
  g.linha("TAXA_MEDIA", { rotulo: "Custo efetivo da dívida — (1+curva)×(1+spread)−1", fmt: PCT2 });
  g.linha("SPREAD_REVOLVER", { rotulo: "Spread do revolver (dívida de emergência)", nota: "premissa", fmt: PCT2 });
  g.linha("TAXA_REVOLVER", { rotulo: "Custo efetivo do revolver", fmt: PCT2 });
  g.linha("SPREAD_APLIC", { rotulo: "% do CDI recebido na aplicação", nota: "premissa", fmt: PCT2 });
  g.linha("TAXA_APLIC", { rotulo: "Rendimento efetivo da aplicação", fmt: PCT2 });
  g.linha("FX_USD", { rotulo: "R$/US$ — final de período (da aba Anual)", fmt: NUM2 });
  g.pular();

  // ---- aplicações de curto prazo (o Modelo Base tem este bloco e nós não
  // tínhamos: sem ele o caixa excedente não rende e o modelo subestima o
  // resultado financeiro) -----------------------------------------------------
  g.linha(null, { rotulo: "SHORT TERM INVESTMENTS", bloco: true });
  g.linha("ST_INI", { rotulo: "Saldo de abertura", fmt: NUM });
  g.linha("ST_VAR", { rotulo: "Variação do período", fmt: NUM });
  g.linha("ST_FIM", { rotulo: "Saldo de fechamento", negrito: true, fmt: NUM });
  g.linha("ST_REND", { rotulo: "Rendimento do período", fmt: NUM });
  g.pular();

  g.linha(null, { rotulo: `TRANCHES DA DÍVIDA EXISTENTE — origem: ${origemDaDivida}`, bloco: true });
  for (const l of dividas) {
    const ch = chaveLinha("dv", l);
    g.linha(`${ch}#ini`, { rotulo: `${l.chave} — saldo de abertura`, fmt: NUM });
    g.linha(`${ch}#prazo`, { rotulo: "    prazo de amortização (anos)", fmt: NUM2 });
    g.linha(`${ch}#carencia`, { rotulo: "    carência (anos sem amortizar)", fmt: NUM2 });
    g.linha(`${ch}#pct`, { rotulo: "    % amortizado no período (SAC)", fmt: PCT });
    g.linha(`${ch}#amort`, { rotulo: "    amortização do período", fmt: NUM });
    g.linha(`${ch}#fim`, { rotulo: "    saldo de fechamento", fmt: NUM });
    g.linha(`${ch}#taxa`, { rotulo: "    custo efetivo aplicado", fmt: PCT2 });
    g.linha(`${ch}#juros`, { rotulo: "    juros do período", fmt: NUM });
    // A SOMBRA DO CRONOGRAMA ORIGINAL, que é o "antes" do reperfilamento. Ela
    // roda com carência ZERO e com o prazo IMPLÍCITO no balanço — não com o que
    // estiver digitado acima —, senão editar o prazo moveria os dois lados da
    // comparação e o alívio apareceria como zero.
    g.linha(`${ch}#ini0`, { rotulo: "    (antes) saldo de abertura", fmt: NUM });
    g.linha(`${ch}#amort0`, { rotulo: "    (antes) amortização do período", fmt: NUM });
    g.linha(`${ch}#juros0`, { rotulo: "    (antes) juros do período", fmt: NUM });
    // A CLASSIFICAÇÃO DO QUE CAI SEM CAIXA — só importa quando "Efeito caixa?"
    // desta tranche = N. Equity = conversão em participação: o saldo cai e o
    // patrimônio líquido sobe na mesma medida, sem passar pelo resultado
    // (dilui o acionista). Haircut = perdão/redução negociada: o saldo cai e
    // vira GANHO no resultado, abaixo do EBITDA — é reestruturação financeira,
    // não desempenho operacional. Sem esta chave as duas alavancas ficavam
    // misturadas na mesma linha de PL, e o comitê não conseguia separar
    // "converteu em capital" de "perdoou dívida".
    g.linha(`${ch}#classe`, {
      rotulo: "    classificação do saldo sem caixa (Equity ou Haircut)",
    });
  }
  // `P29 CHAVE-DE-EFEITO-CAIXA` — o Modelo Base tem uma célula por tranche com
  // validação de lista "S,N" (`ST Inv. & Debt!D128`) que decide se a amortização
  // daquela tranche SAI DO CAIXA. Existe porque dívida reperfilada, capitalizada
  // ou convertida em equity reduz o saldo SEM pagamento — e num mandato de
  // reestruturação isso é a regra, não a exceção. Sem essa chave, todo
  // reperfilamento aparece como saída de caixa que nunca aconteceu.
  for (const l of dividas) {
    const ch = chaveLinha("dv", l);
    const cel = g.celula(g.n(`${ch}#amort`), COL_NOTA);
    cel.value = "S";
    cel.fill = FILL_INPUT;
    cel.font = FONTE_ENTRADA;
    cel.alignment = { horizontal: "center" };
    cel.dataValidation = {
      type: "list", allowBlank: false, formulae: ['"S,N"'],
      showErrorMessage: true, errorTitle: "Efeito caixa",
      error: "S = a amortização desta tranche sai do caixa. N = o saldo cai sem pagamento "
        + "(reperfilamento, capitalização, conversão em equity).",
    };
    cel.note = comoNota(
      "EFEITO CAIXA desta tranche. S = a amortização sai do caixa e entra no fluxo de "
      + "financiamento. N = o saldo diminui SEM pagamento — é o caso de dívida reperfilada, "
      + "capitalizada ou convertida em participação. Marcar N aqui tira a saída do fluxo e "
      + "mantém a queda do saldo no balanço, que é o que de fato acontece.",
    );
  }
  if (dividas.length > 0) {
    g.celula(g.n(chaveLinha("dv", dividas[0]) + "#amort") - 1, COL_NOTA).value = "Efeito caixa?";
  }
  // `P30 CHAVE-DE-CLASSIFICAÇÃO` — o dropdown "Equity,Haircut" por tranche, que
  // decide o destino do saldo marcado "Efeito caixa? = N" acima. Nasce em
  // "Equity" para preservar exatamente o comportamento anterior (que sempre
  // tratou a queda de saldo sem caixa como conversão em participação).
  for (const l of dividas) {
    const ch = chaveLinha("dv", l);
    const cel = g.celula(g.n(`${ch}#classe`), COL_NOTA);
    cel.value = "Equity";
    cel.fill = FILL_INPUT;
    cel.font = FONTE_ENTRADA;
    cel.alignment = { horizontal: "center" };
    cel.dataValidation = {
      type: "list", allowBlank: false, formulae: ['"Equity,Haircut"'],
      showErrorMessage: true, errorTitle: "Classificação do reperfilamento",
      error: "Equity = a queda de saldo vira capital (diluição, sem efeito no resultado). Haircut = a "
        + "queda vira ganho no resultado, fora do EBITDA. Só importa quando \"Efeito caixa?\" = N.",
    };
    cel.note = comoNota(
      "Só importa quando \"Efeito caixa?\" desta tranche = N. Equity = conversão em participação — o "
      + "saldo cai e o patrimônio líquido sobe na mesma medida, direto, sem passar pelo resultado "
      + "(dilui o acionista). Haircut = perdão/redução negociada — o saldo cai e o modelo reconhece "
      + "um GANHO no resultado, abaixo do EBITDA (bloco 'Ganho com redução negociada de dívida' na "
      + "Income Statement), sujeito a imposto como qualquer outro resultado.",
    );
  }
  if (anosSemMapa.length > 0) {
    g.linha("DIV_BALANCO", {
      rotulo: "Dívida bancária do balanço (exercício que o mapa não cobre)", fmt: NUM,
      nota: "realizado, do balanço",
    });
  }
  g.linha("TOTAL_DIVIDA", { rotulo: "DÍVIDA EXISTENTE (fechamento)", negrito: true, topo: true, fmt: NUM });
  g.linha("TOTAL_AMORT_CAIXA", { rotulo: "    da qual COM efeito caixa", fmt: NUM });
  g.linha("TOTAL_AMORT_EQUITY", { rotulo: "    da qual SEM caixa, classificada como Equity", fmt: NUM });
  g.linha("TOTAL_AMORT_HAIRCUT", { rotulo: "    da qual SEM caixa, classificada como Haircut", fmt: NUM });
  g.linha("TOTAL_AMORT", { rotulo: "Amortização total do período", fmt: NUM });
  g.linha("TOTAL_JUROS", { rotulo: "Juros totais do período", fmt: NUM });
  g.linha("SERVICO_ORIG", {
    rotulo: "Serviço das tranches ANTES do reperfilamento (cronograma original)", fmt: NUM,
    nota: "Amortização mais juros que as tranches existentes exigiriam no cronograma que veio do "
      + "balanço: sem carência e no prazo implícito. É o \"antes\" do bloco de reperfilamento do "
      + "Output, e não muda quando alguém edita prazo ou carência acima — se mudasse, os dois lados "
      + "da comparação andariam juntos e o alívio sairia sempre zero.",
  });
  g.pular();

  // ---- DÍVIDA NOVA POR SAFRA (`P14`) ---------------------------------------
  // O Modelo Base dedica 43 linhas a isto (`% Amt Issuance #0…#42`): cada
  // captação anual tem sua PRÓPRIA linha de amortização, e a linha só paga a
  // partir do ano em que a safra existe, parando quando o acumulado atinge o
  // principal. É o que permite modelar carência e prazo diferentes por captação
  // — o que um "% do saldo" único não consegue expressar.
  g.linha(null, { rotulo: "DEBT ISSUANCE — CAPTAÇÃO NOVA, AMORTIZADA POR SAFRA", bloco: true });
  g.linha("EMISSAO_PRAZO", { rotulo: "Prazo de amortização da captação nova (anos)", nota: "premissa", fmt: NUM2 });
  g.linha("EMISSAO_SPREAD", { rotulo: "Spread da captação nova", nota: "premissa", fmt: PCT2 });
  g.linha("EMISSAO_TAXA", { rotulo: "Custo efetivo da captação nova", fmt: PCT2 });
  for (const ano of ctx.proj) {
    g.linha(`emis:${ano}`, { rotulo: `Captação de ${ano} (principal)`, fmt: NUM });
  }
  g.linha("EMISSAO_TOTAL", { rotulo: "Captação do período", negrito: true, topo: true, fmt: NUM });
  for (const ano of ctx.proj) {
    g.linha(`amort:${ano}`, { rotulo: `    amortização da safra de ${ano}`, fmt: NUM });
  }
  g.linha("EMISSAO_AMORT", { rotulo: "Amortização das safras novas", negrito: true, topo: true, fmt: NUM });
  g.linha("EMISSAO_SALDO", { rotulo: "Saldo das captações novas", negrito: true, fmt: NUM });
  g.linha("EMISSAO_JUROS", { rotulo: "Juros das captações novas", fmt: NUM });
  g.pular();

  // ---- NEW MONEY — o dinheiro novo DA REESTRUTURAÇÃO, rotulado à parte -----
  //
  // Mecanicamente é uma tranche só (SAC com carência, a mesma matemática das
  // "TRANCHES DA DÍVIDA EXISTENTE" acima) — o que muda é o propósito: uma
  // única captação, no fechamento do plano, com termo e prioridade
  // NEGOCIADOS para ESTE mandato. Reaproveitar o motor de "DEBT ISSUANCE"
  // (captação por safra) misturaria refinanciamento de operação normal com
  // dinheiro novo de reestruturação na MESMA linha — e são leituras
  // diferentes para o comitê, mesmo quando o número é parecido.
  g.linha(null, { rotulo: "NEW MONEY — dinheiro novo da reestruturação (termo e prioridade próprios)", bloco: true });
  g.linha("NM_VALOR", { rotulo: "Principal captado no fechamento (1º ano projetado)", nota: "premissa de negociação", fmt: NUM });
  g.linha("NM_PRAZO", { rotulo: "    prazo de amortização (anos)", fmt: NUM2 });
  g.linha("NM_CARENCIA", { rotulo: "    carência (anos sem amortizar)", fmt: NUM2 });
  g.linha("NM_SPREAD", { rotulo: "    spread negociado", fmt: PCT2 });
  g.linha("NM_TAXA", { rotulo: "    custo efetivo", fmt: PCT2 });
  g.linha("NM_INI", { rotulo: "    saldo de abertura", fmt: NUM });
  g.linha("NM_PCT", { rotulo: "    % amortizado no período (SAC)", fmt: PCT });
  g.linha("NM_AMORT", { rotulo: "    amortização do período (sempre em caixa)", fmt: NUM });
  g.linha("NM_FIM", { rotulo: "Saldo do new money (fechamento)", negrito: true, fmt: NUM });
  g.linha("NM_JUROS", { rotulo: "    juros do período (despesa — entra no resultado mesmo em PIK)", fmt: NUM });
  g.linha("NM_JUROS_PIK", {
    rotulo: "    dos quais capitalizados (PIK — somam ao saldo, não saem do caixa)", fmt: NUM,
  });
  g.pular();

  g.linha(null, { rotulo: "ADDITIONAL LEVERAGE — REVOLVER", bloco: true });
  g.linha("REVOLVER_INI", { rotulo: "Revolver — saldo de abertura", fmt: NUM });
  g.linha("REVOLVER_SAQUE", { rotulo: "Saque/(amortização) do revolver", fmt: NUM });
  g.linha("REVOLVER_FIM", { rotulo: "Revolver — saldo de fechamento", negrito: true, fmt: NUM });
  g.linha("REVOLVER_JUROS", { rotulo: "Juros do revolver", fmt: NUM });
  g.pular();
  g.linha("DIVIDA_BRUTA", { rotulo: "DÍVIDA BRUTA TOTAL", negrito: true, topo: true, fmt: NUM });
  g.linha("DIVIDA_LIQUIDA", { rotulo: "DÍVIDA LÍQUIDA (bruta − caixa − aplicações)", negrito: true, fmt: NUM });

  // Os dois dropdowns do new money — PIK e prioridade — são cabeçalho, não
  // dado por ano: uma célula só, no mesmo desenho da "Efeito caixa?" acima.
  {
    const celPik = g.celula(g.n("NM_JUROS"), COL_NOTA);
    celPik.value = "N";
    celPik.fill = FILL_INPUT;
    celPik.font = FONTE_ENTRADA;
    celPik.alignment = { horizontal: "center" };
    celPik.dataValidation = {
      type: "list", allowBlank: false, formulae: ['"S,N"'],
      showErrorMessage: true, errorTitle: "PIK",
      error: "S = o juro do new money SOMA ao saldo em vez de sair do caixa (PIK — payment in "
        + "kind). N = o juro sai do caixa normalmente.",
    };
    celPik.note = comoNota(
      "PIK (payment in kind) do new money. S = o juro NÃO sai do caixa — capitaliza, aumentando "
      + "o saldo (linha `NM_JUROS_PIK`, e o Cash Flow soma de volta como não-caixa, igual à "
      + "depreciação). N = juro pago normalmente. O juro sempre entra no RESULTADO (reduz o lucro "
      + "tributável) nos dois casos — PIK muda só o CAIXA, não o lucro.",
    );
    g.celula(g.n("NM_JUROS") - 1, COL_NOTA).value = "PIK?";

    const celPrioridade = g.celula(g.n("NM_VALOR"), COL_NOTA);
    celPrioridade.value = "Sênior";
    celPrioridade.fill = FILL_INPUT;
    celPrioridade.font = FONTE_ENTRADA;
    celPrioridade.alignment = { horizontal: "center" };
    celPrioridade.dataValidation = {
      type: "list", allowBlank: false,
      formulae: ['"Super sênior,Sênior,Pari passu,Júnior"'],
      showErrorMessage: true, errorTitle: "Prioridade",
      error: "A posição do new money na fila de recebimento, em relação à dívida existente. "
        + "Informativo — a planilha não simula uma cascata de prioridade legal.",
    };
    celPrioridade.note = comoNota(
      "Prioridade do new money frente à dívida existente — informativo, para o comitê ver a "
      + "hierarquia à primeira vista. \"Super sênior\" é o padrão de dinheiro novo em "
      + "reestruturação (à frente até dos credores garantidos antigos); a planilha não simula "
      + "uma cascata de prioridade legal, só rotula.",
    );
    g.celula(g.n("NM_VALOR") - 1, COL_NOTA).value = "Prioridade";
  }

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("CAIXA_MIN", ano, ctx.ent.caixaMinimo, { fmt: NUM, fill: FILL_INPUT });
    // Taxa média: implícita no mapa quando ele traz juros e saldo; premissa
    // quando não traz. Sem os dois, ZERO com aviso — juros inventado num modelo
    // de reestruturação é o número que decide se a empresa cabe no plano.
    const somaSaldo = dividas.reduce((s, l) => s + (l.valores[String(ctx.ultimoHist)] ?? 0), 0);
    const somaJuros = jurosDoMapa.reduce((s, l) => s + Math.abs(l.valores[String(ctx.ultimoHist)] ?? 0), 0);
    const taxaImplicita = somaSaldo > 0 ? somaJuros / somaSaldo : 0;
    // TAXA MÉDIA DA DÍVIDA, em três degraus de qualidade, nesta ordem:
    //   1. IMPLÍCITA no mapa da dívida (juros ÷ saldo) — o custo que a empresa
    //      efetivamente paga, medido no documento dela;
    //   2. o CDI da aba Anual (dado versionado), quando o mapa não traz juros —
    //      e declarado como PISO, porque dívida de empresa em reestruturação
    //      custa mais que CDI;
    //   3. zero, com aviso, quando não há nem um nem outro.
    // Nunca um número inventado: num mandato de reestruturação a taxa da dívida é
    // o que decide se a empresa cabe no plano.
    const refCDI = gAnual.tem("macro:CDI")
      ? `${Grade.refExterna("Anual", gAnual.letraDoAno(ano), gAnual.n("macro:CDI"))}/100`
      : null;
    // `P16 CURVA-MACRO` — a curva vem da aba Anual, dado versionado, e o consumo
    // divide por 100 porque a série está em pontos percentuais. É o mesmo contrato
    // do Modelo Base, com uma diferença que corrige o defeito dele: lá a série da
    // Libor carrega o TEXTO "nd" a partir de 2021, e `=Anual!AC86/100` virou
    // #VALUE! que apagou o resultado dos últimos 11 anos do modelo (§20.1 do
    // mapa). Aqui ano sem publicação fica VAZIO (nunca texto) e o consumo tem
    // guarda `N()`, que trata vazio como zero e não propaga erro.
    const curva = refCDI ? `=N(${refCDI})` : null;
    // O ANO SEM CURVA diz o EFEITO. Medido em 01/10/2026: CDI vazio em 2027-2030 zerava
    // TAXA_REVOLVER, TAXA_APLIC, EMISSAO_TAXA, NM_TAXA e a TAXA_MEDIA sem juros no mapa —
    // revolver de ~21 mi grátis — e a nota não dizia nada (afirmava "projetado Focus").
    const semCurva = refCDI !== null
      && gAnual.celula(gAnual.n("macro:CDI"), gAnual.colDoAno(ano)).value == null;
    g.set("CURVA_CDI", ano, curva ?? 0, {
      fmt: PCT2,
      nota: semCurva
        ? `Sem curva de CDI para ${ano}: nem CDI realizado de 12 meses, nem Selic (Focus ou realizada) para `
          + "usar de proxy. revolver/aplicação/new money cobram juro ZERO neste ano, e a taxa média da "
          + "dívida também quando o mapa não traz juros — rever antes de comitê."
        : curva
        ? "Curva de referência da aba Anual, em pontos percentuais: CDI realizado de 12 meses nos anos "
          + "fechados e, nos projetados, uma APROXIMAÇÃO a partir das metas de Selic de fim de ano do Focus "
          + "(realizado composto com a meta no ano corrente; média das metas de t-1 e t nos seguintes; o Focus "
          + "NÃO publica CDI nem a taxa acumulada — ver a nota da célula na aba Anual) "
          + "— daí o /100. O N() trata ano sem publicação como zero em vez de propagar erro: é a "
          + "guarda que falta no Modelo Base, onde um 'nd' na série da Libor apagou o resultado de "
          + "11 anos de projeção."
        : "Sem série de CDI na aba Anual: zero, com aviso.",
    });
    // O SPREAD É DERIVADO DO CUSTO MEDIDO, não arbitrado: se o mapa da dívida traz
    // juros e saldo, o custo implícito é fato do documento, e o spread é o que
    // falta para a curva chegar nele. Assim a composição (1+curva)×(1+spread)−1
    // reproduz o custo real do caso, e mexer na curva move o custo junto.
    const spread = taxaImplicita > 0 && curva
      ? null // calculado por fórmula abaixo, para acompanhar a curva
      : 0;
    if (taxaImplicita > 0 && curva) {
      g.set("SPREAD_DIVIDA", ano, `=IF((1+${g.ref("CURVA_CDI", ano)})=0,0,(1+${taxaImplicita})/(1+${g.ref("CURVA_CDI", ano)})-1)`, {
        fmt: PCT2, fill: FILL_INPUT,
        nota: `Spread DERIVADO do custo implícito medido no mapa da dívida deste caso: juros `
          + `${Math.round(somaJuros)} ÷ saldo ${Math.round(somaSaldo)} = ${(taxaImplicita * 100).toFixed(2)}% a.a. `
          + "O spread é o que falta para a curva chegar nesse custo — então o número total é o do "
          + "documento, e não uma taxa de mercado chutada.",
      });
    } else {
      g.set("SPREAD_DIVIDA", ano, taxaImplicita > 0 ? taxaImplicita : (spread ?? 0), {
        fmt: PCT2, fill: FILL_INPUT,
        nota: taxaImplicita > 0
          ? "Sem curva na aba Anual: o custo implícito medido no mapa entra inteiro como spread."
          : "O mapa da dívida não traz juros e saldo no mesmo exercício: spread ZERO, e o custo "
            + "fica igual à curva. É PISO — dívida de empresa em reestruturação custa mais que CDI, "
            + "e este número tem de ser revisto antes de ir a comitê.",
      });
    }
    // `P15 CUSTO-COMPOSTO` — composição, não soma. Somar curva e spread erra por
    // curva×spread, que a 10% e 5% já é 50 pontos-base.
    g.set("TAXA_MEDIA", ano, `=((1+${g.ref("CURVA_CDI", ano)})*(1+${g.ref("SPREAD_DIVIDA", ano)}))-1`, {
      fmt: PCT2, negrito: true,
      nota: "Custo efetivo = (1+curva)×(1+spread)−1. A composição não é soma.",
    });
    g.set("SPREAD_REVOLVER", ano, `=${g.ref("SPREAD_DIVIDA", ano)}`, {
      fmt: PCT2, fill: FILL_INPUT,
      nota: "Spread do revolver, inicializado IGUAL ao da dívida existente. Na prática dívida de "
        + "emergência custa mais; este valor é PISO e a célula existe para o analista subir. "
        + "Inventar um prêmio aqui seria inventar o número que decide se a empresa cabe no plano.",
    });
    g.set("TAXA_REVOLVER", ano, `=((1+${g.ref("CURVA_CDI", ano)})*(1+${g.ref("SPREAD_REVOLVER", ano)}))-1`, { fmt: PCT2 });
    g.set("SPREAD_APLIC", ano, 1, {
      fmt: PCT2, fill: FILL_INPUT,
      nota: "Percentual da curva que a aplicação rende. 100% = rende a taxa de referência, que é o "
        + "valor NEUTRO. Um CDB de empresa em dificuldade rende menos; baixar aqui é premissa.",
    });
    g.set("TAXA_APLIC", ano, `=${g.ref("CURVA_CDI", ano)}*${g.ref("SPREAD_APLIC", ano)}`, { fmt: PCT2 });
    const refFX = gAnual.tem("macro:CAMBIO_USD")
      ? Grade.refExterna("Anual", gAnual.letraDoAno(ano), gAnual.n("macro:CAMBIO_USD"))
      : null;
    g.set("FX_USD", ano, refFX ? `=${refFX}` : null, {
      fmt: NUM2,
      nota: refFX
        ? "R$/US$ de final de período, da aba Anual. É série de NÍVEL (não percentual), então NÃO "
          + "leva /100 — confundir as duas erra por 100×."
        : "Sem série de câmbio na aba Anual para este ano. Célula VAZIA: dívida em moeda "
          + "estrangeira não pode ser convertida por número inventado.",
    });

    // ---- aplicações: DECOMPOSIÇÃO do caixa, não ativo adicional -------------
    g.set("ST_INI", ano, ant === null ? 0 : `=${g.ref("ST_FIM", ant)}`, { fmt: NUM });
    g.set("ST_VAR", ano, `=${g.ref("ST_FIM", ano)}-${g.ref("ST_INI", ano)}`, { fmt: NUM });
    g.set("ST_REND", ano, `=${g.ref("ST_INI", ano)}*${g.ref("TAXA_APLIC", ano)}`, {
      fmt: NUM,
      nota: "Rendimento sobre o saldo de ABERTURA da aplicação. " + NOTA_CIRCULARIDADE,
    });

    for (const l of dividas) {
      const ch = chaveLinha("dv", l);
      if (hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (e) g.set(`${ch}#fim`, ano, Math.abs(e.valor), { fmt: NUM, fill: FILL_HIST, nota: e.nota, tipo: "calc" });
        else if (notaSemValor(l, ano)) g.set(`${ch}#fim`, ano, null, { fmt: NUM, fill: FILL_HIST, nota: notaSemValor(l, ano), tipo: "calc" });
        continue;
      }
      // ABERTURA: normalmente o fechamento do ano anterior. Quando a tranche não
      // tem saldo no último realizado, cai para o último ano em que teve — e diz.
      const anoSaldo = ultimoAnoComSaldo.get(l);
      const abreEm = iProjDoAno(ano) === 0 && anoSaldo != null && anoSaldo !== ant ? anoSaldo : ant!;
      g.set(`${ch}#ini`, ano, `=${g.ref(`${ch}#fim`, abreEm)}`, {
        fmt: NUM,
        nota: abreEm === ant
          ? undefined
          : `Esta tranche NÃO tem saldo no último exercício realizado (${ant}). A projeção abre no `
            + `último saldo conhecido, de ${abreEm}, e esta nota existe para o número não passar por `
            + "fato do documento.\n\nA alternativa seria abrir em ZERO, e zero aqui afirmaria que a "
            + "dívida foi quitada — o documento não disse isso. Se ela foi mesmo liquidada, apague "
            + "esta célula; se o mapa perdeu a coluna, é dado a reconciliar com quem o produziu.",
      });
      // `iProj` = 0 no PRIMEIRO exercício projetado. O prazo é uma premissa só, na
      // primeira coluna projetada; os anos seguintes apontam para ela, então UMA
      // edição reprojeta a tranche inteira dentro do Excel.
      const iProj = g.anos.indexOf(ano) - g.nHist;
      const refPrazoBase = g.ref(`${ch}#prazo`, g.anos[g.nHist], "$");
      g.set(`${ch}#prazo`, ano, iProj === 0 ? prazoImplicito : `=${refPrazoBase}`, {
        fmt: NUM2, fill: iProj === 0 ? FILL_INPUT : undefined,
        nota: iProj === 0
          ? `Prazo de amortização desta tranche, em anos: ${prazoImplicito}. NÃO é número `
            + (fracCPMedida
              ? `inventado — é o prazo IMPLÍCITO no balanço de ${ctx.ultimoHist}: `
                + `${(fracCP * 100).toFixed(1)}% da dívida bancária está no circulante, e sob `
                + "amortização linear a parcela de 12 meses é 1/n do saldo, logo n = 1 ÷ 0,"
                + `${(fracCP * 100).toFixed(0)} = ${prazoImplicito} anos. Quem declarou o prazo foi a `
                + "demonstração. Se o contrato disser outra coisa, troque AQUI: a linha de % abaixo "
                + "e todos os exercícios seguintes se refazem sozinhos."
              : "inventado por falta de opção melhor: este caso não tem dívida bancária repartida "
                + "entre circulante e não circulante no último exercício, então o prazo implícito "
                + "não pôde ser medido e vale o teto de 10 anos. Troque AQUI pelo prazo do contrato.")
          : "Mesmo prazo da primeira coluna projetada (referência fixa). Edite a célula azul de lá, "
            + "não esta.",
      });
      // AMORTIZAÇÃO LINEAR (SAC), decisão do dono de 07/08/2026. A parcela é
      // constante: 1/n do saldo no primeiro ano, 1/(n−1) do que sobrou no segundo, e
      // assim por diante — o que dá SEMPRE o mesmo principal, e zera a tranche
      // exatamente no vencimento. Antes esta célula era ZERO fixo ("dívida rolada
      // integralmente"), que parece conservador e não é: dívida que nunca amortiza
      // não consome caixa nenhum no horizonte, e o fluxo projetado saía melhor do que
      // a empresa vai viver.
      //
      // O `MIN(1;…)` é o cinto de segurança do prazo fracionário: com n = 0,5 a conta
      // daria 200% do saldo, e uma tranche amortizaria mais do que deve.
      // A CARÊNCIA, e ela é a alavanca de reestruturação que faltava.
      //
      // Durante os anos de carência a tranche NÃO amortiza e continua rendendo
      // juros — que é o que um alongamento negociado faz. Depois dela, o que
      // sobrou se reparte no prazo que resta: é carência DENTRO do prazo, não
      // além dele. Para empurrar o vencimento junto, o caminho é aumentar o
      // prazo na célula acima, e as duas coisas se somam.
      const refCarencia = g.ref(`${ch}#carencia`, g.anos[g.nHist], "$");
      g.set(`${ch}#carencia`, ano, iProj === 0 ? 0 : `=${refCarencia}`, {
        fmt: NUM2, fill: iProj === 0 ? FILL_INPUT : undefined,
        nota: iProj === 0
          ? "CARÊNCIA em anos: quantos exercícios esta tranche passa sem amortizar. Nasce em ZERO, "
            + "porque carência é negociação e não fato do balanço. Durante a carência a dívida "
            + "continua rendendo juros; depois dela o saldo se reparte no prazo que resta, então "
            + "a parcela sobe. Para empurrar o vencimento junto, aumente também o prazo acima.\n\n"
            + "O efeito no serviço da dívida aparece no bloco REPERFILAMENTO do Output, comparado "
            + "com o cronograma original."
          : "Mesma carência da primeira coluna projetada. Edite a célula azul de lá, não esta.",
      });
      g.set(`${ch}#pct`, ano,
        `=IF(${iProj}<${g.ref(`${ch}#carencia`, ano)},0,`
        + `IF(${g.ref(`${ch}#prazo`, ano)}-${iProj}<=0,0,MIN(1,1/(${g.ref(`${ch}#prazo`, ano)}-${iProj}))))`, {
        fmt: PCT,
        nota: "Amortização LINEAR (SAC) até o vencimento: 1 ÷ (prazo − anos já decorridos), e ZERO "
          + "enquanto durar a carência. Dá parcela de principal constante e zera a tranche no "
          + "vencimento. Depois do vencimento a célula devolve zero — não existe amortização "
          + "negativa. Para um cronograma irregular (balão), digite o percentual do ano por cima "
          + "desta fórmula: o saldo e os juros seguem a célula.",
      });
      g.set(`${ch}#amort`, ano, `=${g.ref(`${ch}#ini`, ano)}*${g.ref(`${ch}#pct`, ano)}`, { fmt: NUM });
      g.set(`${ch}#fim`, ano, `=${g.ref(`${ch}#ini`, ano)}-${g.ref(`${ch}#amort`, ano)}`, { fmt: NUM });
      g.set(`${ch}#taxa`, ano, `=${g.ref("TAXA_MEDIA", ano)}`, { fmt: PCT2 });
      // Juros sobre o saldo de ABERTURA — ver NOTA_CIRCULARIDADE.
      g.set(`${ch}#juros`, ano, `=-${g.ref(`${ch}#ini`, ano)}*${g.ref(`${ch}#taxa`, ano)}`,
        { fmt: NUM, nota: NOTA_CIRCULARIDADE });

      // ---- A SOMBRA DO CRONOGRAMA ORIGINAL ("antes") ----------------------
      //
      // Mesma matemática, com dois números CONGELADOS: carência zero e o prazo
      // implícito no balanço, escrito como literal. Referenciar as células
      // editáveis faria os dois lados da comparação andarem juntos, e o alívio
      // do reperfilamento sairia sempre zero — que é justamente o defeito que
      // um bloco "antes × depois" precisa não ter.
      const pct0 = prazoImplicito - iProj <= 0
        ? 0
        : Math.min(1, 1 / (prazoImplicito - iProj));
      g.set(`${ch}#ini0`, ano,
        iProj === 0 ? `=${g.ref(`${ch}#ini`, ano)}` : `=${g.ref(`${ch}#ini0`, ant!)}*${(1 - (prazoImplicito - (iProj - 1) <= 0 ? 0 : Math.min(1, 1 / (prazoImplicito - (iProj - 1))))).toFixed(6)}`,
        { fmt: NUM, nota: "Saldo que esta tranche teria no cronograma original, sem carência." });
      g.set(`${ch}#amort0`, ano, `=${g.ref(`${ch}#ini0`, ano)}*${pct0.toFixed(6)}`, { fmt: NUM });
      g.set(`${ch}#juros0`, ano, `=-${g.ref(`${ch}#ini0`, ano)}*${g.ref(`${ch}#taxa`, ano)}`, { fmt: NUM });
    }
    // A dívida do exercício, com a origem decidida POR ANO (ver `anosSemMapa`).
    if (g.tem("DIV_BALANCO")) {
      const doBalancoNoAno = hist ? dividaBalancoNoAno(ano) : 0;
      g.set("DIV_BALANCO", ano, hist ? doBalancoNoAno : 0, {
        fmt: NUM, fill: hist ? FILL_HIST : undefined, tipo: "calc",
        nota: hist
          ? "Soma das linhas de dívida bancária do balanço deste exercício (empréstimos, "
            + "financiamentos, debêntures, arrendamentos), em módulo. Serve de saldo quando o mapa "
            + "de dívida não cobre o ano."
          : "Zero no projetado: daí em diante quem manda são as tranches e as safras novas.",
      });
    }
    if (hist && anosSemMapa.includes(ano)) {
      g.set("TOTAL_DIVIDA", ano, `=${g.ref("DIV_BALANCO", ano)}`, {
        fmt: NUM, negrito: true,
        nota: `Exercício ${ano}: o mapa de dívida NÃO traz saldo para este ano, então o saldo vem `
          + "da dívida bancária do balanço — uma origem por exercício, nunca as duas somadas. "
          + "Antes esta célula saía ZERO e o balanço abria exatamente no valor da dívida.",
      });
    } else {
      somaOuZero(g, "TOTAL_DIVIDA", ano, dividas.map((l) => g.ref(chaveLinha("dv", l) + "#fim", ano)), true);
    }
    somaOuZero(g, "TOTAL_AMORT", ano, dividas.map((l) => g.ref(chaveLinha("dv", l) + "#amort", ano)));
    somaOuZero(g, "TOTAL_JUROS", ano, dividas.map((l) => g.ref(chaveLinha("dv", l) + "#juros", ano)));
    // O SERVIÇO DO CRONOGRAMA ORIGINAL: amortização mais juros, em módulo, como
    // a linha de serviço do Output. É o "antes" da comparação.
    somaOuZero(g, "SERVICO_ORIG", ano,
      dividas.flatMap((l) => [
        g.ref(chaveLinha("dv", l) + "#amort0", ano),
        `ABS(${g.ref(chaveLinha("dv", l) + "#juros0", ano)})`,
      ]));
    somaOuZero(g, "TOTAL_AMORT_CAIXA", ano, dividas.map((l) => {
      const chAmort = chaveLinha("dv", l) + "#amort";
      const chave = `$${colLetra(COL_NOTA)}$${g.n(chAmort)}`;
      return `IF(${chave}="S",${g.ref(chAmort, ano)},0)`;
    }));
    // A REPARTIÇÃO DO QUE CAI SEM CAIXA: Equity de um lado, Haircut do outro,
    // pela chave `#classe` de cada tranche. Por construção,
    // TOTAL_AMORT_EQUITY + TOTAL_AMORT_HAIRCUT = TOTAL_AMORT − TOTAL_AMORT_CAIXA
    // sempre — nenhuma tranche marcada "Efeito caixa? = N" fica de fora das duas.
    somaOuZero(g, "TOTAL_AMORT_EQUITY", ano, dividas.map((l) => {
      const chAmort = chaveLinha("dv", l) + "#amort";
      const chaveCaixa = `$${colLetra(COL_NOTA)}$${g.n(chAmort)}`;
      const chaveClasse = `$${colLetra(COL_NOTA)}$${g.n(chaveLinha("dv", l) + "#classe")}`;
      return `IF(AND(${chaveCaixa}="N",${chaveClasse}="Equity"),${g.ref(chAmort, ano)},0)`;
    }));
    somaOuZero(g, "TOTAL_AMORT_HAIRCUT", ano, dividas.map((l) => {
      const chAmort = chaveLinha("dv", l) + "#amort";
      const chaveCaixa = `$${colLetra(COL_NOTA)}$${g.n(chAmort)}`;
      const chaveClasse = `$${colLetra(COL_NOTA)}$${g.n(chaveLinha("dv", l) + "#classe")}`;
      return `IF(AND(${chaveCaixa}="N",${chaveClasse}="Haircut"),${g.ref(chAmort, ano)},0)`;
    }));

    // ---- `P14` captação nova, uma safra por ano -----------------------------
    g.set("EMISSAO_PRAZO", ano, PRAZO_EMISSAO_PADRAO, {
      fmt: NUM2, fill: FILL_INPUT,
      nota: `Prazo de amortização da dívida nova, em anos. ${PRAZO_EMISSAO_PADRAO} é o default do `
        + "modelo, não um dado do caso: cada safra amortiza em parcelas iguais nesse prazo, a partir "
        + "do ano seguinte à captação (carência de um ano).",
    });
    g.set("EMISSAO_SPREAD", ano, `=${g.ref("SPREAD_DIVIDA", ano)}`, {
      fmt: PCT2, fill: FILL_INPUT,
      nota: "Spread da captação nova, inicializado igual ao da dívida existente.",
    });
    g.set("EMISSAO_TAXA", ano, `=((1+${g.ref("CURVA_CDI", ano)})*(1+${g.ref("EMISSAO_SPREAD", ano)}))-1`, { fmt: PCT2 });
    for (const safra of ctx.proj) {
      const chE = `emis:${safra}`;
      const chA = `amort:${safra}`;
      if (hist) { g.set(chE, ano, 0, { fmt: NUM, tipo: "calc" }); g.set(chA, ano, 0, { fmt: NUM, tipo: "calc" }); continue; }
      g.set(chE, ano, safra === ano ? 0 : null, safra === ano
        ? {
          fmt: NUM, fill: FILL_INPUT,
          nota: `Principal captado em ${safra}. ZERO por padrão: dívida nova é decisão do plano, `
            + "não default de planilha. Preencher aqui cria a safra, com cronograma próprio.",
        }
        : { fmt: NUM });
      // A safra só amortiza DEPOIS do ano da captação e por `prazo` anos.
      const k = ano - safra;
      const refPrazo = g.ref("EMISSAO_PRAZO", ctx.proj[0], "$");
      g.set(chA, ano,
        k <= 0 ? 0 : `=IF(${refPrazo}<=0,0,IF(${k}<=${refPrazo},${g.ref(chE, safra, "$")}/${refPrazo},0))`,
        {
          fmt: NUM,
          nota: k <= 0
            ? "Carência: a safra do próprio ano não amortiza no ano da captação."
            : `Parcela ${k} de ${PRAZO_EMISSAO_PADRAO} da safra de ${safra}. A linha para de pagar `
              + "quando o prazo termina — é o mecanismo das 43 linhas '% Amt Issuance' do Modelo Base, "
              + "escrito com uma safra por ano em vez de 43 linhas fixas.",
        });
    }
    somaOuZero(g, "EMISSAO_TOTAL", ano, ctx.proj.map((s) => g.ref(`emis:${s}`, ano)), true);
    somaOuZero(g, "EMISSAO_AMORT", ano, ctx.proj.map((s) => g.ref(`amort:${s}`, ano)), true);
    g.set("EMISSAO_SALDO", ano,
      ant === null
        ? `=${g.ref("EMISSAO_TOTAL", ano)}-${g.ref("EMISSAO_AMORT", ano)}`
        : `=${g.ref("EMISSAO_SALDO", ant)}+${g.ref("EMISSAO_TOTAL", ano)}-${g.ref("EMISSAO_AMORT", ano)}`,
      { fmt: NUM, negrito: true });
    // Meia safra de juros no ano da captação (convenção de meio-ano, a mesma do
    // capex). Cobrar o ano inteiro sobre dinheiro que entrou em julho superestima
    // a despesa; não cobrar nada a subestima.
    g.set("EMISSAO_JUROS", ano,
      ant === null
        ? `=-${g.ref("EMISSAO_TOTAL", ano)}/2*${g.ref("EMISSAO_TAXA", ano)}`
        : `=-(${g.ref("EMISSAO_SALDO", ant)}+${g.ref("EMISSAO_TOTAL", ano)}/2)*${g.ref("EMISSAO_TAXA", ano)}`,
      { fmt: NUM, nota: "Juros sobre o saldo de abertura mais meia safra da captação do ano." });

    // ---- NEW MONEY — mesma matemática SAC das tranches existentes, uma
    // tranche só, drenada no primeiro ano projetado (`iProjNM === 0`). ------
    if (hist) {
      for (const ch of ["NM_VALOR", "NM_PRAZO", "NM_CARENCIA", "NM_SPREAD", "NM_TAXA", "NM_INI",
                        "NM_PCT", "NM_AMORT", "NM_FIM", "NM_JUROS", "NM_JUROS_PIK"]) {
        g.set(ch, ano, 0, { fmt: NUM, tipo: "calc" });
      }
    } else {
      const iProjNM = g.anos.indexOf(ano) - g.nHist;
      g.set("NM_VALOR", ano, 0, {
        fmt: NUM, fill: iProjNM === 0 ? FILL_INPUT : undefined,
        nota: iProjNM === 0
          ? "Principal do new money, ZERO por padrão: dinheiro novo é decisão do plano, não default "
            + "de planilha. Uma tranche só, drenada neste ano — o fechamento do plano."
          : "O new money entra só no primeiro ano projetado; esta célula fica em zero.",
      });
      g.set("NM_PRAZO", ano, PRAZO_EMISSAO_PADRAO, {
        fmt: NUM2, fill: FILL_INPUT,
        nota: "Prazo de amortização do new money, em anos. Termo NEGOCIADO — não precisa ser o "
          + "mesmo da captação comum (linha EMISSAO acima).",
      });
      g.set("NM_CARENCIA", ano, 0, {
        fmt: NUM2, fill: FILL_INPUT,
        nota: "Carência do new money, em anos sem amortizar.",
      });
      g.set("NM_SPREAD", ano, `=${g.ref("SPREAD_DIVIDA", ano)}`, {
        fmt: PCT2, fill: FILL_INPUT,
        nota: "Spread do new money, inicializado igual ao da dívida existente — troque pelo termo "
          + "negociado.",
      });
      g.set("NM_TAXA", ano, `=((1+${g.ref("CURVA_CDI", ano)})*(1+${g.ref("NM_SPREAD", ano)}))-1`, { fmt: PCT2 });
      g.set("NM_INI", ano, iProjNM === 0 ? `=${g.ref("NM_VALOR", ano)}` : `=${g.ref("NM_FIM", ant!)}`, { fmt: NUM });
      g.set("NM_PCT", ano,
        `=IF(${iProjNM}<${g.ref("NM_CARENCIA", ano)},0,`
        + `IF(${g.ref("NM_PRAZO", ano)}-${iProjNM}<=0,0,MIN(1,1/(${g.ref("NM_PRAZO", ano)}-${iProjNM}))))`, {
        fmt: PCT,
        nota: "Amortização linear (SAC) até o vencimento — a mesma fórmula das tranches existentes.",
      });
      g.set("NM_AMORT", ano, `=${g.ref("NM_INI", ano)}*${g.ref("NM_PCT", ano)}`, {
        fmt: NUM,
        nota: "Amortização de PRINCIPAL, sempre em caixa — PIK só muda o tratamento do JURO, nunca "
          + "do principal. Para bullet (sem amortização), use carência = prazo.",
      });
      g.set("NM_JUROS", ano, `=-${g.ref("NM_INI", ano)}*${g.ref("NM_TAXA", ano)}`,
        { fmt: NUM, nota: NOTA_CIRCULARIDADE });
      const celPikRef = `$${colLetra(COL_NOTA)}$${g.n("NM_JUROS")}`;
      g.set("NM_JUROS_PIK", ano, `=IF(${celPikRef}="S",-${g.ref("NM_JUROS", ano)},0)`, {
        fmt: NUM,
        nota: "Positivo = quanto do juro deste ano virou principal em vez de sair do caixa.",
      });
      g.set("NM_FIM", ano,
        `=${g.ref("NM_INI", ano)}-${g.ref("NM_AMORT", ano)}+${g.ref("NM_JUROS_PIK", ano)}`,
        { fmt: NUM, negrito: true });
    }

    if (hist) {
      for (const ch of ["REVOLVER_INI", "REVOLVER_SAQUE", "REVOLVER_FIM", "REVOLVER_JUROS"]) {
        g.set(ch, ano, 0, { fmt: NUM, tipo: "calc" });
      }
    } else {
      g.set("REVOLVER_INI", ano, `=${g.ref("REVOLVER_FIM", ant!)}`, { fmt: NUM });
      // O saque é preenchido pela aba Cash Flow (é lá que se sabe o furo de
      // caixa). Aqui a linha existe e aponta para lá: uma tela, uma verdade.
      g.set("REVOLVER_FIM", ano, `=${g.ref("REVOLVER_INI", ano)}+${g.ref("REVOLVER_SAQUE", ano)}`, { fmt: NUM, negrito: true });
      g.set("REVOLVER_JUROS", ano, `=-${g.ref("REVOLVER_INI", ano)}*${g.ref("TAXA_REVOLVER", ano)}`, { fmt: NUM, nota: NOTA_CIRCULARIDADE });
    }
    g.set("DIVIDA_BRUTA", ano,
      `=${g.ref("TOTAL_DIVIDA", ano)}+${g.ref("EMISSAO_SALDO", ano)}+${g.ref("NM_FIM", ano)}+${g.ref("REVOLVER_FIM", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("DESP_FIN", ano,
      `=${g.ref("TOTAL_JUROS", ano)}+${g.ref("EMISSAO_JUROS", ano)}+${g.ref("NM_JUROS", ano)}+${g.ref("REVOLVER_JUROS", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("REC_FIN", ano, `=${g.ref("ST_REND", ano)}`, { fmt: NUM });

    // ---- o espelho ---------------------------------------------------------
    g.set("ESP_REVOLVER", ano, `=${g.ref("REVOLVER_FIM", ano)}`, { fmt: NUM });
    // NO REALIZADO A REPARTIÇÃO NÃO É ESTIMADA: ela está no balanço daquele ano. Só
    // a projeção usa a fração medida no último exercício. Aplicar a fração de 2025
    // ao saldo de 2024 inventaria uma repartição que o documento já informa.
    const frac = hist ? fracCPdoAno(ano) : fracCP;
    const dividaComEmissaoENM = `${g.ref("TOTAL_DIVIDA", ano)}+${g.ref("EMISSAO_SALDO", ano)}+${g.ref("NM_FIM", ano)}`;
    g.set("ESP_DIVIDA_CP", ano,
      `=(${dividaComEmissaoENM})*${frac}+${g.ref("REVOLVER_FIM", ano)}`, {
      fmt: NUM,
      nota: hist
        ? `Repartição curto/longo prazo do PRÓPRIO exercício ${ano} (${(frac * 100).toFixed(1)}% no `
          + "circulante), medida no balanço deste ano. No realizado não se estima o que o documento diz."
        : `Fração de curto prazo (${(fracCP * 100).toFixed(1)}%) MEDIDA no último exercício `
          + "realizado deste caso (dívida no circulante ÷ dívida total). O revolver é integralmente "
          + "curto prazo por natureza. A repartição vive nesta aba, não no balanço: o balanço só lê.",
    });
    g.set("ESP_DIVIDA_LP", ano, `=(${dividaComEmissaoENM})*${1 - frac}`, { fmt: NUM });
    g.set("ESP_CAPTACAO", ano, `=${g.ref("EMISSAO_TOTAL", ano)}+${g.ref("NM_VALOR", ano)}`, {
      fmt: NUM,
      nota: "Captação de dívida nova comum mais o principal do new money (que só é diferente de "
        + "zero no ano do fechamento) — as duas entram como caixa de financiamento no mesmo ano.",
    });
    g.set("ESP_AMORT", ano,
      `=${g.ref("TOTAL_AMORT_CAIXA", ano)}+${g.ref("EMISSAO_AMORT", ano)}+${g.ref("NM_AMORT", ano)}`, {
      fmt: NUM,
      nota: "Só a amortização COM efeito caixa (chave S/N por tranche) mais as safras novas e o "
        + "new money — o juro dele em PIK não entra aqui (não é amortização, e não sai do caixa; "
        + "ver `ESP_JUROS_PIK`). "
        + "Dívida reperfilada reduz saldo sem sair do caixa — e o fluxo tem de refletir isso.",
    });
    g.set("ESP_REVOLVER_MOV", ano, `=${g.ref("REVOLVER_SAQUE", ano)}`, { fmt: NUM });
    g.set("ESP_JUROS_PIK", ano, `=${g.ref("NM_JUROS_PIK", ano)}`, { fmt: NUM });
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Cash Flow — fluxo indireto. É aqui que o furo de caixa aparece e o revolver
// é acionado: nenhuma outra aba tem informação para decidir isso.
// =============================================================================
function abaFluxo(
  wb: ExcelJS.Workbook, ctx: Ctx,
  gDRE: Grade, gWC: Grade, gFA: Grade, gDiv: Grade, gRec: Grade, gTrib: Grade,
): Grade {
  const g = new Grade(wb, "Cash Flow", ctx.anos, ctx.nHist);
  g.cabecalho("CASH FLOW", `Valores em ${ctx.ent.unidade} · método indireto`, eixoHerdado(gRec));

  g.linha(null, { rotulo: "FLUXO DE CAIXA DAS OPERAÇÕES", bloco: true });
  g.linha("NET_INCOME", { sinal: "+", rotulo: "Lucro (prejuízo) líquido", fmt: NUM });
  g.linha("DEPREC", { sinal: "+", rotulo: "Depreciação e amortização", fmt: NUM });
  g.linha("PIK_ADD", {
    sinal: "+", rotulo: "Juros do new money capitalizados (PIK — já reduziram o lucro, não saíram do caixa)", fmt: NUM,
  });
  // O GANHO COM HAIRCUT é o espelho do PIK acima: em vez de uma DESPESA que
  // reduziu o lucro sem sair do caixa, é um GANHO que aumentou o lucro sem
  // ENTRAR caixa nenhum (a dívida some do balanço por perdão negociado, não
  // por pagamento). Sem subtraí-lo aqui, o `NET_INCOME` — que já carrega o
  // ganho não-caixa da DRE — infla o `FCO` no mesmo valor, e o balanço abre
  // exatamente na parcela classificada Haircut.
  g.linha("HAIRCUT_SUB", {
    sinal: "(-)",
    rotulo: "Ganho com haircut (já aumentou o lucro, não entrou caixa nenhum)", fmt: NUM,
  });
  // A VARIAÇÃO DO GIRO, CONTA A CONTA (§5.4 do CONFORMIDADE.md).
  //
  // Era uma linha agregada, e agregado esconde o que o analista precisa: quando o
  // caixa das operações piora, a pergunta seguinte é SEMPRE "por causa de qual
  // conta?" — cliente que atrasou, estoque que subiu, fornecedor que encurtou o
  // prazo. Com uma linha só, a resposta exigia abrir a aba de giro e subtrair dois
  // anos à mão. O Modelo Base abre por conta, e é o padrão de qualquer fluxo
  // indireto publicado.
  //
  // Cada linha é a variação NEGATIVA do saldo (ativo que cresce consome caixa,
  // passivo que cresce libera), lida da aba de giro — a mesma convenção de sinal do
  // total, que continua existindo e continua sendo o que o `FCO` soma. As duas
  // pontas não podem divergir, então o total NÃO é a soma destas linhas: ele
  // continua vindo do espelho do giro, e um assert confere que os dois batem.
  const contasGiro = [
    ...(ctx.linhasPorBloco.get("ativo_circulante") ?? [])
      .filter((l) => !ehImobilizado(l.chave) && !ehCaixa(l.chave))
      .map((l) => ({ l, pref: "wc_a" as const })),
    ...(ctx.linhasPorBloco.get("passivo_circulante") ?? [])
      .filter((l) => !ehDividaFinanceira(l.chave))
      .map((l) => ({ l, pref: "wc_p" as const })),
  ];
  g.linha("VAR_NCG", { sinal: "+/-", rotulo: "Variação da necessidade de capital de giro", fmt: NUM });
  for (const { l, pref } of contasGiro) {
    g.linha(`ncg:${pref}:${l.rotulo_norm}`, {
      rotulo: `    ${pref === "wc_a" ? "(−)" : "(+)"} ${l.chave}`, fmt: NUM,
    });
  }
  g.linha("VAR_NCG_CHECK", {
    rotulo: "    conferência: soma das contas − total (ZERO)", fmt: NUM2,
  });
  // O PAGAMENTO DE TRIBUTO E PARCELAMENTO, com linha própria no operacional.
  //
  // Ele estava DENTRO da variação de giro (as contas de tributo eram projetadas por dias
  // de giro) e por isso subia com a receita em vez de seguir o cronograma do acordo. Agora
  // as contas têm dono único — a aba `Tributos a Recolher` — e a saída de caixa aparece
  // com nome, que é o que o comitê pergunta: quanto do caixa vai para o passado.
  g.linha("PAGO_TRIB", { sinal: "(-)", rotulo: "Pagamento de tributos e parcelamentos", fmt: NUM });
  g.linha("FCO", { sinal: "=", rotulo: "CAIXA DAS OPERAÇÕES", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "FLUXO DE CAIXA DE INVESTIMENTO", bloco: true });
  g.linha("CAPEX", { sinal: "(-)", rotulo: "CAPEX", fmt: NUM });
  g.linha("FCI", { sinal: "=", rotulo: "CAIXA DE INVESTIMENTO", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("FCL", { sinal: "=", rotulo: "FLUXO DE CAIXA LIVRE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "FLUXO DE CAIXA DE FINANCIAMENTO", bloco: true });
  g.linha("CAPTACAO", { sinal: "+", rotulo: "Captação de dívida nova", fmt: NUM });
  g.linha("AMORT", { sinal: "(-)", rotulo: "Amortização de dívida", fmt: NUM });
  g.linha("REVOLVER", { sinal: "+", rotulo: "Saque/(amortização) do revolver", fmt: NUM });
  g.linha("DIVIDENDOS", { sinal: "(-)", rotulo: "Dividendos pagos", fmt: NUM });
  g.linha("FCF", { sinal: "=", rotulo: "CAIXA DE FINANCIAMENTO", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("VAR_CAIXA", { rotulo: "VARIAÇÃO DE CAIXA DO PERÍODO", negrito: true, fmt: NUM });
  g.linha("CAIXA_INI", { rotulo: "Caixa de abertura", fmt: NUM });
  g.linha("CAIXA_ANTES", { rotulo: "Caixa antes do revolver", fmt: NUM });
  g.linha("FURO", { rotulo: "Furo em relação ao caixa mínimo", fmt: NUM });
  g.linha("CAIXA_FIM", { rotulo: "CAIXA DE FECHAMENTO", negrito: true, topo: true, fmt: NUM });

  const caixaHist = (ano: number) => {
    // Caixa realizado: a soma das contas de disponibilidade extraídas.
    const contas = (ctx.linhasPorBloco.get("ativo_circulante") ?? []).filter((l) =>
      /\bcaixa\b|\bdisponív|\bdisponiv|\bbancos?\b|equivalentes|aplica(ç|c)(õ|o)es financeiras/i.test(l.chave));
    return contas.reduce((s, l) => s + (valorNaEscala(l, ano, ctx.ent.unidade)?.valor ?? 0), 0);
  };

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    if (hist) {
      for (const ch of ["NET_INCOME", "DEPREC", "PIK_ADD", "HAIRCUT_SUB", "VAR_NCG", "FCO", "CAPEX", "FCI", "FCL",
                        "CAPTACAO", "AMORT", "REVOLVER", "DIVIDENDOS", "FCF", "VAR_CAIXA", "FURO"]) {
        g.set(ch, ano, 0, { fmt: NUM });
      }
      for (const { l, pref } of contasGiro) g.set(`ncg:${pref}:${l.rotulo_norm}`, ano, 0, { fmt: NUM });
      g.set("VAR_NCG_CHECK", ano, 0, { fmt: NUM2 });
      g.set("CAIXA_INI", ano, ant === null ? 0 : `=${g.ref("CAIXA_FIM", ant)}`, { fmt: NUM });
      g.set("CAIXA_ANTES", ano, caixaHist(ano), { fmt: NUM, fill: FILL_HIST });
      g.set("CAIXA_FIM", ano, caixaHist(ano), {
        fmt: NUM, fill: FILL_HIST, negrito: true,
        nota: "Caixa REALIZADO, soma das contas de disponibilidade extraídas do balanço. "
          + "O fluxo do período realizado não é reconstruído aqui: a DFC extraída é a fonte "
          + "dele, e reconstruir daria dois números para o mesmo fato.",
      });
      continue;
    }
    g.set("NET_INCOME", ano, `=${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}`, { fmt: NUM });
    g.set("DEPREC", ano, `=${g.externa("Fixed Assets & CAPEX", gFA, "ESP_DEPREC_CF", ano)}`, { fmt: NUM });
    g.set("PIK_ADD", ano, `=${g.externa("ST Inv. & Debt", gDiv, "ESP_JUROS_PIK", ano)}`, {
      fmt: NUM,
      nota: "O juro do new money em PIK já reduziu o lucro líquido (linha acima) — mas não saiu do "
        + "caixa, então soma de volta aqui, igual à depreciação.",
    });
    g.set("HAIRCUT_SUB", ano, `=-${g.externa("ST Inv. & Debt", gDiv, "TOTAL_AMORT_HAIRCUT", ano)}`, {
      fmt: NUM,
      nota: "O ganho com haircut já aumentou o lucro líquido (linha acima, via a DRE) — mas não "
        + "entrou caixa nenhum: a dívida some do balanço por perdão negociado, não por pagamento. "
        + "Subtrai de volta aqui, o espelho do PIK_ADD acima.",
    });
    g.set("VAR_NCG", ano, `=${g.externa("Working Capital", gWC, "ESP_VAR_NCG", ano)}`, { fmt: NUM });
    // A abertura conta a conta: variação NEGATIVA do saldo de cada conta de giro,
    // lida da aba onde ela é projetada. `ant` existe sempre aqui (o primeiro ano é
    // realizado e cai no ramo de cima).
    for (const { l, pref } of contasGiro) {
      const chWC = chaveLinha(pref, l);
      if (!gWC.tem(chWC)) { g.set(`ncg:${pref}:${l.rotulo_norm}`, ano, 0, { fmt: NUM }); continue; }
      const atual = g.externa("Working Capital", gWC, chWC, ano);
      const anterior = g.externa("Working Capital", gWC, chWC, ant!);
      g.set(`ncg:${pref}:${l.rotulo_norm}`, ano,
        `=${pref === "wc_a" ? "-" : ""}(${atual}-${anterior})`, {
        fmt: NUM,
        nota: pref === "wc_a"
          ? "Ativo de giro que CRESCE consome caixa — daí o sinal negativo. É a mesma convenção "
            + "do total logo acima."
          : "Passivo de giro que CRESCE libera caixa (o fornecedor está financiando a operação).",
      });
    }
    g.set("VAR_NCG_CHECK", ano,
      `=(${contasGiro.map(({ l, pref }) => g.ref(`ncg:${pref}:${l.rotulo_norm}`, ano)).join("+") || "0"})`
      + `-${g.ref("VAR_NCG", ano)}`, {
      fmt: NUM2,
      nota: "Conferência: a soma das contas menos o total. Tem de ser ZERO — fora disso, a abertura e o total do giro contam coisas diferentes.",
    });
    g.set("PAGO_TRIB", ano, `=-${g.externa("Tributos a Recolher", gTrib, "ESP_PAGO", ano)}`, {
      fmt: NUM,
      nota: "Queda do passivo tributário no período, vinda da aba Tributos a Recolher — é a parcela "
        + "do acordo que saiu do caixa. Negativo porque é saída. No realizado é zero: variação de "
        + "exercício passado já está no saldo extraído.",
    });
    g.set("FCO", ano,
      `=${g.ref("NET_INCOME", ano)}+${g.ref("DEPREC", ano)}+${g.ref("PIK_ADD", ano)}+${g.ref("HAIRCUT_SUB", ano)}`
      + `+${g.ref("VAR_NCG", ano)}+${g.ref("PAGO_TRIB", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("CAPEX", ano, `=-${g.externa("Fixed Assets & CAPEX", gFA, "ESP_CAPEX", ano)}`, { fmt: NUM });
    g.set("FCI", ano, `=${g.ref("CAPEX", ano)}`, { fmt: NUM, negrito: true });
    g.set("FCL", ano, `=${g.ref("FCO", ano)}+${g.ref("FCI", ano)}`, { fmt: NUM, negrito: true });
    g.set("CAPTACAO", ano, `=${g.externa("ST Inv. & Debt", gDiv, "ESP_CAPTACAO", ano)}`, { fmt: NUM });
    g.set("AMORT", ano, `=-${g.externa("ST Inv. & Debt", gDiv, "ESP_AMORT", ano)}`, { fmt: NUM });
    g.set("DIVIDENDOS", ano, 0, {
      fmt: NUM, fill: FILL_INPUT,
      nota: "Célula editável, zero por padrão: num mandato de reestruturação, distribuir caixa é "
        + "decisão que o plano declara. Dividendo pago entra NEGATIVO, como as outras saídas.",
    });
    g.set("CAIXA_INI", ano, `=${g.ref("CAIXA_FIM", ant!)}`, { fmt: NUM });
    // Caixa antes do revolver: sem o saque, para o furo ser visível.
    g.set("CAIXA_ANTES", ano,
      `=${g.ref("CAIXA_INI", ano)}+${g.ref("FCL", ano)}+${g.ref("CAPTACAO", ano)}`
      + `+${g.ref("AMORT", ano)}+${g.ref("DIVIDENDOS", ano)}`, { fmt: NUM });
    g.set("FURO", ano,
      `=MAX(0,${g.externa("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano)}-${g.ref("CAIXA_ANTES", ano)})`, {
      fmt: NUM,
      nota: "Quanto falta para o caixa mínimo. É o número que o revolver cobre — e a linha que "
        + "o comitê procura primeiro.",
    });
    // O revolver saca o furo e amortiza quando há sobra, limitado ao saldo devedor.
    g.set("REVOLVER", ano,
      `=IF(${g.ref("FURO", ano)}>0,${g.ref("FURO", ano)},`
      + `-MIN(${g.externa("ST Inv. & Debt", gDiv, "REVOLVER_INI", ano)},`
      + `MAX(0,${g.ref("CAIXA_ANTES", ano)}-${g.externa("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano)})))`, {
      fmt: NUM,
      nota: "Saca o que falta para o caixa mínimo; havendo sobra, amortiza o revolver até zerá-lo.",
    });
    g.set("FCF", ano,
      `=${g.ref("CAPTACAO", ano)}+${g.ref("AMORT", ano)}+${g.ref("REVOLVER", ano)}+${g.ref("DIVIDENDOS", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("VAR_CAIXA", ano, `=${g.ref("FCL", ano)}+${g.ref("FCF", ano)}`, { fmt: NUM, negrito: true });
    g.set("CAIXA_FIM", ano, `=${g.ref("CAIXA_INI", ano)}+${g.ref("VAR_CAIXA", ano)}`, { fmt: NUM, negrito: true });
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Balance Sheet — e o CHECK que decide se o modelo presta: Ativo − (Passivo +
// PL) tem de ser zero em toda coluna. Modelo que não fecha não é modelo.
// =============================================================================
function abaBalanco(
  wb: ExcelJS.Workbook, ctx: Ctx,
  gCF: Grade, gWC: Grade, gFA: Grade, gDiv: Grade, gDRE: Grade, gRec: Grade, gTrib: Grade,
): Grade {
  const g = new Grade(wb, "Balance Sheet", ctx.anos, ctx.nHist);
  g.cabecalho("BALANCE SHEET", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));

  const anc = ctx.linhasPorBloco.get("ativo_nao_circulante") ?? [];
  const ancNaoImob = anc.filter((l) => !ehImobilizado(l.chave));
  // A dívida bancária do não circulante NÃO entra como conta avulsa: ela é
  // projetada pela aba de dívida e entra por `DIVIDA_LP`. Listá-la aqui também a
  // contaria duas vezes — o mesmo defeito que o giro tinha.
  const pnc = (ctx.linhasPorBloco.get("passivo_nao_circulante") ?? [])
    .filter((l) => !ehDividaFinanceira(l.chave))
    // Tributo e parcelamento de longo prazo entram por `TRIB_PNC`, o espelho da aba que
    // conhece o cronograma. Listá-los aqui também os contaria duas vezes.
    .filter((l) => !ehTributoARecolher(l.chave));
  const pl = ctx.linhasPorBloco.get("patrimonio_liquido") ?? [];

  // A RECONCILIAÇÃO COM O TOTAL INFORMADO — invariante nº 6 aplicado ao modelo.
  //
  // "O TOTAL DA SEÇÃO É O QUE O DOCUMENTO INFORMOU, não a nossa soma": é a regra que
  // as abas analíticas seguem desde o teste v25 (36 de 44 somas do Balanço divergiam)
  // e que o modelo institucional não seguia. Somar as contas extraídas erra sempre
  // que a extração traz a MESMA conta com dois rótulos — medido no v35: "Prejuízos
  // acumulados" e "Resultados Acumulados", ambos −39.150; "Capital social subscrito"
  // e "Capital social subscrito e integralizado". Não é subtotal (a detecção
  // estrutural não pega), é identidade de conta entre documentos, e resolver com
  // heurística de semelhança apagaria conta legítima: duas provisões de mesmo valor
  // são plausíveis.
  //
  // A SOLUÇÃO NÃO É APAGAR NEM ADIVINHAR, é declarar. Cada grupo cujo total o
  // documento informa ganha uma linha de reconciliação = informado − nossa soma. No
  // realizado o grupo passa a fechar com o documento POR CONSTRUÇÃO; a linha diz
  // quanto é, e a nota diz que aquilo é DADO A RECONCILIAR, não premissa. É o mesmo
  // desenho da linha de conferência das abas analíticas, com uma diferença: aqui ela
  // entra na soma, porque o balanço tem de fechar para o modelo se mover.
  //
  // Na projeção ela é mantida CONSTANTE no valor do último realizado — nunca
  // reprojetada. Zerá-la na virada criaria um salto artificial no primeiro ano
  // projetado; crescê-la seria projetar um erro de extração como se fosse conta.
  const reconc = (grupo: string, ancora: string) => ctx.ancoras.has(ancora)
    ? { chave: `RECONC_${grupo}`, ancora }
    : null;
  const rAC = reconc("AC", "DOC_AC");
  const rANC = reconc("ANC", "DOC_ANC");
  const rPC = reconc("PC", "DOC_PC");
  const rPNC = reconc("PNC", "DOC_PNC");
  const rPL = reconc("PL", "DOC_PL");
  const linhaReconc = (r: { chave: string; ancora: string } | null, grupo: string) => {
    if (!r) return;
    g.linha(r.chave, {
      rotulo: `    reconciliação com o ${grupo} informado no documento`, fmt: NUM2,
      nota: "dado a reconciliar",
    });
  };

  g.linha("CAIXA", { rotulo: "Caixa e equivalentes", fmt: NUM });
  g.linha("AC_OPER", { rotulo: "Ativo circulante operacional", fmt: NUM });
  linhaReconc(rAC, "ativo circulante");
  g.linha("AC", { rotulo: "ATIVO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("IMOB", { rotulo: "Imobilizado e intangível", fmt: NUM });
  for (const l of ancNaoImob) g.linha(chaveLinha("anc", l), { rotulo: l.chave, fmt: NUM });
  linhaReconc(rANC, "ativo não circulante");
  g.linha("ANC", { rotulo: "ATIVO NÃO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  // A RECONCILIAÇÃO COM O TOTAL GERAL — o passo que faltava para o modelo FECHAR.
  //
  // O QUE ACONTECIA, medido no v35: cada GRUPO já seguia o total informado (as
  // linhas de reconciliação acima), mas os totais de grupo do próprio documento
  // não somam o total geral dele — circulante 67.878 + não circulante 101.200 =
  // 169.078 contra `TOTAL DO ATIVO` 158.801. Do outro lado a diferença é maior
  // ainda. Resultado: `ATIVO TOTAL` 10.277 acima do documento e o CHECK em
  // −20.529 em TODAS as colunas. Um modelo que não fecha não se move: fluxo,
  // revolver e alavancagem passam a ser aritmética sobre um balanço impossível.
  //
  // A REGRA É CONSERVADORA DE PROPÓSITO. O ajuste só entra quando o documento
  // informa OS DOIS totais gerais (ativo e passivo+PL) e eles CONCORDAM entre si
  // — aí a evidência é dupla e o fechamento do documento é fato, não escolha
  // nossa. Se ele informa só um lado, ou se os dois discordam, NADA é ajustado: o
  // CHECK continua acusando, porque nesse caso o modelo não tem como saber qual
  // número é o certo, e forçar um deles seria inventar.
  const temTotaisGerais = ctx.ancoras.has("DOC_ATIVO") && ctx.ancoras.has("DOC_PASSIVO_PL");
  const rTotalAtivo = temTotaisGerais ? { chave: "RECONC_ATIVO_TOTAL", ancora: "DOC_ATIVO" } : null;
  const rTotalPassivo = temTotaisGerais
    ? { chave: "RECONC_PASSIVO_TOTAL", ancora: "DOC_PASSIVO_PL" } : null;
  if (rTotalAtivo) {
    g.linha(rTotalAtivo.chave, {
      rotulo: "    reconciliação com o ATIVO TOTAL informado no documento", fmt: NUM2,
      nota: "dado a reconciliar",
    });
  }
  g.linha("ATIVO", { rotulo: "ATIVO TOTAL", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("PC_OPER", { rotulo: "Passivo circulante operacional", fmt: NUM });
  g.linha("DIVIDA_CP", { rotulo: "Dívida de curto prazo + revolver", fmt: NUM });
  g.linha("TRIB_CP", { rotulo: "Tributos a recolher e parcelamentos (curto prazo)", fmt: NUM });
  linhaReconc(rPC, "passivo circulante");
  g.linha("PC", { rotulo: "PASSIVO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("DIVIDA_LP", { rotulo: "Dívida de longo prazo", fmt: NUM });
  g.linha("TRIB_PNC", { rotulo: "Tributos a recolher e parcelamentos (longo prazo)", fmt: NUM });
  for (const l of pnc) g.linha(chaveLinha("pnc", l), { rotulo: l.chave, fmt: NUM });
  linhaReconc(rPNC, "passivo não circulante");
  g.linha("PNC", { rotulo: "PASSIVO NÃO CIRCULANTE", negrito: true, topo: true, fmt: NUM });
  g.pular();
  for (const l of pl) g.linha(chaveLinha("pl", l), { rotulo: l.chave, fmt: NUM });
  g.linha("LUCROS_ACUM", { rotulo: "Lucros (prejuízos) acumulados do modelo", fmt: NUM });
  g.linha("REPERFILAMENTO", { rotulo: "Redução de dívida SEM efeito caixa (acumulada)", fmt: NUM });
  // LUCROS RETIDOS TOTAIS — as contas de retenção que o documento trouxe, mais o
  // que o modelo acumulou. Existe para o Altman Z'' do `Output`, e é linha em vez
  // de soma escondida dentro do índice porque quem discorda do Z'' precisa poder
  // ver de onde saiu o X2.
  g.linha("PL_RETIDO", { rotulo: "    dos quais LUCROS RETIDOS (para o Altman)", fmt: NUM });
  linhaReconc(rPL, "patrimônio líquido");
  g.linha("PL", { rotulo: "PATRIMÔNIO LÍQUIDO", negrito: true, topo: true, fmt: NUM });
  if (rTotalPassivo) {
    g.linha(rTotalPassivo.chave, {
      rotulo: "    reconciliação com o PASSIVO + PL informado no documento", fmt: NUM2,
      nota: "dado a reconciliar",
    });
  }
  g.linha("PASSIVO_PL", { rotulo: "PASSIVO + PATRIMÔNIO LÍQUIDO", negrito: true, topo: true, fmt: NUM });
  g.pular();
  g.linha("CHECK", { rotulo: "CHECK — Ativo − (Passivo + PL) deve ser ZERO", negrito: true, fmt: NUM2 });
  g.linha("CHECK_TXT", { rotulo: "    diagnóstico" });

  // ---- CONFERÊNCIA DO REALIZADO CONTRA O DOCUMENTO -------------------------
  //
  // O CHECK acima prova COERÊNCIA INTERNA (as duas metades do balanço batem entre
  // si). Ele não prova FIDELIDADE: um balanço que soma o subtotal E os componentes
  // dele nas duas metades pode fechar em zero e estar 2x o documento — e foi o que
  // aconteceu no arquivo entregue, onde o `ATIVO TOTAL` de 2025 saiu 195.090 contra
  // 95.780 informados. Coerente e falso ao mesmo tempo.
  //
  // Por isso a conferência do ATIVO TOTAL contra o total informado é uma linha
  // SEPARADA: são duas perguntas diferentes, e responder uma não responde a outra.
  const temAncoraAtivo = ctx.ancoras.has("DOC_ATIVO");
  if (temAncoraAtivo) {
    g.linha("DOC_ATIVO", { rotulo: "    Ativo total informado no documento", fmt: NUM });
    g.linha("DIF_ATIVO", { rotulo: "    diferença (modelo − documento) — ZERO", fmt: NUM2 });
  }


  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    g.set("CAIXA", ano, `=${g.externa("Cash Flow", gCF, "CAIXA_FIM", ano)}`, { fmt: NUM });
    g.set("AC_OPER", ano, `=${g.externa("Working Capital", gWC, "ESP_AC", ano)}`, { fmt: NUM });
    const somaAC = [g.ref("CAIXA", ano), g.ref("AC_OPER", ano)];
    escreverReconc(g, ctx, rAC, ano, hist, ant, somaAC);
    g.set("AC", ano, `=${[...somaAC, ...(rAC ? [g.ref(rAC.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });
    g.set("IMOB", ano, `=${g.externa("Fixed Assets & CAPEX", gFA, "ESP_IMOB", ano)}`, { fmt: NUM });
    for (const l of ancNaoImob) {
      const ch = chaveLinha("anc", l);
      const e = valorNaEscala(l, ano, ctx.ent.unidade);
      g.set(ch, ano, hist ? (e?.valor ?? 0) : `=${g.ref(ch, ant!)}`, {
        fmt: NUM, fill: hist ? FILL_HIST : undefined,
        nota: hist ? (e?.nota ?? notaSemValor(l, ano)) : "Conta não operacional mantida constante: sem premissa própria, "
          + "projetá-la por crescimento de receita seria inventar movimento.",
      });
    }
    // A reconciliação de cada grupo: informado − nossa soma no realizado, constante
    // depois. `somaOuZero` recebe a linha dela como termo, então o total do grupo
    // fecha com o documento por construção.
    const somaANC = [g.ref("IMOB", ano), ...ancNaoImob.map((l) => g.ref(chaveLinha("anc", l), ano))];
    escreverReconc(g, ctx, rANC, ano, hist, ant, somaANC);
    somaOuZero(g, "ANC", ano, [...somaANC, ...(rANC ? [g.ref(rANC.chave, ano)] : [])], true);
    escreverReconcTotal(g, ctx, rTotalAtivo, "DOC_PASSIVO_PL", ano, hist, ant,
      [g.ref("AC", ano), g.ref("ANC", ano)]);
    g.set("ATIVO", ano,
      `=${[g.ref("AC", ano), g.ref("ANC", ano),
           ...(rTotalAtivo ? [g.ref(rTotalAtivo.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });

    g.set("PC_OPER", ano, `=${g.externa("Working Capital", gWC, "ESP_PC", ano)}`, { fmt: NUM });
    g.set("DIVIDA_CP", ano, `=${g.externa("ST Inv. & Debt", gDiv, "ESP_DIVIDA_CP", ano)}`, {
      fmt: NUM,
      nota: "Vem da aba de dívida, onde a repartição entre curto e longo prazo é decidida.",
    });
    g.set("TRIB_CP", ano, `=${g.externa("Tributos a Recolher", gTrib, "ESP_CP", ano)}`, {
      fmt: NUM,
      nota: "Espelho da aba Tributos a Recolher. O balanço não projeta tributo: quem projeta é a aba "
        + "que conhece o cronograma do parcelamento.",
    });
    const somaPC = [g.ref("PC_OPER", ano), g.ref("DIVIDA_CP", ano), g.ref("TRIB_CP", ano)];
    escreverReconc(g, ctx, rPC, ano, hist, ant, somaPC);
    g.set("PC", ano, `=${[...somaPC, ...(rPC ? [g.ref(rPC.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });
    g.set("DIVIDA_LP", ano, `=${g.externa("ST Inv. & Debt", gDiv, "ESP_DIVIDA_LP", ano)}`, { fmt: NUM });
    for (const l of pnc) {
      const ch = chaveLinha("pnc", l);
      const e = valorNaEscala(l, ano, ctx.ent.unidade);
      g.set(ch, ano, hist ? Math.abs(e?.valor ?? 0) : `=${g.ref(ch, ant!)}`,
        { fmt: NUM, fill: hist ? FILL_HIST : undefined, nota: hist ? (e?.nota ?? notaSemValor(l, ano)) : undefined });
    }
    g.set("TRIB_PNC", ano, `=${g.externa("Tributos a Recolher", gTrib, "ESP_PNC", ano)}`, {
      fmt: NUM,
      nota: "Espelho da aba Tributos a Recolher — a parte do parcelamento que vence depois de 12 meses. "
        + "Antes esta parcela ficava CONGELADA aqui, o que dizia que o acordo nunca é pago.",
    });
    const somaPNC = [g.ref("DIVIDA_LP", ano), g.ref("TRIB_PNC", ano),
      ...pnc.map((l) => g.ref(chaveLinha("pnc", l), ano))];
    escreverReconc(g, ctx, rPNC, ano, hist, ant, somaPNC);
    somaOuZero(g, "PNC", ano, [...somaPNC, ...(rPNC ? [g.ref(rPNC.chave, ano)] : [])], true);
    for (const l of pl) {
      const ch = chaveLinha("pl", l);
      const e = valorNaEscala(l, ano, ctx.ent.unidade);
      g.set(ch, ano, hist ? (e?.valor ?? 0) : `=${g.ref(ch, ant!)}`,
        { fmt: NUM, fill: hist ? FILL_HIST : undefined, nota: hist ? (e?.nota ?? notaSemValor(l, ano)) : undefined });
    }
    g.set("LUCROS_ACUM", ano, hist ? 0 : `=${g.ref("LUCROS_ACUM", ant!)}+${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}+${g.externa("Cash Flow", gCF, "DIVIDENDOS", ano)}`, {
      fmt: NUM,
      nota: hist ? "Zero no realizado: o PL realizado já está nas contas extraídas acima. "
        + "Somar lucro acumulado aqui contaria o mesmo patrimônio duas vezes."
        : undefined,
    });
    // OS LUCROS RETIDOS, para o X2 do Altman. Soma as contas de retenção que o
    // documento trouxe (`ehLucrosRetidos`) mais o que o modelo acumulou.
    //
    // SEM NENHUMA CONTA EXTRAÍDA, A LINHA PUBLICA "n.a." E O ÍNDICE NÃO SAI.
    // Zero aqui não é neutro: ele derruba o Z'' em até 3,26 pontos e joga uma
    // empresa saudável na zona de aflição. Documento que não isola lucro retido
    // não autoriza afirmar que ele é zero.
    {
      const retidas = pl.filter((l) => ehLucrosRetidos(l.chave));
      g.set("PL_RETIDO", ano,
        retidas.length === 0
          ? '="n.a."'
          : `=${[...retidas.map((l) => g.ref(chaveLinha("pl", l), ano)),
                 g.ref("LUCROS_ACUM", ano)].join("+")}`, {
          fmt: NUM,
          nota: retidas.length === 0
            ? "Nenhuma conta de lucro retido foi isolada no documento deste caso, então o Altman "
              + "Z'' não sai. Zero aqui não seria neutro: ele derruba o índice em até 3,26 pontos."
            : `Soma de ${retidas.length} conta(s) de retenção do documento mais o resultado que o `
              + "modelo acumulou. É o X2 do Altman, e fica em linha própria para quem discordar do "
              + "índice poder ver de onde ele saiu.",
        });
    }

    // A CONTRAPARTIDA DA CONVERSÃO EM EQUITY. A chave "Efeito caixa? = N" de uma
    // tranche faz o saldo dela cair SEM pagamento — e uma redução de passivo sem
    // saída de caixa precisa de contrapartida, senão o balanço abre exatamente no
    // valor dela. Só a parcela classificada "Equity" (chave `#classe`) entra
    // AQUI, direto: é a conversão em participação, sem passar pelo resultado. A
    // parcela "Haircut" ganha contrapartida por OUTRO caminho — vira ganho na
    // Income Statement (`GANHO_HAIRCUT`) e chega ao patrimônio via
    // `LUCROS_ACUM`, líquida do imposto que ela mesma gera. Somar as duas aqui
    // contaria a mesma redução de passivo em capital duas vezes.
    g.set("REPERFILAMENTO", ano,
      hist
        ? 0
        : `=${g.ref("REPERFILAMENTO", ant!)}+${g.externa("ST Inv. & Debt", gDiv, "TOTAL_AMORT_EQUITY", ano)}`, {
      fmt: NUM,
      nota: hist
        ? "Zero no realizado: o PL realizado já vem das contas extraídas."
        : "Acumula a parcela da amortização SEM efeito caixa classificada como Equity (chave "
          + "`#classe` por tranche, na aba de dívida). Conversão em participação reduz passivo e "
          + "aumenta patrimônio direto, sem passar pelo resultado — sem esta linha, o balanço abriria "
          + "exatamente no valor convertido. A parcela Haircut chega ao patrimônio por outra linha "
          + "(GANHO_HAIRCUT → LUCROS_ACUM), porque ela passa pelo resultado e pelo imposto.",
    });
    // O PL É O GRUPO ONDE A CONTA DUPLICADA MAIS APARECE (o v35 traz "Prejuízos
    // acumulados" e "Resultados Acumulados" com o mesmo −39.150). A reconciliação
    // considera apenas as contas EXTRAÍDAS: `LUCROS_ACUM` e `REPERFILAMENTO` são
    // linhas do modelo, zero no realizado, e entrariam como divergência falsa.
    const somaPLextraido = pl.map((l) => g.ref(chaveLinha("pl", l), ano));
    escreverReconc(g, ctx, rPL, ano, hist, ant, somaPLextraido);
    somaOuZero(g, "PL", ano,
      [...somaPLextraido, g.ref("LUCROS_ACUM", ano), g.ref("REPERFILAMENTO", ano),
       ...(rPL ? [g.ref(rPL.chave, ano)] : [])], true);
    escreverReconcTotal(g, ctx, rTotalPassivo, "DOC_ATIVO", ano, hist, ant,
      [g.ref("PC", ano), g.ref("PNC", ano), g.ref("PL", ano)]);
    g.set("PASSIVO_PL", ano,
      `=${[g.ref("PC", ano), g.ref("PNC", ano), g.ref("PL", ano),
           ...(rTotalPassivo ? [g.ref(rTotalPassivo.chave, ano)] : [])].join("+")}`,
      { fmt: NUM, negrito: true });

    // O CHECK. Formatação condicional não seria suficiente: o número tem de estar
    // na cara, e o diagnóstico tem de dizer o que fazer.
    const cellCheck = g.set("CHECK", ano, `=${g.ref("ATIVO", ano)}-${g.ref("PASSIVO_PL", ano)}`, {
      fmt: NUM2, negrito: true,
      nota: hist
        ? "No período REALIZADO, com as linhas de reconciliação acima, cada GRUPO já segue o total "
          + "que o documento informa. Então diferente de zero aqui significa uma coisa só: os "
          + "próprios totais informados não somam entre si (circulante + não circulante ≠ ativo "
          + "total, ou passivo + PL ≠ ativo). A causa está no documento ou na extração dele, não no "
          + "modelo — confira a aba de dados linha a linha e a de revisão."
        : "No período PROJETADO tem de ser ZERO. Diferente de zero é defeito do modelo: "
          + "alguma linha de projeção não tem contrapartida.",
    });
    cellCheck.fill = FILL_CHECK_OK;
    g.set("CHECK_TXT", ano,
      `=IF(ABS(${g.ref("CHECK", ano)})<0.5,"fecha","NÃO FECHA: "&TEXT(${g.ref("CHECK", ano)},"#,##0"))`, {});
    g.ws.getRow(g.n("CHECK_TXT")).getCell(g.colDoAno(ano)).fill = FILL_CHECK_ERRO;

    if (temAncoraAtivo) {
      const e = hist ? valorDaAncora(ctx, "DOC_ATIVO", ano) : null;
      if (e) {
        g.set("DOC_ATIVO", ano, e.valor, { fmt: NUM, fill: FILL_HIST, nota: e.nota, tipo: "calc" });
        g.set("DIF_ATIVO", ano, `=${g.ref("ATIVO", ano)}-${g.ref("DOC_ATIVO", ano)}`, {
          fmt: NUM2,
          nota: "Modelo menos documento. Diferente de zero no realizado significa que o balanço "
            + "montado aqui não é o balanço do documento: subtotal somado junto com os componentes "
            + "dele (dobra o grupo), conta que não caiu em nenhum bloco, ou escala. O CHECK acima "
            + "pode estar em zero e esta linha não — coerência interna não é fidelidade.",
        });
      } else {
        g.set("DOC_ATIVO", ano, null, {
          nota: hist
            ? "O documento deste exercício não informa o total do ativo."
            : "Exercício projetado: não há documento contra o que conferir.",
        });
        g.set("DIF_ATIVO", ano, null, {});
      }
    }
  }
  if (temAncoraAtivo) {
    const colIni = colLetra(COL_PRIMEIRO_ANO);
    const colFim = colLetra(COL_PRIMEIRO_ANO + ctx.anos.length - 1);
    const linha = g.n("DIF_ATIVO");
    g.ws.addConditionalFormatting({
      ref: `${colIni}${linha}:${colFim}${linha}`,
      rules: [
        { type: "expression", formulae: [`ABS(${colIni}${linha})>0.5`], style: { fill: FILL_CHECK_ERRO }, priority: 1 },
        { type: "expression", formulae: [`ISNUMBER(${colIni}${linha})`], style: { fill: FILL_CHECK_OK }, priority: 2 },
      ],
    });
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Goodwill, Taxes & Div. — ágio, tributos diferidos e dividendos.
// =============================================================================
function abaGoodwill(wb: ExcelJS.Workbook, ctx: Ctx, gDRE: Grade, gCF: Grade, gRec: Grade): Grade {
  const g = new Grade(wb, "Goodwill, Taxes & Div.", ctx.anos, ctx.nHist);
  g.cabecalho("GOODWILL, TAXES & DIVIDENDS", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));

  g.linha(null, { rotulo: "TRIBUTOS SOBRE O LUCRO", bloco: true });
  g.linha("EBT", { rotulo: "EBT", fmt: NUM });
  g.linha("ALIQ", { rotulo: "Alíquota nominal", nota: "premissa", fmt: PCT });
  g.linha("TRIB", { rotulo: "Tributos do período", fmt: NUM });
  g.linha("ALIQ_EFET", { rotulo: "Alíquota EFETIVA (tributo ÷ EBT)", fmt: PCT });
  g.pular();
  g.linha(null, { rotulo: "DIVIDENDOS", bloco: true });
  g.linha("LUCRO", { rotulo: "Lucro líquido", fmt: NUM });
  g.linha("PAYOUT", { rotulo: "Payout", nota: "premissa", fmt: PCT });
  g.linha("DIV", { rotulo: "Dividendos declaráveis", fmt: NUM });
  g.linha("DIV_PAGO", { rotulo: "Dividendos efetivamente pagos (do fluxo)", fmt: NUM });
  g.pular();
  g.linha(null, { rotulo: "ÁGIO", bloco: true });
  g.linha("AGIO", { rotulo: "Ágio — saldo", fmt: NUM });
  g.linha("AGIO_AMORT", { rotulo: "Amortização do ágio", fmt: NUM });

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    g.set("EBT", ano, `=${g.externa("Income Statement", gDRE, "EBT", ano)}`, { fmt: NUM });
    g.set("ALIQ", ano, ctx.ent.aliquotaTributos, { fmt: PCT, fill: FILL_INPUT });
    g.set("TRIB", ano, `=${g.externa("Income Statement", gDRE, "TAX", ano)}`, { fmt: NUM });
    g.set("ALIQ_EFET", ano, `=IF(${g.ref("EBT", ano)}<>0,-${g.ref("TRIB", ano)}/${g.ref("EBT", ano)},0)`, {
      fmt: PCT,
      nota: "Alíquota efetiva. Com prejuízo, ela sai ZERO porque não há tributo sobre prejuízo "
        + "— e não negativa, que é o que apareceria se o modelo gerasse crédito automático.",
    });
    g.set("LUCRO", ano, `=${g.externa("Income Statement", gDRE, "NET_PROFIT", ano)}`, { fmt: NUM });
    g.set("PAYOUT", ano, 0, {
      fmt: PCT, fill: FILL_INPUT,
      nota: "Payout ZERO por padrão num mandato de reestruturação. Distribuir enquanto se "
        + "renegocia dívida é decisão que o plano declara.",
    });
    g.set("DIV", ano, `=MAX(0,${g.ref("LUCRO", ano)})*${g.ref("PAYOUT", ano)}`, {
      fmt: NUM, nota: "Só sobre lucro POSITIVO: prejuízo não distribui.",
    });
    g.set("DIV_PAGO", ano, `=${g.externa("Cash Flow", gCF, "DIVIDENDOS", ano)}`, { fmt: NUM });
    g.set("AGIO", ano, 0, { fmt: NUM, fill: hist ? FILL_HIST : FILL_INPUT, nota: "Sem ágio identificado nos documentos do caso." });
    g.set("AGIO_AMORT", ano, 0, { fmt: NUM });
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Tributos a Recolher — o parcelamento tributário, que num mandato de
// reestruturação é quase sempre a segunda maior dívida e quase nunca está no
// mapa de dívida bancária.
// =============================================================================
/**
 * CONTA DE TRIBUTO A RECOLHER — o que a aba `Tributos a Recolher` POSSUI.
 *
 * Um predicado só, em escopo de módulo, porque três abas precisam concordar sobre
 * ele: a de tributos (que projeta), a de giro (que precisa NÃO projetar as mesmas
 * contas) e o balanço (que lê o espelho em vez da conta). Duas cópias desta regra
 * divergiriam na primeira mudança, e o efeito de divergir é dupla contagem — o
 * mesmo defeito que a dívida bancária no giro tinha até a sessão 39.
 *
 * Vale só para linha de PASSIVO: no ativo a mesma expressão pegaria "ICMS a
 * recuperar" e "créditos tributários", que são direito, não obrigação.
 */
const ehTributoARecolher = (chave: string) =>
  /tribut|imposto|icms|pis|cofins|inss|fgts|irrf|iss|parcelament|refis|previd/i.test(chave);

function abaTributos(wb: ExcelJS.Workbook, ctx: Ctx, gRec: Grade): Grade {
  const g = new Grade(wb, "Tributos a Recolher", ctx.anos, ctx.nHist);
  g.cabecalho("TRIBUTOS A RECOLHER — PARCELAMENTOS", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));

  const tribCP = (ctx.linhasPorBloco.get("passivo_circulante") ?? [])
    .filter((l) => ehTributoARecolher(l.chave));
  const tribPNC = (ctx.linhasPorBloco.get("passivo_nao_circulante") ?? [])
    .filter((l) => ehTributoARecolher(l.chave));
  const tributarios = [...tribCP, ...tribPNC];

  if (tributarios.length === 0) {
    g.linha(null, {
      rotulo: "Nenhuma conta de tributo a recolher foi identificada nas linhas extraídas deste caso.",
    });
    g.linha(null, {
      rotulo: "A aba fica VAZIA de propósito — inventar um parcelamento seria pior que não ter a aba.",
    });
    // O ESPELHO EXISTE MESMO VAZIO, com zeros. O balanço e o fluxo leem estas âncoras
    // sempre; se elas só existissem quando o caso tem tributo, um caso sem tributo
    // derrubaria a geração inteira — e foi exatamente o que aconteceu na primeira
    // versão desta mudança (a fixture do (0105) não tem conta tributária).
    g.pular();
    g.espelho("BALANCE SHEET ACCOUNTS", [
      { chave: "ESP_CP", rotulo: "Tributos a recolher — circulante (para o Balance Sheet)" },
      { chave: "ESP_PNC", rotulo: "Tributos a recolher — não circulante (para o Balance Sheet)" },
    ]);
    g.espelho("CASH FLOW ACCOUNTS", [
      { chave: "ESP_PAGO", rotulo: "Pagamento do período (para o Cash Flow)" },
    ]);
    for (const ano of ctx.anos) {
      for (const ch of ["ESP_CP", "ESP_PNC", "ESP_PAGO"]) g.set(ch, ano, 0, { fmt: NUM });
    }
    // Mesmo vazia a aba é entregue e impressa — o teste (0105f) pegou esta saída
    // antecipada sem área de impressão.
    g.finalizar("__unidade");
    return g;
  }
  // ===========================================================================
  // PARCELAMENTO AMORTIZA; TRIBUTO CORRENTE A RECOLHER ROLA. SÃO COISAS DIFERENTES.
  //
  // O DEFEITO QUE ISTO CORRIGE. Todas as linhas desta aba tinham `% pago = 0` fixo,
  // com a nota "ZERO = saldo rolado". Para o ICMS do mês isso é verdade — o saldo
  // renova na mesma velocidade em que é pago. Para um PARCELAMENTO é falso, e cara:
  // parcelamento é, por definição, um cronograma de pagamento; deixá-lo congelado
  // significa que a empresa nunca paga o acordo que assinou, o caixa projetado não
  // sente essa saída, e a dívida tributária aparece no balanço de 2030 igualzinha à
  // de 2025. Medido no v35: 11.978 de parcelamento parados nos cinco exercícios,
  // dentro de 34.912 de tributos igualmente congelados.
  //
  // A REGRA, e de onde vem cada número:
  //   • PARCELAMENTO (`parcelamento`, `REFIS`, `PERT`, transação tributária, dívida
  //     ativa) → amortiza LINEARMENTE, como a dívida bancária, e pelo mesmo prazo
  //     implícito: sob pagamento linear em `n` anos, a parcela que vence em 12 meses
  //     é `1/n` do saldo, logo `n = 1 ÷ fração no circulante`, medida no balanço.
  //     No v35: 3.272 no circulante contra 11.978 no total → 27,3% → 3,7 anos.
  //   • TRIBUTO CORRENTE (ICMS, IRRF, ISS, PIS/COFINS, obrigações tributárias) →
  //     saldo ROTATIVO: fica constante. Zerá-lo diria que a empresa deixou de ter
  //     imposto a recolher, o que só acontece se ela parar de operar.
  //   • PROVISÃO tributária → fica constante: ela se resolve por decisão judicial ou
  //     acordo, e nenhum dos dois tem data que o modelo possa inferir.
  //
  // Sem repartição curto/longo prazo do parcelamento no caso, o prazo cai em 5 anos
  // (60 meses é o parcelamento ordinário da legislação federal) e a nota DIZ que é
  // padrão legal, não medição — que é diferente de inventar em silêncio.
  // ===========================================================================
  const ehParcelamento = (chave: string) =>
    /parcelament|reparcelament|refis|\bpert\b|paes|paex|transa(ç|c)(ã|a)o tribut|d(í|i)vida ativa/i
      .test(chave);
  const ehProvisao = (chave: string) => /provis(ã|a)o|conting(ê|e)nc/i.test(chave);
  const somaParcelamento = (bloco: BlocoModelo) =>
    (ctx.linhasPorBloco.get(bloco) ?? [])
      .filter((l) => ehParcelamento(l.chave))
      .reduce((acc, l) => acc + Math.abs(valorNaEscala(l, ctx.ultimoHist, ctx.ent.unidade)?.valor ?? 0), 0);
  const parcCP = somaParcelamento("passivo_circulante");
  const parcLP = somaParcelamento("passivo_nao_circulante");
  const fracParcCP = parcCP + parcLP > 0 ? parcCP / (parcCP + parcLP) : 0;
  const prazoParcelamentoMedido = fracParcCP > 0;
  const prazoParcelamento = prazoParcelamentoMedido
    ? Math.min(10, Math.max(1, Math.round((1 / fracParcCP) * 10) / 10))
    : 5;

  for (const l of tributarios) {
    const ch = chaveLinha("trib", l);
    g.linha(ch, { rotulo: l.chave, nota: (l.documentos ?? []).join(" · "), fmt: NUM });
    if (ehParcelamento(l.chave)) {
      g.linha(`${ch}#prazo`, { rotulo: "    prazo do parcelamento (anos)", fmt: NUM2 });
      g.linha(`${ch}#pct`, { rotulo: "    % pago no período (parcela linear)", fmt: PCT });
    } else {
      g.linha(`${ch}#pct`, { rotulo: "    % pago no período (premissa)", fmt: PCT });
    }
  }
  g.linha("TOTAL", { rotulo: "TOTAL A RECOLHER", negrito: true, topo: true, fmt: NUM });
  // `P18` — O ESPELHO DESTA ABA. É daqui que o balanço lê o passivo tributário e o
  // fluxo lê o pagamento. Sem o espelho, esta aba era DECORATIVA: as mesmas contas
  // eram projetadas por dias de giro no `Working Capital` e ficavam congeladas no
  // não circulante do balanço, então a aba podia dizer que o parcelamento amortiza
  // enquanto o balanço dizia que não — duas verdades sobre a mesma conta.
  g.pular();
  g.espelho("BALANCE SHEET ACCOUNTS", [
    { chave: "ESP_CP", rotulo: "Tributos a recolher — circulante (para o Balance Sheet)" },
    { chave: "ESP_PNC", rotulo: "Tributos a recolher — não circulante (para o Balance Sheet)" },
  ]);
  g.espelho("CASH FLOW ACCOUNTS", [
    { chave: "ESP_PAGO", rotulo: "Pagamento do período (para o Cash Flow)" },
  ]);

  for (const ano of ctx.anos) {
    const hist = !g.ehProjetado(ano);
    const ant = g.anoAnterior(ano);
    for (const l of tributarios) {
      const ch = chaveLinha("trib", l);
      if (hist) {
        const e = valorNaEscala(l, ano, ctx.ent.unidade);
        if (e) g.set(ch, ano, Math.abs(e.valor), { fmt: NUM, fill: FILL_HIST, nota: e.nota });
        else if (notaSemValor(l, ano)) g.set(ch, ano, null, { fmt: NUM, fill: FILL_HIST, nota: notaSemValor(l, ano) });
        continue;
      }
      if (ehParcelamento(l.chave)) {
        // O prazo é premissa: uma célula na primeira coluna projetada, e os anos
        // seguintes apontando para ela — uma edição reprojeta o parcelamento todo.
        const iProj = g.anos.indexOf(ano) - g.nHist;
        const refPrazoBase = g.ref(`${ch}#prazo`, g.anos[g.nHist], "$");
        g.set(`${ch}#prazo`, ano, iProj === 0 ? prazoParcelamento : `=${refPrazoBase}`, {
          fmt: NUM2, fill: iProj === 0 ? FILL_INPUT : undefined,
          nota: iProj === 0
            ? (prazoParcelamentoMedido
              ? `Prazo do parcelamento: ${prazoParcelamento} anos. NÃO é número inventado — é o prazo `
                + `IMPLÍCITO no balanço de ${ctx.ultimoHist}: ${(fracParcCP * 100).toFixed(1)}% do `
                + "parcelamento está no circulante, e sob parcela linear a fração de 12 meses é 1/n do "
                + "saldo. Se o termo de adesão disser outro prazo, troque AQUI: a linha de % e todos os "
                + "exercícios seguintes se refazem sozinhos."
              : "Prazo do parcelamento: 5 anos (60 meses), que é o parcelamento ORDINÁRIO da legislação "
                + "federal. Este caso não traz o parcelamento repartido entre circulante e não "
                + "circulante, então o prazo implícito não pôde ser medido — é padrão legal, não "
                + "medição. Troque AQUI pelo prazo do termo de adesão.")
            : "Mesmo prazo da primeira coluna projetada (referência fixa). Edite a célula azul de lá.",
        });
        g.set(`${ch}#pct`, ano,
          `=IF(${g.ref(`${ch}#prazo`, ano)}-${iProj}<=0,0,MIN(1,1/(${g.ref(`${ch}#prazo`, ano)}-${iProj})))`, {
          fmt: PCT,
          nota: "Parcela LINEAR até o fim do parcelamento: 1 ÷ (prazo − anos já decorridos). Dá "
            + "pagamento constante e zera o acordo no prazo. Parcelamento é cronograma — deixá-lo "
            + "congelado dizia que a empresa nunca paga o que assinou, e o caixa projetado não sentia "
            + "a saída. Para um cronograma irregular, digite o percentual do ano por cima.",
        });
      } else {
        g.set(`${ch}#pct`, ano, 0, {
          fmt: PCT, fill: FILL_INPUT,
          nota: ehProvisao(l.chave)
            ? "ZERO porque provisão não tem cronograma: ela se resolve por decisão judicial ou acordo, "
              + "e nenhum dos dois tem data que o modelo possa inferir. Quando houver desfecho, ele "
              + "entra aqui como percentual do ano."
            : "ZERO porque este é saldo ROTATIVO, não dívida a liquidar: o tributo corrente é pago no "
              + "mês seguinte e o do mês seguinte toma o lugar dele. Zerar a linha diria que a empresa "
              + "deixou de ter imposto a recolher, o que só acontece se ela parar de operar. Se houver "
              + "acordo para quitar este saldo, o percentual do ano entra aqui.",
        });
      }
      g.set(ch, ano, `=${g.ref(ch, ant!)}*(1-${g.ref(`${ch}#pct`, ano)})`, { fmt: NUM });
    }
    somaOuZero(g, "TOTAL", ano, tributarios.map((l) => g.ref(chaveLinha("trib", l), ano)), true);
    somaOuZero(g, "ESP_CP", ano, tribCP.map((l) => g.ref(chaveLinha("trib", l), ano)));
    somaOuZero(g, "ESP_PNC", ano, tribPNC.map((l) => g.ref(chaveLinha("trib", l), ano)));
    // O PAGAMENTO É DERIVADO DO SALDO, não calculado de novo. Ele é exatamente a queda
    // do total — então qualquer mudança de regra aqui (prazo editado no Excel, cronograma
    // digitado por cima) chega ao caixa sozinha, e as duas contas não podem divergir.
    // No realizado é ZERO: a variação de um exercício já ocorrido é história, e lançá-la
    // como pagamento projetado tiraria caixa duas vezes.
    g.set("ESP_PAGO", ano, hist || ant === null ? 0 : `=${g.ref("TOTAL", ant)}-${g.ref("TOTAL", ano)}`, {
      fmt: NUM,
      nota: hist ? "Zero no realizado: o que foi pago no passado já está no saldo extraído."
        : "Queda do total no período — é o que saiu do caixa. Derivado do saldo de propósito: "
          + "duas contas do mesmo pagamento divergiriam na primeira mudança de premissa.",
    });
  }
  g.finalizar("__unidade");
  return g;
}

// =============================================================================
// ABA Output — o resumo que vai para o comitê: crescimento, margem, alavancagem,
// cobertura de juros, liquidez. E o INTERRUPTOR DE CENÁRIO, que mora aqui e só
// aqui: `G2`. Toda outra aba lê `Output!$G$2`.
//
// Dois interruptores seriam o defeito clássico: alguém muda o da aba em que está,
// o resto do modelo continua no cenário antigo, e o arquivo mostra uma mistura de
// dois cenários sem nada denunciar.
// =============================================================================
function abaOutput(
  wb: ExcelJS.Workbook, ctx: Ctx,
  gDRE: Grade, gBS: Grade, gDiv: Grade, gCF: Grade, gFA: Grade, gWC: Grade,
  gRec: Grade, gGW: Grade, gTrib: Grade,
): { g: Grade; graficos: EspecGrafico[] } {
  const g = new Grade(wb, "Output", ctx.anos, ctx.nHist);

  // ---- SCENARIO + CHECK SCENARIO -------------------------------------------
  //
  // O interruptor mora em `G2` e só ali; toda outra aba lê `Output!$G$2`. Dois
  // interruptores seriam o defeito clássico: alguém muda o da aba em que está, o
  // resto do modelo continua no cenário antigo, e o arquivo mostra uma mistura de
  // dois cenários sem nada denunciar.
  //
  // O BLOCO `CHECK SCENARIO` é do Modelo Base (`Output!I2:L5`) e faz o caminho de
  // VOLTA: lê o cenário de dentro de cada aba de driver e mostra ao lado. Se uma
  // aba perder o vínculo com o dial — porque alguém colou por cima, ou porque a
  // referência quebrou —, aparece aqui, e não num número errado três abas adiante.
  //
  // NOTA DE LAYOUT, e é um defeito que esta rodada corrigiu: as linhas 1 a 5 são
  // escritas com `celula()`, que NÃO move o cursor da `Grade`. O código antigo
  // fazia `pular(4)` depois de escrever até a linha 5, e o cabeçalho caía
  // exatamente sobre a legenda "3 = Stress Case" — medido no arquivo gerado, que
  // trazia o título da aba no lugar do rótulo do terceiro cenário. Agora o cursor
  // é sincronizado explicitamente.
  g.celula(1, COL_ROTULO).value = "SCENARIO";
  g.celula(1, COL_ROTULO).font = fonte({ bold: true, size: TAM_TITULO_ABA });
  const cellCen = g.celula(2, 7);
  cellCen.value = 1;
  cellCen.fill = FILL_INPUT;
  cellCen.font = fonte({ bold: true, color: { argb: FONTE_COR.entrada } });
  cellCen.numFmt = "0";
  cellCen.dataValidation = {
    type: "whole", operator: "between", formulae: [1, 3], allowBlank: false,
    showErrorMessage: true, errorTitle: "Cenário inválido",
    error: "1 = Base Case, 2 = Cliente Case, 3 = Stress Case. Fora disso, CHOOSE devolve #VALUE! "
      + "em todas as abas — e um modelo cheio de #VALUE! é um modelo que ninguém lê.",
  };
  cellCen.note = comoNota(
    "INTERRUPTOR ÚNICO DE CENÁRIO. 1 = Base, 2 = Cliente, 3 = Stress. Todas as outras abas leem "
    + "esta célula; não existe segundo interruptor, de propósito.",
  );
  g.celula(2, COL_ROTULO).value = "Cenário ativo →";
  g.celula(2, COL_ROTULO).font = fonte();
  for (let i = 0; i < CENARIOS.length; i++) {
    const c = g.celula(3 + i, COL_ROTULO);
    c.value = `${i + 1} = ${CENARIOS[i]}`;
    c.font = fonte({ size: 9, italic: true, color: { argb: FONTE_COR.auxiliar } });
  }
  // CHECK SCENARIO — o caminho de volta, uma linha por aba com dial.
  g.celula(1, 9).value = "CHECK SCENARIO — o cenário lido DE VOLTA de cada aba";
  g.celula(1, 9).font = fonte({ bold: true });
  const abasComDial: [string, Grade][] = [
    ["Revenues, COGS & SG&A", gRec], ["Working Capital", gWC], ["Fixed Assets & CAPEX", gFA],
    ["ST Inv. & Debt", gDiv],
  ];
  abasComDial.forEach(([nome, grade], i) => {
    const r = 2 + i;
    g.celula(r, 9).value = nome;
    g.celula(r, 9).font = fonte({ size: 9 });
    const cel = g.celula(r, 12);
    cel.value = { formula: `'${nome}'!${grade.celulaCenario.replace(/\$/g, "")}` };
    cel.font = fonte({ color: { argb: FONTE_COR.externo } });
    cel.numFmt = "0";
    const dif = g.celula(r, 13);
    dif.value = { formula: `IF(${colLetra(12)}${r}=$G$2,"ok","DIVERGE")` };
    dif.font = fonte({ bold: true });
    dif.note = comoNota(
      `Lê o cenário de dentro da aba "${nome}" e compara com o interruptor. "DIVERGE" significa que `
      + "aquela aba perdeu o vínculo com o dial — e que os números dela são de outro cenário.",
    );
  });
  // ---- OS TRÊS CENÁRIOS SÃO TRÊS? -----------------------------------------
  //
  // O `CHECK SCENARIO` acima responde "todas as abas estão no mesmo cenário?".
  // Esta linha responde a OUTRA pergunta, que o arquivo não respondia: **os
  // cenários são diferentes entre si?**
  //
  // POR QUE ELA PRECISA EXISTIR. O `Cliente Case` nasce como `=<Base Case>` em
  // toda conta do modelo — convenção do Modelo Base, e certa como ponto de
  // partida. O efeito é que, num arquivo recém-exportado, girar o dial de 1 para
  // 2 não muda um número sequer, e nada denuncia isso. Um "Cliente Case" que é o
  // Base Case pode chegar a um comitê sem que a planilha o contradiga — e o
  // dropdown com três opções é a evidência de que ela deveria contradizer.
  //
  // O Stress tem a forma espelhada do mesmo risco: ele é o Base vezes um haircut
  // único (`Considerações!$F$8`). Zerada aquela célula, o Stress vira o Base e o
  // dropdown continua oferecendo três.
  //
  // A medida é EXATA e vem da aba de receita (`DIF_CENARIO`): a soma, conta a
  // conta e ano a ano, de `ABS(premissa do cenário − premissa do Base)`. Zero em
  // todos os anos significa premissas idênticas, e não pode significar outra
  // coisa. E ela é FÓRMULA VIVA: no minuto em que o analista digitar a primeira
  // premissa própria do Cliente Case dentro do Excel, o aviso some sozinho.
  g.celula(7, COL_ROTULO).value = "OS TRÊS CENÁRIOS SÃO TRÊS?";
  g.celula(7, COL_ROTULO).font = fonte({ bold: true });
  const projetadosDoDial = ctx.anos.filter((a) => g.ehProjetado(a));
  [["Cliente Case", "DIF_CENARIO#cli"], ["Stress Case", "DIF_CENARIO#str"]].forEach(
    ([nome, chave], i) => {
      const r = 8 + i;
      g.celula(r, COL_ROTULO).value = `    ${nome} vs Base`;
      g.celula(r, COL_ROTULO).font = fonte({ size: 9 });
      const soma = projetadosDoDial
        .map((a) => `N(${g.externa("Revenues, COGS & SG&A", gRec, chave, a)})`)
        .join("+");
      const cel = g.celula(r, 7);
      cel.value = { formula: soma.length > 0
        ? `IF((${soma})=0,"IDÊNTICO AO BASE","diferenciado")`
        : `"sem exercício projetado"` };
      cel.font = fonte({ bold: true, color: { argb: FONTE_COR.externo } });
      cel.note = comoNota(
        `Soma, conta a conta e em todos os exercícios projetados, de ABS(premissa do ${nome} − `
        + "premissa do Base). Zero significa que este cenário NÃO foi diferenciado: girar o dial "
        + "para ele não muda um número sequer do modelo.\n\n"
        + (nome === "Cliente Case"
          ? "É o estado NORMAL de um arquivo recém-exportado — o Cliente Case nasce espelhando o "
            + "Base, e é o analista que o preenche, na aba \"Revenues, COGS & SG&A\". O aviso some "
            + "sozinho na primeira premissa própria que for digitada."
          : "O Stress é o Base vezes o haircut de Considerações!$F$8. \"IDÊNTICO AO BASE\" aqui "
            + "significa que aquele haircut está zerado — e um cenário de estresse sem estresse é "
            + "pior que não ter cenário de estresse, porque parece que alguém olhou."),
      );
    });

  // Sincroniza o cursor com o que foi escrito à mão acima.
  g.pular(9 - g.proximaLinha() + 1);

  // ---- O AVISO QUE IMPEDE UM MODELO VAZIO DE PARECER UM MODELO --------------
  //
  // Medido contra a fixture: quando a extração não classifica `secao_canonica`,
  // TODO bloco do modelo fica vazio, a receita sai zero, e o arquivo entrega 14
  // abas de zeros com aparência de modelo institucional. Zero com aparência de
  // resultado é o pior defeito que este projeto pode produzir.
  const impedimentos: string[] = [];
  const nReceita = (ctx.linhasPorBloco.get("receita") ?? []).length;
  const receitaHist = (ctx.linhasPorBloco.get("receita") ?? [])
    .reduce((acc, l) => acc + Math.abs(valorNaEscala(l, ctx.ultimoHist, ctx.ent.unidade)?.valor ?? 0), 0);
  if (nReceita === 0) {
    impedimentos.push("NENHUMA conta caiu no bloco de RECEITA. Causa quase certa: as linhas "
      + "extraídas estão sem `secao_canonica` (a classificação por seção não rodou ou o "
      + "documento não foi reconhecido). Sem receita, todo o modelo projeta zero.");
  } else if (receitaHist === 0) {
    impedimentos.push(`As ${nReceita} contas de receita não têm valor no último exercício `
      + `realizado (${ctx.ultimoHist}). A projeção parte de zero e permanece zero.`);
  }
  if (ctx.premissaPorLinha.size === 0) {
    impedimentos.push("NENHUMA conta tem premissa vinculada. Todas ficam constantes: o arquivo "
      + "mostra o último realizado repetido, não uma projeção. Vincular na seção Modelagem do portal.");
  }
  if (ctx.hist.length === 0) {
    impedimentos.push("Nenhum exercício realizado identificado para a entidade modelada. "
      + "Conferir a entidade escolhida no passo 1 da Modelagem contra as abas de dados.");
  }
  if (impedimentos.length > 0) {
    g.pular();
    const rAviso = g.linha(null, {
      rotulo: "⚠ ESTE MODELO NÃO ESTÁ PROJETÁVEL — leia antes de usar qualquer número",
      negrito: true,
    });
    const cAviso = g.celula(rAviso, COL_ROTULO);
    cAviso.fill = FILL_CHECK_ERRO;
    cAviso.font = fonte({ bold: true, size: TAM_TITULO_ABA });
    for (const texto of impedimentos) {
      const r = g.linha(null, { rotulo: `• ${texto}` });
      g.celula(r, COL_ROTULO).fill = FILL_CHECK_ERRO;
      g.celula(r, COL_ROTULO).alignment = { wrapText: true };
      g.ws.getRow(r).height = 28;
    }
  }

  g.pular();
  g.cabecalho("OUTPUT — RESUMO PARA COMITÊ", `Valores em ${ctx.ent.unidade}`, eixoHerdado(gRec));

  // Categoria dos gráficos: o ano como NÚMERO. O cabeçalho é data (`P01`), e uma
  // série de datas num eixo de categoria sai como número de série no gráfico.
  g.linha("ANO_GRAF", { rotulo: "Exercício (eixo dos gráficos)" });

  // ---- SUMMARY --------------------------------------------------------------
  g.linha(null, { rotulo: "SUMMARY", bloco: true });
  g.linha("REC_LIQ", { rotulo: "Net Revenues", fmt: NUM });
  g.linha("REC_CRESC", { rotulo: "    % Growth", fmt: PCT });
  g.linha("EBITDA", { rotulo: "EBITDA", negrito: true, fmt: NUM });
  g.linha("EBITDA_MG", { rotulo: "    % EBITDA Margin", fmt: PCT });
  g.linha("EBIT", { rotulo: "EBIT", fmt: NUM });
  g.linha("LUCRO", { rotulo: "Net Profit", fmt: NUM });
  g.linha("CAPEX", { rotulo: "Capex", fmt: NUM });
  g.linha("VAR_NCG", { rotulo: "Variação NCG", fmt: NUM });
  g.linha("FCL", { rotulo: "Free Cash Flow", negrito: true, fmt: NUM });
  g.pular();

  // ---- RESUMO DOS TRÊS CENÁRIOS --------------------------------------------
  //
  // O bloco que o `Arquitetura do Sistema/4 Análises e Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md` §2.2 pediu: "um bloco
  // 'Resumo dos três cenários' calculado INDEPENDENTEMENTE do seletor — as três
  // cascatas em paralelo para essas poucas linhas, não para o modelo inteiro".
  //
  // O SUMMARY logo acima mostra um cenário por vez, porque lê o interruptor. Este
  // mostra os três ao mesmo tempo, porque lê a cascata paralela da aba de receita.
  // Sem ele, o motivo de existirem três cenários não estava em lugar nenhum do
  // arquivo: para comparar, o analista girava o dial e anotava números num papel.
  //
  // A FRONTEIRA DO BLOCO É A DA CASCATA, e ela está DITA na aba (linha
  // `CEN_FORA`), não silenciada. Receita, EBITDA e margem saem da cascata de
  // receita, que já é parametrizada por cenário. ND/EBITDA, DSCR e pico de caixa
  // NÃO entram: eles exigiriam replicar a cascata de dívida e o fluxo de caixa por
  // cenário — três modelos paralelos dentro do arquivo —, e num arquivo que vai a
  // credor cada linha nova é uma chance de ele passar a mentir. Um bloco que
  // mostrasse ND/EBITDA "dos três cenários" lendo a dívida de UM seria pior que a
  // ausência dele: o número existiria, pareceria comparação, e não seria.
  g.linha(null, { rotulo: "RESUMO DOS TRÊS CENÁRIOS (não olha o interruptor)", bloco: true });
  g.linha("CEN_CHECK", {
    rotulo: "    CHECK: o cenário ativo bate com a cascata paralela (0 = bate)", fmt: NUM,
  });
  // A ORDEM DAS TRÊS LINHAS DE CADA MÉTRICA É A DO `CHOOSE` (Base, Cliente,
  // Stress), como em `CENARIOS_SUF`. O teste (36) lê por deslocamento a partir do
  // rótulo da métrica, então trocar a ordem aqui faria o arquivo comparar o Stress
  // contra a coluna do Cliente — e o teste cai, que é o ponto.
  for (const [chave, rotulo, fmt] of [
    ["CEN_REC", "Receita líquida", NUM],
    ["CEN_CRESC", "    % crescimento da receita", PCT],
    ["CEN_EBITDA", "EBITDA", NUM],
    ["CEN_MG", "    Margem EBITDA", PCT],
  ] as const) {
    g.linha(null, { rotulo, negrito: fmt === NUM });
    for (const [suf, nome] of CENARIOS_SUF) {
      g.linha(`${chave}#${suf}`, { rotulo: `        ${nome}`, fmt });
    }
  }

  // ---- OS DOIS ÍNDICES QUE O CREDOR OLHA, POR CENÁRIO ----------------------
  //
  // ELES SÃO SENSIBILIDADE, NÃO COMPARAÇÃO COMPLETA, e a diferença está escrita
  // na tela porque ela muda o que o número autoriza concluir.
  //
  // O que varia entre as três colunas é o EBITDA, que vem da cascata paralela. O
  // que NÃO varia é a dívida: os três leem a dívida líquida e o serviço do
  // cenário ATIVO. Replicar a dívida por cenário exigiria três cascatas de
  // amortização e três fluxos de caixa dentro do arquivo, porque o revolver saca
  // conforme o caixa — e é justamente no cenário pior que ele saca mais.
  //
  // POR QUE ISSO AINDA VALE: a leitura é um PISO da deterioração. No cenário
  // conservador a dívida também sobe, então o ND/EBITDA verdadeiro é PIOR que o
  // publicado e o DSCR verdadeiro é MENOR. Logo "rompe aqui" implica "rompe lá",
  // que é a pergunta que o credor faz. O contrário não vale, e é isso que a nota
  // impede alguém de concluir.
  g.linha(null, { rotulo: "Sensibilidade dos covenants ao cenário (dívida do cenário ativo)", bloco: true });
  // OS RÓTULOS NÃO REPETEM OS DO BLOCO DE RATIOS, de propósito: dois rótulos
  // idênticos na mesma aba fazem quem procura achar o primeiro e ler o outro. O
  // teste tropeçou nisso antes do comitê.
  for (const [chave, rotulo, fmt] of [
    ["CEN_ND", "Net Debt / EBITDA por cenário", MULT],
    ["CEN_DSCR", "DSCR por cenário", MULT],
  ] as const) {
    g.linha(null, { rotulo, negrito: true });
    for (const [suf, nome] of CENARIOS_SUF) {
      g.linha(`${chave}#${suf}`, { rotulo: `        ${nome}`, fmt });
      g.linha(`${chave}#${suf}#t`, { rotulo: "            rompe?" });
    }
  }
  g.linha("CEN_CHECK_DIV", {
    rotulo: "    CHECK: a coluna do cenário ATIVO bate com os índices acima (0 = bate)", fmt: NUM2,
    nota: "Distância entre a sensibilidade do cenário ativo e as linhas de ND/EBITDA e DSCR do "
      + "bloco de RATIOS. Zero por construção: as duas leem a mesma dívida e o mesmo EBITDA. "
      + "Diferente de zero significa que este bloco deixou de descrever o modelo ao lado.",
  });
  const rCenFora = g.linha("CEN_FORA", {
    rotulo: "    Este bloco é um PISO deliberado, mantido como CONTRAPROVA do bloco abaixo: aqui só "
      + "o EBITDA muda, a dívida é a do cenário ATIVO. Não há CHECK que compare os dois — medido "
      + "antes de escrever, a desigualdade \"a réplica nunca é mais otimista que o piso\" não é "
      + "invariante (depende de qual cenário está ativo). O que o bloco abaixo tem é a coluna do "
      + "cenário ATIVO batendo exatamente com este, e essa é a garantia que existe.",
  });
  g.celula(rCenFora, COL_ROTULO).font = fonte({ italic: true, size: 9 });
  g.celula(rCenFora, COL_ROTULO).alignment = { wrapText: true };
  g.ws.getRow(rCenFora).height = 28;
  g.pular();

  // ---- A RÉPLICA COMPLETA: dívida e caixa por cenário, de verdade ----------
  //
  // O que o bloco de sensibilidade acima declarava como fora do alcance sem
  // "três fluxos de caixa dentro do arquivo" — e isso não mudou: o que muda é
  // que a cascata de caixa por cenário passa a existir, só que compacta, aqui
  // no Output, em vez de replicada linha a linha nas outras 5 abas.
  //
  // POR QUE CABE AQUI, e não replicando Working Capital inteiro / Fixed Assets
  // inteiro / ST Inv. & Debt inteiro / Cash Flow inteiro / Balance Sheet
  // inteiro: medido antes de escrever (o método de sempre) que CAPEX e
  // depreciação já são tratados como invariantes ao cenário pela PRÓPRIA
  // sombra da DRE (`EBITDA#v_${suf}` soma `DEPRECIACAO` ativa, sem sombra
  // própria — sessão 54) — então replicá-los aqui seria inventar uma
  // divergência que o resto do arquivo não tem. E as tranches EXISTENTES e a
  // captação nova são cronograma CONTRATUAL (SAC sobre saldo original, prazo e
  // carência fixos) — não dependem de receita, então TOTAL_JUROS,
  // TOTAL_AMORT_CAIXA, EMISSAO_JUROS e EMISSAO_AMORT são os MESMOS nos três
  // cenários. A ÚNICA peça que de fato varia com o cenário, além do EBITDA que
  // já tinha sombra, é o REVOLVER — porque ele saca conforme o caixa, e é
  // justamente no cenário pior que ele saca mais. É por isso que a réplica
  // completa precisa de pouco mais que a NCG por cenário (Working Capital,
  // acima) e uma segunda cascata de revolver: EBIT → tributo → FCO → caixa →
  // furo → saque, ano a ano, na MESMA técnica sem circularidade do revolver
  // ativo (juros sobre o saldo de ABERTURA, nunca sobre o saque do próprio
  // ano — ver `NOTA_CIRCULARIDADE` na aba de dívida).
  g.linha(null, { rotulo: "RÉPLICA COMPLETA POR CENÁRIO (dívida e caixa correm nos três, não só no ativo)", bloco: true });
  for (const [suf, nome] of CENARIOS_SUF) {
    g.linha(null, { rotulo: `    ${nome}` });
    g.linha(`CEN_EBIT#${suf}`, { rotulo: "        EBIT (EBITDA da sombra − depreciação ativa)", fmt: NUM });
    g.linha(`CEN_FIN_EXP#${suf}`, { rotulo: "        despesa financeira (tranches + captação, ativas; revolver, deste cenário)", fmt: NUM });
    g.linha(`CEN_FIN_INC#${suf}`, { rotulo: "        receita financeira (aplicação do caixa excedente deste cenário)", fmt: NUM });
    g.linha(`CEN_TAX#${suf}`, { rotulo: "        tributo sobre o lucro (só sobre EBT positivo)", fmt: NUM });
    g.linha(`CEN_FCO#${suf}`, { rotulo: "        caixa de operação (lucro + depreciação + ΔNCG deste cenário − tributo pago)", fmt: NUM });
    g.linha(`CEN_CAIXA_ANTES#${suf}`, { rotulo: "        caixa antes do revolver", fmt: NUM });
    g.linha(`CEN_FURO#${suf}`, { rotulo: "        furo em relação ao caixa mínimo", fmt: NUM });
    g.linha(`CEN_ST_FIM#${suf}`, { rotulo: "        aplicação — excedente ao caixa mínimo", fmt: NUM });
    g.linha(`CEN_REV_INI#${suf}`, { rotulo: "        revolver — saldo de abertura", fmt: NUM });
    g.linha(`CEN_REV_JUROS#${suf}`, { rotulo: "        revolver — juros do período", fmt: NUM });
    g.linha(`CEN_REV_SAQUE#${suf}`, { rotulo: "        revolver — saque/(amortização)", fmt: NUM });
    g.linha(`CEN_REV_FIM#${suf}`, { rotulo: "        revolver — saldo de fechamento", negrito: true, fmt: NUM });
    g.linha(`CEN_CAIXA_FIM#${suf}`, { rotulo: "        caixa de fechamento", negrito: true, fmt: NUM });
    g.linha(`CEN_DIV_LIQ#${suf}`, { rotulo: "        dívida líquida", negrito: true, fmt: NUM });
    g.linha(`CEN_SERVICO#${suf}`, { rotulo: "        serviço da dívida (juros + amortização de caixa)", fmt: NUM });
    g.linha(`CEN_ND_REAL#${suf}`, { rotulo: "        Net Debt / EBITDA — RÉPLICA COMPLETA", negrito: true, fmt: MULT });
    g.linha(`CEN_ND_REAL#${suf}#t`, { rotulo: "            rompe?" });
    g.linha(`CEN_DSCR_REAL#${suf}`, { rotulo: "        DSCR — RÉPLICA COMPLETA", negrito: true, fmt: MULT });
    g.linha(`CEN_DSCR_REAL#${suf}#t`, { rotulo: "            rompe?" });
    g.linha(`CEN_PICO_REVOLVER#${suf}`, {
      rotulo: "        pico de uso do revolver (máximo acumulado até o ano)", negrito: true, fmt: NUM,
    });
  }
  // POR QUE NÃO HÁ UM CHECK "a réplica nunca é mais otimista que o piso": a
  // primeira versão deste bloco tentou essa desigualdade, e medir antes de
  // escrever (o método de sempre) mostrou que ela só vale na direção óbvia
  // quando o cenário comparado é PIOR que o ativo — com o dial no Stress, a
  // coluna do Cliente no piso carrega a dívida (alta) do Stress sobre um
  // EBITDA melhor, e a réplica de verdade (dívida mais baixa, porque o
  // Cliente puxa menos revolver) fica MAIS otimista que esse piso, não menos.
  // A desigualdade depende de qual cenário está ativo, então não é um
  // invariante — e um CHECK que reprova sozinho, imprevisível conforme o
  // dial, é pior que nenhum CHECK. O que fica é só a igualdade provável por
  // construção: a coluna do cenário ATIVO tem de bater nos dois blocos.
  g.linha("CEN_CHECK_REAL", {
    rotulo: "    CHECK: a réplica completa do cenário ATIVO bate com a dívida líquida do bloco de "
      + "RATIOS (0 = bate)", fmt: NUM2,
    nota: "Distância entre a réplica completa do cenário ATIVO (via CHOOSE, como o `CEN_CHECK_DIV` "
      + "acima) e `DV_LIQ`. Zero por construção: os dois leem exatamente os mesmos insumos quando o "
      + "cenário da réplica é o mesmo que está ligado no interruptor. Diferente de zero é a réplica "
      + "tendo se separado do modelo que ela deveria descrever.",
  });
  g.pular();

  // ---- BALANCE SHEET (espelho) ---------------------------------------------
  //
  // CONTA A CONTA, não só os totais (§5.1 do CONFORMIDADE.md — era o item de maior
  // impacto da fila). O `Output` é a aba que o comitê lê; um espelho que só mostra
  // "Current Assets" obriga quem está com o papel na mão a voltar ao `Balance Sheet`
  // para saber DE QUE é feito o ativo circulante. A referência abre conta a conta, e
  // é isso que faz do `Output` um relatório em vez de um sumário.
  //
  // As linhas de detalhe são as MESMAS da aba de origem, por referência — não há
  // segunda soma, nem segunda verdade: se o balanço mudar, o espelho acompanha. O
  // `Mismatch` continua sendo calculado das duas linhas de total daqui, que é a
  // guarda contra ler a linha errada por deslocamento de âncora.
  // O caixa já é a linha `Cash & Short Term Inv.` logo acima do bloco: repeti-lo
  // aqui seria mostrar o mesmo número duas vezes na mesma coluna.
  const detalheAC = [
    { chave: "AC_OPER", rotulo: "    Operating current assets" },
    ...(gBS.tem("RECONC_AC") ? [{ chave: "RECONC_AC", rotulo: "    reconciliation w/ reported total" }] : []),
  ];
  const detalheANC = [
    { chave: "IMOB", rotulo: "    Property, plant & intangibles" },
    ...(gBS.tem("RECONC_ANC") ? [{ chave: "RECONC_ANC", rotulo: "    reconciliation w/ reported total" }] : []),
  ];
  const detalhePC = [
    { chave: "PC_OPER", rotulo: "    Operating current liabilities" },
    { chave: "DIVIDA_CP", rotulo: "    Short-term debt + revolver" },
    ...(gBS.tem("RECONC_PC") ? [{ chave: "RECONC_PC", rotulo: "    reconciliation w/ reported total" }] : []),
  ];
  const detalhePNC = [
    { chave: "DIVIDA_LP", rotulo: "    Long-term debt" },
    ...(gBS.tem("RECONC_PNC") ? [{ chave: "RECONC_PNC", rotulo: "    reconciliation w/ reported total" }] : []),
  ];
  const detalhePL = [
    { chave: "LUCROS_ACUM", rotulo: "    Retained earnings (model)" },
    { chave: "PL_RETIDO", rotulo: "    Retained earnings (extracted + model)" },
    { chave: "REPERFILAMENTO", rotulo: "    Debt-to-equity conversion (cumulative)" },
    ...(gBS.tem("RECONC_PL") ? [{ chave: "RECONC_PL", rotulo: "    reconciliation w/ reported total" }] : []),
  ];
  const espelhoDoBalanco: Array<{ chave: string; rotulo: string; detalhe?: typeof detalheAC }> = [
    { chave: "BS_AC", rotulo: "Current Assets", detalhe: detalheAC },
    { chave: "BS_ANC", rotulo: "Long-Term & Permanent Assets", detalhe: detalheANC },
    { chave: "BS_ATIVO", rotulo: "ASSETS" },
    { chave: "BS_PC", rotulo: "Current Liabilities", detalhe: detalhePC },
    { chave: "BS_PNC", rotulo: "Long-Term Liabilities", detalhe: detalhePNC },
    { chave: "BS_PL", rotulo: "Shareholder's Equity", detalhe: detalhePL },
    { chave: "BS_PASSIVO", rotulo: "LIABILITIES & EQUITY" },
  ];
  g.linha(null, { rotulo: "BALANCE SHEET", bloco: true });
  g.linha("BS_CAIXA", { rotulo: "Cash & Short Term Inv.", fmt: NUM });
  for (const bloco of espelhoDoBalanco) {
    const total = bloco.chave === "BS_ATIVO" || bloco.chave === "BS_PASSIVO";
    g.linha(bloco.chave, { rotulo: bloco.rotulo, negrito: total, topo: total, fmt: NUM });
    for (const d of bloco.detalhe ?? []) {
      g.linha(`bsd:${d.chave}`, { rotulo: d.rotulo, fmt: NUM });
    }
  }
  g.linha("BS_MISMATCH", { rotulo: "Mismatch (ASSETS − LIABILITIES & EQUITY)", negrito: true, fmt: NUM2 });
  g.pular();

  // ---- INCOME STATEMENT (espelho) ------------------------------------------
  g.linha(null, { rotulo: "INCOME STATEMENT", bloco: true });
  g.linha("IS_GROSS", { rotulo: "Gross Revenues", fmt: NUM });
  g.linha("IS_DEDUC", { rotulo: "Deductions", fmt: NUM });
  g.linha("IS_NET", { rotulo: "Net Revenues", negrito: true, fmt: NUM });
  g.linha("IS_COGS", { rotulo: "COGS", fmt: NUM });
  g.linha("IS_GP", { rotulo: "Gross Profit", fmt: NUM });
  g.linha("IS_SGA", { rotulo: "SG&A", fmt: NUM });
  g.linha("IS_EBITDA", { rotulo: "EBITDA", negrito: true, fmt: NUM });
  g.linha("IS_DA", { rotulo: "Depreciation & Amortization", fmt: NUM });
  g.linha("IS_EBIT", { rotulo: "EBIT", negrito: true, fmt: NUM });
  g.linha("IS_FIN", { rotulo: "Financial Result", fmt: NUM });
  g.linha("IS_EBT", { rotulo: "EBT", fmt: NUM });
  g.linha("IS_TAX", { rotulo: "Income Tax", fmt: NUM });
  g.linha("IS_NP", { rotulo: "NET PROFIT", negrito: true, topo: true, fmt: NUM });
  g.pular();

  // ---- CASH FLOW (espelho) --------------------------------------------------
  // Também conta a conta (§5.1): as três atividades abertas nas linhas que as
  // compõem. Sem isto, "Cash Flow from Operations" negativo no papel não diz se o
  // problema é resultado, giro ou depreciação — e é a primeira pergunta do comitê.
  const detalheFCO = [
    { chave: "NET_INCOME", rotulo: "    Net income" },
    { chave: "DEPREC", rotulo: "    (+) D&A" },
    { chave: "VAR_NCG", rotulo: "    (+/−) Change in working capital" },
  ];
  const detalheFCF = [
    { chave: "CAPTACAO", rotulo: "    (+) New debt" },
    { chave: "AMORT", rotulo: "    (−) Debt amortization" },
    { chave: "REVOLVER", rotulo: "    (+/−) Revolver" },
    { chave: "DIVIDENDOS", rotulo: "    (−) Dividends" },
  ];
  g.linha(null, { rotulo: "CASH FLOW", bloco: true });
  g.linha("CF_FCO", { rotulo: "Cash Flow from Operations", fmt: NUM });
  for (const d of detalheFCO) g.linha(`cfd:${d.chave}`, { rotulo: d.rotulo, fmt: NUM });
  g.linha("CF_FCI", { rotulo: "Cash Flow from Investing", fmt: NUM });
  g.linha("cfd:CAPEX", { rotulo: "    (−) CAPEX", fmt: NUM });
  g.linha("CF_FCL", { rotulo: "FREE CASH FLOW", negrito: true, fmt: NUM });
  g.linha("CF_FCF", { rotulo: "Cash Flow from Financing", fmt: NUM });
  for (const d of detalheFCF) g.linha(`cfd:${d.chave}`, { rotulo: d.rotulo, fmt: NUM });
  g.linha("CF_VAR", { rotulo: "Net Change in Cash", fmt: NUM });
  g.linha("CF_INI", { rotulo: "Beg. of the Period Cash", fmt: NUM });
  g.linha("CF_FIM", { rotulo: "END OF PERIOD CASH", negrito: true, topo: true, fmt: NUM });
  g.linha("CF_MIN", { rotulo: "Required (minimum) Cash", fmt: NUM });
  g.pular();

  // ---- DEBT & RATIOS -------------------------------------------------------
  //
  // O Modelo Base dedica 79 linhas a isto (13 blocos de tranche), e HOJE 627 das
  // fórmulas dele estão com `#REF!` — o bloco inteiro aponta para uma tabela de
  // dívida que não existe mais no arquivo (§20 do mapa). Aqui a mesma informação
  // é montada a partir do espelho da aba de dívida, que existe e é auditável.
  g.linha(null, { rotulo: "DEBT & RATIOS", bloco: true });
  g.linha("DV_EXISTENTE", { rotulo: "Dívida existente (fechamento)", fmt: NUM });
  g.linha("DV_NOVA", { rotulo: "Captações novas (saldo)", fmt: NUM });
  g.linha("DV_NOVOMONEY", { rotulo: "New money da reestruturação (saldo)", fmt: NUM });
  g.linha("DV_REVOLVER", { rotulo: "Revolver (saldo)", fmt: NUM });
  g.linha("DV_TOTAL", { rotulo: "Total Financial Debt", negrito: true, topo: true, fmt: NUM });
  g.linha("DV_CAIXA", { rotulo: "(−) Caixa e equivalentes", fmt: NUM });
  g.linha("DV_LIQ", { rotulo: "Net Financial Debt", negrito: true, fmt: NUM });
  g.linha("DV_JUROS", { rotulo: "Juros e encargos do período", fmt: NUM });
  g.linha("DV_AMORT", { rotulo: "Amortização do período", fmt: NUM });
  g.linha("DV_SERVICO", { rotulo: "Serviço da dívida (juros + amortização)", negrito: true, fmt: NUM });
  g.linha("DV_TRIB", { rotulo: "Parcelamentos tributários (saldo)", fmt: NUM });
  g.pular();

  // ---- RATIOS + COVENANTS --------------------------------------------------
  //
  // Cada índice vem com o CORTE SUGERIDO ao lado (é o desenho do Modelo Base:
  // `Corte Sugerido` / `Covenant Sugerido` nas tabelas laterais que alimentam os
  // gráficos) e com um teste explícito de rompimento. Um índice sem o corte ao
  // lado obriga quem lê a saber o covenant de cabeça.
  g.linha(null, { rotulo: "RATIOS & COVENANTS", bloco: true });
  g.linha("R_ND_EBITDA", { rotulo: "Net Debt / EBITDA", negrito: true, fmt: MULT });
  g.linha("C_ND_EBITDA", { rotulo: "    corte sugerido (covenant)", fmt: MULT });
  g.linha("T_ND_EBITDA", { rotulo: "    rompe?" });
  g.linha("R_DIV_EBITDA", { rotulo: "Total Debt / EBITDA", fmt: MULT });
  g.linha("R_COBERTURA", { rotulo: "EBITDA / Serviço da dívida (DSCR)", negrito: true, fmt: MULT });
  g.linha("C_COBERTURA", { rotulo: "    corte sugerido (covenant)", fmt: MULT });
  g.linha("T_COBERTURA", { rotulo: "    rompe?" });
  g.linha("R_JUROS", { rotulo: "EBITDA / Juros (Interest Coverage)", fmt: MULT });
  g.linha("R_LIQ_CORR", { rotulo: "Liquidez corrente", fmt: MULT });
  g.linha("C_LIQ_CORR", { rotulo: "    corte sugerido (covenant)", fmt: MULT });
  g.linha("T_LIQ_CORR", { rotulo: "    rompe?" });
  g.linha("R_LIQ_SECA", { rotulo: "Liquidez seca (sem estoque)", fmt: MULT });
  g.linha("R_LIQ_IMED", { rotulo: "Liquidez imediata (só caixa)", fmt: MULT });
  g.linha("R_ALAV_PL", { rotulo: "Dívida bruta / Patrimônio líquido", fmt: MULT });
  g.pular();

  // ---- RETORNO E SOLVÊNCIA -------------------------------------------------
  //
  // O `Arquitetura do Sistema/2 Especificação/f0/08` fasejou ROA, ROE e Altman "até a extração isolar as linhas-conceito
  // necessárias". Ela isola desde as 14 abas: o balanço tem ativo total e
  // patrimônio líquido, a DRE tem lucro líquido e EBIT. O bloqueio documentado lá
  // deixou de valer para o arquivo de modelagem, e ninguém tinha revisitado.
  //
  // POR QUE O Z'' E NÃO O Z ORIGINAL. O Z de 1968 usa VALOR DE MERCADO do
  // patrimônio, que empresa fechada não tem, e foi calibrado em indústria de
  // capital aberto. O Z'' (Altman, mercados emergentes) troca por valor contábil
  // e derruba o giro do ativo, justamente para servir a empresa fechada e não
  // industrial — que é o universo destes mandatos.
  g.linha(null, { rotulo: "RETORNO E SOLVÊNCIA", bloco: true });
  g.linha("R_ROA", { rotulo: "ROA — lucro líquido / ativo total", fmt: PCT });
  g.linha("R_ROE", { rotulo: "ROE — lucro líquido / patrimônio líquido", fmt: PCT });
  g.linha("R_ALTMAN", { rotulo: "Altman Z\u2033 (mercados emergentes)", negrito: true, fmt: NUM2 });
  g.linha("T_ALTMAN", { rotulo: "    zona" });
  g.pular();

  // ---- REPERFILAMENTO: a alavanca, e o que ela resolve ---------------------
  //
  // O §2.6 do diagnóstico: quando o Output diz DSCR 0,3 e ND/EBITDA 10,8x, a
  // pergunta seguinte do mandato é QUAL REESTRUTURAÇÃO RESOLVE. O arquivo
  // diagnosticava e não tinha alavanca nenhuma.
  //
  // A alavanca é a CARÊNCIA por tranche, na aba de dívida, ao lado do prazo que
  // já era editável. Este bloco mostra o que ela fez: o serviço que o cronograma
  // original exigia, o serviço depois do que foi negociado, e o alívio de cada
  // exercício — com o DSCR nos dois lados, que é onde o alívio vira ou não vira
  // covenant cumprido.
  //
  // O QUE ELE COMPARA, e está escrito na tela: as TRANCHES EXISTENTES. O efeito
  // de segunda ordem — menos serviço, mais caixa, menos revolver, menos juros de
  // revolver — não entra no "antes", porque o "antes" teria de ser um modelo
  // inteiro rodando em paralelo. Isso torna o alívio publicado um PISO: o
  // benefício real é maior.
  g.linha(null, { rotulo: "REPERFILAMENTO — o que a carência negociada resolve", bloco: true });
  g.linha("RP_ANTES", { rotulo: "Serviço das tranches no cronograma original", fmt: NUM });
  g.linha("RP_DEPOIS", { rotulo: "Serviço das mesmas tranches como está negociado", fmt: NUM });
  g.linha("RP_ALIVIO", { rotulo: "Alívio do exercício (antes − depois)", negrito: true, fmt: NUM });
  g.linha("RP_DSCR_SEM", { rotulo: "DSCR que o cronograma original produziria", fmt: MULT });
  g.linha("RP_DSCR_COM", { rotulo: "DSCR de hoje (o do bloco de RATIOS)", negrito: true, fmt: MULT });
  g.linha("RP_VEREDITO", { rotulo: "    a negociação resolve o covenant?" });
  g.pular();

  // ---- CICLO DE CAIXA ------------------------------------------------------
  //
  // `Arquitetura do Sistema/2 Especificação/f0/08` fasejou PMR/PME/PMP "até a extração isolar as linhas-conceito
  // necessárias como âncoras endereçáveis". Ela ISOLA: o `Working Capital`
  // separa clientes, estoques e fornecedores para aplicar dias de giro a cada um
  // — o que faltava era publicar os espelhos e fazer a divisão aqui.
  //
  // Por que 360 e não 365: é a convenção do giro que a própria aba usa para
  // projetar (dias × base ÷ 360). Misturar as duas bases faria o ciclo publicado
  // divergir dos dias que dirigem a projeção, e a diferença (1,4%) apareceria
  // como erro de arredondamento que ninguém consegue explicar.
  //
  // ZERO NÃO É RESPOSTA. Caso sem conta de clientes publica "n.a.", não "0 dias":
  // zero dias de recebimento afirma que a empresa vende à vista, que é uma
  // afirmação sobre o negócio. É a mesma regra do `Arquitetura do Sistema/2 Especificação/f0/08` — sem o insumo, a
  // célula não estima.
  g.linha(null, { rotulo: "CICLO DE CAIXA (dias)", bloco: true });
  g.linha("CC_PMR", { rotulo: "PMR — prazo médio de recebimento", fmt: NUM2 });
  g.linha("CC_PME", { rotulo: "PME — prazo médio de estocagem", fmt: NUM2 });
  g.linha("CC_PMP", { rotulo: "PMP — prazo médio de pagamento a fornecedores", fmt: NUM2 });
  g.linha("CC_OPER", { rotulo: "Ciclo operacional (PMR + PME)", negrito: true, topo: true, fmt: NUM2 });
  g.linha("CC_FIN", { rotulo: "Ciclo financeiro (− PMP)", negrito: true, fmt: NUM2 });
  g.pular();

  // ---- NECESSIDADE DE RECURSOS E CAPACIDADE DE PAGAMENTO -------------------
  //
  // O ARQUIVO DIAGNOSTICAVA E NÃO DIMENSIONAVA. Ele já dizia que o DSCR fica em
  // 0,3 e que o ND/EBITDA vai a 10,8x — e o revolver, sacando o que falta todo
  // ano, chegava a 122.216 sem que nada dissesse que isso É a necessidade de
  // recursos. O revolver é uma FICÇÃO DE FECHAMENTO: ele existe para o balanço
  // fechar, não porque alguém vai emprestar 122 milhões a uma empresa com DSCR
  // de 0,3. Quem lê precisava fazer a conta de cabeça, ano a ano, na aba errada.
  //
  // Nenhuma linha daqui é dado novo: todas saem de linhas que já existem nesta
  // aba ou no `Cash Flow`. O que muda é a leitura — de "o modelo mostra que não
  // fecha" para "o rombo é de X, no ano Y, e vem daqui".
  //
  // SOBRE A DÍVIDA SUSTENTÁVEL, e por que ela é ND/EBITDA e não uma tabela de
  // amortização: dívida líquida sustentável = corte de covenant × EBITDA é a
  // definição do próprio covenant, e não exige inventar prazo nenhum. Sustentar
  // um número de dívida a partir de um perfil de amortização suposto seria
  // fabricar a premissa mais sensível do caso dentro de uma linha de resumo.
  // O mesmo vale para o serviço: EBITDA ÷ DSCR alvo é a leitura direta do corte.
  //
  // Os dois cortes vêm das células AZUIS de covenant logo acima (`C_ND_EBITDA` e
  // `C_COBERTURA`), nunca das constantes: negociou outro patamar, digita lá e
  // este bloco inteiro se move junto.
  g.linha(null, { rotulo: "NECESSIDADE DE RECURSOS E CAPACIDADE DE PAGAMENTO", bloco: true });
  g.linha("NR_FURO", { rotulo: "Necessidade de recursos do exercício", negrito: true, fmt: NUM });
  g.linha("NR_ACUM", { rotulo: "    acumulada desde o início da projeção", negrito: true, fmt: NUM });
  g.linha("NR_PICO", { rotulo: "    pico do horizonte projetado", fmt: NUM });
  g.linha("NR_ANO_PICO", { rotulo: "    ano do pico", fmt: "0" });
  g.linha("NR_DIV_SUST", { rotulo: "Dívida líquida sustentável (ao corte de ND/EBITDA)", fmt: NUM });
  g.linha("NR_DIV_EXC", { rotulo: "    excesso sobre o sustentável", negrito: true, fmt: NUM });
  g.linha("NR_SERV_SUP", { rotulo: "Serviço da dívida suportado (ao corte de DSCR)", fmt: NUM });
  g.linha("NR_SERV_EXC", { rotulo: "    excesso de serviço sobre o suportado", negrito: true, fmt: NUM });
  g.linha(null, { rotulo: "    para onde vai o caixa gerado", bloco: false });
  g.linha("NR_USO_SERV", { rotulo: "    (−) serviço da dívida", fmt: NUM });
  g.linha("NR_USO_TRIB", { rotulo: "    (−) tributos e parcelamentos", fmt: NUM });
  g.linha("NR_USO_GIRO", { rotulo: "    (−) variação do giro", fmt: NUM });
  g.linha("NR_USO_CAPEX", { rotulo: "    (−) capex", fmt: NUM });
  g.linha("NR_USO_TOTAL", { rotulo: "    = total dos usos", negrito: true, topo: true, fmt: NUM });
  g.linha("NR_COBERTO", { rotulo: "    EBITDA cobre os usos? (EBITDA − usos)", negrito: true, fmt: NUM });
  g.pular();

  // ---- CHECKS DO MODELO ----------------------------------------------------
  g.linha(null, { rotulo: "CHECKS DO MODELO", bloco: true });
  g.linha("CHECK_BS", { rotulo: "Balanço fecha? (0 = sim)", fmt: NUM2 });
  g.linha("CHECK_CAIXA", { rotulo: "Caixa ≥ mínimo? (0 = sim)", fmt: NUM2 });
  g.linha("CHECK_EBITDA", { rotulo: "EBITDA positivo? (0 = sim)", fmt: NUM2 });
  g.linha("CHECK_TXT", { rotulo: "Diagnóstico do exercício" });

  // -------------------------------------------------------------- preencher
  const ext = (aba: string, grade: Grade, chave: string, ano: number) => `=${g.externa(aba, grade, chave, ano)}`;
  const temTrib = gTrib.tem("TOTAL");

  // Faixas do horizonte PROJETADO, para o pico da necessidade de recursos. O
  // realizado fica de fora de propósito: necessidade de recursos é uma pergunta
  // sobre o futuro, e um furo que já aconteceu já foi financiado de algum jeito.
  const anosProjetados = ctx.anos.filter((a) => g.ehProjetado(a));
  const faixaFuro = anosProjetados.length > 0
    ? `$${g.letraDoAno(anosProjetados[0])}$${g.n("NR_FURO")}`
      + `:$${g.letraDoAno(anosProjetados[anosProjetados.length - 1])}$${g.n("NR_FURO")}`
    : "";
  const faixaAnos = anosProjetados.length > 0
    ? `$${g.letraDoAno(anosProjetados[0])}$${g.n("__titulo")}`
      + `:$${g.letraDoAno(anosProjetados[anosProjetados.length - 1])}$${g.n("__titulo")}`
    : "";

  for (const ano of ctx.anos) {
    const ant = g.anoAnterior(ano);
    g.set("ANO_GRAF", ano, `=YEAR(${g.letraDoAno(ano)}${g.n("__titulo")})`, {
      fmt: "0",
      nota: "O ano como número inteiro. O cabeçalho é uma DATA (o eixo do tempo do modelo), e uma "
        + "data num eixo de categoria de gráfico apareceria como número de série.",
    });

    // SUMMARY
    g.set("REC_LIQ", ano, ext("Income Statement", gDRE, "NET_REV", ano), { fmt: NUM });
    g.set("REC_CRESC", ano, ant === null ? null
      : `=IF(${g.ref("REC_LIQ", ant)}<>0,${g.ref("REC_LIQ", ano)}/${g.ref("REC_LIQ", ant)}-1,0)`, { fmt: PCT });
    g.set("EBITDA", ano, ext("Income Statement", gDRE, "EBITDA", ano), { fmt: NUM, negrito: true });
    g.set("EBITDA_MG", ano, `=IF(${g.ref("REC_LIQ", ano)}<>0,${g.ref("EBITDA", ano)}/${g.ref("REC_LIQ", ano)},0)`, { fmt: PCT });
    g.set("EBIT", ano, ext("Income Statement", gDRE, "EBIT", ano), { fmt: NUM });
    g.set("LUCRO", ano, ext("Income Statement", gDRE, "NET_PROFIT", ano), { fmt: NUM });
    g.set("CAPEX", ano, ext("Fixed Assets & CAPEX", gFA, "ESP_CAPEX", ano), { fmt: NUM });
    g.set("VAR_NCG", ano, ext("Working Capital", gWC, "ESP_VAR_NCG", ano), { fmt: NUM });
    g.set("FCL", ano, ext("Cash Flow", gCF, "FCL", ano), { fmt: NUM, negrito: true });

    // RESUMO DOS TRÊS CENÁRIOS — os três ao mesmo tempo, lendo a cascata paralela
    // da aba de receita. As sombras existem só na projeção (o passado é um), então
    // as colunas realizadas ficam vazias aqui de propósito: repetir o mesmo número
    // três vezes convidaria a procurar uma diferença que não existe.
    if (g.ehProjetado(ano)) {
      for (const [suf] of CENARIOS_SUF) {
        g.set(`CEN_REC#${suf}`, ano,
          ext("Revenues, COGS & SG&A", gRec, `RECEITA_LIQUIDA#v_${suf}`, ano), { fmt: NUM });
        // O crescimento do PRIMEIRO ano projetado é medido contra o realizado, que
        // é comum aos três — e é por isso que ele usa a linha ativa da aba de
        // receita como base. Sem isso, o primeiro ano ficaria sem crescimento
        // justamente onde a diferença entre os cenários começa.
        const baseAnterior = ant === null
          ? null
          : g.ehProjetado(ant)
            ? g.ref(`CEN_REC#${suf}`, ant)
            : ext("Revenues, COGS & SG&A", gRec, "RECEITA_LIQUIDA", ant).slice(1);
        g.set(`CEN_CRESC#${suf}`, ano, baseAnterior === null ? null
          : `=IF(${baseAnterior}<>0,${g.ref(`CEN_REC#${suf}`, ano)}/${baseAnterior}-1,0)`,
          { fmt: PCT });
        g.set(`CEN_EBITDA#${suf}`, ano,
          ext("Revenues, COGS & SG&A", gRec, `EBITDA#v_${suf}`, ano), { fmt: NUM });
        g.set(`CEN_MG#${suf}`, ano,
          `=IF(${g.ref(`CEN_REC#${suf}`, ano)}<>0,`
          + `${g.ref(`CEN_EBITDA#${suf}`, ano)}/${g.ref(`CEN_REC#${suf}`, ano)},0)`, { fmt: PCT });
      }
      // O CHECK vem da aba de receita, onde a comparação é feita entre a sombra do
      // cenário ativo e a linha ativa. Trazê-lo para cá é o que faz o comitê ver o
      // zero sem abrir outra aba — e ver diferente de zero se as duas cascatas se
      // separarem.
      g.set("CEN_CHECK", ano, ext("Revenues, COGS & SG&A", gRec, "CHECK_SOMBRA", ano), {
        fmt: NUM,
        nota: "Distância entre a cascata paralela do cenário ATIVO e as linhas ativas da aba de "
          + "receita (receita líquida, custos e SG&A). Zero por construção: as duas saem do mesmo "
          + "código. Diferente de zero significa que alguém separou as duas, e aí este bloco "
          + "deixou de descrever o modelo ao lado.",
      });

      // A SENSIBILIDADE DOS DOIS COVENANTS. O EBITDA é o do cenário; a dívida
      // líquida e o serviço são os do cenário ATIVO, e a nota diz isso em toda
      // célula porque é o que separa esta leitura de uma comparação completa.
      for (const [suf, nome] of CENARIOS_SUF) {
        const ebitdaCen = g.ref(`CEN_EBITDA#${suf}`, ano);
        g.set(`CEN_ND#${suf}`, ano,
          `=IF(${ebitdaCen}<=0,"EBITDA<=0",${g.ref("DV_LIQ", ano)}/${ebitdaCen})`, {
          fmt: MULT,
          nota: `Dívida líquida do cenário ATIVO dividida pelo EBITDA do ${nome}. É PISO: no `
            + "cenário pior o revolver saca mais e a dívida sobe, então o índice verdadeiro é maior "
            + "que este.",
        });
        g.set(`CEN_ND#${suf}#t`, ano,
          `=IF(NOT(ISNUMBER(${g.ref(`CEN_ND#${suf}`, ano)})),"n.a.",`
          + `IF(${g.ref(`CEN_ND#${suf}`, ano)}>${g.ref("C_ND_EBITDA", ano)},"ROMPE","ok"))`, {});
        g.set(`CEN_DSCR#${suf}`, ano,
          `=IF(${g.ref("DV_SERVICO", ano)}<=0,"sem serviço de dívida",${ebitdaCen}/${g.ref("DV_SERVICO", ano)})`, {
          fmt: MULT,
          nota: `Serviço da dívida do cenário ATIVO contra o EBITDA do ${nome}. É PISO da `
            + "deterioração, pelo mesmo motivo do índice acima.",
        });
        g.set(`CEN_DSCR#${suf}#t`, ano,
          `=IF(NOT(ISNUMBER(${g.ref(`CEN_DSCR#${suf}`, ano)})),"n.a.",`
          + `IF(${g.ref(`CEN_DSCR#${suf}`, ano)}<${g.ref("C_COBERTURA", ano)},"ROMPE","ok"))`, {});
      }

      // A RÉPLICA COMPLETA. EBIT → tributo → caixa de operação → caixa antes do
      // revolver → furo → saque — a MESMA cadeia da aba `Cash Flow`, com a MESMA
      // técnica sem circularidade (juros sobre o saldo de ABERTURA, nunca sobre o
      // saque do próprio ano), calculada TRÊS vezes, uma por cenário. CAPEX,
      // depreciação, o serviço das tranches existentes e da captação nova são os
      // MESMOS nos três — não dependem de receita — e entram por referência à
      // aba ativa, sem replicar.
      for (const [suf] of CENARIOS_SUF) {
        // `k(chave)` tira o gabarito literal aninhado (`` `CEN_X#${suf}` ``
        // dentro doutro gabarito) — achado de revisão (SonarCloud
        // `typescript:S4624`): um gabarito aninhado é mais fácil de errar a
        // interpolação sem notar, e esta função troca todos por uma chamada.
        const k = (chave: string) => `${chave}#${suf}`;
        const kEbit = k("CEN_EBIT"); const kFinExp = k("CEN_FIN_EXP"); const kFinInc = k("CEN_FIN_INC");
        const kTax = k("CEN_TAX"); const kFco = k("CEN_FCO"); const kCaixaAntes = k("CEN_CAIXA_ANTES");
        const kFuro = k("CEN_FURO"); const kStFim = k("CEN_ST_FIM"); const kRevIni = k("CEN_REV_INI");
        const kRevJuros = k("CEN_REV_JUROS"); const kRevSaque = k("CEN_REV_SAQUE"); const kRevFim = k("CEN_REV_FIM");
        const kCaixaFim = k("CEN_CAIXA_FIM"); const kDivLiq = k("CEN_DIV_LIQ"); const kServico = k("CEN_SERVICO");
        const kNdReal = k("CEN_ND_REAL"); const kDscrReal = k("CEN_DSCR_REAL"); const kPico = k("CEN_PICO_REVOLVER");
        const kEbitda = k("CEN_EBITDA"); const kNcgWC = `VAR_NCG#v_${suf}`;

        g.set(kEbit, ano, `=${g.ref(kEbitda, ano)}-${ext("Income Statement", gDRE, "DA", ano).slice(1)}`, { fmt: NUM });

        // O ANO ANTERIOR da MESMA sombra — caixa, revolver e aplicação. Três
        // casos, não dois: sem `ant` nenhum (zero anos históricos — o caso que
        // `impedimentos` já detecta e avisa, mas continua gerando a aba), com
        // `ant` histórico (a base é a linha ATIVA, comum aos três cenários), ou
        // com `ant` já projetado (a sombra do próprio ano anterior). O mesmo
        // desenho do `baseAnterior` do resumo de receita logo acima — e do
        // `ncgAnterior` da sombra de NCG no Working Capital, que já tratava os
        // três casos. Um helper, não três ternários aninhados copiados — achado
        // de revisão: os três repetiam a mesma forma e só trocavam a chave e a
        // referência externa de fallback.
        const anteriorDe = (chaveSombra: string, aba: string, grade: Grade, chaveAtiva: string): string => {
          if (ant === null) return "0";
          if (g.ehProjetado(ant)) return g.ref(chaveSombra, ant);
          return ext(aba, grade, chaveAtiva, ant).slice(1);
        };
        const caixaAnterior = anteriorDe(kCaixaFim, "Cash Flow", gCF, "CAIXA_FIM");
        const revolverAnterior = anteriorDe(kRevFim, "ST Inv. & Debt", gDiv, "REVOLVER_FIM");
        const stFimAnterior = anteriorDe(kStFim, "ST Inv. & Debt", gDiv, "ST_FIM");

        g.set(kRevIni, ano, `=${revolverAnterior}`, { fmt: NUM });
        g.set(kRevJuros, ano,
          `=-${g.ref(kRevIni, ano)}*${ext("ST Inv. & Debt", gDiv, "TAXA_REVOLVER", ano).slice(1)}`, {
          fmt: NUM,
          nota: "Juros sobre o saldo de ABERTURA — não sobre o saque deste ano. É a mesma técnica "
            + "do revolver ativo, e é o que evita circularidade sem precisar de cálculo iterativo.",
        });
        g.set(kFinExp, ano,
          `=${ext("ST Inv. & Debt", gDiv, "TOTAL_JUROS", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "EMISSAO_JUROS", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "NM_JUROS", ano).slice(1)}`
          + `+${g.ref(kRevJuros, ano)}`, {
          fmt: NUM,
          nota: "Juros das tranches existentes, da captação nova e do new money são os MESMOS do "
            + "cenário ativo (cronograma contratual, não depende de receita) — só o juro do "
            + "revolver é deste cenário.",
        });
        g.set(kFinInc, ano,
          `=${stFimAnterior}*${ext("ST Inv. & Debt", gDiv, "TAXA_APLIC", ano).slice(1)}`, { fmt: NUM });
        // O GANHO COM HAIRCUT é invariante ao cenário — vem da alavanca de
        // negociação (aba de dívida), não da receita —, igual à depreciação
        // logo abaixo. Sem ele aqui, `kTax` subtributaria e `kFco` subestimaria
        // o lucro líquido da sombra sempre que alguma tranche estivesse
        // classificada Haircut, e o CEN_CHECK_REAL deixaria de bater com o
        // modelo ativo justo quando essa alavanca estivesse em uso.
        const kGanhoHaircut = ext("ST Inv. & Debt", gDiv, "TOTAL_AMORT_HAIRCUT", ano).slice(1);
        g.set(kTax, ano,
          `=-MAX(0,${g.ref(kEbit, ano)}+${g.ref(kFinExp, ano)}+${g.ref(kFinInc, ano)}+${kGanhoHaircut})`
          + `*${ext("Income Statement", gDRE, "TAX_RATE", ano).slice(1)}`, { fmt: NUM });
        g.set(kFco, ano,
          `=${g.ref(kEbit, ano)}+${g.ref(kFinExp, ano)}+${g.ref(kFinInc, ano)}+${kGanhoHaircut}`
          + `+${g.ref(kTax, ano)}+${ext("Income Statement", gDRE, "DA", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "ESP_JUROS_PIK", ano).slice(1)}-${kGanhoHaircut}`
          + `+${ext("Working Capital", gWC, kNcgWC, ano).slice(1)}`
          + `+${ext("Cash Flow", gCF, "PAGO_TRIB", ano).slice(1)}`, {
          fmt: NUM,
          nota: "Lucro líquido deste cenário (EBIT + resultado financeiro deste cenário + ganho com "
            + "haircut, invariante ao cenário + tributo deste cenário) mais depreciação, mais o juro "
            + "do new money capitalizado em PIK (não-cash, igual à depreciação — invariante ao "
            + "cenário), MENOS o próprio ganho com haircut de volta (ele aumentou o lucro mas não "
            + "entrou caixa nenhum, o espelho do PIK acima), mais a variação de NCG deste cenário "
            + "(Working Capital), mais o tributo parcelado pago (o mesmo cronograma do cenário ativo).",
        });
        g.set(kCaixaAntes, ano,
          `=${caixaAnterior}+${g.ref(kFco, ano)}+${ext("Cash Flow", gCF, "CAPEX", ano).slice(1)}`
          + `+${ext("Cash Flow", gCF, "CAPTACAO", ano).slice(1)}+${ext("Cash Flow", gCF, "AMORT", ano).slice(1)}`
          + `+${ext("Cash Flow", gCF, "DIVIDENDOS", ano).slice(1)}`, { fmt: NUM });
        g.set(kFuro, ano,
          `=MAX(0,${ext("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano).slice(1)}-${g.ref(kCaixaAntes, ano)})`,
          { fmt: NUM });
        g.set(kRevSaque, ano,
          `=IF(${g.ref(kFuro, ano)}>0,${g.ref(kFuro, ano)},`
          + `-MIN(${g.ref(kRevIni, ano)},`
          + `MAX(0,${g.ref(kCaixaAntes, ano)}-${ext("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano).slice(1)})))`,
          { fmt: NUM });
        g.set(kRevFim, ano, `=${g.ref(kRevIni, ano)}+${g.ref(kRevSaque, ano)}`, { fmt: NUM, negrito: true });
        // Caixa antes do revolver, mais o saque — não repete os cinco termos
        // que já compõem `CEN_CAIXA_ANTES`, senão as duas fórmulas têm de ser
        // editadas em par para sempre, e nada aqui garante isso.
        g.set(kCaixaFim, ano, `=${g.ref(kCaixaAntes, ano)}+${g.ref(kRevSaque, ano)}`, { fmt: NUM, negrito: true });
        g.set(kStFim, ano,
          `=MAX(0,${g.ref(kCaixaFim, ano)}-${ext("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano).slice(1)})`,
          { fmt: NUM });

        g.set(kDivLiq, ano,
          `=${ext("ST Inv. & Debt", gDiv, "TOTAL_DIVIDA", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "EMISSAO_SALDO", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "NM_FIM", ano).slice(1)}`
          + `+${g.ref(kRevFim, ano)}-${g.ref(kCaixaFim, ano)}`, { fmt: NUM, negrito: true });
        g.set(kServico, ano,
          `=${ext("ST Inv. & Debt", gDiv, "TOTAL_AMORT_CAIXA", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "EMISSAO_AMORT", ano).slice(1)}`
          + `+${ext("ST Inv. & Debt", gDiv, "NM_AMORT", ano).slice(1)}`
          + `+ABS(${g.ref(kFinExp, ano)})`, { fmt: NUM });
        g.set(kNdReal, ano,
          `=IF(${g.ref(kEbitda, ano)}<=0,"EBITDA<=0",${g.ref(kDivLiq, ano)}/${g.ref(kEbitda, ano)})`,
          { fmt: MULT, negrito: true });
        g.set(`${kNdReal}#t`, ano,
          `=IF(NOT(ISNUMBER(${g.ref(kNdReal, ano)})),"n.a.",`
          + `IF(${g.ref(kNdReal, ano)}>${g.ref("C_ND_EBITDA", ano)},"ROMPE","ok"))`, {});
        g.set(kDscrReal, ano,
          `=IF(${g.ref(kServico, ano)}<=0,"sem serviço de dívida",${g.ref(kEbitda, ano)}/${g.ref(kServico, ano)})`,
          { fmt: MULT, negrito: true });
        g.set(`${kDscrReal}#t`, ano,
          `=IF(NOT(ISNUMBER(${g.ref(kDscrReal, ano)})),"n.a.",`
          + `IF(${g.ref(kDscrReal, ano)}<${g.ref("C_COBERTURA", ano)},"ROMPE","ok"))`, {});

        // PICO DE USO DO REVOLVER: máximo ACUMULADO até este ano, na MESMA
        // sombra — cada coluna mostra o pico até ali, e a última coluna é o
        // pico do horizonte inteiro. `MAX` sobre um intervalo que começa no
        // primeiro ano projetado desta mesma linha.
        const colAno = g.letraDoAno(ano);
        const colPrimeiroProj = g.letraDoAno(ctx.proj[0]);
        const linhaRevFim = g.n(kRevFim);
        g.set(kPico, ano, `=MAX(${colPrimeiroProj}${linhaRevFim}:${colAno}${linhaRevFim})`, {
          fmt: NUM,
          nota: "Maior saldo de revolver visto do primeiro ano projetado até este — a pergunta "
            + "\"quanto de dinheiro novo este cenário pode exigir, no pior momento\".",
        });
      }

      // O CHECK QUE PRENDE O BLOCO AO MODELO. A coluna do cenário ativo tem de
      // reproduzir exatamente as linhas de RATIOS, e o `CHOOSE` é o que escolhe
      // qual das três é a ativa. Sem este zero, o bloco poderia derivar do
      // modelo em silêncio — os números continuariam plausíveis.
      {
        // O INTERRUPTOR DO `Output` NÃO É O `celulaCenario` DA GRADE. Nas outras
        // abas o dial mora na coluna de nota, linha 1; aqui ele é a célula de
        // input `$G$2`, que é a que o comitê gira. Usar o da grade fazia o CHOOSE
        // ler célula vazia e devolver zero — o CHECK acusou na primeira execução.
        const celCen = `$${colLetra(7)}$2`;
        const escolhe = (ch: string) =>
          `CHOOSE(${celCen},${CENARIOS_SUF.map(([su]) => g.ref(`${ch}#${su}`, ano)).join(",")})`;
        g.set("CEN_CHECK_DIV", ano,
          `=IF(OR(NOT(ISNUMBER(${escolhe("CEN_ND")})),NOT(ISNUMBER(${g.ref("R_ND_EBITDA", ano)}))),0,`
          + `${escolhe("CEN_ND")}-${g.ref("R_ND_EBITDA", ano)})`
          + `+IF(OR(NOT(ISNUMBER(${escolhe("CEN_DSCR")})),NOT(ISNUMBER(${g.ref("R_COBERTURA", ano)}))),0,`
          + `${escolhe("CEN_DSCR")}-${g.ref("R_COBERTURA", ano)})`, {
          fmt: NUM2,
          nota: "Soma das duas distâncias entre a coluna do cenário ATIVO e as linhas de RATIOS. "
            + "Zero por construção: os dois blocos leem a mesma dívida e o mesmo EBITDA. Índice "
            + "que não é número (EBITDA negativo, sem serviço de dívida) entra como zero, porque "
            + "comparar texto com número daria #VALUE! e esconderia o resto do CHECK.",
        });
        g.set("CEN_CHECK_REAL", ano,
          `=${escolhe("CEN_DIV_LIQ")}-${g.ref("DV_LIQ", ano)}`, { fmt: NUM2 });
      }
    }

    // BALANCE SHEET
    g.set("BS_CAIXA", ano, ext("Balance Sheet", gBS, "CAIXA", ano), { fmt: NUM });
    g.set("BS_AC", ano, ext("Balance Sheet", gBS, "AC", ano), { fmt: NUM });
    g.set("BS_ANC", ano, ext("Balance Sheet", gBS, "ANC", ano), { fmt: NUM });
    g.set("BS_ATIVO", ano, ext("Balance Sheet", gBS, "ATIVO", ano), { fmt: NUM, negrito: true });
    g.set("BS_PC", ano, ext("Balance Sheet", gBS, "PC", ano), { fmt: NUM });
    g.set("BS_PNC", ano, ext("Balance Sheet", gBS, "PNC", ano), { fmt: NUM });
    g.set("BS_PL", ano, ext("Balance Sheet", gBS, "PL", ano), { fmt: NUM });
    g.set("BS_PASSIVO", ano, ext("Balance Sheet", gBS, "PASSIVO_PL", ano), { fmt: NUM, negrito: true });
    // O DETALHE conta a conta, por referência à aba de origem (§5.1).
    for (const bloco of espelhoDoBalanco) {
      for (const d of bloco.detalhe ?? []) {
        g.set(`bsd:${d.chave}`, ano, ext("Balance Sheet", gBS, d.chave, ano), {
          fmt: NUM,
          nota: "Detalhe do bloco acima, lido do `Balance Sheet`. Não há soma nova aqui: o total do "
            + "bloco também vem de lá, então espelho e origem não podem divergir.",
        });
      }
    }
    g.set("BS_MISMATCH", ano, `=${g.ref("BS_ATIVO", ano)}-${g.ref("BS_PASSIVO", ano)}`, {
      fmt: NUM2, negrito: true,
      nota: "Ativo menos passivo + PL, recalculado aqui a partir das duas linhas acima. "
        + "Diferente de zero significa que o balanço não fecha.",
    });

    // INCOME STATEMENT
    g.set("IS_GROSS", ano, ext("Income Statement", gDRE, "GROSS", ano), { fmt: NUM });
    g.set("IS_DEDUC", ano, ext("Income Statement", gDRE, "DEDUC", ano), { fmt: NUM });
    g.set("IS_NET", ano, ext("Income Statement", gDRE, "NET_REV", ano), { fmt: NUM, negrito: true });
    g.set("IS_COGS", ano, ext("Income Statement", gDRE, "COGS", ano), { fmt: NUM });
    g.set("IS_GP", ano, ext("Income Statement", gDRE, "GROSS_PROFIT", ano), { fmt: NUM });
    g.set("IS_SGA", ano, ext("Income Statement", gDRE, "SGA", ano), { fmt: NUM });
    g.set("IS_EBITDA", ano, ext("Income Statement", gDRE, "EBITDA", ano), { fmt: NUM, negrito: true });
    g.set("IS_DA", ano, ext("Income Statement", gDRE, "DA", ano), { fmt: NUM });
    g.set("IS_EBIT", ano, ext("Income Statement", gDRE, "EBIT", ano), { fmt: NUM, negrito: true });
    g.set("IS_FIN", ano, ext("Income Statement", gDRE, "FIN_RESULT", ano), { fmt: NUM });
    g.set("IS_EBT", ano, ext("Income Statement", gDRE, "EBT", ano), { fmt: NUM });
    g.set("IS_TAX", ano, ext("Income Statement", gDRE, "TAX", ano), { fmt: NUM });
    g.set("IS_NP", ano, ext("Income Statement", gDRE, "NET_PROFIT", ano), { fmt: NUM, negrito: true });

    // CASH FLOW
    g.set("CF_FCO", ano, ext("Cash Flow", gCF, "FCO", ano), { fmt: NUM });
    g.set("CF_FCI", ano, ext("Cash Flow", gCF, "FCI", ano), { fmt: NUM });
    g.set("CF_FCL", ano, ext("Cash Flow", gCF, "FCL", ano), { fmt: NUM, negrito: true });
    g.set("CF_FCF", ano, ext("Cash Flow", gCF, "FCF", ano), { fmt: NUM });
    g.set("CF_VAR", ano, ext("Cash Flow", gCF, "VAR_CAIXA", ano), { fmt: NUM });
    g.set("CF_INI", ano, ext("Cash Flow", gCF, "CAIXA_INI", ano), { fmt: NUM });
    g.set("CF_FIM", ano, ext("Cash Flow", gCF, "CAIXA_FIM", ano), { fmt: NUM, negrito: true });
    g.set("CF_MIN", ano, ext("ST Inv. & Debt", gDiv, "CAIXA_MIN", ano), { fmt: NUM });
    // O detalhe das três atividades, por referência à aba de fluxo (§5.1).
    for (const d of [...detalheFCO, { chave: "CAPEX", rotulo: "" }, ...detalheFCF]) {
      g.set(`cfd:${d.chave}`, ano, ext("Cash Flow", gCF, d.chave, ano), {
        fmt: NUM,
        nota: "Detalhe da atividade acima, lido do `Cash Flow`. O total continua vindo de lá — "
          + "somar as parcelas aqui criaria um segundo número para o mesmo fato.",
      });
    }

    // DEBT & RATIOS
    g.set("DV_EXISTENTE", ano, ext("ST Inv. & Debt", gDiv, "TOTAL_DIVIDA", ano), { fmt: NUM });
    g.set("DV_NOVA", ano, ext("ST Inv. & Debt", gDiv, "EMISSAO_SALDO", ano), { fmt: NUM });
    g.set("DV_NOVOMONEY", ano, ext("ST Inv. & Debt", gDiv, "NM_FIM", ano), {
      fmt: NUM,
      nota: "Rotulada à parte de `DV_NOVA` de propósito: dinheiro novo da reestruturação (prioridade "
        + "e termo próprios) não é refinanciamento comum, mesmo quando o número é parecido.",
    });
    g.set("DV_REVOLVER", ano, ext("ST Inv. & Debt", gDiv, "REVOLVER_FIM", ano), { fmt: NUM });
    g.set("DV_TOTAL", ano,
      `=${g.ref("DV_EXISTENTE", ano)}+${g.ref("DV_NOVA", ano)}+${g.ref("DV_NOVOMONEY", ano)}+${g.ref("DV_REVOLVER", ano)}`,
      { fmt: NUM, negrito: true });
    g.set("DV_CAIXA", ano, `=${g.ref("BS_CAIXA", ano)}`, { fmt: NUM });
    g.set("DV_LIQ", ano, `=${g.ref("DV_TOTAL", ano)}-${g.ref("DV_CAIXA", ano)}`, { fmt: NUM, negrito: true });
    g.set("DV_JUROS", ano, `=-${g.externa("ST Inv. & Debt", gDiv, "DESP_FIN", ano)}`, {
      fmt: NUM, nota: "Com sinal invertido para leitura: a despesa financeira é negativa na DRE.",
    });
    g.set("DV_AMORT", ano, ext("ST Inv. & Debt", gDiv, "ESP_AMORT", ano), { fmt: NUM });
    g.set("DV_SERVICO", ano, `=${g.ref("DV_JUROS", ano)}+${g.ref("DV_AMORT", ano)}`, { fmt: NUM, negrito: true });
    // ---- REPERFILAMENTO: antes × depois --------------------------------
    //
    // O "depois" é o serviço que o modelo já calcula (`DV_SERVICO`). O "antes"
    // vem da sombra da aba de dívida, que roda o cronograma original com
    // carência zero e prazo implícito. Os dois lados são das TRANCHES
    // EXISTENTES: o revolver e as captações novas ficam fora dos dois, porque
    // não é sobre eles que se negocia carência.
    g.set("RP_ANTES", ano, ext("ST Inv. & Debt", gDiv, "SERVICO_ORIG", ano), {
      fmt: NUM,
      nota: "Amortização mais juros que as tranches existentes exigiriam no cronograma que veio do "
        + "balanço: sem carência, no prazo implícito. Não se move quando alguém edita prazo ou "
        + "carência — é o ponto de partida da negociação.",
    });
    // MAÇÃ COM MAÇÃ: os dois lados são as MESMAS tranches existentes. Usar o
    // serviço total do modelo aqui misturaria revolver e captação nova de um
    // lado só, e o alívio da negociação apareceria contaminado pelo que o
    // revolver fez — que é outra conversa.
    //
    // E O "DEPOIS" É AMORTIZAÇÃO DE CAIXA (`TOTAL_AMORT_CAIXA`), NÃO A BRUTA.
    // Este bloco mede caixa liberado, e a chave "Efeito caixa? = N" da aba de
    // dívida existe exatamente para dizer que aquela tranche cai SEM pagamento —
    // haircut, capitalização, conversão em equity. Com a amortização bruta aqui,
    // o haircut movia o `DV_SERVICO` (que lê `ESP_AMORT`, e essa já é de caixa) e
    // NÃO movia este lado: o alívio saía ZERO para a alavanca que o próprio
    // veredito abaixo manda usar, e o contrafactual `RP_DSCR_SEM` — que soma o
    // alívio de volta ao serviço — andava sozinho. Medido: com uma chave virada
    // para "N", o serviço caía de 55.150 para 52.917 e o alívio continuava em
    // zero. As duas pontas passam a ler a mesma base, e o contrafactual fica
    // parado quando se puxa a alavanca, que é o que ele tem de fazer.
    g.set("RP_DEPOIS", ano,
      `=${ext("ST Inv. & Debt", gDiv, "TOTAL_AMORT_CAIXA", ano).slice(1)}`
      + `+ABS(${ext("ST Inv. & Debt", gDiv, "TOTAL_JUROS", ano).slice(1)})`, {
      fmt: NUM,
      nota: "Amortização COM EFEITO CAIXA mais juros das MESMAS tranches, com a carência e o prazo "
        + "que estiverem na aba de dívida. Tranche marcada \"Efeito caixa? = N\" sai daqui — ela "
        + "reduz o saldo sem pagamento, e este bloco mede caixa. Revolver e captações novas ficam "
        + "fora dos dois lados: não é sobre eles que se negocia carência.",
    });
    g.set("RP_ALIVIO", ano, `=${g.ref("RP_ANTES", ano)}-${g.ref("RP_DEPOIS", ano)}`, {
      fmt: NUM, negrito: true,
      nota: "Quanto de caixa a negociação libera neste exercício. É PISO: o alívio real é maior, "
        + "porque menos serviço significa menos revolver sacado e menos juros de revolver no ano "
        + "seguinte, e esse efeito de segunda ordem não está no lado \"antes\".",
    });
    // O CONTRAFACTUAL, e ele é UM só. O DSCR de hoje é o do bloco de RATIOS,
    // referenciado e não recalculado — recalcular criaria um segundo DSCR na
    // mesma página, com o mesmo nome e outro número. O que este bloco
    // acrescenta é o DSCR que existiria SEM a negociação: o serviço de hoje com
    // o alívio de volta, tudo o mais igual.
    g.set("RP_DSCR_SEM", ano,
      `=IF((${g.ref("DV_SERVICO", ano)}+${g.ref("RP_ALIVIO", ano)})<=0,"sem serviço",`
      + `${g.ref("EBITDA", ano)}/(${g.ref("DV_SERVICO", ano)}+${g.ref("RP_ALIVIO", ano)}))`, {
      fmt: MULT,
      nota: "O DSCR que o modelo teria se as tranches seguissem o cronograma original: o serviço "
        + "de hoje com o alívio devolvido, mantido todo o resto. Tudo o mais igual é hipótese, e "
        + "ela é conservadora — sem a negociação o caixa seria menor e o revolver, maior.",
    });
    g.set("RP_DSCR_COM", ano, `=${g.ref("R_COBERTURA", ano)}`, {
      fmt: MULT, negrito: true,
      nota: "É a MESMA linha do bloco de RATIOS, por referência. Recalcular aqui criaria um "
        + "segundo DSCR na mesma página, com o mesmo nome e outro número.",
    });
    // O VEREDITO É A ÚNICA LINHA QUE O COMITÊ PRECISA LER DEPOIS DE NEGOCIAR.
    // Ele não diz "melhorou": diz se atravessou o corte, que é a pergunta.
    g.set("RP_VEREDITO", ano,
      `=IF(OR(NOT(ISNUMBER(${g.ref("RP_DSCR_COM", ano)})),NOT(ISNUMBER(${g.ref("RP_DSCR_SEM", ano)}))),"n.a.",`
      + `IF(${g.ref("RP_DSCR_COM", ano)}>=${g.ref("C_COBERTURA", ano)},`
      + `IF(${g.ref("RP_DSCR_SEM", ano)}>=${g.ref("C_COBERTURA", ano)},"já cumpria","SIM — passou a cumprir"),`
      + `"não basta"))`, {
      nota: "Compara o DSCR depois da negociação com o corte de covenant. \"não basta\" significa "
        + "que a carência ajudou e não foi suficiente: o caminho seguinte é prazo maior, haircut "
        + "(a chave de efeito caixa na aba de dívida) ou dinheiro novo.",
    });

    g.set("DV_TRIB", ano, temTrib ? ext("Tributos a Recolher", gTrib, "TOTAL", ano) : 0, {
      fmt: NUM,
      nota: temTrib
        ? "Parcelamentos tributários — no mandato de reestruturação são quase sempre a segunda maior "
          + "dívida, e quase nunca estão no mapa de dívida bancária."
        : "Nenhuma conta de parcelamento tributário identificada neste caso.",
    });

    // RATIOS & COVENANTS
    // Alavancagem com EBITDA negativo é ARMADILHA: −3x parece confortável e
    // significa o oposto. O IF devolve texto e o comitê lê o que está acontecendo.
    g.set("R_ND_EBITDA", ano,
      `=IF(${g.ref("EBITDA", ano)}<=0,"EBITDA<=0",${g.ref("DV_LIQ", ano)}/${g.ref("EBITDA", ano)})`, {
      fmt: MULT, negrito: true,
      nota: "Com EBITDA negativo a razão não tem significado: −3,0x parece confortável e é o "
        + "contrário. A célula diz 'EBITDA<=0' em vez de mostrar um múltiplo enganoso.",
    });
    g.set("C_ND_EBITDA", ano, COVENANT_ND_EBITDA, {
      fmt: MULT, fill: FILL_INPUT,
      nota: `Corte sugerido de alavancagem (${COVENANT_ND_EBITDA}x). É PREMISSA de negociação, não `
        + "dado do caso — a célula existe para o corte do term sheet entrar aqui e o teste abaixo "
        + "responder sozinho.",
    });
    g.set("T_ND_EBITDA", ano,
      `=IF(NOT(ISNUMBER(${g.ref("R_ND_EBITDA", ano)})),"n.a.",`
      + `IF(${g.ref("R_ND_EBITDA", ano)}>${g.ref("C_ND_EBITDA", ano)},"ROMPE","ok"))`, {});
    g.set("R_DIV_EBITDA", ano,
      `=IF(${g.ref("EBITDA", ano)}<=0,"EBITDA<=0",${g.ref("DV_TOTAL", ano)}/${g.ref("EBITDA", ano)})`, { fmt: MULT });
    g.set("R_COBERTURA", ano,
      `=IF(${g.ref("DV_SERVICO", ano)}<=0,"sem serviço de dívida",${g.ref("EBITDA", ano)}/${g.ref("DV_SERVICO", ano)})`,
      { fmt: MULT, negrito: true });
    g.set("C_COBERTURA", ano, COVENANT_DSCR, {
      fmt: MULT, fill: FILL_INPUT,
      nota: `Corte sugerido de cobertura (${COVENANT_DSCR}x). Premissa de negociação.`,
    });
    g.set("T_COBERTURA", ano,
      `=IF(NOT(ISNUMBER(${g.ref("R_COBERTURA", ano)})),"n.a.",`
      + `IF(${g.ref("R_COBERTURA", ano)}<${g.ref("C_COBERTURA", ano)},"ROMPE","ok"))`, {});
    g.set("R_JUROS", ano,
      `=IF(${g.ref("DV_JUROS", ano)}<=0,"sem juros",${g.ref("EBITDA", ano)}/${g.ref("DV_JUROS", ano)})`, { fmt: MULT });
    // ZERO NÃO É "SEM PASSIVO CIRCULANTE", e a diferença acendia um covenant que
    // não existe. Com PC = 0 esta célula devolvia o NÚMERO 0, e `T_LIQ_CORR`
    // testa `ISNUMBER` para decidir se o teste se aplica: zero é número, então o
    // teste rodava, comparava 0 < corte e publicava "ROMPE". A empresa com a
    // MELHOR liquidez possível — nada a pagar no curto prazo — era reportada ao
    // comitê como quebrando o covenant de liquidez. A célula passa a devolver
    // texto, como `R_LIQ_IMED` já fazia ao lado, e aí o teste diz "n.a.".
    g.set("R_LIQ_CORR", ano,
      `=IF(${g.ref("BS_PC", ano)}<=0,"PC<=0",IF(${g.ref("BS_AC", ano)}<0,"AC<0",${g.ref("BS_AC", ano)}/${g.ref("BS_PC", ano)}))`, {
      fmt: MULT,
      nota: "Ativo circulante sobre passivo circulante. Com passivo circulante ZERO ou NEGATIVO a "
        + "razão não existe e a célula diz isso. Zero faria o teste de covenant ao lado ler 0 < corte "
        + "e acusar rompimento justamente na empresa que não deve nada no curto prazo; NEGATIVO é "
        + "pior — a razão sai negativa e se lê como liquidez péssima, quando o passivo é que ficou "
        + "impossível. Achado no arnês de variações: PC de −4.680 publicava liquidez de −9,56x.",
    });
    g.set("C_LIQ_CORR", ano, COVENANT_LIQUIDEZ, {
      fmt: MULT, fill: FILL_INPUT,
      nota: `Corte sugerido de liquidez corrente (${COVENANT_LIQUIDEZ}x). Premissa de negociação.`,
    });
    g.set("T_LIQ_CORR", ano,
      `=IF(NOT(ISNUMBER(${g.ref("R_LIQ_CORR", ano)})),"n.a.",`
      + `IF(${g.ref("R_LIQ_CORR", ano)}<${g.ref("C_LIQ_CORR", ano)},"ROMPE","ok"))`, {});
    // Liquidez SECA: sem estoque. Num mandato de reestruturação o estoque é o
    // ativo que menos vira caixa, e é o que separa "tem liquidez" de "tem
    // liquidez se conseguir vender tudo".
    g.set("R_LIQ_SECA", ano,
      `=IF(${g.ref("BS_PC", ano)}<=0,"PC<=0",IF(${g.ref("BS_AC", ano)}<0,"AC<0",`
      + `(${g.ref("BS_AC", ano)}-${g.externa("Working Capital", gWC, "ESP_ESTOQUE", ano)})`
      + `/${g.ref("BS_PC", ano)}))`, {
      fmt: MULT,
      nota: "Ativo circulante menos estoque, sobre o passivo circulante: separa liquidez de liquidez "
        + "que depende de vender estoque. Sem passivo circulante a razão não existe, e a célula diz "
        + "isso em vez de publicar zero — zero aqui se lê como a PIOR liquidez e é a melhor.",
    });
    // Liquidez IMEDIATA: só o caixa, sem contar com receber de ninguém. É a
    // pergunta que o credor faz primeiro numa mesa de reestruturação — "quanto
    // dá para pagar hoje" —, e ela não é a liquidez seca: esta ainda conta o
    // recebível, que depende de o cliente pagar.
    g.set("R_LIQ_IMED", ano,
      `=IF(${g.ref("BS_PC", ano)}<=0,"PC<=0",${g.ref("BS_CAIXA", ano)}/${g.ref("BS_PC", ano)})`, {
      fmt: MULT,
      nota: "Caixa e aplicações sobre o passivo circulante. Diferente da liquidez seca, que ainda "
        + "conta o recebível: aqui não se conta com ninguém pagar.",
    });
    // A GUARDA DIZIA "PL<=0" E TESTAVA "<>0" — e com patrimônio a descoberto ela
    // publicava um múltiplo NEGATIVO. Medido na própria fixture: PL de −632.191
    // saía como alavancagem de −1,03x, que lido rápido diz "quase sem dívida" e
    // significa o oposto — o patrimônio foi consumido inteiro. É a mesma
    // armadilha que o `R_ROE` logo abaixo já evita com a guarda certa, e que o
    // `R_ND_EBITDA` evita para EBITDA negativo. O rótulo passa a ser verdade.
    g.set("R_ALAV_PL", ano,
      `=IF(${g.ref("BS_PL", ano)}<=0,"PL<=0",${g.ref("DV_TOTAL", ano)}/${g.ref("BS_PL", ano)})`, {
      fmt: MULT,
      nota: "Dívida bruta sobre patrimônio líquido. Com PL zero ou negativo a razão não se aplica: "
        + "dívida dividida por patrimônio negativo dá múltiplo NEGATIVO, que parece alavancagem "
        + "baixa e é patrimônio a descoberto.",
    });

    // ---- RETORNO E SOLVÊNCIA ----------------------------------------------
    //
    // PL NEGATIVO NÃO VIRA PORCENTAGEM. Empresa em reestruturação com patrimônio
    // a descoberto produziria um ROE positivo enorme (prejuízo ÷ PL negativo), e
    // esse número lido rápido diz o contrário do que acontece. Publicar "PL<=0"
    // é a leitura honesta: o indicador não se aplica.
    g.set("R_ROA", ano,
      `=IF(${g.ref("BS_ATIVO", ano)}<=0,"sem ativo",${g.ref("LUCRO", ano)}/${g.ref("BS_ATIVO", ano)})`,
      { fmt: PCT });
    g.set("R_ROE", ano,
      `=IF(${g.ref("BS_PL", ano)}<=0,"PL<=0",${g.ref("LUCRO", ano)}/${g.ref("BS_PL", ano)})`, {
      fmt: PCT,
      nota: "Com patrimônio líquido negativo o indicador não se aplica, e a célula diz isso: "
        + "prejuízo dividido por PL negativo daria um retorno POSITIVO, que lido rápido afirma o "
        + "contrário do que está acontecendo.",
    });

    // ALTMAN Z'' — quatro razões, e nenhuma inventada.
    //
    //   Z'' = 6,56·X1 + 3,26·X2 + 6,72·X3 + 1,05·X4
    //   X1 = capital de giro ÷ ativo total      (AC − PC)
    //   X2 = lucros retidos ÷ ativo total
    //   X3 = EBIT ÷ ativo total
    //   X4 = patrimônio líquido ÷ passivo total (valor CONTÁBIL, não de mercado)
    //
    // ZONAS: acima de 2,6 segura; entre 1,1 e 2,6 cinzenta; abaixo de 1,1
    // aflição. Elas vêm do próprio Altman e entram como texto ao lado, porque um
    // número sozinho obriga quem lê a saber os cortes de cabeça.
    //
    // X2 É O QUE PODE FALTAR, e aí o índice inteiro não sai. Lucros retidos é
    // linha do patrimônio líquido, e nem todo documento a isola — quando o
    // extrator não achou nenhuma e o modelo ainda não acumulou resultado, a
    // célula publica "sem lucros retidos" em vez de tratar a ausência como zero.
    // Zero em X2 não é neutro: ele derruba o Z'' em até 3,26 pontos e joga uma
    // empresa saudável na zona de aflição.
    {
      const at = g.ref("BS_ATIVO", ano);
      const x1 = `(${g.ref("BS_AC", ano)}-${g.ref("BS_PC", ano)})/${at}`;
      const x2 = `${g.ref("bsd:PL_RETIDO", ano)}/${at}`;
      const x3 = `${g.ref("EBIT", ano)}/${at}`;
      const x4 = `${g.ref("BS_PL", ano)}/(${g.ref("BS_PC", ano)}+${g.ref("BS_PNC", ano)})`;
      g.set("R_ALTMAN", ano,
        `=IF(${at}<=0,"sem ativo",IF(NOT(ISNUMBER(${g.ref("bsd:PL_RETIDO", ano)})),"sem lucros retidos",`
        + `IF((${g.ref("BS_PC", ano)}+${g.ref("BS_PNC", ano)})<=0,"sem passivo",`
        + `6.56*(${x1})+3.26*(${x2})+6.72*(${x3})+1.05*(${x4}))))`, {
        fmt: NUM2, negrito: true,
        nota: "Altman Z\u2033, a versão para mercados emergentes e empresa de capital fechado: usa "
          + "o valor CONTÁBIL do patrimônio (o Z original usa valor de mercado, que empresa "
          + "fechada não tem) e não usa giro do ativo, para não penalizar quem não é indústria.\n\n"
          + "Z'' = 6,56×(capital de giro/ativo) + 3,26×(lucros retidos/ativo) + "
          + "6,72×(EBIT/ativo) + 1,05×(PL/passivo).",
      });
      g.set("T_ALTMAN", ano,
        `=IF(NOT(ISNUMBER(${g.ref("R_ALTMAN", ano)})),"n.a.",`
        + `IF(${g.ref("R_ALTMAN", ano)}>2.6,"segura",`
        + `IF(${g.ref("R_ALTMAN", ano)}>=1.1,"cinzenta","AFLIÇÃO")))`, {
        nota: "Cortes do próprio Altman para o Z'': acima de 2,6 zona segura, de 1,1 a 2,6 zona "
          + "cinzenta, abaixo de 1,1 zona de aflição.",
      });
    }

    // CICLO DE CAIXA — dias, a partir dos espelhos do giro.
    //
    // O denominador de cada prazo é a linha de DRE contra a qual aquela conta
    // GIRA, e é a mesma escolha que a aba de giro faz para projetar: recebível
    // gira contra receita líquida, estoque e fornecedor giram contra custo. Usar
    // receita para o fornecedor — erro comum — infla o PMP pela margem inteira.
    {
      const dias = (esp: string, base: string) =>
        `=IF(OR(${g.externa("Working Capital", gWC, esp, ano)}=0,ABS(${base})=0),"n.a.",`
        + `${g.externa("Working Capital", gWC, esp, ano)}/ABS(${base})*360)`;
      const cogs = g.externa("Working Capital", gWC, "BASE_COGS", ano);
      g.set("CC_PMR", ano, dias("ESP_CLIENTES", g.ref("REC_LIQ", ano)), { fmt: NUM2 });
      g.set("CC_PME", ano, dias("ESP_ESTOQUE", cogs), { fmt: NUM2 });
      g.set("CC_PMP", ano, dias("ESP_FORNEC", cogs), { fmt: NUM2 });
      // O ciclo só existe se as pernas existirem: somar "n.a." com número daria
      // #VALUE!, e tratar "n.a." como zero publicaria um ciclo curto por FALTA de
      // dado, que é o pior dos dois mundos.
      const num = (ch: string) => `ISNUMBER(${g.ref(ch, ano)})`;
      g.set("CC_OPER", ano,
        `=IF(AND(${num("CC_PMR")},${num("CC_PME")}),${g.ref("CC_PMR", ano)}+${g.ref("CC_PME", ano)},"n.a.")`,
        { fmt: NUM2, negrito: true });
      g.set("CC_FIN", ano,
        `=IF(AND(ISNUMBER(${g.ref("CC_OPER", ano)}),${num("CC_PMP")}),`
        + `${g.ref("CC_OPER", ano)}-${g.ref("CC_PMP", ano)},"n.a.")`, {
        fmt: NUM2, negrito: true,
        nota: "Dias entre pagar o fornecedor e receber do cliente — o giro que a empresa precisa "
          + "financiar. Ciclo que ABRE ao longo da projeção é necessidade de capital de giro "
          + "crescente, e ela aparece no fluxo como consumo de caixa.",
      });
    }

    // NECESSIDADE DE RECURSOS — leitura, não dado novo.
    //
    // O furo vem do `Cash Flow` (é ele quem sabe o que sobra antes do revolver);
    // o acumulado soma o ano anterior porque necessidade de recursos é ESTOQUE,
    // não fluxo: quem precisou de 30 no primeiro ano e 20 no segundo precisa de
    // 50 de dinheiro novo, não de 20.
    g.set("NR_FURO", ano, ext("Cash Flow", gCF, "FURO", ano), {
      fmt: NUM, negrito: true,
      nota: "O que falta para o caixa mínimo ANTES do revolver. É a necessidade de recursos do "
        + "exercício — o revolver, logo abaixo dela no fluxo, é só a suposição de que alguém a "
        + "financia.",
    });
    g.set("NR_ACUM", ano, ant === null || !g.ehProjetado(ano)
      ? `=${g.ref("NR_FURO", ano)}`
      : `=${g.ref("NR_ACUM", ant)}+${g.ref("NR_FURO", ano)}`, { fmt: NUM, negrito: true });

    // O PICO E O ANO DO PICO, repetidos em toda coluna projetada — mesmo idioma
    // das linhas de corte de covenant logo acima, que também são constantes
    // horizontais. É o par de números que responde "de quanto e para quando",
    // que é a pergunta de quem vai levantar o dinheiro.
    if (anosProjetados.length > 0) {
      g.set("NR_PICO", ano, g.ehProjetado(ano) ? `=MAX(${faixaFuro})` : null, { fmt: NUM });
      g.set("NR_ANO_PICO", ano, g.ehProjetado(ano)
        // Sem furo em ano nenhum, "ano do pico" não existe — e escrever o
        // primeiro ano por padrão seria apontar um problema onde não há.
        ? `=IF(MAX(${faixaFuro})<=0,"—",YEAR(INDEX(${faixaAnos},MATCH(MAX(${faixaFuro}),${faixaFuro},0))))`
        : null, { fmt: "0" });
    }

    // CAPACIDADE DE PAGAMENTO — o corte vem da célula azul, nunca da constante.
    g.set("NR_DIV_SUST", ano, `=${g.ref("C_ND_EBITDA", ano)}*${g.ref("EBITDA", ano)}`, {
      fmt: NUM,
      nota: "Dívida líquida que o covenant de alavancagem comporta: corte × EBITDA. Não supõe "
        + "prazo nem cronograma — é a leitura direta do próprio covenant.",
    });
    g.set("NR_DIV_EXC", ano, `=${g.ref("DV_LIQ", ano)}-${g.ref("NR_DIV_SUST", ano)}`, {
      fmt: NUM, negrito: true,
      nota: "Positivo = quanto de dívida está acima do que a geração sustenta. É o tamanho do "
        + "problema a resolver — por alongamento, deságio, capitalização ou venda de ativo.",
    });
    g.set("NR_SERV_SUP", ano,
      `=IF(${g.ref("C_COBERTURA", ano)}<>0,${g.ref("EBITDA", ano)}/${g.ref("C_COBERTURA", ano)},0)`,
      { fmt: NUM });
    g.set("NR_SERV_EXC", ano, `=${g.ref("DV_SERVICO", ano)}-${g.ref("NR_SERV_SUP", ano)}`, {
      fmt: NUM, negrito: true,
      nota: "Positivo = o serviço contratado passa do que o EBITDA paga no DSCR alvo. É o número "
        + "que dimensiona a carência ou o alongamento que o plano precisa pedir.",
    });

    // PARA ONDE VAI O CAIXA — sinais normalizados para SAÍDA POSITIVA.
    //
    // No `Cash Flow` cada linha carrega o sinal da convenção do fluxo (capex sai
    // negativo, variação de giro pode ir para os dois lados). Aqui todas viram
    // "quanto de caixa este uso consumiu", positivo, para poderem ser somadas e
    // comparadas com o EBITDA sem ninguém precisar lembrar de sinal.
    g.set("NR_USO_SERV", ano, `=${g.ref("DV_SERVICO", ano)}`, { fmt: NUM });
    g.set("NR_USO_TRIB", ano, `=-${ext("Cash Flow", gCF, "PAGO_TRIB", ano).slice(1)}`, { fmt: NUM });
    g.set("NR_USO_GIRO", ano, `=-${ext("Cash Flow", gCF, "VAR_NCG", ano).slice(1)}`, {
      fmt: NUM,
      nota: "Sinal invertido em relação ao fluxo: aqui a linha responde 'quanto de caixa o giro "
        + "CONSUMIU'. Giro que libera caixa aparece negativo, como uso negativo.",
    });
    g.set("NR_USO_CAPEX", ano, `=-${ext("Cash Flow", gCF, "CAPEX", ano).slice(1)}`, { fmt: NUM });
    g.set("NR_USO_TOTAL", ano,
      `=${g.ref("NR_USO_SERV", ano)}+${g.ref("NR_USO_TRIB", ano)}+${g.ref("NR_USO_GIRO", ano)}`
      + `+${g.ref("NR_USO_CAPEX", ano)}`, { fmt: NUM, negrito: true });
    g.set("NR_COBERTO", ano, `=${g.ref("EBITDA", ano)}-${g.ref("NR_USO_TOTAL", ano)}`, {
      fmt: NUM, negrito: true,
      nota: "Negativo significa que o EBITDA do ano não paga o que o ano exige — e a diferença "
        + "tem de vir de dinheiro novo, de venda de ativo ou de renegociação. É a mesma história "
        + "que o furo conta, dita pelo lado da origem.",
    });

    // CHECKS
    g.set("CHECK_BS", ano, ext("Balance Sheet", gBS, "CHECK", ano), { fmt: NUM2 });
    g.set("CHECK_CAIXA", ano,
      `=MIN(0,${g.ref("CF_FIM", ano)}-${g.ref("CF_MIN", ano)})`, {
      fmt: NUM2,
      nota: "Negativo significa que o revolver não cobriu o furo — ou porque o limite não foi "
        + "modelado, ou porque o cenário é insustentável. Nos dois casos é informação, não erro "
        + "a esconder.",
    });
    g.set("CHECK_EBITDA", ano, `=MIN(0,${g.ref("EBITDA", ano)})`, { fmt: NUM2 });
    g.set("CHECK_TXT", ano,
      `=IF(ABS(${g.ref("CHECK_BS", ano)})>0.5,"BALANÇO NÃO FECHA",`
      + `IF(${g.ref("CHECK_CAIXA", ano)}<0,"CAIXA ABAIXO DO MÍNIMO",`
      + `IF(${g.ref("CHECK_EBITDA", ano)}<0,"EBITDA NEGATIVO",`
      + `IF(${g.ref("T_ND_EBITDA", ano)}="ROMPE","COVENANT DE ALAVANCAGEM ROMPIDO","ok"))))`, {
      nota: "Um diagnóstico por exercício, na ordem de gravidade. É a linha que o comitê lê primeiro.",
    });
  }

  // ---- formatação condicional nos checks -----------------------------------
  //
  // O Modelo Base tem ZERO formatação condicional (medido, §17.4): o `Mismatch`
  // dele é um número que alguém precisa olhar. Aqui os checks se pintam — verde
  // quando fecham, vermelho quando não. É acréscimo nosso, e é o tipo de coisa
  // que impede um modelo aberto às pressas de passar por bom.
  const colIni = colLetra(COL_PRIMEIRO_ANO);
  const colFim = colLetra(COL_PRIMEIRO_ANO + ctx.anos.length - 1);
  for (const [chave, regra] of [
    ["CHECK_BS", `ABS(${colIni}${g.n("CHECK_BS")})>0.5`],
    ["CHECK_CAIXA", `${colIni}${g.n("CHECK_CAIXA")}<0`],
    ["CHECK_EBITDA", `${colIni}${g.n("CHECK_EBITDA")}<0`],
    ["BS_MISMATCH", `ABS(${colIni}${g.n("BS_MISMATCH")})>0.5`],
  ] as const) {
    const linha = g.n(chave);
    g.ws.addConditionalFormatting({
      ref: `${colIni}${linha}:${colFim}${linha}`,
      rules: [
        { type: "expression", formulae: [regra], style: { fill: FILL_CHECK_ERRO }, priority: 1 },
        { type: "expression", formulae: ["TRUE"], style: { fill: FILL_CHECK_OK }, priority: 2 },
      ],
    });
  }
  for (const chave of ["T_ND_EBITDA", "T_COBERTURA", "T_LIQ_CORR", "CHECK_TXT"] as const) {
    const linha = g.n(chave);
    g.ws.addConditionalFormatting({
      ref: `${colIni}${linha}:${colFim}${linha}`,
      rules: [
        { type: "containsText", operator: "containsText", text: "ROMPE", style: { fill: FILL_CHECK_ERRO }, priority: 1 },
        { type: "containsText", operator: "containsText", text: "NÃO FECHA", style: { fill: FILL_CHECK_ERRO }, priority: 2 },
        { type: "containsText", operator: "containsText", text: "ok", style: { fill: FILL_CHECK_OK }, priority: 3 },
      ],
    });
  }

  g.finalizar("__unidade");

  // ---- os 8 gráficos -------------------------------------------------------
  //
  // Mesmo número e mesma família do Modelo Base (8, todos de linha, todos nesta
  // aba). O padrão dele é "índice + corte de covenant" em quatro deles; aqui o
  // corte entra TRACEJADO, que é o que distingue no papel preto e branco uma
  // linha de projeção de uma linha de limite contratual.
  const faixa = (chave: string) =>
    `Output!$${colIni}$${g.n(chave)}:$${colFim}$${g.n(chave)}`;
  const cat = faixa("ANO_GRAF");
  const rotulo = (chave: string) => `Output!$${colLetra(COL_ROTULO)}$${g.n(chave)}`;
  const COR = { receita: "0E7490", ebitda: "1E293B", divida: "B45309", caixa: "15803D", corte: "B91C1C" };
  const alt = 15;
  // OS GRÁFICOS FICAM DENTRO DA ÁREA DE IMPRESSÃO.
  //
  // Medido no arquivo entregue: os 8 gráficos estavam ancorados nas colunas N a AE
  // e a área de impressão do `Output` é B:K — ou seja, quem imprimisse ou gerasse
  // PDF do Output (que é como o comitê recebe) não levava gráfico nenhum. Eles
  // passam a ficar ABAIXO dos números, dois por faixa, nas mesmas colunas da área
  // de impressão, e a área é estendida até o último deles.
  //
  // Âncora do OOXML é base 0: `COL_SINAL` (=2, coluna B) é o índice 1, e a última
  // coluna que a área de impressão cobre é a do último ano. Um gráfico por faixa,
  // ocupando a largura toda: dois lado a lado nesta largura sairiam com 4 colunas
  // cada, e gráfico de 4 colunas em paisagem não se lê.
  const colEsq = COL_SINAL - 1;
  const colDireita = COL_PRIMEIRO_ANO + ctx.anos.length - 2;
  const linhaBase = g.proximaLinha() + 1;
  const graficos: EspecGrafico[] = [
    { titulo: "Receita líquida e EBITDA", series: [
      { refNome: rotulo("REC_LIQ"), refCategorias: cat, refValores: faixa("REC_LIQ"), cor: COR.receita },
      { refNome: rotulo("EBITDA"), refCategorias: cat, refValores: faixa("EBITDA"), cor: COR.ebitda },
    ] },
    { titulo: "Margem EBITDA", fmtValor: "0.0%", series: [
      { refNome: rotulo("EBITDA_MG"), refCategorias: cat, refValores: faixa("EBITDA_MG"), cor: COR.ebitda },
    ] },
    { titulo: "Dívida total e dívida líquida", series: [
      { refNome: rotulo("DV_TOTAL"), refCategorias: cat, refValores: faixa("DV_TOTAL"), cor: COR.divida },
      { refNome: rotulo("DV_LIQ"), refCategorias: cat, refValores: faixa("DV_LIQ"), cor: COR.ebitda },
    ] },
    { titulo: "Net Debt / EBITDA vs covenant", fmtValor: '0.0"x"', series: [
      { refNome: rotulo("R_ND_EBITDA"), refCategorias: cat, refValores: faixa("R_ND_EBITDA"), cor: COR.divida },
      { refNome: rotulo("C_ND_EBITDA"), refCategorias: cat, refValores: faixa("C_ND_EBITDA"), cor: COR.corte, tracejada: true },
    ] },
    { titulo: "Cobertura do serviço da dívida vs covenant", fmtValor: '0.0"x"', series: [
      { refNome: rotulo("R_COBERTURA"), refCategorias: cat, refValores: faixa("R_COBERTURA"), cor: COR.caixa },
      { refNome: rotulo("C_COBERTURA"), refCategorias: cat, refValores: faixa("C_COBERTURA"), cor: COR.corte, tracejada: true },
    ] },
    { titulo: "Fluxo de caixa livre", series: [
      { refNome: rotulo("FCL"), refCategorias: cat, refValores: faixa("FCL"), cor: COR.caixa },
    ] },
    { titulo: "Caixa de fechamento vs caixa mínimo", series: [
      { refNome: rotulo("CF_FIM"), refCategorias: cat, refValores: faixa("CF_FIM"), cor: COR.caixa },
      { refNome: rotulo("CF_MIN"), refCategorias: cat, refValores: faixa("CF_MIN"), cor: COR.corte, tracejada: true },
    ] },
    { titulo: "Liquidez corrente vs covenant", fmtValor: '0.0"x"', series: [
      { refNome: rotulo("R_LIQ_CORR"), refCategorias: cat, refValores: faixa("R_LIQ_CORR"), cor: COR.receita },
      { refNome: rotulo("C_LIQ_CORR"), refCategorias: cat, refValores: faixa("C_LIQ_CORR"), cor: COR.corte, tracejada: true },
    ] },
  ].map((espec, i) => ({
    aba: "Output",
    titulo: espec.titulo,
    fmtValor: espec.fmtValor,
    series: espec.series,
    // Um por faixa, ABAIXO dos números e dentro das colunas que imprimem.
    de: { col: colEsq, linha: linhaBase + i * (alt + 1) },
    ate: { col: colDireita, linha: linhaBase + i * (alt + 1) + alt },
  }));

  // A área de impressão passa a cobrir os gráficos. Sem isto o `finalizar()` acima
  // já fixou `B1:<último ano><última linha de dado>` e o papel sai sem eles.
  const ultimaLinhaGrafico = graficos.reduce((m, esp) => Math.max(m, esp.ate.linha + 1), 0);
  g.estenderImpressao(ultimaLinhaGrafico);

  return { g, graficos };
}

// =============================================================================
// ABA Considerações — as premissas-chave e as divergências de método, na frente.
// Também é onde mora o haircut do Stress ($F$8), lido por várias abas.
// =============================================================================
function abaConsideracoes(wb: ExcelJS.Workbook, ctx: Ctx): void {
  const ws = wb.addWorksheet("Considerações");
  ws.getColumn(2).width = 34;
  ws.getColumn(3).width = 60;
  ws.getColumn(6).width = 12;
  const put = (r: number, c: number, v: ExcelJS.CellValue, font?: Partial<ExcelJS.Font>) => {
    const cell = ws.getRow(r).getCell(c);
    cell.value = v;
    if (font) cell.font = font;
    return cell;
  };
  put(2, 2, "CONSIDERAÇÕES E PREMISSAS-CHAVE", { bold: true, size: 14 });
  put(3, 2, `${ctx.ent.caso.nome} — ${ctx.ent.entidade ?? "(entidade não definida)"}`, { size: 11 });
  put(4, 2, `Gerado em ${ctx.ent.agora.toLocaleString("pt-BR")} · setor: ${ctx.ent.setor ?? "(não definido)"}`,
    { size: 9, italic: true });

  put(6, 2, "CENÁRIOS", { bold: true });
  put(7, 2, "Cenário ativo");
  const c = ws.getRow(7).getCell(3);
  c.value = { formula: `CHOOSE(Output!$G$2,"${CENARIOS[0]}","${CENARIOS[1]}","${CENARIOS[2]}")` };
  c.font = { bold: true };
  put(8, 2, "Haircut do Stress Case");
  const cellStress = ws.getRow(8).getCell(6);
  cellStress.value = ctx.ent.stressPct;
  cellStress.numFmt = PCT;
  cellStress.fill = FILL_INPUT;
  cellStress.note = comoNota(
    "A única célula que define o Stress Case. Ela piora receita (crescimento menor), custo "
    + "(percentual maior), giro (ativo mais lento, passivo mais rápido) e capex (corte).",
  );
  put(8, 3, "piora cada linha no sentido que a torna pior — não é o mesmo ajuste em todas");

  put(10, 2, "PREMISSAS DO MANDATO", { bold: true });
  let r = 11;
  put(r, 2, "Alíquota de tributos"); ws.getRow(r).getCell(6).value = ctx.ent.aliquotaTributos;
  ws.getRow(r).getCell(6).numFmt = PCT; r++;
  put(r, 2, "Caixa mínimo operacional"); ws.getRow(r).getCell(6).value = ctx.ent.caixaMinimo;
  ws.getRow(r).getCell(6).numFmt = NUM; r++;
  put(r, 2, "Exercícios realizados"); put(r, 3, ctx.hist.join(", ") || "(nenhum)"); r++;
  put(r, 2, "Exercícios projetados"); put(r, 3, ctx.proj.join(", ") || "(nenhum)"); r++;
  put(r, 2, "Premissas ativas no caso"); put(r, 3, String(ctx.ent.premissas.length)); r++;
  put(r, 2, "Contas com premissa vinculada"); put(r, 3, String(ctx.premissaPorLinha.size)); r += 2;

  put(r, 2, "MÉTODO — DIVERGÊNCIAS DECLARADAS", { bold: true }); r++;
  for (const texto of [
    NOTA_CIRCULARIDADE,
    "Conta sem premissa vinculada fica CONSTANTE na projeção, e aparece na conferência do portal.",
    "Subtotal não tem premissa própria: é sempre a soma dos componentes projetados.",
    "Tributo incide apenas sobre lucro POSITIVO. Compensação de prejuízo fiscal é decisão "
    + "tributária e não subproduto de fórmula.",
    "Histórico não é digitado: vem da extração, com a proveniência de cada célula em nota.",
    "Depreciação: linear sobre o saldo de abertura, mais meia safra do capex do ano.",
  ]) {
    const cell = put(r, 2, texto);
    ws.mergeCells(r, 2, r, 8);
    cell.alignment = { wrapText: true, vertical: "top" };
    ws.getRow(r).height = 30;
    r++;
  }

  // ---- A MATRIZ DE CENÁRIOS DA REFERÊNCIA ----------------------------------
  //
  // A `Considerações` do Modelo Base é uma matriz 3×4 — três cenários nas linhas,
  // quatro premissas-chave nas colunas (Crescimento, Margem Ebitda, Investimento,
  // Capital de giro) — com as células de texto em BRANCO e altura de 77 pontos
  // para o analista escrever a justificativa de cada uma. É a única aba do
  // arquivo dele feita para receber texto humano, e o nosso export não a tinha.
  //
  // Aqui ela existe com a mesma anatomia, e cada célula já vem com o que o
  // sistema SABE (a premissa vinculada, o valor, a origem) — o analista completa
  // o porquê. Célula em branco num entregável institucional é convite a esquecer;
  // célula com o fato e sem a justificativa é um pedido explícito.
  r += 1;
  put(r, 2, "MATRIZ DE CENÁRIOS — a justificativa de cada premissa", { bold: true, size: 12 });
  r += 1;
  const COLUNAS_MATRIZ = ["Crescimento", "Margem EBITDA", "Investimento (Capex)", "Capital de giro"];
  const rCab = r;
  put(rCab, 2, "Cenários", { bold: true, color: { argb: ORIA.branco } }).fill = FILL_SECAO;
  COLUNAS_MATRIZ.forEach((nome, i) => {
    const c = put(rCab, 3 + i, nome, { bold: true, color: { argb: ORIA.branco } });
    c.fill = FILL_SECAO;
    c.alignment = { horizontal: "center", wrapText: true };
    ws.getColumn(3 + i).width = 30;
  });
  r += 1;
  const premissasPorFormula = (formula: string) => ctx.ent.premissas
    .filter((p) => p.formula === formula)
    .map((p) => `${p.nome} (${p.origem ?? "digitado"})`);
  const fatoConhecido = [
    premissasPorFormula("crescimento_composto").concat(premissasPorFormula("indice_macro")),
    premissasPorFormula("pct_de_linha"),
    ctx.ent.premissas.filter((p) => /capex|investimento/i.test(p.nome)).map((p) => p.nome),
    premissasPorFormula("dias_de_giro"),
  ];
  for (let i = 0; i < CENARIOS.length; i++) {
    const rLinha = r + i;
    const cCen = put(rLinha, 2, CENARIOS[i], { bold: true });
    cCen.alignment = { vertical: "top" };
    cCen.fill = FILL_SUBTOTAL;
    for (let j = 0; j < COLUNAS_MATRIZ.length; j++) {
      const c = ws.getRow(rLinha).getCell(3 + j);
      const fatos = fatoConhecido[j];
      c.value = i === 0
        ? (fatos.length > 0
          ? `Premissas ativas: ${fatos.join("; ")}.\n\n(justificar aqui)`
          : "(nenhuma premissa ativa nesta família — justificar aqui)")
        : i === 1
          ? "Espelha o Base Case salvo onde o cliente divergir — anotar aqui a divergência."
          : `Haircut de ${(ctx.ent.stressPct * 100).toFixed(0)}% aplicado com o sinal correto em cada `
            + "linha (receita piora, custo piora, giro piora, capex é cortado) — justificar o nível aqui.";
      c.alignment = { wrapText: true, vertical: "top" };
      c.font = fonte({ size: 9 });
      c.border = { top: { style: "hair" }, bottom: { style: "hair" }, left: { style: "hair" }, right: { style: "hair" } };
    }
    ws.getRow(rLinha).height = 66;
  }
  r += CENARIOS.length + 1;

  // ---- a legenda das cores, que é o manual de leitura do arquivo ------------
  put(r, 2, "GRAMÁTICA DE CORES", { bold: true }); r += 1;
  for (const item of LEGENDA_CORES) {
    const c = put(r, 2, item.texto, { color: { argb: item.cor }, bold: item.fundo !== undefined });
    if (item.fundo) c.fill = preencherArgb(item.fundo);
    ws.mergeCells(r, 2, r, 6);
    r += 1;
  }

  ws.views = [{ state: "frozen", ySplit: 5, showGridLines: false }];
  ws.pageSetup = { orientation: "landscape", fitToPage: true, fitToWidth: 1, fitToHeight: 0, printArea: `B1:H${r}` };
}

function abaCapa(wb: ExcelJS.Workbook, ctx: Ctx): void {
  const ws = wb.addWorksheet("Capa");
  // A CAPA É A CARA DA ORIA NO ENTREGÁVEL. O Modelo Base tem duas células de
  // texto (`Unimed Rio` e `Projeções Financeiras`) e nada mais — funciona como
  // capa de papel de trabalho, não como capa de documento que vai a comitê ou a
  // credor. Aqui ela é composta: faixa institucional, entidade, produto do
  // mandato, cenário ATIVO por fórmula (não texto congelado) e a legenda das
  // cores, que é o que permite ler o resto do arquivo sem manual.
  ws.getColumn(2).width = 3;
  ws.getColumn(3).width = 92;
  ws.views = [{ showGridLines: false }];

  const faixa = (r: number, altura: number) => {
    ws.getRow(r).height = altura;
    for (let c = 2; c <= 9; c++) ws.getRow(r).getCell(c).fill = FILL_SECAO;
  };
  faixa(2, 6);
  faixa(3, 34);
  const titulo = ws.getRow(3).getCell(3);
  titulo.value = "ORIA PARTNERS";
  titulo.font = fonte({ bold: true, size: 16, color: { argb: ORIA.branco } });
  titulo.alignment = { vertical: "middle" };
  faixa(4, 6);

  const linhaTexto = (r: number, valor: ExcelJS.CellValue, f: Partial<ExcelJS.Font>, altura?: number) => {
    const c = ws.getRow(r).getCell(3);
    c.value = valor;
    c.font = fonte(f);
    if (altura) ws.getRow(r).height = altura;
    return c;
  };

  linhaTexto(6, ctx.ent.entidade ?? ctx.ent.caso.nome, { bold: true, size: TAM_CAPA_TITULO }, 34);
  linhaTexto(7, "Modelo financeiro institucional — projeções", { size: 13, color: { argb: ORIA.acento } });
  linhaTexto(9, `${ctx.ent.caso.nome} · ${ctx.ent.caso.produto}`, { size: 11 });
  linhaTexto(10, `Setor: ${ctx.ent.setor ?? "(não definido)"}`, { size: 10, color: { argb: FONTE_COR.auxiliar } });
  linhaTexto(11,
    `Exercícios realizados: ${ctx.hist.join(", ") || "(nenhum)"} · projetados: ${ctx.proj.join(", ") || "(nenhum)"}`,
    { size: 10, color: { argb: FONTE_COR.auxiliar } });
  linhaTexto(12, `Gerado em ${ctx.ent.agora.toLocaleDateString("pt-BR")}`,
    { size: 10, italic: true, color: { argb: FONTE_COR.auxiliar } });

  // O cenário ativo na CAPA, por fórmula. Numa capa de texto congelado, o
  // arquivo circula dizendo "Base Case" com o dial em Stress — e ninguém percebe.
  linhaTexto(14, "Cenário ativo", { bold: true });
  const cen = ws.getRow(15).getCell(3);
  cen.value = { formula: `CHOOSE(Output!$G$2,"${CENARIOS[0]}","${CENARIOS[1]}","${CENARIOS[2]}")` };
  cen.font = fonte({ bold: true, size: 13, color: { argb: ORIA.acento } });
  cen.note = comoNota(
    "Lido do interruptor único (`Output!$G$2`) por fórmula. Capa com cenário escrito à mão circula "
    + "dizendo 'Base Case' com o modelo em 'Stress' — e o leitor não tem como saber.",
  );

  linhaTexto(17, "COMO LER ESTE ARQUIVO", { bold: true });
  let r = 18;
  for (const item of LEGENDA_CORES) {
    const c = ws.getRow(r).getCell(3);
    c.value = item.texto;
    c.font = fonte({ color: { argb: item.cor }, bold: item.fundo !== undefined });
    if (item.fundo) c.fill = preencherArgb(item.fundo);
    r++;
  }
  r++;
  for (const texto of [
    "As 14 primeiras abas são o MODELO (projeção). As demais são a PROVENIÊNCIA: o dado extraído "
    + "linha a linha, com o documento de origem — é o que permite auditar qualquer número daqui.",
    "Toda projeção é FÓRMULA. Mudar uma premissa (célula azul) move o modelo inteiro; nenhum número "
    + "projetado foi calculado fora do arquivo.",
    "O calendário sai de UMA célula — o último exercício realizado, na aba 'Revenues, COGS & SG&A'.",
    "A aba 'Considerações' declara as divergências de método. Ler antes de usar qualquer número.",
  ]) {
    const c = ws.getRow(r).getCell(3);
    c.value = texto;
    c.font = fonte({ size: 9, color: { argb: FONTE_COR.auxiliar } });
    c.alignment = { wrapText: true, vertical: "top" };
    ws.getRow(r).height = 26;
    r++;
  }
  linhaTexto(r + 1, "Documento de trabalho — Oria Partners. Circulação restrita.",
    { size: 9, italic: true, color: { argb: FONTE_COR.auxiliar } });
  ws.pageSetup = { orientation: "portrait", fitToPage: true, fitToWidth: 1, fitToHeight: 1, printArea: `B1:I${r + 1}` };
}

// =============================================================================
// Ponto de entrada
// =============================================================================
export function construirModeloInstitucional(
  workbook: ExcelJS.Workbook,
  ent: EntradaModeloInstitucional,
): EspecGrafico[] {
  if (ent.anosProjetados.length === 0) {
    throw new Error("construirModeloInstitucional: sem anos projetados — nada a modelar.");
  }
  // SEM SÉRIE HISTÓRICA NÃO HÁ DE ONDE PROJETAR, e a recusa precisa acontecer AQUI.
  //
  // Achado rodando o arnês de variações, na variante em que a extração devolve o
  // TEXTO do valor e não o número (`valor_num` nulo, `valor_texto` preenchido) —
  // caso corriqueiro de leitura de PDF ruim. Sem número, `fn_valores_por_ano` não
  // devolve ano nenhum, `anosHistoricos` chega vazio, `ultimoHist` cai para
  // `proj[0] - 1` (um ano FORA do eixo) e `anoAnterior` da primeira coluna
  // projetada é `null`. O arquivo morria 300 linhas adiante com
  // `modelo-institucional: ano null fora do horizonte` — erro de programador na
  // cara do analista, e nenhum export saía.
  //
  // Recusar aqui, com o motivo, é o que o resto deste arquivo faz o tempo todo:
  // "EBITDA<=0", "PL<=0", "sem lucros retidos", "PC=0". O chamador decide o que
  // fazer com a recusa; o que ele não pode é receber um erro que não explica nada.
  if (ent.anosHistoricos.length === 0) {
    throw new Error(
      "construirModeloInstitucional: nenhum exercício com valor NUMÉRICO. O modelo projeta a partir "
      + "do realizado, e não há realizado — as linhas extraídas chegaram sem `valor_num` (texto que "
      + "não virou número, ou coluna que a extração não leu). Não é caso de projetar: é caso de "
      + "voltar à extração.",
    );
  }
  const ctx = contexto(ent);

  // Ordem de construção = ordem de dependência das fórmulas. Cada `Grade` só pode
  // ser referenciada depois de existir, e é isso que impede uma referência a uma
  // linha que ainda não foi ancorada.
  const gAnual = abaAnual(workbook, ctx);
  const gPrem = abaPremissas(workbook, ctx);
  const gRec = abaReceita(workbook, ctx, gPrem, gAnual);
  const gDiv = abaDivida(workbook, ctx, gAnual, gRec);
  const gFA = abaImobilizado(workbook, ctx, gRec);
  const gWC = abaCapitalGiro(workbook, ctx, gRec);
  // A aba de tributos nasce ANTES do fluxo e do balanço porque agora os dois LEEM dela
  // (passivo tributário e pagamento do período). Ela só depende da receita, então subir
  // na ordem não custa nada — e a ordem das abas no arquivo é decidida no fim, por
  // `orderNo`, não por quem foi criado primeiro.
  const gTrib = abaTributos(workbook, ctx, gRec);
  const gDRE = abaDRE(workbook, ctx, gRec, gPrem, gDiv);
  const gCF = abaFluxo(workbook, ctx, gDRE, gWC, gFA, gDiv, gRec, gTrib);
  const gBS = abaBalanco(workbook, ctx, gCF, gWC, gFA, gDiv, gDRE, gRec, gTrib);
  const gGW = abaGoodwill(workbook, ctx, gDRE, gCF, gRec);
  const saidaOutput = abaOutput(workbook, ctx, gDRE, gBS, gDiv, gCF, gFA, gWC, gRec, gGW, gTrib);
  abaConsideracoes(workbook, ctx);
  abaCapa(workbook, ctx);

  // ---- Costura de volta: o que só se sabe depois de o fluxo existir ---------
  // O revolver é DECIDIDO no fluxo (é lá que o furo aparece) e CONTABILIZADO na
  // dívida. A alternativa seria calcular o furo duas vezes, em duas abas, com
  // duas fórmulas que divergiriam na primeira mudança.
  for (const ano of ctx.proj) {
    gDiv.set("REVOLVER_SAQUE", ano, `=${Grade.refExterna("Cash Flow", gCF.letraDoAno(ano), gCF.n("REVOLVER"))}`, {
      fmt: NUM,
      nota: "Decidido na aba Cash Flow, onde o furo de caixa é conhecido. Uma conta, um lugar.",
    });
    // A APLICAÇÃO É O EXCEDENTE DO CAIXA AO CAIXA MÍNIMO — decomposição, não
    // ativo adicional. O caixa operacional mínimo fica em conta movimento e não
    // rende; só o que passa dele é aplicado. Publicar isto como conta de balanço
    // somaria o mesmo dinheiro duas vezes, que é o defeito que esta rodada
    // corrigiu no giro.
    gDiv.set("ST_FIM", ano,
      `=MAX(0,${Grade.refExterna("Cash Flow", gCF.letraDoAno(ano), gCF.n("CAIXA_FIM"))}-${gDiv.ref("CAIXA_MIN", ano)})`, {
      fmt: NUM, negrito: true,
      nota: "PARTE do caixa, não um ativo a mais: é o excedente ao caixa mínimo. O `Balance Sheet` "
        + "carrega o caixa TOTAL numa linha só; esta aqui existe para o rendimento incidir apenas "
        + "sobre o que de fato é aplicado.",
    });
  }
  for (const ano of ctx.hist) {
    gDiv.set("REVOLVER_SAQUE", ano, 0, { fmt: NUM, tipo: "calc" });
    gDiv.set("ST_FIM", ano,
      `=MAX(0,${Grade.refExterna("Cash Flow", gCF.letraDoAno(ano), gCF.n("CAIXA_FIM"))}-${gDiv.ref("CAIXA_MIN", ano)})`,
      { fmt: NUM });
  }

  // O EBITDA DA ABA DE RECEITA ESTAVA DECLARADO E VAZIO — rótulo "EBITDA" com
  // todas as colunas em branco, que é exatamente o que a linha `DEPRECIACAO`
  // logo abaixo já foi antes de alguém notar. Duas linhas declaradas e nunca
  // preenchidas, na mesma aba, pelo mesmo motivo: ambas dependem de uma aba
  // construída depois desta.
  //
  // Ele é ESPELHO do Income Statement e não um segundo cálculo. Naquela aba o
  // EBITDA carrega, no realizado, a reconciliação com o número que o documento
  // informou (`escreverReconc`); recomputá-lo aqui daria duas respostas para "qual
  // foi o EBITDA de 2025", que é a família de defeito que a convenção "o total da
  // seção é o que o documento informou" existe para matar. Na PROJEÇÃO as duas
  // contas coincidem — e é isso que faz a sombra por cenário (que soma a cascata
  // desta aba) poder ser comparada com este número sem ressalva.
  for (const ano of ctx.anos) {
    gRec.set("EBITDA", ano,
      `=${Grade.refExterna("Income Statement", gDRE.letraDoAno(ano), gDRE.n("EBITDA"))}`, {
      fmt: NUM, negrito: true,
      nota: "Espelho do EBITDA da aba Income Statement, que é onde ele é calculado e onde, no "
        + "realizado, ele reconcilia com o valor informado no documento. Uma segunda conta aqui "
        + "daria duas respostas para a mesma pergunta.",
    });
    gRec.set("EBITDA_MARGEM", ano,
      `=IF(${gRec.ref("RECEITA_LIQUIDA", ano)}<>0,`
      + `${gRec.ref("EBITDA", ano)}/${gRec.ref("RECEITA_LIQUIDA", ano)},0)`,
      { fmt: PCT });
  }

  // A DEPRECIAÇÃO CHEGANDO À DRE — o defeito que esta rodada encontrou no NOSSO
  // lado, e o mais grave dos dois.
  //
  // A linha `Revenues, COGS & SG&A!DEPRECIACAO` era DECLARADA e nunca preenchida.
  // Consequência medida: `Income Statement!EBITDA` somava uma célula vazia (então
  // EBITDA = EBIT, exatamente o erro que o comentário do EBITDA alerta), `D&A`
  // saía ZERO em todos os anos mesmo com `Fixed Assets & CAPEX` calculando
  // depreciação, e o `Cash Flow` somava de volta uma depreciação que a DRE nunca
  // tinha subtraído — o que infla o lucro E o caixa, e abre o balanço.
  // Ela é preenchida aqui, e não na `abaReceita`, porque a aba de imobilizado é
  // construída depois — é a mesma costura de volta do revolver.
  // NO REALIZADO A DEPRECIAÇÃO TAMBÉM CHEGA — e o comentário que dizia o contrário
  // estava errado sobre a aritmética.
  //
  // Ela sai ZERO na aba de imobilizado no realizado (correto: lá ela é projetada), e
  // por isso a linha da DRE ficava zero no histórico. O efeito medido no arquivo
  // entregue: `EBITDA = EBIT` em 2024 e 2025 — exatamente o erro que o comentário do
  // EBITDA alerta — apesar de a DRE extraída trazer "Depreciação industrial" de
  // −5.180 e −5.540 DENTRO do custo, e da depreciação acumulada do balanço andar
  // 5.500 entre os dois exercícios.
  //
  // NÃO É DUPLA CONTAGEM: `EBITDA = LUCRO BRUTO − SG&A + D&A` SOMA a depreciação de
  // volta justamente para desfazer o abatimento que já está dentro do custo, e
  // `EBIT = EBITDA − D&A` a subtrai outra vez. O EBIT continua idêntico (e continua
  // batendo com o documento, o que a nova conferência prova); o que muda é que o
  // EBITDA realizado deixa de ser EBIT com outro nome — e é dele que sai toda
  // alavancagem que o comitê olha.
  const depreciacaoHistorica = [
    ...(ctx.linhasPorBloco.get("custo") ?? []),
    ...(ctx.linhasPorBloco.get("sga") ?? []),
  ].filter((l) => /deprecia|amortiza|exaust/i.test(l.chave));
  for (const ano of ctx.anos) {
    const hist = ctx.hist.includes(ano);
    if (hist && depreciacaoHistorica.length > 0) {
      const termos = depreciacaoHistorica.map((l) => {
        const bloco: BlocoModelo = (ctx.linhasPorBloco.get("custo") ?? []).includes(l) ? "custo" : "sga";
        return Grade.refExterna("Premissas", gPrem.letraDoAno(ano), gPrem.n(chaveLinha(bloco, l)));
      });
      gRec.set("DEPRECIACAO", ano, `=${termos.join("+")}`, {
        fmt: NUM,
        nota: "Depreciação REALIZADA, somada das linhas de custo e despesa que a extração trouxe "
          + `(${depreciacaoHistorica.map((l) => l.chave).join(" · ")}). Ela é somada de volta no `
          + "EBITDA para desfazer o abatimento que já está dentro do custo, e subtraída outra vez no "
          + "EBIT — que continua igual ao do documento.",
      });
      continue;
    }
    gRec.set("DEPRECIACAO", ano,
      `=${Grade.refExterna("Fixed Assets & CAPEX", gFA.letraDoAno(ano), gFA.n("ESP_DEPREC"))}`, {
      fmt: NUM,
      nota: hist
        ? "A DRE extraída deste exercício não traz linha de depreciação dentro de custo ou despesa: "
          + "zero, e o EBITDA realizado fica igual ao EBIT. Não é defeito do modelo, é o que o "
          + "documento informa — e está dito aqui para não parecer defeito."
        : "Depreciação do período, do espelho da aba Fixed Assets & CAPEX.",
    });
  }

  // ---- O CHECK DO BALANÇO NO TOPO DOS DRIVERS (§5.3) -----------------------
  //
  // A linha existe nas quatro abas de driver desde a construção; aqui ela recebe a
  // fórmula, porque só agora o `Balance Sheet` existe. Mesma costura do revolver e
  // da depreciação — e mesma razão: a dependência aponta do driver PARA a
  // demonstração, nunca ao contrário.
  for (const gDriver of [gRec, gWC, gFA, gDiv]) {
    if (!gDriver.tem("CHECK_MODELO")) continue;
    const colIni = colLetra(COL_PRIMEIRO_ANO);
    const colFim = colLetra(COL_PRIMEIRO_ANO + ctx.anos.length - 1);
    for (const ano of ctx.anos) {
      gDriver.set("CHECK_MODELO", ano,
        `=${Grade.refExterna("Balance Sheet", gBS.letraDoAno(ano), gBS.n("CHECK"))}`, {
        fmt: NUM2,
        nota: "Ativo − (Passivo + PL) do `Balance Sheet`, repetido aqui porque é NESTA aba que a "
          + "premissa é mexida. Diferente de zero quer dizer que a mudança que você acabou de "
          + "fazer abriu o balanço — e o lugar de descobrir isso é aqui, não duas abas adiante.",
      });
    }
    const linha = gDriver.n("CHECK_MODELO");
    gDriver.ws.addConditionalFormatting({
      ref: `${colIni}${linha}:${colFim}${linha}`,
      rules: [
        { type: "expression", formulae: [`ABS(${colIni}${linha})>0.5`], style: { fill: FILL_CHECK_ERRO }, priority: 1 },
        { type: "expression", formulae: ["TRUE"], style: { fill: FILL_CHECK_OK }, priority: 2 },
      ],
    });
  }

  // ---- COCKPIT da aba `Premissas`: endereço e valor VIVO de cada alavanca ---
  //
  // Preenchido aqui pelo mesmo motivo do `CHECK`: as linhas foram reservadas na
  // construção da `Premissas` (segunda aba a nascer) e só agora as abas de origem
  // existem para dizer em que LINHA cada premissa caiu. Endereço escrito à mão
  // envelheceria na primeira linha inserida; este é derivado da âncora.
  {
    const grades = new Map<string, Grade>([
      ["Revenues, COGS & SG&A", gRec], ["ST Inv. & Debt", gDiv],
      ["Fixed Assets & CAPEX", gFA], ["Output", saidaOutput.g],
    ]);
    const anoBase = ctx.proj[0] ?? ctx.ultimoHist;
    for (const b of botoesDoModelo(ctx)) {
      if (!gPrem.tem(b.chave)) continue;
      const origem = grades.get(b.aba);
      // SUFIXOS `#…` SÃO POR TRANCHE: o cockpit aponta para a primeira e diz
      // quantas são, porque uma linha por tranche transformaria o painel na
      // própria aba de dívida. `#prazo` (prazo), `#amort` (a chave "Efeito
      // caixa?", que mora na mesma linha da amortização) e `#classe`
      // (Equity/Haircut) são os três hoje.
      const ehPorTranche = b.alvo.startsWith("#");
      const alvo = ehPorTranche
        ? origem?.chaves().find((k) => k.endsWith(b.alvo))
        : b.alvo;
      const nTranches = ehPorTranche
        ? (origem?.chaves().filter((k) => k.endsWith(b.alvo)).length ?? 0)
        : 0;
      const rotuloCel = gPrem.ws.getRow(gPrem.n(b.chave)).getCell(COL_ROTULO);
      if (!origem || !alvo || !origem.tem(alvo)) {
        // AUSÊNCIA DECLARADA, nunca linha em branco: "não se aplica" é informação
        // (o caso não tem tranche de dívida, não tem premissa de crescimento), e
        // célula vazia é indistinguível de defeito do gerador.
        gPrem.ws.getRow(gPrem.n(b.chave)).getCell(COL_NOTA).value = "não se aplica";
        rotuloCel.note = comoNota(
          `${b.rotulo} — este caso não tem essa alavanca: ${b.efeito}. A linha fica visível de `
          + "propósito, para a ausência ser lida como ausência e não como esquecimento.",
        );
        continue;
      }
      const linhaAlvo = origem.n(alvo);
      const col = b.naNota ? colLetra(COL_NOTA) : origem.letraDoAno(anoBase);
      gPrem.ws.getRow(gPrem.n(b.chave)).getCell(COL_NOTA).value =
        `${b.aba}!${col}${linhaAlvo}${nTranches > 1 ? ` (+${nTranches - 1})` : ""}`;
      rotuloCel.note = comoNota(
        `${b.efeito}.\n\nEdite em ${b.aba}, célula ${col}${linhaAlvo}`
        + (nTranches > 1 ? ` — e nas outras ${nTranches - 1} tranches, uma célula cada.` : ".")
        + "\n\nO valor mostrado aqui é REFERÊNCIA à célula de origem: muda junto, não é cópia.",
      );
      // O valor: a série inteira quando a premissa é por ano, e a célula única
      // quando é um dropdown (que não tem série).
      if (b.naNota) {
        // Referência ABSOLUTA e sem formato numérico: a célula do dropdown guarda
        // TEXTO ("IPCA", "(nenhum)"), e um `0,00%` em cima de texto mostraria a
        // premissa como se fosse um número.
        gPrem.set(b.chave, anoBase, `='${b.aba.replace(/'/g, "''")}'!$${col}$${linhaAlvo}`, {});
      } else {
        for (const ano of ctx.anos) {
          if (!origem.anos.includes(ano)) continue;
          // SÓ ESPELHA CÉLULA QUE EXISTE. Referência a célula vazia mostra ZERO no
          // Excel, e zero numa linha de prazo ou de spread é uma afirmação — "o prazo
          // é zero" — quando o fato é "esta premissa não vale para o exercício
          // realizado". O mesmo princípio do item de conteúdo do auditor.
          if (origem.ws.getRow(linhaAlvo).getCell(origem.colDoAno(ano)).value == null) continue;
          gPrem.set(b.chave, ano,
            `=${Grade.refExterna(b.aba, origem.letraDoAno(ano), linhaAlvo)}`, { fmt: b.fmt });
        }
      }
    }
  }

  // ---- Ordem das abas ------------------------------------------------------
  // `workbook.worksheets` é um GETTER que devolve cópia ORDENADA: mexer no array
  // devolvido não faz nada (defeito real, sessão 12 — o assert acusou
  // `modelagem=9` depois de um `splice` que não splicou). Quem manda é `orderNo`.
  //
  // E a ordem tem de ser atribuída a TODAS as abas, não só às do modelo: numerar
  // só estas 14 deixa as abas de dado com o `orderNo` default e o Excel intercala
  // as duas famílias (medido: "Modelagem · Considerações · Resumo · Capa · Dados
  // · Output · Balanço · Revenues…"). Um modelo institucional intercalado com as
  // abas de conferência é um arquivo que ninguém navega.
  const ORDEM_MODELO = new Map(ABAS_MODELO.map((n, i) => [n as string, i + 1]));
  let proximoOutro = 100;
  for (const ws of workbook.worksheets) {
    const alvo = ws.name === "Modelagem"
      // A aba `Modelagem` agregada (Fase 7) continua sendo a primeira: é a que o
      // dono já valida ao vivo, e é dela que o modelo institucional é comparado.
      ? 0
      : ORDEM_MODELO.get(ws.name) ?? proximoOutro++;
    (ws as unknown as { orderNo: number }).orderNo = alvo;
  }

  // Recalcular ao abrir: o arquivo sai com fórmula e sem valor em cache, então sem
  // isto o Excel mostra célula vazia até alguém apertar F9.
  workbook.calcProperties = { fullCalcOnLoad: true };

  // Os gráficos NÃO podem ser escritos pelo ExcelJS (ele não tem API de gráfico,
  // conferido no runtime da versão do lock). A especificação sai daqui e é
  // injetada no .xlsx já gerado por `injetarGraficosNoBuffer`, no mesmo
  // pós-processamento que já amplia a caixa das notas.
  return saidaOutput.graficos;
}
