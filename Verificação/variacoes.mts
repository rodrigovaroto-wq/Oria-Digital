// ARNÊS DE VARIAÇÕES — a mesma cadeia real de produção, sobre N documentos sujos.
//
// POR QUE ELE EXISTE, e o que ele NÃO substitui. O `run.mts` ao lado prova a
// costura produtor→banco→export sobre UM insumo: o book de Vertentes, que é
// extração FIEL por construção. Documento de mandato real não é fiel — vem com
// escala trocada no meio da página, locale anglo, negativo entre parênteses,
// subtotal que o PDF não imprimiu, comparativo sem coluna de período, moeda
// misturada, bloco perdido no fatiamento e rodapé de CNPJ vazando como conta.
//
// Este arnês injeta essas sujeiras NO PONTO EM QUE A OPENAI RESPONDE e deixa o
// resto correr igual: o código do nó sai do JSON gerado (o mesmo que o dono
// importa), o banco é o das 82 migrations, e o export é o do portal. Ou seja,
// tudo depois da leitura do PDF é produção de verdade.
//
// O QUE ELE NÃO PROVA, e precisa estar escrito para ninguém confundir com o B1:
// a leitura do PDF em si. Scan torto, carimbo, coluna deslocada e tabela
// quebrada entre páginas são defeitos da OpenAI lendo o arquivo, e nenhum arnês
// que começa DEPOIS da resposta dela os alcança. O B1 continua de pé.
//
// Roda em segundos porque o banco é clonado de um MOLDE já migrado:
//
//   PGHOST=/tmp/pgo/sock PGPORT=5433 PGUSER=postgres E2E_PSQL=psql \
//     ./portal/node_modules/.bin/tsx Verificação/variacoes.mts
//
// `--so=nome` roda uma variação só. `--manter` não derruba os bancos, para
// inspecionar à mão depois.

import { execFileSync } from "node:child_process";
import { readFileSync, writeFileSync, mkdirSync, readdirSync } from "node:fs";
import ExcelJS from "exceljs";
import { buildExportWorkbook } from "../portal/src/lib/export.ts";
import type { CampoExtraido, DocumentoParaExport } from "../portal/src/lib/types.ts";
import { avaliarCelula, esquecerMemoria } from "../portal/scripts/lib/avaliar-formula.mts";
import type { EntradaModeloInstitucional, LinhaModelo } from "../portal/src/lib/modelo-institucional.ts";
import { seriesPorLinha, serieDaLinha } from "../portal/src/lib/modelagem-linha.ts";
import { provedor } from "../N8N/lib/provedor.mjs";

// O arnês injeta a sujeira NO PONTO EM QUE A IA RESPONDE — então o envelope tem
// de ser o do provedor ATIVO. Escrito na forma da OpenAI enquanto o nó lê a do
// Google, toda variação viraria "zero campos": o arnês estaria medindo o
// desalinhamento dele mesmo, não a robustez da cadeia.
const PROV = provedor();

function envelopeDaResposta(conteudo: string, uso: { prompt_tokens: number; completion_tokens: number }) {
  return PROV.dialeto === "gemini"
    ? {
      candidates: [{ content: { parts: [{ text: conteudo }] }, finishReason: "STOP" }],
      usageMetadata: {
        promptTokenCount: uso.prompt_tokens,
        candidatesTokenCount: uso.completion_tokens,
        cachedContentTokenCount: 0,
      },
    }
    : {
      choices: [{ finish_reason: "stop", message: { content: conteudo } }],
      usage: uso,
    };
}

const RAIZ = new URL("../", import.meta.url).pathname;
const PSQL = (process.env.E2E_PSQL ?? "psql").split(/\s+/);
const MOLDE = process.env.E2E_MOLDE ?? "tdf_tpl";
const SO = process.argv.find((a) => a.startsWith("--so="))?.slice(5);
const MANTER = process.argv.includes("--manter");

function psql(sql: string, db: string): string {
  return execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-A", "-t", "-d", db, "-c", sql],
    { encoding: "utf8", cwd: RAIZ, maxBuffer: 64 * 1024 * 1024 });
}
function psqlJson<T>(sql: string, db: string): T {
  return JSON.parse(psql(`select coalesce(json_agg(t), '[]'::json) from (${sql}) t`, db).trim()) as T;
}
const lit = (s: string | null | undefined) => (s == null ? "null" : `'${String(s).replace(/'/g, "''")}'`);

// ---------------------------------------------------------------------------
// O CÓDIGO DO NÓ sai do workflow GERADO, não da lib — é o que o dono importa.
// ---------------------------------------------------------------------------
const wf = JSON.parse(readFileSync(`${RAIZ}N8N/workflow.e1-ingestao.json`, "utf8")) as {
  nodes: Array<{ name: string; parameters: { jsCode: string } }>;
};
const codigoDoNo = (nome: string) => {
  const n = wf.nodes.find((x) => x.name === nome);
  if (!n) throw new Error(`nó "${nome}" não existe no workflow gerado`);
  return n.parameters.jsCode;
};
const AsyncFunction = Object.getPrototypeOf(async function () {}).constructor as new (
  ...args: string[]
) => (...a: unknown[]) => Promise<{ json: Record<string, unknown> }>;

async function rodarNo(nome: string, item: unknown, refs: Record<string, unknown> = {}) {
  const $input = { item, first: () => item, all: () => [item] };
  const $ = (ref: string) => {
    if (!(ref in refs)) throw new Error(`referência não mockada: $('${ref}')`);
    return { first: () => refs[ref], item: refs[ref] };
  };
  const fn = new AsyncFunction("$input", "$", "$env", "$json", "$itemIndex", "Buffer", codigoDoNo(nome));
  return fn.call({}, $input, $, {}, (item as { json: unknown }).json, 0, Buffer);
}

const fixture = JSON.parse(
  readFileSync(`${RAIZ}portal/scripts/fixtures/book-vertentes.json`, "utf8"),
) as { documentos: DocumentoParaExport[]; campos: CampoExtraido[] };

function respostaDaIA(campos: CampoExtraido[], moeda = "BRL") {
  const unidade = campos.find((c) => c.unidade)?.unidade ?? null;
  return {
    json: envelopeDaResposta(
      JSON.stringify({
        moeda,
        unidade,
        diagnostico: {
          entidade: null, tipo_confirma: true, tipo_sugerido: "BALANCO",
          periodo_tipo: "anual", periodo_referencia: "12M25",
          legibilidade: "ok", nota_legibilidade: null, resumo: "var", justificativa: "var",
        },
        linhas: campos.map((c, i) => ({
          s: c.secao, sc: c.secao_canonica ?? "NAO_CLASSIFICAVEL",
          ec: c.entidade_coluna, pc: c.periodo_coluna, k: c.chave,
          vt: c.valor_texto, vn: c.valor_num, op: c.origem_pagina,
          cf: c.confianca ?? 0.9, ordem: i,
          ...(c.unidade ? { u: c.unidade } : {}),
          ...(c.moeda ? { m: c.moeda } : {}),
        })),
      }),
      { prompt_tokens: 1000, completion_tokens: 500 },
    ),
  };
}

// ---------------------------------------------------------------------------
// O MOLDE. As migrations são aplicadas UMA vez; cada variação clona (0,2 s). Sem
// isto, 22 variações × 84 migrations levariam minutos em vez de segundos — e um
// arnês lento é um arnês que ninguém roda.
// ---------------------------------------------------------------------------
function garantirMolde() {
  const existe = psql(`select count(*) from pg_database where datname = '${MOLDE}'`, "postgres").trim();
  if (existe === "1") return;
  console.log(`   (molde ${MOLDE} não existe — aplicando as migrations uma vez)`);
  psql(`create database ${MOLDE}`, "postgres");
  // E O SCHEMA `auth` (27/10/2026): a 0215 cria FK para `auth.users` e lê `auth.uid()`. É o mesmo mínimo que
  // `Supabase/test/run.sh` monta, com o mesmo corpo — sem ele a 0215 morre em "schema auth does not exist".
  // OS PAPÉIS DO SUPABASE são criados AQUI, como o `Verificação/run.mts` faz. Até
  // 01/10/2026 este molde dependia de outro processo (o `Supabase/test/run.sh`) já
  // tê-los criado no mesmo cluster: funcionava porque o CI rodava tudo num job só,
  // em série, e morreu com "role anon does not exist" no primeiro run com os jobs em
  // paralelo (fa6ccda). Dependência de ordem que ninguém declarou é dependência que
  // quebra no dia em que a ordem muda.
  psql(`do $$ begin
          if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
          if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
          if not exists (select 1 from pg_roles where rolname = 'service_role') then create role service_role nologin; end if;
        end $$;
        create schema if not exists storage;
        create table if not exists storage.buckets(id text primary key, name text, public boolean default false);
        create table if not exists storage.objects(id uuid default gen_random_uuid() primary key,
          bucket_id text, name text, owner uuid);
        alter table storage.objects enable row level security;
        create schema if not exists auth;
        create table if not exists auth.users(id uuid primary key default gen_random_uuid(), email text);
        create or replace function auth.uid() returns uuid language sql stable as $f$
          select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                          (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $f$;
        grant usage on schema auth to authenticated, service_role;
        grant execute on function auth.uid() to anon, authenticated, service_role;
        grant select on auth.users to service_role;
        grant usage on schema public to anon, authenticated, service_role;`, MOLDE);
  // A LISTA DAS MIGRATIONS SAI DO DISCO, E NÃO DE UM SHELL. Até aqui ela vinha de
  // `bash -c "ls Supabase/migrations/*.sql"`: o `bash` era resolvido pelo PATH
  // herdado do processo, então um executável com esse nome num diretório gravável
  // que aparecesse antes na busca rodaria no lugar do shell — e é logo abaixo que
  // o molde do banco é montado com essas migrations. `readdirSync` lê o mesmo
  // diretório sem criar processo nenhum, e o `sort()` reproduz a ordem
  // lexicográfica do `ls`, que é a ordem em que as migrations TÊM de ser
  // aplicadas (é o prefixo numérico do nome que as ordena).
  const arquivos = readdirSync(`${RAIZ}Supabase/migrations`)
    .filter((nome) => nome.endsWith(".sql"))
    .sort()
    .map((nome) => `Supabase/migrations/${nome}`);
  // Ver a nota longa em `Verificação/run.mts`: lista vazia tem de ESTOURAR. Aqui
  // o molde viraria um `datistemplate` sem uma tabela dentro, e cada variação
  // clonaria o vazio — 25 rodadas "sem achado" sobre nada.
  if (arquivos.length === 0) {
    throw new Error(
      `Nenhuma migration .sql em ${RAIZ}Supabase/migrations — o molde nasceria VAZIO.`);
  }
  for (const arq of arquivos) {
    execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-d", MOLDE, "-f", arq],
      { cwd: RAIZ, stdio: "pipe" });
  }
  psql(`update pg_database set datistemplate = true where datname = '${MOLDE}'`, "postgres");
  console.log(`   molde pronto com ${arquivos.length} migrations`);
}

// ---------------------------------------------------------------------------
// AS VARIAÇÕES. Cada uma transforma os campos extraídos, e o comentário diz que
// realidade de documento ela imita e o que se espera que o sistema faça.
// ---------------------------------------------------------------------------
type Campos = CampoExtraido[];
interface Variacao {
  nome: string;
  oque: string;
  espera: string;
  transformar: (c: Campos) => Campos;
  moeda?: string;
  /**
   * Quando a variante DESTRÓI as âncoras de propósito, o balanço não pode fechar
   * — e exigir que feche seria exigir que o modelo invente o total que o
   * documento não trouxe. Aqui o que se cobra é o inverso: que ele DECLARE.
   */
  balancoAbreDeProposito?: boolean;
  /** A variante impede a modelagem de propósito; o arquivo tem de EXPLICAR, não montar. */
  modelagemNaoMonta?: boolean;
  /** Registra TODO documento com este tipo (classificação colapsada). */
  tipoUnico?: string;
  /** Registra todo documento com este tipo de período. */
  periodoTipo?: string;
  /** Registra os documentos sem período nenhum. */
  semPeriodo?: boolean;
  /** Todos os documentos com o MESMO hash de conteúdo. */
  hashUnico?: boolean;
}
const clone = (c: Campos): Campos => JSON.parse(JSON.stringify(c)) as Campos;

// Tipo do documento por versão — várias variantes precisam mexer só na DRE, ou
// só no balanço, e é assim que um mandato real chega: em pedaços.
const tipoDaVersao = new Map<string, string>();
for (const d of fixture.documentos) {
  for (const v of d.documento_versao ?? []) tipoDaVersao.set(v.id, d.tipo_taxonomia ?? "");
}
const ehDe = (c: CampoExtraido, re: RegExp) => re.test(tipoDaVersao.get(c.documento_versao_id) ?? "");

// O CONJUNTO CONSOLIDADO. Cinco rodadas de variantes trocadas por completo
// acharam cinco defeitos reais; as variantes que os pegaram ficam aqui como
// RELIGAMENTO — marcadas com [PEGOU] e o que caiu. O resto é amostra larga das
// cinco rodadas, escolhida para cobrir as famílias sem repetir mecanismo.
const VARIACOES: Variacao[] = [
  { nome: "base", oque: "o book intacto — controle da rodada",
    espera: "balanço fecha em zero; tudo o mais é medido contra isto", transformar: (c) => c },

  // ---- [PEGOU] as cinco variantes que denunciaram defeito de produção --------
  {
    nome: "so_texto_sem_numero",
    oque: "[PEGOU] a extração devolveu o TEXTO do valor e não o número (vn nulo)",
    espera: "sem realizado o modelo NÃO monta e o arquivo EXPLICA — antes o export inteiro morria "
      + "com 'ano null fora do horizonte' e o analista não recebia arquivo nenhum",
    modelagemNaoMonta: true,
    transformar: (c) => clone(c).map((x) => ({
      ...x,
      valor_texto: typeof x.valor_num === "number" ? x.valor_num.toLocaleString("pt-BR") : x.valor_texto,
      valor_num: null,
    })),
  },
  {
    nome: "codigo_contabil_no_rotulo",
    oque: "[PEGOU] rótulos do ERP com código na frente: \"1.1.01.002 Caixa e bancos\"",
    espera: "as âncoras casam mesmo com o código — sem isso não há reconciliação e o balanço "
      + "abria em −36.116",
    // O CÓDIGO É DA CONTA, não da linha: a mesma conta tem o mesmo código em todas as colunas
    // de período, como num balancete de ERP. Antes o código vinha do índice da linha, e a mesma
    // conta ganhava um código por exercício — o modelo via contas diferentes, uma por ano, e o
    // achado de dívida que sumia misturava duas causas (a conta partida e o TOTAL tratado como
    // tranche). Só a segunda existe fora do arnês.
    transformar: (c) => {
      const codigo = new Map<string, string>();
      return clone(c).map((x) => {
        if (!codigo.has(x.chave)) {
          const n = codigo.size;
          codigo.set(x.chave, `${1 + (n % 4)}.${1 + (n % 3)}.${String(n % 90).padStart(2, "0")}`);
        }
        return { ...x, chave: `${codigo.get(x.chave)} ${x.chave}` };
      });
    },
  },
  {
    nome: "caracteres_de_controle",
    oque: "[PEGOU] tabulação, retorno de carro e espaço de largura zero no rótulo",
    espera: "caractere invisível não cria conta nova — o U+200B fazia a série quebrar em duas e "
      + "o balanço abrir em 180",
    transformar: (c) => clone(c).map((x, i) =>
      i % 3 === 0 ? { ...x, chave: `\t${x.chave}\u200b\r` } : x),
  },
  {
    nome: "periodo_fora_de_ordem",
    oque: "[PEGOU] colunas de período invertidas (2024 no lugar de 2025)",
    espera: "a dívida NÃO evapora: tranche sem saldo no último realizado abre no último saldo "
      + "conhecido. Antes ia a zero sem amortização — 37.719 de dívida sumindo",
    balancoAbreDeProposito: true,
    transformar: (c) => clone(c).map((x) => ({
      ...x, periodo_coluna: x.periodo_coluna === "2025" ? "2024"
        : x.periodo_coluna === "2024" ? "2025" : x.periodo_coluna })),
  },
  {
    nome: "tudo_numa_secao_so",
    oque: "[PEGOU] a classificação colapsou: toda linha marcada como ativo circulante",
    espera: "o passivo circulante fica negativo e a liquidez SE RECUSA em vez de publicar −0,69x",
    transformar: (c) => clone(c).map((x) => ({ ...x, secao_canonica: "ativo_circulante" })),
  },

  // ---- amostra larga das cinco rodadas ---------------------------------------
  { nome: "escala_mista", oque: "metade em unidade, metade em milhar",
    espera: "escala por linha é aplicada por linha",
    transformar: (c) => clone(c).map((x, i) => i % 2 === 0 ? x
      : { ...x, unidade: x.unidade === "mil" ? "unidade" : "mil" }) },
  { nome: "locale_anglo", oque: "valores como 1,234.56",
    espera: "o número é o mesmo",
    transformar: (c) => clone(c).map((x) => ({ ...x, valor_texto: typeof x.valor_num === "number"
      ? x.valor_num.toLocaleString("en-US", { minimumFractionDigits: 2 }) : x.valor_texto })) },
  { nome: "negativo_parenteses", oque: "negativo como (1.234)",
    espera: "o sinal é preservado",
    transformar: (c) => clone(c).map((x) => ({ ...x, valor_texto:
      typeof x.valor_num === "number" && x.valor_num < 0
        ? `(${Math.abs(x.valor_num).toLocaleString("pt-BR")})` : x.valor_texto })) },
  { nome: "sem_subtotais", oque: "o PDF não imprimiu os totais",
    espera: "o modelo soma as folhas sem inventar total",
    transformar: (c) => clone(c).filter((x) =>
      !/^total\b|^ativo total|^passivo total|receita operacional bruta/i.test(x.chave)) },
  { nome: "subtotal_diverge_da_soma", oque: "o TOTAL impresso não bate com a soma",
    espera: "a diferença vira resíduo declarado",
    transformar: (c) => clone(c).map((x) =>
      /^total\b|^ativo total|^passivo total/i.test(x.chave) && typeof x.valor_num === "number"
        ? { ...x, valor_num: Math.round(x.valor_num * 1.03) } : x) },
  { nome: "truncado", oque: "30% das linhas perdidas no fatiamento",
    espera: "a cobertura acusa",
    transformar: (c) => clone(c).filter((_, i) => i % 10 >= 3) },
  { nome: "entidade_vazia", oque: "sem entidade_coluna em nenhuma linha",
    espera: "cai na entidade do documento",
    transformar: (c) => clone(c).map((x) => ({ ...x, entidade_coluna: null })) },
  { nome: "empresa_unica", oque: "mandato de UMA empresa, não de grupo",
    espera: "o caso mais comum da mesa continua fechando",
    transformar: (c) => clone(c).map((x) => ({ ...x, entidade_coluna: null }))
      .filter((x, i, a) => a.findIndex((y) => y.documento_versao_id === x.documento_versao_id
        && y.chave === x.chave && y.periodo_coluna === x.periodo_coluna) === i) },
  { nome: "patrimonio_a_descoberto", oque: "PL negativo — o normal da mesa",
    espera: "ROE e alavancagem se recusam em vez de publicar múltiplo que se lê como saúde",
    transformar: (c) => clone(c).map((x) => x.secao_canonica === "patrimonio_liquido"
      && typeof x.valor_num === "number" ? { ...x, valor_num: -Math.abs(x.valor_num) * 3 } : x) },
  { nome: "caixa_negativo", oque: "conta bancária a descoberto",
    espera: "liquidez imediata negativa é leitura CORRETA (numerador negativo), não defeito",
    transformar: (c) => clone(c).map((x) => /caixa|banco|aplica(ç|c)(õ|o)es/i.test(x.chave)
      && typeof x.valor_num === "number" ? { ...x, valor_num: -Math.abs(x.valor_num) } : x) },
  { nome: "divida_maior_que_o_ativo", oque: "insolvência: dívida acima do ativo",
    espera: "nada pode parecer confortável",
    transformar: (c) => clone(c).map((x) =>
      /empr(é|e)stimo|financiamento|debentures?|banco/i.test(x.chave) && typeof x.valor_num === "number"
        ? { ...x, valor_num: Math.abs(x.valor_num) * 8 } : x) },
  { nome: "so_balanco_sem_dre", oque: "o cliente mandou só os balanços",
    espera: "monta com o que tem e não inventa resultado",
    transformar: (c) => clone(c).filter((x) => !ehDe(x, /DRE|DEMONSTRACAO_RESULTADO/i)) },
  { nome: "sem_mapa_de_divida", oque: "sem mapa de dívida — só o balanço",
    espera: "a dívida vem do balanço, com prazo implícito",
    transformar: (c) => clone(c).filter((x) => !ehDe(x, /MAPA_DIVIDA|DIVIDA/i)) },
  { nome: "documento_duplicado", oque: "o mesmo documento duas vezes na leva",
    espera: "as linhas não contam duas vezes",
    transformar: (c) => { const b = clone(c); const v0 = b[0]?.documento_versao_id;
      return [...b, ...b.filter((x) => x.documento_versao_id === v0)
        .map((x) => ({ ...x, id: `${x.id}-c`, ordem: (x.ordem ?? 0) + 5000 }))]; } },
  { nome: "balancete_de_mil_linhas", oque: "balancete analítico grande",
    espera: "volume não muda resultado",
    transformar: (c) => { const b = clone(c);
      return [...b, ...[1, 2].flatMap((k) => b.slice(0, 200).map((x) => ({ ...x, id: `${x.id}-v${k}`,
        chave: `${x.chave} — subconta ${k}`, valor_num: 0, valor_texto: "0,00",
        ordem: (x.ordem ?? 0) + 20000 * k })))]; } },
  { nome: "valor_nao_finito", oque: "NaN e Infinity vindos do JSON da extração",
    espera: "não-número não vira zero",
    transformar: (c) => clone(c).map((x, i) => i % 31 === 0
      ? { ...x, valor_num: (i % 62 === 0 ? Infinity : NaN) as unknown as number } : x) },
  { nome: "acentos_perdidos", oque: "PDF sem acentuação",
    espera: "acento não é identidade de conta",
    transformar: (c) => clone(c).map((x) => ({
      ...x, chave: x.chave.normalize("NFD").replace(/[\u0300-\u036f]/g, "") })) },
  { nome: "campos_rejeitados", oque: "o analista rejeitou parte das linhas",
    espera: "linha rejeitada não entra no modelo",
    transformar: (c) => clone(c).map((x, i) => i % 6 === 0 ? { ...x, status_aceite: "rejeitado" } : x) },
  { nome: "hash_repetido", oque: "o mesmo arquivo enviado 14 vezes",
    espera: "a dedup (0118) colapsa em 1 documento com 14 versões e o arquivo explica",
    transformar: (c) => c, hashUnico: true, modelagemNaoMonta: true },
];

// ---------------------------------------------------------------------------
// A AUDITORIA de cada rodada. Cada item devolve `null` (passou) ou o defeito.
// ---------------------------------------------------------------------------
interface Achado { variacao: string; item: string; detalhe: string; }
const achados: Achado[] = [];
/** Resíduo do CHECK por variação — publicado SEMPRE, inclusive onde ele é esperado. */
const residuo = new Map<string, number>();
const registrar = (variacao: string, item: string, detalhe: string) =>
  achados.push({ variacao, item, detalhe });

const ERRO_EXCEL = /#(REF|VALUE|DIV\/0|NAME|NUM|N\/A|NULL)!?/;

function auditarWorkbook(v: string, wb: ExcelJS.Workbook, abreDeProposito = false, naoMonta = false) {
  // (1) Nenhuma célula com erro literal do Excel.
  let erros = 0; const ondeErro: string[] = [];
  wb.eachSheet((ws) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      for (let c = 1; c <= ws.columnCount; c++) {
        const cell = ws.getRow(r).getCell(c);
        const val = cell.value as unknown;
        const txt = typeof val === "string" ? val
          : (val && typeof val === "object" && "error" in (val as object)) ? String((val as { error: unknown }).error)
          : (val && typeof val === "object" && "result" in (val as object)) ? String((val as { result: unknown }).result)
          : "";
        if (ERRO_EXCEL.test(txt)) { erros++; if (ondeErro.length < 5) ondeErro.push(`${ws.name}!${cell.address}=${txt}`); }
      }
    }
  });
  if (erros > 0) registrar(v, "célula com erro do Excel", `${erros} célula(s): ${ondeErro.join(", ")}`);

  const out = wb.getWorksheet("Output");
  if (!out) {
    // A ausência do Output só é achado quando ela NÃO era o comportamento pedido.
    // Onde é, o que se cobra é a explicação: aba que não existe não diz por quê.
    if (!naoMonta) {
      registrar(v, "aba Output ausente", "o export não montou o modelo institucional");
      // A EXPLICAÇÃO PODE ESTAR EM DUAS ABAS, e as duas contam: a do caminho "sem
      // exercício numérico" e a do caminho "sem entidade reconhecida", que já
      // existia. Procurar só por um nome fazia a auditoria acusar ausência de
      // explicação num arquivo que explicava — e régua que erra assim ensina a
      // ignorar régua.
    } else if (!wb.getWorksheet("Modelagem não montada")
               && !wb.worksheets.some((w) => /modelagem/i.test(w.name)
                  && /não montad/i.test(String(w.getRow(1).getCell(1).value ?? "")))) {
      registrar(v, "a modelagem não montou E não explicou",
        "sem a aba de explicação o analista não distingue 'não montou' de 'não rodou'");
    }
    return;
  }
  if (naoMonta) {
    registrar(v, "a modelagem montou onde NÃO devia",
      "sem exercício com valor numérico, projetar inventaria a série inteira");
  }
  esquecerMemoria(out);
  const acharLinha = (re: RegExp) => {
    for (let r = 1; r <= out.rowCount; r++) {
      if (re.test(String(out.getRow(r).getCell(3).value ?? ""))) return r;
    }
    return 0;
  };
  const COLS = ["E", "F", "G", "H", "I", "J", "K"];

  // (2) O BALANÇO TEM DE FECHAR — nos DOIS lugares que o afirmam: o `Mismatch` do
  //     Output e o CHECK da própria aba de balanço. Conferir só um deixaria passar
  //     o caso em que o espelho concorda consigo mesmo e discorda da origem.
  const rMis = acharLinha(/^Mismatch \(ASSETS/);
  if (!rMis) registrar(v, "o Output perdeu a linha de Mismatch", "o modelo deixou de publicar o próprio invariante");
  else {
    let pior = 0, ondePior = "";
    for (const c of COLS) {
      const x = avaliarCelula(out, c, rMis);
      if (typeof x === "number" && Math.abs(x) > Math.abs(pior)) { pior = x; ondePior = c; }
    }
    residuo.set(v, pior);
    if (Math.abs(pior) >= 1 && !abreDeProposito) {
      registrar(v, "o balanço NÃO fecha (Mismatch do Output)", `pior resíduo ${pior.toFixed(2)} na coluna ${ondePior}`);
    }
    if (Math.abs(pior) < 1 && abreDeProposito) {
      registrar(v, "o balanço fecha onde NÃO devia fechar",
        "a variante destrói as âncoras; fechar em zero significaria inventar o total que o documento não trouxe");
    }
  }
  const bs = wb.getWorksheet("Balance Sheet");
  if (!bs) registrar(v, "aba Balance Sheet ausente", "o modelo institucional não montou");
  else {
    esquecerMemoria(bs);
    let rC = 0;
    for (let r = 1; r <= bs.rowCount; r++) {
      if (/^CHECK — Ativo/.test(String(bs.getRow(r).getCell(3).value ?? ""))) { rC = r; break; }
    }
    if (!rC) registrar(v, "o Balance Sheet perdeu o CHECK", "o invariante do balanço saiu da aba de origem");
    else {
      let pior = 0, onde = "";
      for (const c of COLS) {
        const x = avaliarCelula(bs, c, rC);
        if (typeof x === "number" && Math.abs(x) > Math.abs(pior)) { pior = x; onde = c; }
      }
      if (Math.abs(pior) >= 1 && !abreDeProposito) {
        registrar(v, "o balanço NÃO fecha (CHECK do Balance Sheet)", `pior resíduo ${pior.toFixed(2)} na coluna ${onde}`);
      }
    }
    // (2b) As linhas de RECONCILIAÇÃO declaram o que o modelo não conseguiu casar.
    for (let r = 1; r <= bs.rowCount; r++) {
      const rot = String(bs.getRow(r).getCell(3).value ?? "");
      if (!/^reconcilia..o com/i.test(rot)) continue;
      let pior = 0, onde = "";
      for (const c of COLS) {
        const x = avaliarCelula(bs, c, r);
        if (typeof x === "number" && Math.abs(x) > Math.abs(pior)) { pior = x; onde = c; }
      }
      if (Math.abs(pior) >= 1 && !abreDeProposito) {
        registrar(v, "resíduo de reconciliação", `${rot.trim().slice(0, 58)} — ${pior.toFixed(0)} (coluna ${onde})`);
      }
    }
  }

  // (3) NENHUM covenant pode acusar rompimento a partir de razão que não existe.
  //     Se a razão publica texto ("PC=0"), o teste ao lado tem de dizer "n.a.".
  for (const [rot, nome] of [
    [/^Liquidez corrente/, "liquidez corrente"],
    [/^Net Debt \/ EBITDA/, "ND/EBITDA"],
    [/^Cobertura do serviço|^DSCR/, "DSCR"],
  ] as const) {
    const r = acharLinha(rot as RegExp);
    if (!r) continue;
    for (const c of COLS) {
      const razao = avaliarCelula(out, c, r);
      const veredito = avaliarCelula(out, c, r + 2);
      if (typeof razao !== "number" && typeof veredito === "string"
          && /ROMPE/.test(veredito)) {
        registrar(v, "covenant acusa rompimento sem razão calculável",
          `${nome}, coluna ${c}: razão=${JSON.stringify(razao)} veredito=${JSON.stringify(veredito)}`);
      }
    }
  }

  // (3b) A GUARDA DA LIQUIDEZ TEM DE DISPARAR quando o denominador não é positivo.
  //
  // Auditar o INVARIANTE e não o efeito: antes eu só olhava "saiu múltiplo
  // negativo?", e isso não religava a correção — desfazendo a guarda, a variante
  // que a expôs produzia PC exatamente ZERO e o texto antigo ("PC=0") também não
  // era número. Aqui a pergunta é direta: com PC ≤ 0, a célula PODE ser número?
  {
    const rPC = acharLinha(/^Current Liabilities$/);
    for (const [rot, nome] of [
      [/^Liquidez corrente/, "liquidez corrente"],
      [/^Liquidez seca/, "liquidez seca"],
      [/^Liquidez imediata/, "liquidez imediata"],
    ] as const) {
      const r = acharLinha(rot as RegExp);
      if (!r || !rPC) continue;
      // O ATIVO CIRCULANTE NEGATIVO ENTRA JUNTO, e a diferença com o caixa é o
      // ponto: conta bancária a descoberto é fato, e liquidez imediata negativa
      // lê certo. ATIVO circulante negativo não existe em balanço coerente — a
      // razão sobre ele não é leitura, é número sem base.
      const rAC = acharLinha(/^Current Assets$/);
      for (const c of COLS) {
        const pc = avaliarCelula(out, c, rPC);
        const ac = rAC ? avaliarCelula(out, c, rAC) : null;
        const denRuim = typeof pc === "number" && pc <= 0;
        const numRuim = /corrente|seca/.test(nome) && typeof ac === "number" && ac < 0;
        if (!denRuim && !numRuim) continue;
        const x = avaliarCelula(out, c, r);
        if (typeof x === "number") {
          registrar(v, "índice de liquidez publica número sobre base impossível",
            `${nome}, coluna ${c} = ${x.toFixed(3)} (ativo circ. ${String(ac)}, passivo circ. ${String(pc)})`);
        }
      }
    }
  }

  // (3c) A DÍVIDA NÃO PODE EVAPORAR na virada para o projetado.
  //
  // O invariante: se havia dívida no último realizado e ela cai na primeira coluna
  // projetada, a queda tem de ser explicada por AMORTIZAÇÃO. Dívida que some sem
  // pagamento é a mentira mais lisonjeira que este arquivo pode contar — e foi
  // exatamente o que uma variante encontrou (37.719 sumindo).
  {
    const div = wb.getWorksheet("ST Inv. & Debt");
    if (div) {
      esquecerMemoria(div);
      const achaEm = (ws: ExcelJS.Worksheet, re: RegExp) => {
        for (let r = 1; r <= ws.rowCount; r++) {
          if (re.test(String(ws.getRow(r).getCell(3).value ?? ""))) return r;
        }
        return 0;
      };
      const rCP = achaEm(div, /^Dívida de curto prazo \(fim do per/);
      const rLP = achaEm(div, /^Dívida de longo prazo \(fim do per/);
      const rAm = achaEm(div, /^Amortização de dívida no per/);
      // A última coluna histórica e a primeira projetada, pelo cabeçalho de anos.
      const iUlt = COLS.length - 1;
      for (let k = 1; k <= iUlt; k++) {
        const antes = [rCP, rLP].filter(Boolean)
          .map((r) => avaliarCelula(div, COLS[k - 1], r)).filter((x): x is number => typeof x === "number");
        const depois = [rCP, rLP].filter(Boolean)
          .map((r) => avaliarCelula(div, COLS[k], r)).filter((x): x is number => typeof x === "number");
        if (antes.length === 0 || depois.length === 0) continue;
        const a = antes.reduce((x, y) => x + y, 0);
        const d = depois.reduce((x, y) => x + y, 0);
        const am = rAm ? avaliarCelula(div, COLS[k], rAm) : 0;
        const amort = typeof am === "number" ? Math.abs(am) : 0;
        // Só interessa a queda GRANDE e sem amortização que a explique.
        if (a > 1 && d < a * 0.05 && amort < a * 0.5) {
          registrar(v, "a dívida EVAPORA na virada para o projetado",
            `de ${a.toFixed(0)} para ${d.toFixed(0)} entre ${COLS[k - 1]} e ${COLS[k]}, `
            + `com amortização de apenas ${amort.toFixed(0)}`);
          break;
        }
      }
    }
  }

  // (4) MÚLTIPLO NEGATIVO SÓ É ACHADO QUANDO O SINAL VEM DO DENOMINADOR.
  //
  // A distinção não é sutileza: é o que separa defeito de verdade útil. Alavancagem
  // com PL negativo dá múltiplo NEGATIVO que se lê como "quase sem dívida" — sinal
  // trocado fazendo o ruim parecer bom, e é defeito. Liquidez imediata com CAIXA
  // negativo (conta a descoberto) também dá múltiplo negativo, e ali o número diz
  // exatamente o que está acontecendo — recusá-lo seria esconder informação.
  //
  // A régua, então: negativo com numerador ≥ 0 é impossível e vira achado; negativo
  // porque o numerador é negativo é a leitura correta e passa.
  const rBSPC = acharLinha(/^Current Liabilities$/);
  const rBSAC = acharLinha(/^Current Assets$/);
  const rBSCX = acharLinha(/^Cash & Short/);
  for (const [rot, nome, rNum] of [
    [/^Dívida bruta \/ Patrim/, "alavancagem sobre PL", 0],
    [/^Liquidez corrente/, "liquidez corrente", rBSAC],
    [/^Liquidez seca/, "liquidez seca", rBSAC],
    [/^Liquidez imediata/, "liquidez imediata", rBSCX],
  ] as const) {
    const r = acharLinha(rot as RegExp);
    if (!r) continue;
    for (const c of COLS) {
      const x = avaliarCelula(out, c, r);
      // Tolerância: −0,000 é arredondamento de ponto flutuante, não leitura.
      if (typeof x !== "number" || x >= -0.01) continue;
      const num = rNum ? avaliarCelula(out, c, rNum as number) : 0;
      const den = rBSPC ? avaliarCelula(out, c, rBSPC) : 0;
      const numNegativo = typeof num === "number" && num < 0;
      if (numNegativo) continue;   // negativo porque o numerador é: leitura correta
      registrar(v, "índice publica múltiplo negativo com numerador não-negativo",
        `${nome}, coluna ${c} = ${x.toFixed(3)} (numerador ${String(num)}, denominador ${String(den)})`);
    }
  }
}

// ---------------------------------------------------------------------------
// UMA RODADA.
// ---------------------------------------------------------------------------
async function rodar(v: Variacao) {
  const db = `tdf_var_${v.nome}`;
  psql(`drop database if exists "${db}"`, "postgres");
  psql(`create database "${db}" template ${MOLDE}`, "postgres");

  // Campos transformados, agrupados por versão de documento.
  const porVersao = new Map<string, CampoExtraido[]>();
  for (const c of v.transformar(fixture.campos)) {
    const l = porVersao.get(c.documento_versao_id) ?? [];
    l.push(c); porVersao.set(c.documento_versao_id, l);
  }

  // FASE 1 — o produtor real.
  const produzidos = new Map<string, Array<Record<string, unknown>>>();
  let falhasDoNo = 0;
  for (const [versaoId, campos] of porVersao) {
    const req = { json: { documento_versao_id: versaoId, tipo: "BALANCO", ia_body: {} } };
    try {
      const out = await rodarNo("Parse Extracao", respostaDaIA(campos, v.moeda), { "Montar Req Extracao": req });
      produzidos.set(versaoId, (out.json.campos ?? []) as Array<Record<string, unknown>>);
    } catch (e) {
      falhasDoNo++;
      registrar(v.nome, "o nó Parse Extracao ESTOUROU", String(e).slice(0, 200));
    }
  }
  if (falhasDoNo === 0 && produzidos.size === 0) {
    registrar(v.nome, "o produtor não emitiu campo nenhum", "porVersao vazio");
  }

  // FASE 2 — banco.
  const casoId = psql(`insert into caso (nome) values ('var ${v.nome}') returning id`, db).trim();
  for (const doc of fixture.documentos) {
    const versao = doc.documento_versao?.[0];
    if (!versao) continue;
    const ent = doc.entidade?.razao_social ?? null;
    const per = doc.periodo;
    const perTipo = v.semPeriodo ? null : (v.periodoTipo ?? per?.tipo ?? null);
    const perRef = v.semPeriodo ? null : (per?.referencia ?? null);
    const hash = v.hashUnico ? `H-${v.nome}-UNICO` : `H-${v.nome}-${versao.id}`;
    const r = psql(`select fn_registrar_documento(
      ${lit(casoId)}, ${lit(ent)}, ${lit(perTipo)}, ${lit(perRef)},
      ${lit(v.tipoUnico ?? doc.tipo_taxonomia)}, 0.9, 'nome_arquivo', 'supabase_storage',
      ${lit(`b/${versao.id}.pdf`)},
      ${lit(versao.nome_original ?? "x.pdf")}, null, ${lit(hash)}, 'ok')::text`, db).trim();
    const novaVersao = JSON.parse(r).documento_versao_id as string;
    const campos = produzidos.get(versao.id) ?? [];
    // POR ARQUIVO, não por `-c`: um balancete analítico grande estourava o ARG_MAX
    // do processo (`spawnSync psql E2BIG`). É limite do arnês, não do sistema — em
    // produção o JSON vai por HTTP —, e consertá-lo é o que faz o arnês conseguir
    // testar VOLUME, que era justamente a variante que ele derrubava.
    mkdirSync(`${RAIZ}Verificação/saida`, { recursive: true });
    const tmp = `${RAIZ}Verificação/saida/_campos-${v.nome}.sql`;
    writeFileSync(tmp, `select fn_registrar_campos_extraidos(${lit(novaVersao)}, `
      + `$json$${JSON.stringify(campos)}$json$::jsonb, 'N0', null);`);
    execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-d", db, "-f", tmp],
      { cwd: RAIZ, stdio: "pipe" });
  }
  psql(`select fn_recomputar_completude(${lit(casoId)})`, db);

  const gravadas = Number(psql(`select count(*) from campo_extraido ce
    join documento_versao dv on dv.id = ce.documento_versao_id
    join documento d on d.id = dv.documento_id where d.caso_id = ${lit(casoId)}`, db).trim());
  const emitidas = [...produzidos.values()].reduce((s, x) => s + x.length, 0);
  if (gravadas !== emitidas) {
    registrar(v.nome, "o banco não gravou o que o produtor emitiu", `emitidas=${emitidas} gravadas=${gravadas}`);
  }

  const pend = psqlJson<Array<{ tipo: string; descricao: string }>>(
    `select tipo, descricao from pendencia where caso_id = ${lit(casoId)} and estado <> 'resolvida'`, db);

  // FASE 3 — ler como o portal lê e montar o export.
  const documentos = psqlJson<DocumentoParaExport[]>(`
    select d.id, d.tipo_taxonomia, d.status::text as status,
           json_build_object('razao_social', e.razao_social) as entidade,
           json_build_object('tipo', p.tipo::text, 'referencia', p.referencia) as periodo,
           json_agg(json_build_object('id', dv.id, 'nome_original', dv.nome_original)) as documento_versao
      from documento d
      left join entidade e on e.id = d.entidade_id
      left join periodo p on p.id = d.periodo_id
      join documento_versao dv on dv.documento_id = d.id
     where d.caso_id = ${lit(casoId)}
     group by d.id, d.tipo_taxonomia, d.status, e.razao_social, p.tipo, p.referencia
     order by e.razao_social nulls last, d.id`, db);
  const campos = psqlJson<CampoExtraido[]>(`
    select ce.* from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
     where d.caso_id = ${lit(casoId)}`, db);

  // A MODELAGEM, montada como a produção monta (mesmo caminho de
  // `gerar-export-do-banco.mts`): parâmetros do caso, premissas ativas, vínculos,
  // e as séries por ano vindas das funções do banco. Sem isto o export sai só com
  // as abas de dado, e o pedido é justamente o arquivo de MODELAGEM.
  // A ENTIDADE MODELADA É ESCOLHIDA DE FORMA DETERMINÍSTICA, e isto não é
  // preciosismo de teste: a primeira versão pegava `documentos[0]`, e como a
  // consulta não tinha `order by`, o Postgres devolvia ordem diferente entre
  // rodadas. Duas variações modelaram empresas DIFERENTES do grupo e eu quase
  // creditei ao sistema uma divergência de 2.985 células que era minha.
  // Critério: a entidade com MAIS linhas extraídas, desempate alfabético.
  const entidadeModelada = psqlJson<Array<{ razao_social: string }>>(`
    select e.razao_social
      from campo_extraido ce
      join documento_versao dv on dv.id = ce.documento_versao_id
      join documento d on d.id = dv.documento_id
      join entidade e on e.id = d.entidade_id
     where d.caso_id = ${lit(casoId)} and e.razao_social is not null
     group by e.razao_social
     order by count(*) desc, e.razao_social
     limit 1`, db)[0]?.razao_social ?? null;
  const ULTIMO_REAL = 2025;
  let modeloInstitucional: EntradaModeloInstitucional | undefined;
  if (entidadeModelada) {
    psql(`insert into caso_modelagem (caso_id, entidade, ultimo_exercicio_real, anos_projetados, atualizado_por)
          values (${lit(casoId)}, ${lit(entidadeModelada)}, ${ULTIMO_REAL}, 5, 'variacoes')
          on conflict (caso_id) do update set entidade = excluded.entidade,
            ultimo_exercicio_real = excluded.ultimo_exercicio_real`, db);

    // Ativa as premissas sugeridas para o setor — é o que a tela oferece por padrão.
    const sugeridas = psqlJson<Array<{ codigo: string }>>(
      `select codigo from fn_premissas_sugeridas(null)`, db);
    for (const sg of sugeridas.slice(0, 12)) {
      try {
        psql(`select fn_ativar_premissa(${lit(casoId)}, ${lit(sg.codigo)},
              '{"2026":0.1,"2027":0.1,"2028":0.1,"2029":0.1,"2030":0.1}'::jsonb, 'digitado', 'variacoes')`, db);
      } catch { /* premissa que o catálogo não aceita neste caso — não é o alvo do arnês */ }
    }
    const premissas = psqlJson<Array<{ codigo: string; nome: string; formula: string; unidade: string | null;
      natureza: string; origem: string | null; valores: Record<string, number> }>>(`
      select cp.premissa_codigo as codigo, pc.nome, pc.formula::text as formula, pc.unidade,
             pc.natureza::text as natureza, cp.origem, cp.valores
        from caso_premissa cp join premissa_catalogo pc on pc.codigo = cp.premissa_codigo
       where cp.caso_id = ${lit(casoId)} and cp.ativo`, db);
    const vinculos = psqlJson<Array<{ rotulo_norm: string; premissa_codigo: string | null;
      sazonalidade_codigo: string | null }>>(
      `select rotulo_norm, premissa_codigo, sazonalidade_codigo
         from caso_linha_premissa where caso_id = ${lit(casoId)}`, db);
    const linhasRpc = psqlJson<Array<{ secao_canonica: string | null; chave: string; rotulo_norm: string;
      papel: LinhaModelo["papel"]; unidade: string | null; moeda: string | null; documentos: string[] | null }>>(
      `select * from fn_linhas_para_modelagem(${lit(casoId)})`, db);
    const valores = psqlJson<Array<{ rotulo_norm: string; secao_canonica: string | null; ano: number; valor: number }>>(
      `select rotulo_norm, secao_canonica, ano, valor
         from fn_valores_por_ano(${lit(casoId)}, ${lit(entidadeModelada)})`, db);

    const anosHistoricos = [...new Set(valores.map((x) => x.ano))].filter((a) => a <= ULTIMO_REAL).sort((a, b) => a - b);
    const anosProjetados = Array.from({ length: 5 }, (_, i) => ULTIMO_REAL + 1 + i);
    const series = seriesPorLinha(valores, anosHistoricos);
    const linhasModelo: LinhaModelo[] = linhasRpc.map((l) => ({
      secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
      papel: l.papel, unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
      valores: serieDaLinha(series, l.secao_canonica, l.rotulo_norm),
    }));
    const cont = new Map<string, number>();
    for (const l of linhasModelo) if (l.unidade) cont.set(l.unidade, (cont.get(l.unidade) ?? 0) + 1);
    const dominante = [...cont.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
    modeloInstitucional = {
      caso: { nome: `Variação ${v.nome}`, produto: "reestruturacao" },
      agora: new Date("2026-08-22T12:00:00Z"),
      entidade: entidadeModelada, setor: null,
      anosHistoricos, anosProjetados,
      stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
      linhas: linhasModelo, premissas,
      vinculos: vinculos.map((x) => ({ rotulo_norm: x.rotulo_norm, premissa_codigo: x.premissa_codigo,
        sazonalidade_codigo: x.sazonalidade_codigo })),
      macro: [],
      unidade: dominante === "milhar" ? "R$ mil" : dominante === "unidade" ? "R$" : (dominante ?? "R$"),
    } as EntradaModeloInstitucional;
  } else {
    registrar(v.nome, "nenhuma entidade chegou ao export", "sem entidade o modelo institucional nem é montado");
  }

  let wb: ExcelJS.Workbook | null = null;
  try {
    wb = buildExportWorkbook({
      caso: { nome: `Variação ${v.nome}`, produto: "reestruturacao" },
      documentos, campos, agora: new Date("2026-08-22T12:00:00Z"),
      modeloInstitucional,
    });
  } catch (e) {
    registrar(v.nome, "o EXPORT ESTOUROU", String(e).slice(0, 300));
  }
  if (wb) {
    // O ARQUIVO FICA EM DISCO. Auditoria que só existe em memória não deixa nada
    // para conferir à mão depois — e o `auditar-xlsx.mts` roda sobre arquivo.
    mkdirSync(`${RAIZ}Verificação/saida`, { recursive: true });
    await wb.xlsx.writeFile(`${RAIZ}Verificação/saida/modelagem-${v.nome}.xlsx`);
    auditarWorkbook(v.nome, wb, v.balancoAbreDeProposito === true, v.modelagemNaoMonta === true);
  }

  if (!MANTER) psql(`drop database if exists "${db}"`, "postgres");
  return { linhas: gravadas, pendencias: pend.length, tiposPend: [...new Set(pend.map((p) => p.tipo))] };
}

// ---------------------------------------------------------------------------
const alvo = SO ? VARIACOES.filter((v) => v.nome === SO) : VARIACOES;
if (alvo.length === 0) { console.error(`variação "${SO}" não existe`); process.exit(2); }

console.log(`ARNÊS DE VARIAÇÕES — ${alvo.length} rodada(s), cadeia real, zero chamada de API\n`);
garantirMolde();
const resumo: Array<Record<string, unknown>> = [];
for (const v of alvo) {
  const antes = achados.length;
  process.stdout.write(`— ${v.nome.padEnd(24)} ${v.oque.slice(0, 60).padEnd(62)}`);
  let r: Awaited<ReturnType<typeof rodar>> | null = null;
  try {
    r = await rodar(v);
  } catch (e) {
    registrar(v.nome, "a RODADA estourou", String(e).slice(0, 300));
  }
  const novos = achados.length - antes;
  console.log(novos === 0 ? "ok" : `${novos} achado(s)`);
  resumo.push({ variacao: v.nome, ...r, achados: novos, espera: v.espera });
}

console.log(`\n${"=".repeat(78)}\nRESUMO\n${"=".repeat(78)}`);
console.log(`${"variação".padEnd(26)}${"linhas".padStart(8)}${"pend.".padStart(7)}${"resíduo".padStart(12)}${"achados".padStart(9)}`);
for (const r of resumo) {
  const res = residuo.get(String(r.variacao));
  // O RESÍDUO APARECE SEMPRE. Onde ele é esperado vai marcado com *, e não some
  // do relatório — esconder o número da variação que "pode abrir" é como um
  // portão deixa de medir.
  const marca = (VARIACOES.find((v) => v.nome === r.variacao)?.balancoAbreDeProposito) ? "*" : " ";
  console.log(
    `${String(r.variacao).padEnd(26)}${String(r.linhas ?? "-").padStart(8)}${String(r.pendencias ?? "-").padStart(7)}` +
    `${(res === undefined ? "-" : res.toFixed(0)).padStart(11)}${marca}${String(r.achados).padStart(9)}`);
}
console.log("\n* balanço que abre DE PROPÓSITO: a variante destrói as âncoras ou o eixo do tempo, e");
console.log("  fechar exigiria inventar o número que o documento não trouxe. O que se cobra ali é");
console.log("  que o sistema DECLARE — e o resíduo acima é essa declaração.");

if (achados.length > 0) {
  console.log(`\n${"=".repeat(78)}\nACHADOS (${achados.length})\n${"=".repeat(78)}`);
  for (const a of achados) console.log(`  [${a.variacao}] ${a.item}\n      ${a.detalhe}`);
}
mkdirSync(`${RAIZ}Verificação/saida`, { recursive: true });
writeFileSync(`${RAIZ}Verificação/saida/variacoes.json`, JSON.stringify({ resumo, achados }, null, 2));
console.log(`\n${achados.length} achado(s) no total. Detalhe em Verificação/saida/variacoes.json`);
