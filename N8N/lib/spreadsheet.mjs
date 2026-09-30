// Converte conteúdo de planilha em texto compacto para enviar ao LLM.
// Usado no fallback quando o arquivo é CSV/XLSX (o modelo não lê xlsx binário).

// TETO DE SEGURANÇA, NÃO DE CONVENIÊNCIA.
//
// Era 50 linhas × 25 colunas, e 50 é menos do que um documento real tem: um
// faturamento de 24 meses por 5 entidades são 120 linhas, um balancete
// analítico passa de 500. O resto ia embora com uma nota discreta no meio do
// prompt ("… (+N linhas omitidas)") que só a IA lia — o banco recebia a
// extração como se estivesse completa, e o book saía com faturamento parcial
// sem UMA pendência. É o item 1 do §7.4 do Onboarding: "perde dado de verdade".
//
// O teto continua existindo porque input é dinheiro e porque uma planilha
// absurda tem de parar em algum lugar; o que muda é (a) a ordem de grandeza,
// que agora cobre documento real, e (b) o corte deixar de ser silencioso —
// `avisoTruncamentoPlanilha` transforma o que ficou de fora em pendência.
export const MAX_LINHAS_PLANILHA = 2000;
export const MAX_COLUNAS_PLANILHA = 60;

// rows: array de objetos (uma linha = um objeto coluna→valor), como sai do
// nó "Extract From File" do N8N ou de um CSV parseado.
//
// `colunas` (opcional): a UNIÇÃO de colunas medida sobre TODAS as linhas, quando
// `rows` já vem cortada em `maxRows` pelo `Agrupar Linhas` (17/09/2026) — sem
// ela o cabeçalho sairia só das linhas que sobraram e uma coluna que só existe
// depois da linha 2000 sumiria do texto, que é o que o código antigo NÃO fazia.
export function spreadsheetToText(
  rows,
  { maxRows = MAX_LINHAS_PLANILHA, maxCols = MAX_COLUNAS_PLANILHA, colunas = null, totalLinhas = null } = {},
) {
  if (!Array.isArray(rows) || rows.length === 0) return '(planilha vazia)';
  const cols = (Array.isArray(colunas) ? colunas : colunasDaPlanilha(rows)).slice(0, maxCols);
  const nTotal = Number.isFinite(Number(totalLinhas)) && Number(totalLinhas) > rows.length
    ? Number(totalLinhas) : rows.length;
  const header = cols.join(' | ');
  const corpo = rows
    .slice(0, maxRows)
    .map((r) => cols.map((c) => String(r[c] ?? '')).join(' | '))
    .join('\n');
  const extra = nTotal > maxRows ? `\n… (+${nTotal - maxRows} linhas omitidas)` : '';
  return `${header}\n${corpo}${extra}`;
}

// UNIÃO das chaves, não as chaves da PRIMEIRA linha.
//
// `Object.keys(rows[0])` assume que a linha 0 declara todas as colunas. Vale
// para CSV (o cabeçalho manda), mas o "Extract From File" do N8N devolve objeto
// esparso: célula vazia não vira chave. Uma planilha cuja primeira linha de
// dados tem a coluna de 2024 em branco perdia a coluna 2024 do documento
// INTEIRO — mesma família de perda silenciosa que o teto de linhas.
//
// ORDEM: chave que parece inteiro ('2025') o JS reordena para a frente das
// textuais, então a ordem daqui não é a ordem visual do documento. Não desalinha
// nada (cabeçalho e corpo usam esta mesma lista) e não se corrige sem carregar a
// ordem original desde o parse — fica para quando o "Extract From File" entrar.
// Registrado para ninguém "consertar" achando que é bug.
export function colunasDaPlanilha(rows) {
  const vistas = new Set();
  for (const r of rows) {
    if (r && typeof r === 'object') for (const k of Object.keys(r)) vistas.add(k);
  }
  return [...vistas];
}

// O que `spreadsheetToText` deixou de fora, em texto que vira PENDÊNCIA.
//
// Devolve null quando nada foi cortado (o caso normal, e o silêncio aqui é
// legítimo). Quando corta, o texto entra em `falha_motivo` — que a 0016 já
// converte em pendência `extracao_falhou` visível no portal. Sem isto, o corte
// existia só dentro do prompt: a IA sabia, o analista não.
//
// `totais` (opcional, `{linhas, colunas}`): o que foi MEDIDO sobre a planilha
// inteira quando `rows` já chegou cortada pelo `Agrupar Linhas`. Sem ele vale
// `rows.length`, como sempre — e com ele o aviso diz "150000 linhas", não
// "2000 de 2000" (a ausência apresentada como completude, regra 1).
export function avisoTruncamentoPlanilha(
  rows,
  { maxRows = MAX_LINHAS_PLANILHA, maxCols = MAX_COLUNAS_PLANILHA, totais = null } = {},
) {
  if (!Array.isArray(rows) || rows.length === 0) return null;
  const nLinhas = totais && Number(totais.linhas) > rows.length ? Number(totais.linhas) : rows.length;
  const nColunas = totais && Number.isFinite(Number(totais.colunas)) ? Number(totais.colunas) : colunasDaPlanilha(rows).length;
  const partes = [];
  if (nLinhas > maxRows) {
    partes.push(
      `${nLinhas - maxRows} de ${nLinhas} linhas não foram enviadas à extração `
      + `(teto de ${maxRows})`,
    );
  }
  if (nColunas > maxCols) {
    partes.push(
      `${nColunas - maxCols} de ${nColunas} colunas não foram enviadas à extração `
      + `(teto de ${maxCols})`,
    );
  }
  if (partes.length === 0) return null;
  return `Planilha maior que o teto de envio: ${partes.join('; ')}. `
    + 'A extração deste documento está INCOMPLETA — o que falta não está no banco '
    + 'nem no book. Reenvie o arquivo fatiado ou peça ao dono para elevar o teto.';
}

// CSV simples → array de objetos (separador , ou ;). Suficiente para o fallback;
// casos complexos (aspas com vírgula) o dono valida/ajusta no N8N.
/**
 * CSV → objetos, com ASPAS TRATADAS. Segue o RFC 4180 no que importa aqui.
 *
 * O QUE ESTAVA ERRADO, e é corrupção silenciosa de dado. A versão anterior era
 * `linha.split(sep)`, sem noção de aspas. Num CSV brasileiro isso quebra no caso
 * mais comum que existe — razão social com vírgula:
 *
 *     Empresa,"Silva, João & Cia",1000
 *     split(',')  →  ['Empresa', '"Silva', ' João & Cia"', '1000']
 *
 * Quatro células onde há três. O cabeçalho é lido pelo mesmo split, então TODA
 * coluna depois da que tem vírgula desliza uma casa, e os valores passam a ser
 * gravados sob o rótulo errado. Não estoura, não avisa, e o número chega ao
 * modelo debaixo de outro nome — a família de defeito que este projeto existe
 * para não ter.
 *
 * A máquina de estados abaixo resolve os três casos do formato de uma vez:
 * separador dentro de aspas, aspas escapadas (`""` vira `"`), e quebra de linha
 * dentro de campo — esta última é legal no RFC e era impossível de tratar
 * enquanto o código começava por `split(/\r?\n/)`.
 *
 * O SEPARADOR é detectado CONTANDO FORA DAS ASPAS, pelo mesmo motivo: numa linha
 * como `Nome;"a,b,c";1` a vírgula aparece três vezes e o ponto e vírgula uma —
 * contar sem olhar aspas elegia a vírgula e quebrava o arquivo inteiro.
 */
function contarForaDeAspas(texto, alvo) {
  let n = 0, dentro = false;
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (c === '"') {
      if (dentro && texto[i + 1] === '"') { i++; continue; }
      dentro = !dentro;
    } else if (c === alvo && !dentro) n++;
    else if ((c === '\n') && !dentro) break; // só o primeiro registro decide
  }
  return n;
}

function registrosDoCsv(texto, sep) {
  const regs = [];
  let campo = '', reg = [], dentro = false;
  for (let i = 0; i < texto.length; i++) {
    const c = texto[i];
    if (dentro) {
      if (c === '"') {
        if (texto[i + 1] === '"') { campo += '"'; i++; } else dentro = false;
      } else campo += c;
      continue;
    }
    if (c === '"') { dentro = true; continue; }
    if (c === sep) { reg.push(campo); campo = ''; continue; }
    if (c === '\r') continue;
    if (c === '\n') { reg.push(campo); regs.push(reg); reg = []; campo = ''; continue; }
    campo += c;
  }
  reg.push(campo);
  regs.push(reg);
  // Registro totalmente vazio é linha em branco, não dado.
  return regs.filter((r) => r.some((x) => x.trim() !== ''));
}

export function parseCsv(texto) {
  const src = String(texto || '');
  if (src.trim() === '') return [];
  const sep = contarForaDeAspas(src, ';') > contarForaDeAspas(src, ',') ? ';' : ',';
  const regs = registrosDoCsv(src, sep);
  if (regs.length === 0) return [];
  const cabecalho = regs[0].map((c) => c.trim());
  return regs.slice(1).map((celulas) => {
    const obj = {};
    cabecalho.forEach((c, i) => { obj[c || `col${i}`] = (celulas[i] ?? '').trim(); });
    return obj;
  });
}

