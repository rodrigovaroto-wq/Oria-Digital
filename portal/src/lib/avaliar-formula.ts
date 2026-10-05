/**
 * Avaliador das fórmulas que o export emite, para os scripts de verificação
 * conferirem os NÚMEROS sem abrir o Excel.
 *
 * POR QUE ELE CRESCEU (sessão 21). Até a Etapa 2 ele cobria o que as abas de
 * demonstração usam: referências, `SUM`, aritmética e `IFERROR`. Isso bastava
 * porque a Modelagem era conferida por ESTRUTURA (o texto da fórmula), nunca
 * por valor. A Etapa 6 pede o contrário — "todas as fórmulas funcionando",
 * "validar um caso real do início ao fim" — e para isso é preciso RESOLVER o
 * modelo: as conferências dele têm de fechar em zero, e um `#VALUE!` ou um
 * `#N/A` no meio do caminho tem de aparecer.
 *
 * A alternativa seria recalcular com o LibreOffice. MEDIDO neste container: ele
 * se recusa a abrir até um .xlsx mínimo de três células gerado pelo openpyxl —
 * e recusa igualmente o arquivo v35 que o dono abriu no Excel sem problema.
 * É o ambiente, não os arquivos; mas significa que não há motor externo aqui.
 *
 * O QUE ELE COBRE, que é exatamente o que `buildExportWorkbook` gera:
 *   referências absolutas e mistas (`$C$4`, `BO$8`), `:` em intervalos,
 *   `+ - * / ^`, `&`, comparações, `IF`, `IFERROR`, `SUM`, `PRODUCT`, `MAX`,
 *   `MIN`, `ROUND`, `N`, `ISNUMBER`, `INDEX` (1-D e 2-D) e `MATCH` exato.
 *
 * O QUE ELE NÃO COBRE continua devolvendo `null` — "não sei avaliar". É melhor
 * um teste dizer "não sei" do que afirmar 0 e passar verde por engano; quem
 * chama tem de tratar `null` como desconhecido, nunca como zero.
 *
 * LIMITES CONHECIDOS E DELIBERADOS:
 *   • Referência ENTRE ABAS é seguida (`'Balance Sheet'!J42`) — foi acrescentada
 *     quando o modelo institucional passou a ser conferido por VALOR, e sem ela
 *     nenhuma fórmula dele era avaliável. O comentário anterior dizia o oposto e
 *     estava desatualizado.
 *   • Célula VAZIA é devolvida como 0 (ver o comentário em `avaliarCelula`), e
 *     por isso a comparação `x=""` trata 0 e vazio do mesmo jeito. No Excel são
 *     coisas diferentes: vazio="" é VERDADEIRO, mas 0="" é FALSO. Para tudo que
 *     este export gera o resultado coincide (as células que precisam responder
 *     "" são FÓRMULAS que devolvem "", não células vazias), mas uma metodologia
 *     que rendesse exatamente 0,00% seria lida aqui como ausente. Fica
 *     registrado em vez de corrigido com um sentinela: o custo do sentinela é
 *     alto e o caso não ocorre no que se gera hoje.
 */
import type ExcelJS from "exceljs";

export type Valor = number | string | boolean | null;

const semCifrao = (x: string) => x.replace(/\$/g, "");

// MEMÓRIA POR PLANILHA. Sem ela, avaliar a Modelagem é exponencial e o teto de
// profundidade vira o limite prático: o saldo de caixa de dezembro do 5º ano
// depende do de novembro, que depende do de outubro… 60 elos, e cada elo puxa
// receita, custo, juros e capital de giro, que puxam a mesma cadeia de novo.
// Medido antes de memoizar: 1.110 das 4.380 fórmulas do modelo devolviam
// "não sei" — e o motivo NÃO era o modelo, era o avaliador desistindo.
//
// O marcador EM_CURSO é o que distingue "cadeia longa" de "referência
// circular": uma célula que se pede a si mesma devolve null (como o Excel
// acusaria), em vez de estourar a pilha.
const EM_CURSO = Symbol("em-curso");
const memoria = new WeakMap<ExcelJS.Worksheet, Map<string, Valor | typeof EM_CURSO>>();

export function avaliarCelula(
  ws: ExcelJS.Worksheet,
  col: string,
  row: number,
  prof = 0,
): Valor {
  // O teto continua existindo, mas alto: com memória, a profundidade real é a
  // da cadeia mais longa (dezenas), não o número de células.
  if (prof > 4000) return null;
  const chave = `${semCifrao(col)}${row}`;
  let cache = memoria.get(ws);
  if (!cache) { cache = new Map(); memoria.set(ws, cache); }
  const guardado = cache.get(chave);
  if (guardado === EM_CURSO) return null; // referência circular
  if (guardado !== undefined) return guardado as Valor;
  cache.set(chave, EM_CURSO);
  const r = avaliarCelulaSemMemoria(ws, col, row, prof);
  cache.set(chave, r);
  return r;
}

/**
 * Invalida a memória de uma planilha. Necessário para quem MEXE nas células
 * entre duas avaliações — por exemplo, trocar a metodologia do seletor e
 * recalcular. Sem isto o segundo cálculo devolveria o primeiro.
 */
export function esquecerMemoria(ws: ExcelJS.Worksheet): void {
  memoria.delete(ws);
}

function avaliarCelulaSemMemoria(
  ws: ExcelJS.Worksheet,
  col: string,
  row: number,
  prof: number,
): Valor {
  const v = ws.getRow(row).getCell(semCifrao(col)).value;
  // Célula VAZIA vale 0 numa referência, como no Excel. Devolver null aqui fazia
  // qualquer soma que tocasse uma célula vazia virar null e, no chamador, NaN —
  // e uma seção padrão sem dado (ex.: "Investimentos" num balanço que não tem
  // investimento) é justamente uma célula vazia LEGÍTIMA. No teste v29 isso
  // produziu 7 "divergências" no Ativo Não Circulante que não existiam: o Excel
  // calcula aquelas somas sem reclamar. Ferramenta de conferência que grita à
  // toa é a mesma classe de problema de guarda que grita à toa — faz a sessão
  // seguinte perseguir defeito que não está lá.
  if (v == null) return 0;
  if (typeof v === "number") return v;
  if (typeof v === "string") return v;
  // CÉLULA DE DATA. O eixo do tempo do modelo institucional é uma data (uma raiz
  // e duas recorrências de EOMONTH), e sem esta conversão toda célula de
  // cabeçalho vinha como `null` — "não sei avaliar" — e qualquer assert sobre o
  // calendário passava sem provar nada.
  if (v instanceof Date) return Math.round((v.getTime() - Date.UTC(1899, 11, 30)) / 86400000);
  if (typeof v === "object" && "formula" in v) {
    return avaliarExpressao((v as ExcelJS.CellFormulaValue).formula, ws, prof + 1);
  }
  if (typeof v === "object" && "result" in v) {
    const r = (v as { result?: unknown }).result;
    return typeof r === "number" || typeof r === "string" ? r : null;
  }
  return null;
}

const RE_REF = /^\$?([A-Z]+)\$?([0-9]+)$/;
const RE_RANGE = /^\$?([A-Z]+)\$?([0-9]+):\$?([A-Z]+)\$?([0-9]+)$/;

const colParaNum = (c: string) => {
  let n = 0;
  for (const ch of c) n = n * 26 + (ch.charCodeAt(0) - 64);
  return n;
};
const numParaCol = (n: number) => {
  let s = "";
  let x = n;
  while (x > 0) { const r = (x - 1) % 26; s = String.fromCharCode(65 + r) + s; x = Math.floor((x - 1) / 26); }
  return s;
};

/** Células de um intervalo, em ordem de leitura (linha a linha). */
function celulasDoIntervalo(bruto: string): Array<{ col: string; row: number }> | null {
  const m = RE_RANGE.exec(bruto.trim());
  if (!m) {
    const u = RE_REF.exec(bruto.trim());
    return u ? [{ col: u[1], row: Number(u[2]) }] : null;
  }
  const [, c1, r1, c2, r2] = m;
  const a = colParaNum(c1); const b = colParaNum(c2);
  const out: Array<{ col: string; row: number }> = [];
  for (let r = Number(r1); r <= Number(r2); r++) {
    for (let c = Math.min(a, b); c <= Math.max(a, b); c++) out.push({ col: numParaCol(c), row: r });
  }
  return out;
}

/**
 * Endereço para onde um `INDEX(intervalo, a[, b])` aponta — sem resolver o
 * VALOR. É o que permite a `COUNT` distinguir "célula vazia" de "célula com
 * zero": `avaliarCelula` devolve 0 para as duas (e tem de devolver, ver o
 * comentário lá), então quem precisa da diferença tem de olhar a célula crua.
 *
 * No Excel isso não é um detalhe do arnês: `ISNUMBER(INDEX(...))` é VERDADEIRO
 * para célula vazia, porque INDEX de vazio vale 0. `COUNT(INDEX(...))` é o
 * idioma correto, e só funciona porque INDEX devolve REFERÊNCIA.
 */
function enderecoDeIndex(bruto: string, ws: ExcelJS.Worksheet, prof: number): { col: string; row: number } | null {
  const m = /^INDEX\s*\(([\s\S]*)\)$/i.exec(bruto.trim());
  if (!m) return null;
  const dentro = m[1];
  const partes: string[] = [];
  let nivel = 0; let atual = "";
  for (let k = 0; k < dentro.length; k++) {
    const ch = dentro[k];
    if (ch === "(") nivel++;
    if (ch === ")") nivel--;
    if (ch === '"') { atual += ch; k++; while (k < dentro.length && dentro[k] !== '"') { atual += dentro[k++]; } atual += '"'; continue; }
    // Idem para nome de aba entre apóstrofos — mesma vírgula, mesmo estrago.
    if (ch === "'") { atual += ch; k++; while (k < dentro.length && dentro[k] !== "'") { atual += dentro[k++]; } atual += "'"; continue; }
    if (ch === "," && nivel === 0) { partes.push(atual.trim()); atual = ""; continue; }
    atual += ch;
  }
  partes.push(atual.trim());
  const mr = RE_RANGE.exec(partes[0] ?? "");
  if (!mr) return null;
  const [, c1, r1, c2, r2] = mr;
  const cIni = Math.min(colParaNum(c1), colParaNum(c2));
  const cFim = Math.max(colParaNum(c1), colParaNum(c2));
  const rIni = Math.min(Number(r1), Number(r2));
  const rFim = Math.max(Number(r1), Number(r2));
  const a = avaliarExpressao(partes[1] ?? "", ws, prof + 1);
  if (typeof a !== "number") return null;
  if (partes.length >= 3) {
    const b = avaliarExpressao(partes[2] ?? "", ws, prof + 1);
    if (typeof b !== "number") return null;
    if (a < 1 || a > rFim - rIni + 1 || b < 1 || b > cFim - cIni + 1) return null;
    return { col: numParaCol(cIni + b - 1), row: rIni + a - 1 };
  }
  if (rIni === rFim) {
    if (a < 1 || a > cFim - cIni + 1) return null;
    return { col: numParaCol(cIni + a - 1), row: rIni };
  }
  if (cIni === cFim) {
    if (a < 1 || a > rFim - rIni + 1) return null;
    return { col: numParaCol(cIni), row: rIni + a - 1 };
  }
  return null;
}

/** Avalia uma expressão de fórmula (sem o "=" inicial). */
export function avaliarExpressao(src: string, ws: ExcelJS.Worksheet, prof = 0): Valor {
  if (prof > 4000) return null;
  let i = 0;
  const s = src;

  const pular = () => { while (i < s.length && s[i] === " ") i++; };

  const num = (v: Valor): number | null => (typeof v === "number" ? v : null);

  // comparacao := concat (('<='|'>='|'<>'|'<'|'>'|'=') concat)?
  const comparacao = (): Valor => {
    const a = concat();
    pular();
    const doisChars = s.slice(i, i + 2);
    let op: string | null = null;
    if (doisChars === "<=" || doisChars === ">=" || doisChars === "<>") { op = doisChars; i += 2; }
    else if (s[i] === "<" || s[i] === ">" || s[i] === "=") { op = s[i]; i += 1; }
    if (!op) return a;
    const b = concat();
    // Excel compara vazio com "" como IGUAL — e o modelo depende disso: a
    // premissa faz `IF(<celula>="","",<celula>)` para propagar ausência.
    const norm = (v: Valor) => (v === 0 || v === "" || v == null ? "" : v);
    switch (op) {
      case "=": return norm(a) === norm(b) || a === b;
      case "<>": return !(norm(a) === norm(b) || a === b);
      default: {
        const x = num(a); const y = num(b);
        if (x == null || y == null) return null;
        if (op === "<=") return x <= y;
        if (op === ">=") return x >= y;
        if (op === "<") return x < y;
        return x > y;
      }
    }
  };

  // concat := soma ('&' soma)*
  const concat = (): Valor => {
    let acc = soma();
    for (;;) {
      pular();
      if (s[i] !== "&") return acc;
      i++;
      const d = soma();
      // Os dois ramos de `typeof v === "number"` eram String(v) — o ternário não
      // decidia nada. `String` já cobre número, texto e booleano.
      const txt = (v: Valor) => (v == null ? "" : String(v));
      acc = txt(acc) + txt(d);
    }
  };

  // soma := termo (('+'|'-') termo)*
  const soma = (): Valor => {
    let acc = termo();
    for (;;) {
      pular();
      const op = s[i];
      // `-` só é subtração se não iniciar um novo fator negativo já consumido.
      if (op !== "+" && op !== "-") return acc;
      i++;
      const d = termo();
      const a = num(acc); const b = num(d);
      if (a == null || b == null) return null;
      acc = op === "+" ? a + b : a - b;
    }
  };

  // termo := potencia (('*'|'/') potencia)*
  const termo = (): Valor => {
    let acc = potencia();
    for (;;) {
      pular();
      const op = s[i];
      if (op !== "*" && op !== "/") return acc;
      i++;
      const d = potencia();
      const a = num(acc); const b = num(d);
      if (a == null || b == null) return null;
      if (op === "/") {
        if (b === 0) return null; // divisão por zero: é o que o IFERROR captura
        acc = a / b;
      } else acc = a * b;
    }
  };

  // potencia := fator ('^' fator)*
  const potencia = (): Valor => {
    let acc = fator();
    for (;;) {
      pular();
      if (s[i] !== "^") return acc;
      i++;
      const d = fator();
      const a = num(acc); const b = num(d);
      if (a == null || b == null) return null;
      // Base negativa com expoente fracionário é #NUM! no Excel — devolve null
      // para o IFERROR de fora capturar, em vez de NaN escapando como número.
      const r = Math.pow(a, b);
      acc = Number.isFinite(r) ? r : null;
      if (acc == null) return null;
    }
  };

  const fator = (): Valor => {
    pular();
    if (s[i] === "-") { i++; const v = fator(); const n = num(v); return n == null ? null : -n; }
    if (s[i] === "+") { i++; return fator(); }
    if (s[i] === "(") {
      i++;
      const v = comparacao();
      pular();
      if (s[i] === ")") i++;
      return v;
    }
    if (s[i] === '"') {
      i++;
      let t = "";
      while (i < s.length && s[i] !== '"') t += s[i++];
      i++;
      return t;
    }
    const mNum = /^[0-9]+(\.[0-9]+)?/.exec(s.slice(i));
    if (mNum) { i += mNum[0].length; return Number(mNum[0]); }

    // Referência absoluta/mista: começa com `$`.
    if (s[i] === "$") {
      const mAbs = /^\$?([A-Z]+)\$?([0-9]+)/.exec(s.slice(i));
      if (!mAbs) return null;
      i += mAbs[0].length;
      return avaliarCelula(ws, mAbs[1], Number(mAbs[2]), prof + 1);
    }

    // REFERÊNCIA ENTRE ABAS: `'Balance Sheet'!J42` ou `Anual!U54`.
    //
    // Sem isto o avaliador devolvia `null` para toda fórmula do modelo
    // institucional — que é feito de referência cruzada — e o arnês não tinha como
    // provar que o balanço fecha. Pior: `null` propagava como "não sei" e o assert
    // passaria por não conseguir avaliar, que é a forma mais silenciosa de teste
    // que não prova nada.
    const mExt = /^('(?:[^']|'')+'|[A-Za-zÀ-ÿ0-9_.&][A-Za-zÀ-ÿ0-9_.&\s]*)!(\$?[A-Z]+\$?[0-9]+)/
      .exec(s.slice(i));
    if (mExt) {
      const nomeBruto = mExt[1];
      const nome = nomeBruto.startsWith("'")
        ? nomeBruto.slice(1, -1).replace(/''/g, "'")
        : nomeBruto;
      const outra = ws.workbook?.getWorksheet(nome);
      const alvo = RE_REF.exec(mExt[2]);
      if (!outra || !alvo) return null;
      i += mExt[0].length;
      return avaliarCelula(outra, alvo[1], Number(alvo[2]), prof + 1);
    }

    const mId = /^([A-Za-z_][A-Za-z0-9_.]*)/.exec(s.slice(i));
    if (!mId) return null;
    const id = mId[1];
    const depoisId = i + id.length;

    if (s[depoisId] === "(") {
      i = depoisId + 1;
      const brutos: string[] = [];
      for (;;) {
        pular();
        const inicio = i;
        let nivel = 0;
        while (i < s.length) {
          const ch = s[i];
          if (ch === "(") nivel++;
          if (ch === ")") { if (nivel === 0) break; nivel--; }
          if (ch === "," && nivel === 0) break;
          if (ch === '"') { i++; while (i < s.length && s[i] !== '"') { i++; } }
          // ASPAS SIMPLES TAMBÉM, e este era um BURACO REAL do arnês: nome de aba
          // com vírgula vai entre apóstrofos (`'Revenues, COGS & SG&A'!F39`), e sem
          // pular esse trecho a vírgula DE DENTRO DO NOME partia o argumento em
          // dois. `N('Revenues` não avalia nada e devolve 0 — então TODA fórmula
          // que referenciasse a aba principal do modelo dentro de uma função
          // avaliava zero, em silêncio, e o assert passava por não conseguir
          // avaliar. Achado ao escrever o teste do painel de cenários, que
          // reprovava dizendo "IDÊNTICO AO BASE" sobre um Stress de 20%.
          if (ch === "'") { i++; while (i < s.length && s[i] !== "'") { i++; } }
          i++;
        }
        brutos.push(s.slice(inicio, i).trim());
        if (s[i] === ",") { i++; continue; }
        if (s[i] === ")") { i++; break; }
        break;
      }
      const nome = id.toUpperCase();
      const val = (k: number) => avaliarExpressao(brutos[k] ?? "", ws, prof + 1);
      // Valores de um argumento que pode ser intervalo OU expressão.
      const valores = (bruto: string): Valor[] => {
        const cels = celulasDoIntervalo(bruto);
        if (cels) return cels.map((c) => avaliarCelula(ws, c.col, c.row, prof + 1));
        return [avaliarExpressao(bruto, ws, prof + 1)];
      };

      if (nome === "SUM") {
        let t: number | null = null;
        for (const bruto of brutos) {
          for (const x of valores(bruto)) if (typeof x === "number") t = (t ?? 0) + x;
        }
        return t;
      }
      if (nome === "PRODUCT") {
        let t: number | null = null;
        for (const bruto of brutos) {
          for (const x of valores(bruto)) {
            // PRODUCT ignora TEXTO num intervalo, mas um argumento que é
            // EXPRESSÃO e resolve para texto é #VALUE! — e é justamente o caso
            // das médias (`1+X/100` com X vazio). Devolver null deixa o IFERROR
            // de fora fazer o que faz no Excel.
            if (typeof x === "number") t = (t ?? 1) * x;
            else if (celulasDoIntervalo(bruto) == null) return null;
          }
        }
        return t;
      }
      if (nome === "MAX" || nome === "MIN") {
        const xs: number[] = [];
        for (const bruto of brutos) for (const x of valores(bruto)) if (typeof x === "number") xs.push(x);
        if (xs.length === 0) return 0;
        return nome === "MAX" ? Math.max(...xs) : Math.min(...xs);
      }
      if (nome === "ROUND") {
        const x = num(val(0)); const d = num(val(1)) ?? 0;
        if (x == null) return null;
        const f = Math.pow(10, d);
        return Math.round(x * f) / f;
      }
      if (nome === "N") {
        // `N(x)`: número passa; texto (inclusive "") e vazio viram 0. É a
        // semântica de CÉLULA VAZIA aplicada a uma fórmula — o modelo usa isso
        // para ler uma premissa que devolve "" sem estourar #VALUE!.
        const v = val(0);
        return typeof v === "number" ? v : 0;
      }
      if (nome === "ISNUMBER") return typeof val(0) === "number";
      // NOT/AND/OR e ABS/YEAR: o modelo institucional os usa nos testes de
      // covenant (`IF(NOT(ISNUMBER(x)),"n.a.",…)`), no diagnóstico por exercício
      // e no eixo do tempo (`YEAR` do cabeçalho). Sem eles o avaliador devolvia
      // `null` e o assert passava por não conseguir avaliar — que é a forma mais
      // silenciosa de teste que não prova nada, exatamente o que este arquivo
      // existe para evitar.
      if (nome === "NOT") {
        const v = val(0);
        if (v == null) return null;
        return !(v === true || (typeof v === "number" && v !== 0));
      }
      if (nome === "AND" || nome === "OR") {
        const bools: boolean[] = [];
        for (const bruto of brutos) {
          const v = avaliarExpressao(bruto, ws, prof + 1);
          if (v == null) return null;
          bools.push(v === true || (typeof v === "number" && v !== 0));
        }
        return nome === "AND" ? bools.every(Boolean) : bools.some(Boolean);
      }
      if (nome === "ABS") {
        const x = num(val(0));
        return x == null ? null : Math.abs(x);
      }
      if (nome === "YEAR") {
        // O cabeçalho de ano do modelo é uma DATA (o eixo do tempo sai de uma
        // célula só). Aqui basta devolver o ano dela.
        const v = val(0);
        if (typeof v === "number") {
          // Serial do Excel: 1 = 1900-01-01, com o bug do ano bissexto de 1900.
          const ms = Date.UTC(1899, 11, 30) + v * 86400000;
          return new Date(ms).getUTCFullYear();
        }
        return null;
      }
      if (nome === "EOMONTH") {
        const v = val(0);
        const meses = num(val(1)) ?? 0;
        const base = typeof v === "number" ? new Date(Date.UTC(1899, 11, 30) + v * 86400000) : null;
        if (!base) return null;
        const d = new Date(Date.UTC(base.getUTCFullYear(), base.getUTCMonth() + meses + 1, 0));
        return Math.round((d.getTime() - Date.UTC(1899, 11, 30)) / 86400000);
      }
      if (nome === "COUNT" || nome === "ISBLANK") {
        // Contam CÉLULAS, não valores — e é por isso que precisam do endereço:
        // uma célula vazia vale 0 quando lida, mas não conta como número.
        let n = 0; let vistas = 0;
        for (const bruto of brutos) {
          const cels = celulasDoIntervalo(bruto);
          if (cels) {
            for (const c of cels) {
              vistas++;
              if (typeof ws.getRow(c.row).getCell(c.col).value === "number") n++;
            }
            continue;
          }
          const end = enderecoDeIndex(bruto, ws, prof + 1);
          if (end) {
            vistas++;
            const cru = ws.getRow(end.row).getCell(end.col).value;
            if (typeof cru === "number") n++;
            else if (cru && typeof cru === "object" && "formula" in cru) {
              // Célula com FÓRMULA conta se ela resolve para número.
              if (typeof avaliarCelula(ws, end.col, end.row, prof + 1) === "number") n++;
            }
            continue;
          }
          vistas++;
          if (typeof avaliarExpressao(bruto, ws, prof + 1) === "number") n++;
        }
        if (nome === "ISBLANK") return vistas > 0 && n === 0;
        return n;
      }
      if (nome === "IF") {
        const c = val(0);
        const verdade = c === true || (typeof c === "number" && c !== 0);
        if (c == null) return null;
        return verdade ? val(1) : (brutos.length > 2 ? val(2) : false);
      }
      if (nome === "IFERROR") {
        const v = val(0);
        if (v == null) return val(1);
        return v;
      }
      if (nome === "MATCH") {
        const alvo = val(0);
        const cels = celulasDoIntervalo(brutos[1] ?? "");
        if (!cels) return null;
        const igual = (a: Valor, b: Valor) => {
          if (typeof a === "number" && typeof b === "number") return a === b;
          return String(a ?? "") === String(b ?? "");
        };
        for (let k = 0; k < cels.length; k++) {
          if (igual(avaliarCelula(ws, cels[k].col, cels[k].row, prof + 1), alvo)) return k + 1;
        }
        return null; // #N/A — o IFERROR de fora captura, como no Excel
      }
      if (nome === "INDEX") {
        const m = RE_RANGE.exec((brutos[0] ?? "").trim());
        if (!m) return null;
        const [, c1, r1, c2, r2] = m;
        const cIni = Math.min(colParaNum(c1), colParaNum(c2));
        const cFim = Math.max(colParaNum(c1), colParaNum(c2));
        const rIni = Math.min(Number(r1), Number(r2));
        const rFim = Math.max(Number(r1), Number(r2));
        const nLin = rFim - rIni + 1;
        const nCol = cFim - cIni + 1;
        const a = num(val(1));
        if (a == null) return null;
        if (brutos.length >= 3) {
          const b = num(val(2));
          if (b == null) return null;
          if (a < 1 || a > nLin || b < 1 || b > nCol) return null; // #REF!
          return avaliarCelula(ws, numParaCol(cIni + b - 1), rIni + a - 1, prof + 1);
        }
        // 1-D: o intervalo é uma linha só ou uma coluna só.
        if (nLin === 1) {
          if (a < 1 || a > nCol) return null;
          return avaliarCelula(ws, numParaCol(cIni + a - 1), rIni, prof + 1);
        }
        if (nCol === 1) {
          if (a < 1 || a > nLin) return null;
          return avaliarCelula(ws, numParaCol(cIni), rIni + a - 1, prof + 1);
        }
        return null;
      }
      // CHOOSE(n, a, b, c) — o interruptor de cenário do modelo institucional.
      // Índice fora de 1..n devolve null ("não sei"), como o #VALUE! do Excel:
      // devolver o primeiro argumento faria o arnês avaliar o cenário Base
      // enquanto o arquivo mostraria erro.
      if (nome === "CHOOSE") {
        const idx = num(avaliarExpressao(brutos[0] ?? "", ws, prof + 1));
        if (idx == null) return null;
        const escolhido = brutos[Math.round(idx)];
        if (escolhido === undefined) return null;
        return avaliarExpressao(escolhido, ws, prof + 1);
      }
      // TEXT(v, fmt) — só o suficiente para as células de diagnóstico do modelo
      // não virarem "não sei" e contaminarem um assert vizinho.
      if (nome === "TEXT") {
        const v = avaliarExpressao(brutos[0] ?? "", ws, prof + 1);
        return typeof v === "number" ? String(v) : (typeof v === "string" ? v : "");
      }
      return null; // função desconhecida: "não sei", nunca 0
    }

    const mRef = RE_REF.exec(id);
    if (mRef) {
      i = depoisId;
      // Pode ser `BO$8` (coluna relativa, linha absoluta) — o `$` no meio não
      // entra no identificador, então o casamento acima só pega `BO8`. Trata-se
      // o caso misto explicitamente.
      return avaliarCelula(ws, mRef[1], Number(mRef[2]), prof + 1);
    }
    const mMisto = /^([A-Z]+)\$([0-9]+)/.exec(s.slice(i));
    if (mMisto) {
      i += mMisto[0].length;
      return avaliarCelula(ws, mMisto[1], Number(mMisto[2]), prof + 1);
    }
    return null;
  };

  const out = comparacao();
  return out;
}

/** Colunas de valor (todas menos a coluna A do rótulo). */
export function colunasDeValor(ws: ExcelJS.Worksheet): string[] {
  const cols: string[] = [];
  for (let c = 2; c <= ws.columnCount; c++) cols.push(ws.getColumn(c).letter);
  return cols;
}

/**
 * Uma linha está "100% vazia" quando NENHUMA coluna de valor tem conteúdo.
 * Zero CONTA como conteúdo: se o documento diz que a conta é 0,00, isso é
 * informação (e apagar a linha esconderia o que o arquivo declarou).
 */
export function linhaVazia(ws: ExcelJS.Worksheet, row: number): boolean {
  for (const c of colunasDeValor(ws)) {
    const v = avaliarCelula(ws, c, row);
    if (typeof v === "number") return false;
    if (typeof v === "string" && v.trim() !== "") return false;
  }
  return true;
}
