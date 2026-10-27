// Validação ENCADEADA: extração → banco → export, num só fluxo.
//
// Por que ela precisou existir. As três suítes do projeto são estanques:
//
//   N8N/test/*.test.mjs            libs + nós simulados. Não toca banco nem export.
//   Supabase/test/run.sh                 funções SQL contra uma fixture escrita em Python.
//   portal/scripts/verificar-*.mts export a partir de uma fixture JSON.
//
// As duas fixtures vêm da MESMA origem (`Supabase/test/gerar_fixture.py`, com `--json`),
// então elas concordam entre si. O que ninguém cobria é a COSTURA: nada roda o
// produtor real de campos e verifica que o que ele emite é o que o SQL grava e o
// que o export lê. Cada seam era afirmado à mão nas duas pontas — e as duas pontas
// podem estar erradas juntas.
//
// Foi essa classe de defeito que produziu os bugs mais caros deste repositório:
// a entidade que vinha vazia (o produtor não emitia o campo), a RLS que devolvia
// zero linhas (o leitor não chegava no dado), a escala que era gravada e nunca
// aplicada (o consumidor ignorava o campo). Nenhum dos três é visível olhando um
// lado só.
//
// Rodar (o socket local usa peer auth, então quem troca de usuário é o psql):
//   E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" npx tsx Verificação/run.mts
//
// Num Postgres em que o usuário do checkout já tem acesso, basta:
//   npx tsx Verificação/run.mts
//
// Cria e destrói o próprio banco (`tdf_e2e`), não toca em Supabase e não chama
// chamada de IA nenhuma — o insumo é o book determinístico de `Dados de Teste/book-vertentes`.

import { execFileSync } from "node:child_process";
import { readFileSync, readdirSync } from "node:fs";
import { buildExportWorkbook } from "../portal/src/lib/export.ts";
import type { CampoExtraido, DocumentoParaExport } from "../portal/src/lib/types.ts";
import { avaliarCelula } from "../portal/scripts/lib/avaliar-formula.mts";
import { provedor } from "../N8N/lib/provedor.mjs";

// O ARNÊS FALA O DIALETO DO PROVEDOR ATIVO. Ele injeta a resposta no ponto em
// que a IA responde, então escrevê-la na forma da OpenAI enquanto o nó lê a do
// Google significaria testar a cadeia inteira contra uma resposta que o nó não
// entende — e o sintoma seria "zero campos", exatamente o silêncio que este
// arnês existe para não deixar passar.
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
const DB = process.env.E2E_DB ?? "tdf_e2e";

let ok = 0;
const falhas: string[] = [];
function checar(cond: boolean, desc: string, detalhe = "") {
  if (cond) {
    ok += 1;
    console.log(`ok    ${desc}`);
  } else {
    falhas.push(`${desc}${detalhe ? ` — ${detalhe}` : ""}`);
    console.log(`FALHOU ${desc}${detalhe ? ` — ${detalhe}` : ""}`);
  }
}

// ---------------------------------------------------------------------------
// psql como cliente. Evita dependência de driver: o portal não tem `pg`, e
// acrescentar dependência de produção para um teste seria pior que um exec.
// ---------------------------------------------------------------------------
// O comando é configurável porque o socket local do Postgres usa peer auth: o
// arnês roda como o usuário do checkout, e o cluster só aceita o usuário `postgres`.
// `npx` como `postgres` não funciona (HOME e certs diferentes), então quem troca de
// usuário é o psql, não o Node.
//   E2E_PSQL="sudo -u postgres psql" npx tsx Verificação/run.mts
const PSQL = (process.env.E2E_PSQL ?? "psql").split(/\s+/);
function psql(sql: string, db = DB): string {
  return execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-A", "-t", "-d", db, "-c", sql], {
    encoding: "utf8",
    cwd: RAIZ,
  });
}
function psqlJson<T>(sql: string): T {
  const out = psql(`select coalesce(json_agg(t), '[]'::json) from (${sql}) t`).trim();
  return JSON.parse(out) as T;
}

// ---------------------------------------------------------------------------
// FASE 1 — o produtor REAL de campos.
//
// Reconstrói a resposta da IA a partir do book e roda o código do nó
// `Parse Extracao` extraído do JSON GERADO (não a lib): é o mesmo padrão de
// `N8N/test/workflow-sim.test.mjs`, e é o que garante que o que se testa é o que
// o dono importa no n8n.
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

const gabarito = JSON.parse(
  readFileSync(`${RAIZ}Dados de Teste/book-vertentes/pdf/GABARITO.json`, "utf8"),
) as Record<string, unknown>;

// Campos do book agrupados por versão, para montar uma resposta por documento.
const camposPorVersao = new Map<string, CampoExtraido[]>();
for (const c of fixture.campos) {
  const lista = camposPorVersao.get(c.documento_versao_id) ?? [];
  lista.push(c);
  camposPorVersao.set(c.documento_versao_id, lista);
}

// A resposta da IA usa chaves CURTAS (s/sc/ec/pc/k/vt/vn/op/cf) — foi uma
// otimização de custo de output. Reconstruí-las aqui é o que exercita o mapeamento
// curto→longo do nó, que é exatamente um dos seams não cobertos.
function respostaDaIA(campos: CampoExtraido[]) {
  const unidade = campos.find((c) => c.unidade)?.unidade ?? null;
  return {
    json: envelopeDaResposta(
      JSON.stringify({
        moeda: "BRL",
        unidade,
        diagnostico: {
          entidade: null,
          tipo_confirma: true,
          tipo_sugerido: "BALANCO",
          periodo_tipo: "anual",
          periodo_referencia: "12M25",
          legibilidade: "ok",
          nota_legibilidade: null,
          resumo: "e2e",
          justificativa: "e2e",
        },
        linhas: campos.map((c, i) => ({
          s: c.secao,
          sc: c.secao_canonica ?? "NAO_CLASSIFICAVEL",
          ec: c.entidade_coluna,
          pc: c.periodo_coluna,
          k: c.chave,
          vt: c.valor_texto,
          vn: c.valor_num,
          op: c.origem_pagina,
          cf: c.confianca ?? 0.9,
          ordem: i,
        })),
      }),
      { prompt_tokens: 1000, completion_tokens: 500 },
    ),
  };
}

console.log("== fase 1: o produtor real de campos (nó Parse Extracao)");
const camposDoProdutor = new Map<string, Array<Record<string, unknown>>>();
for (const [versaoId, campos] of camposPorVersao) {
  const req = { json: { documento_versao_id: versaoId, tipo: "BALANCO", ia_body: {} } };
  const out = await rodarNo("Parse Extracao", respostaDaIA(campos), { "Montar Req Extracao": req });
  camposDoProdutor.set(versaoId, out.json.campos as Array<Record<string, unknown>>);
}

// AVISO DE CONTEÚDO (item 1 do §7.4): o que o preparo já sabia estar faltando
// ANTES da chamada tem de virar `falha_motivo` — que é o que a 0016 converte em
// pendência visível. O caminho passa por DOIS nós (Preparar Conteudo → Montar Req
// Extracao → Parse Extracao) e nenhuma das outras suítes o atravessa: aqui roda o
// código real do nó, com o aviso vindo pela referência, como em produção.
{
  const [versaoId, campos] = [...camposPorVersao.entries()][0];
  const aviso = "Planilha maior que o teto de envio: 137 de 2137 linhas não foram enviadas à extração (teto de 2000).";
  const req = { json: { documento_versao_id: versaoId, tipo: "BALANCO", aviso_conteudo: aviso, ia_body: {} } };
  const out = await rodarNo("Parse Extracao", respostaDaIA(campos), { "Montar Req Extracao": req });
  const motivo = String(out.json.falha_motivo ?? "");
  checar(motivo.includes("137 de 2137 linhas"),
    "o aviso do preparo de conteúdo chega a falha_motivo (vira pendência)", motivo.slice(0, 120));
  checar((out.json.campos as unknown[]).length === campos.length,
    "…e as linhas que VIERAM continuam valendo — o aviso não descarta extração");

  const semAviso = await rodarNo("Parse Extracao", respostaDaIA(campos),
    { "Montar Req Extracao": { json: { documento_versao_id: versaoId, tipo: "BALANCO", ia_body: {} } } });
  checar(semAviso.json.falha_motivo == null,
    "…e sem aviso nenhum o motivo continua nulo (nada de pendência inventada)",
    String(semAviso.json.falha_motivo));
}

const totalProduzido = [...camposDoProdutor.values()].reduce((s, v) => s + v.length, 0);
checar(
  totalProduzido === fixture.campos.length,
  "o nó real produz o mesmo número de linhas que a fixture afirma",
  `nó=${totalProduzido} fixture=${fixture.campos.length}`,
);

// A COSTURA propriamente dita: o vocabulário de campos que o produtor emite tem de
// ser o que o banco grava e o export lê. Se o nó parar de emitir `secao_canonica`
// (ou passar a chamá-lo de outra coisa), NENHUMA das três suítes atuais percebe —
// a fixture continuaria afirmando o campo dos dois lados.
const CAMPOS_DO_CONTRATO = [
  "ordem", "secao", "secao_canonica", "entidade_coluna", "periodo_coluna",
  // `moeda` (0035): entrou no contrato porque era EXATAMENTE isto que faltava —
  // a extração calculava a moeda e nenhum campo a levava ao banco. Se o nó
  // parar de emitir, esta lista reprova aqui, que é o único lugar onde o
  // vocabulário do produtor é confrontado com o que o banco grava.
  "chave", "valor_texto", "valor_num", "unidade", "moeda", "confianca", "origem_pagina",
];
{
  const umaLinha = [...camposDoProdutor.values()][0][0];
  const faltando = CAMPOS_DO_CONTRATO.filter((k) => !(k in umaLinha));
  checar(faltando.length === 0, "o produtor emite todo o vocabulário que o banco grava", `faltando: ${faltando.join(", ")}`);
}

// ---------------------------------------------------------------------------
// FASE 2 — o banco REAL, pelas funções REAIS.
// ---------------------------------------------------------------------------
console.log("\n== fase 2: gravar pelas funções reais do Postgres");
psql(`drop database if exists ${DB}`, "postgres");
psql(`create database ${DB}`, "postgres");
// Bootstrap do que o Supabase provê por padrão e as migrations assumem. É o MESMO
// de `Supabase/test/run.sh` — inclusive `storage.buckets`, sem o qual a 0003 não aplica,
// e, até 20/10/2026, o GRANT default de tabela, que a 0028 mostrou ser indispensável para um defeito
// de AUTORIZAÇÃO ser sequer visível num teste local. O default saiu junto com o de `Supabase/test/run.sh`: o
// Supabase deixa de concedê-lo em 30/10/2026 e quem concede agora é a 0214 (e a migration de cada tabela).
// Mantê-los idênticos importa:
// dois bootstraps diferentes produziriam duas verdades diferentes sobre o schema.
// E O SCHEMA `auth` (27/10/2026): a 0215 cria FK para `auth.users` e lê `auth.uid()`. É o mesmo mínimo que
// `Supabase/test/run.sh` monta, com o mesmo corpo — sem ele a 0215 morre em "schema auth does not exist".
psql(`
  do $$ begin
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
  create table if not exists auth.users(id uuid primary key default gen_random_uuid(), email text,
    email_confirmed_at timestamptz, banned_until timestamptz, deleted_at timestamptz, is_anonymous boolean not null default false);
  create or replace function auth.uid() returns uuid language sql stable as $f$
    select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid $f$;
  grant usage on schema auth to authenticated, service_role;
  grant execute on function auth.uid() to anon, authenticated, service_role;
  grant select on auth.users to service_role;
  grant usage on schema public to anon, authenticated, service_role;
`);
// A LISTA DAS MIGRATIONS SAI DO DISCO, E NÃO DE UM SHELL. Até aqui ela vinha de
// `bash -c "ls Supabase/migrations/*.sql"`: o `bash` era resolvido pelo PATH
// herdado do processo, então um executável com esse nome num diretório gravável
// que aparecesse antes na busca rodaria no lugar do shell — e o que este trecho
// faz em seguida é aplicar migrations com o psql. `readdirSync` lê o mesmo
// diretório sem criar processo nenhum, e o `sort()` reproduz a ordem
// lexicográfica do `ls`, que é a ordem em que as migrations TÊM de ser
// aplicadas (é o prefixo numérico do nome que as ordena).
// LISTA VAZIA É FALHA, NÃO SILÊNCIO. O `bash -c "ls .../*.sql"` que estava aqui
// antes ESTOURAVA quando o glob não casava nada (o ls sai 2 e o execFileSync
// lança) — barulhento, e essa era a única coisa boa dele. O `readdirSync` que o
// substituiu devolve `[]` sem reclamar: o `for` não roda, nenhuma migration é
// aplicada, e a linha seguinte anuncia sucesso do mesmo jeito. Basta a próxima
// reorganização mover as migrations para um subdiretório (`migrations/2026/`)
// para o diretório continuar existindo, o filtro devolver zero, e a suíte seguir
// contra um banco VAZIO até morrer adiante com um erro de tabela inexistente que
// ninguém liga a esta linha. É o `estagio-desligado-parece-limpo` da memória,
// trocado de lugar. A contagem exata não é fixada de propósito: ela mudaria a
// cada migration nova e reprovaria pelo motivo errado; quem confere o número é o
// `Supabase/test/run.sh`, contra o README.
const MIGRATIONS = readdirSync(`${RAIZ}Supabase/migrations`)
  .filter((nome) => nome.endsWith(".sql"))
  .sort()
  .map((nome) => `Supabase/migrations/${nome}`);
if (MIGRATIONS.length === 0) {
  throw new Error(
    `Nenhuma migration .sql em ${RAIZ}Supabase/migrations — a suíte estaria rodando contra um banco VAZIO.`);
}
for (const arquivo of MIGRATIONS) {
  execFileSync(PSQL[0], [...PSQL.slice(1), "-v", "ON_ERROR_STOP=1", "-q", "-d", DB, "-f", arquivo], { cwd: RAIZ, stdio: "pipe" });
}
console.log(`   ${MIGRATIONS.length} migrations aplicadas`);

const casoId = psql(`insert into caso (nome) values ('e2e book vertentes') returning id`).trim();

// Registra cada documento pela função de produção e grava os campos que o NÓ
// produziu (não os da fixture) — é isso que fecha a costura produtor→banco.
for (const doc of fixture.documentos) {
  const versaoOriginal = doc.documento_versao?.[0];
  if (!versaoOriginal) continue;
  const ent = (doc.entidade?.razao_social ?? "").replace(/'/g, "''");
  const per = doc.periodo;
  const r = psql(`select fn_registrar_documento(
    '${casoId}', ${ent ? `'${ent}'` : "null"},
    ${per ? `'${per.tipo}'` : "null"}, ${per ? `'${per.referencia}'` : "null"},
    ${doc.tipo_taxonomia ? `'${doc.tipo_taxonomia}'` : "null"}, 0.9, 'nome_arquivo',
    'supabase_storage', 'b/${versaoOriginal.id}.pdf',
    '${(versaoOriginal.nome_original ?? "x.pdf").replace(/'/g, "''")}',
    null, 'HASH-E2E-${versaoOriginal.id}', 'ok')::text`).trim();
  const novaVersao = JSON.parse(r).documento_versao_id as string;

  const campos = camposDoProdutor.get(versaoOriginal.id) ?? [];
  const json = JSON.stringify(campos).replace(/'/g, "''");
  psql(`select fn_registrar_campos_extraidos('${novaVersao}', '${json}'::jsonb, 'N0', null)`);
}
psql(`select fn_recomputar_completude('${casoId}')`);

const nLinhas = Number(psql(`select count(*) from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id where d.caso_id = '${casoId}'`).trim());
checar(nLinhas === fixture.campos.length, "o banco gravou todas as linhas que o produtor emitiu", `banco=${nLinhas}`);

// O contrato do fixture: extração FIEL não abre pendência de reconciliação. É o que
// `gerar_fixture.py` documenta como cenário ("o arquivo foi 100% extraído").
const pendencias = psqlJson<Array<{ tipo: string; descricao: string }>>(
  `select tipo, descricao from pendencia where caso_id = '${casoId}' and estado <> 'resolvida'`,
);
const reconc = pendencias.filter((p) => p.tipo.startsWith("reconciliacao"));
checar(
  reconc.length === 0,
  "extração fiel não abre pendência de reconciliação (contrato do fixture)",
  reconc.map((p) => p.descricao?.slice(0, 100)).join(" | "),
);

// ---------------------------------------------------------------------------
// FASE 3 — ler de volta como o portal lê, e montar o export.
// ---------------------------------------------------------------------------
console.log("\n== fase 3: ler como o portal lê e montar o export");
const documentos = psqlJson<DocumentoParaExport[]>(`
  select d.id, d.tipo_taxonomia, d.status::text as status,
         json_build_object('razao_social', e.razao_social) as entidade,
         json_build_object('tipo', p.tipo, 'referencia', p.referencia) as periodo,
         (select json_agg(json_build_object('id', dv.id, 'n_versao', dv.n_versao, 'nome_original', dv.nome_original)
                          order by dv.n_versao)
            from documento_versao dv where dv.documento_id = d.id) as documento_versao
  from documento d
  left join entidade e on e.id = d.entidade_id
  left join periodo  p on p.id = d.periodo_id
  where d.caso_id = '${casoId}'
`);
const campos = psqlJson<CampoExtraido[]>(`
  select ce.id, ce.documento_versao_id, ce.secao, ce.secao_canonica, ce.entidade_coluna,
         ce.periodo_coluna, ce.chave, ce.valor_texto, ce.valor_num, ce.unidade, ce.confianca,
         ce.origem_pagina, ce.ordem, ce.status_aceite::text as status_aceite, ce.aceito_por,
         ce.aceito_em
  from campo_extraido ce
  join documento_versao dv on dv.id = ce.documento_versao_id
  join documento d on d.id = dv.documento_id
  where d.caso_id = '${casoId}'
  order by ce.ordem nulls last
`);

checar(documentos.length === fixture.documentos.length, "o portal lê todos os documentos", `leu ${documentos.length}`);
checar(campos.length === fixture.campos.length, "o portal lê todas as linhas", `leu ${campos.length}`);

const wb = buildExportWorkbook({
  caso: { nome: "e2e book vertentes", produto: "reestruturacao" },
  documentos,
  campos,
  agora: new Date("2026-07-31T12:00:00Z"),
});

const abas = wb.worksheets.map((w) => w.name);
for (const obrigatoria of ["Resumo", "Balanço", "DRE", "Modelagem"]) {
  checar(abas.includes(obrigatoria), `a aba "${obrigatoria}" existe no book gerado ponta a ponta`);
}

// ---------------------------------------------------------------------------
// FASE 4 — conferir contra o GABARITO do book.
// ---------------------------------------------------------------------------
console.log("\n== fase 4: conferir contra o gabarito determinístico do book");
const resumo = wb.getWorksheet("Resumo")!;
const valorResumo = (rot: string) => {
  for (let r = 1; r <= resumo.rowCount; r++) {
    if (String(resumo.getRow(r).getCell(1).value ?? "") === rot) return String(resumo.getRow(r).getCell(2).value ?? "");
  }
  return "";
};
checar(
  valorResumo("Linhas totais extraídas") === String(fixture.campos.length),
  "o Resumo anuncia o mesmo total que o banco tem",
  valorResumo("Linhas totais extraídas"),
);
// A escala do book Vertentes é milhar (as demonstrações) — a fatia 3 fez o export
// declarar isso, e aqui a declaração é conferida ponta a ponta.
checar(/R\$ mil/.test(valorResumo("Escala dos valores")), "a escala declarada é a do book", valorResumo("Escala dos valores"));

// Números do gabarito. Só os que o gabarito expõe como escalares — o objetivo aqui
// é provar que a CADEIA preserva o número, não reauditar o export (que já tem 146
// invariantes próprios).
// Confere os SUBTOTAIS NOMEADOS que o gabarito publica para a DRE da Metalúrgica.
// São o teste certo para a cadeia: cada um é um número que o book calcula a partir
// de várias linhas, então bater com ele prova que produtor → banco → export não
// perdeu nem deslocou nenhuma delas.
//
// O que NÃO se confere aqui, e por quê: `gabarito.receita_bruta_2025` (138.400) não
// existe como subtotal no export. A seção agrupa receita bruta E deduções sob
// "Receita Bruta e Deduções", então o subtotal dela é a receita LÍQUIDA. As três
// contas de receita aparecem individualmente e somam 138.400, mas não há linha de
// "Receita Bruta". É escolha de apresentação, não defeito — e fica registrada aqui
// porque foi o que meu primeiro assert cobrou por engano.
{
  const dre = wb.getWorksheet("DRE");
  const subtotais = (gabarito as { dre_metalurgica_2025?: Record<string, number> }).dre_metalurgica_2025 ?? {};
  // O export emite FÓRMULA, não valor: ler `cell.value` cru devolveria
  // `{formula: "SUM(...)"}` e o assert nasceria vazio (aconteceu na 1ª rodada).
  // `avaliarCelula` é o mesmo avaliador dos 146 invariantes do export.
  const valoresResolvidos: number[] = [];
  if (dre) {
    for (let r = 1; r <= dre.rowCount; r++) {
      for (const col of ["B", "C", "D", "E", "F", "G", "H"]) {
        const v = avaliarCelula(dre, col, r);
        if (typeof v === "number") valoresResolvidos.push(v);
      }
    }
  }
  for (const [nome, esperado] of Object.entries(subtotais)) {
    const achou = valoresResolvidos.some((v) => Math.abs(v - esperado) < 1);
    const perto = valoresResolvidos
      .slice()
      .sort((a, b) => Math.abs(a - esperado) - Math.abs(b - esperado))[0];
    checar(
      achou,
      `o subtotal "${nome}" do gabarito (${esperado}) sobreviveu à cadeia produtor→banco→export`,
      `mais próximo: ${perto}`,
    );
  }
  checar(Object.keys(subtotais).length >= 3, "o gabarito publica subtotais suficientes para valer como conferência");
}

// ---------------------------------------------------------------------------
// FASE 5 — a COSTURA da Etapa 3: a BASE DO MODELO é o mesmo número da aba.
//
// A Modelagem deixou de ler as abas de dados por fórmula e passou a receber os
// valores escritos. Isso cria uma junta nova, e ela é exatamente do tipo que
// esta suíte existe para cobrir: duas cópias do mesmo número, produzidas por
// caminhos diferentes, que podem divergir sem ninguém perceber. Um invariante
// do export não pega — lá as duas pontas nascem da mesma fixture.
//
// Aqui a corrente é inteira: PDF do book → nó real de extração → funções reais
// do Postgres → export. Se a base do modelo divergir da aba de origem, é
// porque a cópia se perdeu no caminho.
// ---------------------------------------------------------------------------
console.log("\n== fase 5: a base do modelo é o mesmo número que a aba mostra");
{
  const mod = wb.getWorksheet("Modelagem");
  const dre = wb.getWorksheet("DRE");
  checar(mod != null && dre != null, "as abas Modelagem e DRE existem");
  if (mod && dre) {
    // Nenhuma fórmula da Modelagem pode citar outra aba — a Etapa 3 inteira em
    // uma linha, conferida sobre o arquivo que a cadeia real produziu.
    const citadas = new Set<string>();
    for (let r = 1; r <= mod.rowCount; r++) {
      for (let c = 1; c <= mod.columnCount; c++) {
        const v = mod.getRow(r).getCell(c).value as { formula?: string } | undefined;
        if (v?.formula) for (const m of v.formula.matchAll(/'([^']+)'!/g)) citadas.add(m[1]);
      }
    }
    checar(citadas.size === 0,
      "nenhuma fórmula da Modelagem referencia outra aba (Etapa 3), no arquivo da cadeia real",
      `cita: ${[...citadas].join(", ")}`);

    // E o número: "DRE · Receita Líquida" da base tem de existir, resolvido,
    // na aba DRE.
    let rBase = -1;
    for (let r = 1; r <= mod.rowCount; r++) {
      if (String(mod.getRow(r).getCell(1).value ?? "") === "DRE · Receita Líquida") { rBase = r; break; }
    }
    checar(rBase > 0, "a base do modelo traz a linha \"DRE · Receita Líquida\"");
    const naBase: number[] = [];
    if (rBase > 0) {
      for (let c = 2; c <= mod.columnCount; c++) {
        const v = mod.getRow(rBase).getCell(c).value;
        if (typeof v === "number") naBase.push(v);
      }
    }
    checar(naBase.length > 0, "…com pelo menos um exercício preenchido", `${naBase.length} valores`);

    const naDre: number[] = [];
    for (let r = 1; r <= dre.rowCount; r++) {
      for (const col of ["B", "C", "D", "E", "F", "G", "H"]) {
        const v = avaliarCelula(dre, col, r);
        if (typeof v === "number") naDre.push(v);
      }
    }
    for (const v of naBase) {
      checar(naDre.some((x) => Math.abs(x - v) < 1),
        `a Receita Líquida ${v} da base do modelo é a MESMA que a aba DRE mostra`,
        `mais próximo na DRE: ${naDre.slice().sort((a, b) => Math.abs(a - v) - Math.abs(b - v))[0]}`);
    }
  }
}

// ---------------------------------------------------------------------------
// FASE 6 — O MODELO INSTITUCIONAL REPRODUZ O DOCUMENTO.
//
// POR QUE ESTA FASE EXISTE, e por que ela é o portão que faltava. As fases 1 a 5
// provam a cadeia até as abas ANALÍTICAS. O modelo institucional — as 14 abas que
// o dono manda para comitê — nunca foi conferido contra o gabarito por NENHUMA
// suíte: o `verificar-export` monta o modelo a partir de uma entrada escrita à
// mão, e uma entrada escrita à mão não descobre o que a cadeia real faz com o
// dado real.
//
// O custo disso, medido na sessão 40 no arquivo que o dono exportou: a DRE
// realizada saiu com receita líquida de 170.220 onde o documento diz 106.580 e
// resultado de +268.041 onde o documento diz −17.901 — 100+ PRs verdes, e o único
// juiz foi o dono abrindo o .xlsx.
//
// Aqui o modelo é montado pelas MESMAS consultas da rota de export (é o que
// `gerar-export-do-banco.mts` replica) e cada linha de resultado é comparada com o
// gabarito do book, com tolerância de 1 centavo. Sem premissa nenhuma de propósito:
// o que está sob teste é a FIDELIDADE DO REALIZADO, não a projeção.
// ---------------------------------------------------------------------------
console.log("\n== fase 6: o modelo institucional reproduz o documento");
{
  const ENTIDADE = "VERTENTES METALÚRGICA LTDA.";
  const ULTIMO_REAL = 2025;
  psql(`select fn_definir_modelagem('${casoId}', '${ENTIDADE}', ${ULTIMO_REAL}, 'IPCA', 'industria', 'e2e', 3)`);

  type LinhaSql = {
    chave: string; rotulo_norm: string; papel: string; secao_canonica: string | null;
    unidade: string | null; moeda: string | null; documentos: string[] | null;
  };
  const linhasSql = psqlJson<LinhaSql[]>(`select chave, rotulo_norm, papel::text as papel,
      secao_canonica, unidade, moeda, documentos
    from fn_linhas_para_modelagem('${casoId}')`);
  const valoresSql = psqlJson<Array<{ rotulo_norm: string; ano: number; valor: number }>>(
    `select rotulo_norm, ano, valor from fn_valores_por_ano('${casoId}', '${ENTIDADE}')`);

  const porRotulo = new Map<string, Record<string, number>>();
  const anos = new Set<number>();
  for (const v of valoresSql) {
    if (v.ano > ULTIMO_REAL) continue;
    anos.add(v.ano);
    if (!porRotulo.has(v.rotulo_norm)) porRotulo.set(v.rotulo_norm, {});
    porRotulo.get(v.rotulo_norm)![String(v.ano)] = Number(v.valor);
  }
  const anosHistoricos = [...anos].sort((a, b) => a - b);
  checar(anosHistoricos.length >= 2,
    "o caso do book tem pelo menos dois exercícios realizados (é o que faz a série valer como base)",
    JSON.stringify(anosHistoricos));

  const wbModelo = buildExportWorkbook({
    caso: { nome: "e2e book vertentes", produto: "reestruturacao" },
    documentos, campos, agora: new Date("2026-07-31T12:00:00Z"), modo: "completo",
    modeloInstitucional: {
      caso: { nome: "e2e book vertentes", produto: "reestruturacao" },
      agora: new Date("2026-07-31T12:00:00Z"),
      entidade: ENTIDADE, setor: "industria",
      anosHistoricos, anosProjetados: [2026, 2027, 2028],
      stressPct: 0.2, caixaMinimo: 0, aliquotaTributos: 0.34,
      linhas: linhasSql.map((l) => ({
        secao_canonica: l.secao_canonica, chave: l.chave, rotulo_norm: l.rotulo_norm,
        papel: l.papel as "conta" | "subtotal" | "derivado" | "serie_mensal",
        unidade: l.unidade, moeda: l.moeda, documentos: l.documentos,
        valores: porRotulo.get(l.rotulo_norm) ?? {},
      })),
      // Nenhuma premissa: o que se confere aqui é o REALIZADO. Projeção sem premissa
      // mantém as contas constantes, que é o comportamento declarado do modelo.
      premissas: [], vinculos: [], macro: [], unidade: "R$ mil",
    },
  });

  const is = wbModelo.getWorksheet("Income Statement");
  const bs = wbModelo.getWorksheet("Balance Sheet");
  checar(!!is && !!bs, "o modelo institucional foi construído pela cadeia real (banco → export)");

  /** Linha da aba pelo rótulo exato da coluna C, e o valor avaliado na coluna do ano. */
  const linhaPorRotulo = (ws: NonNullable<typeof is>, rotulo: string) => {
    for (let r = 1; r <= ws.rowCount; r++) {
      if (String(ws.getRow(r).getCell(3).value ?? "").trim() === rotulo) return r;
    }
    return null;
  };
  const COL = ["E", "F", "G", "H", "I"]; // 2024, 2025, 2026, 2027, 2028
  const iDe = (ano: number) => anosHistoricos.indexOf(ano);

  if (is && bs) {
    // O GABARITO DA DRE, exercício a exercício. O book publica os subtotais de 2025;
    // os de 2024 vêm da mesma cascata (`dre_metalurgica_2025` é o nome do bloco, o
    // conteúdo tem os dois anos nas abas). Aqui usa-se o que o gabarito expõe.
    const sub = (gabarito as { dre_metalurgica_2025?: Record<string, number> }).dre_metalurgica_2025 ?? {};
    const paresDRE: Array<[string, string]> = [
      ["NET REVENUES", "RECEITA OPERACIONAL LÍQUIDA"],
      ["GROSS PROFIT", "LUCRO BRUTO"],
      ["EBIT", "RESULTADO OPERACIONAL ANTES DO RESULTADO FINANCEIRO"],
      ["NET PROFIT", "PREJUÍZO LÍQUIDO DO EXERCÍCIO"],
    ];
    for (const [rotuloModelo, chaveGabarito] of paresDRE) {
      const esperado = sub[chaveGabarito];
      if (esperado === undefined) continue;
      const r = linhaPorRotulo(is, rotuloModelo);
      const v = r === null ? null : avaliarCelula(is, COL[iDe(2025)], r);
      checar(typeof v === "number" && Math.abs(v - esperado) < 0.01,
        `(fase 6) o modelo institucional reproduz "${chaveGabarito}" de 2025 (${esperado}) — `
        + "é o número que o arquivo entregue errava",
        `modelo: ${JSON.stringify(v)}`);
    }

    // O BALANÇO: cada grupo e o total, contra o gabarito por entidade e ano.
    const bpGab = (gabarito as {
      balanco_por_entidade?: Record<string, Record<string, Record<string, number>>>;
    }).balanco_por_entidade ?? {};
    for (const ano of anosHistoricos) {
      const g = bpGab[String(ano)]?.metalurgica;
      if (!g) continue;
      for (const [rotulo, chaveGab] of [
        ["ATIVO CIRCULANTE", "AC"], ["ATIVO NÃO CIRCULANTE", "ANC"], ["ATIVO TOTAL", "ATIVO"],
        ["PASSIVO CIRCULANTE", "PC"], ["PASSIVO NÃO CIRCULANTE", "PNC"], ["PATRIMÔNIO LÍQUIDO", "PL"],
      ] as const) {
        const esperado = g[chaveGab];
        if (esperado === undefined) continue;
        const r = linhaPorRotulo(bs, rotulo);
        const v = r === null ? null : avaliarCelula(bs, COL[iDe(ano)], r);
        checar(typeof v === "number" && Math.abs(v - esperado) < 0.01,
          `(fase 6) "${rotulo}" de ${ano} é o do documento (${esperado})`,
          `modelo: ${JSON.stringify(v)}`);
      }
    }

    // E O CHECK FECHA — em todo exercício, realizado e projetado.
    const rCheck = linhaPorRotulo(bs, "CHECK — Ativo − (Passivo + PL) deve ser ZERO");
    const desvios: string[] = [];
    for (let i = 0; i < anosHistoricos.length + 3; i++) {
      const v = rCheck === null ? null : avaliarCelula(bs, COL[i], rCheck);
      if (typeof v !== "number") { desvios.push(`col ${COL[i]}: ${JSON.stringify(v)}`); continue; }
      if (Math.abs(v) > 0.01) desvios.push(`col ${COL[i]}: ${v.toFixed(2)}`);
    }
    checar(rCheck !== null && desvios.length === 0,
      "(fase 6) O BALANÇO DO MODELO FECHA na cadeia real, em todos os exercícios",
      desvios.join(" · "));
  }
}

if (!process.env.E2E_MANTER) psql(`drop database if exists ${DB}`, "postgres");

console.log(`\n${ok} verificações OK / ${falhas.length} falhas`);
for (const f of falhas) console.log("  FALHOU:", f);
process.exit(falhas.length ? 1 : 0);
