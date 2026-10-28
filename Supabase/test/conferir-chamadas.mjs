#!/usr/bin/env node
// O QUE O CÓDIGO CHAMA TEM DE EXISTIR NO BANCO EM QUE ELE VAI RODAR.
//
// POR QUE ESTE ARQUIVO EXISTE (medido em 02/09/2026, ensaio de aplicação).
// O `ESTADO.md` declara produção **na 0150**. Montei um banco parado exatamente
// aí — as migrations 0001…0150 e nada além — e perguntei duas coisas:
//
//   • `fn_instalacao_conferir()` → nenhum requisito ausente que importe
//   • os nós Postgres do `workflow.e1-ingestao.json` → **TRÊS não resolvem**
//
//       fn_abrir_lote_execucao(uuid, text, jsonb)      não existe   (0156)
//       fn_reconciliar_caso(uuid)                      não existe   (0152)
//       fn_reconciliar_por_documento(uuid, unknown)    não existe   (0152)
//
// `Abrir Lote` é o primeiro nó depois de o orçamento aprovar o lote. Ou seja: a
// sonda em que o projeto confia diz que a instalação está boa, e a próxima
// rodada morre no começo com `function ... does not exist`.
//
// A sonda não está errada — ela é CEGA por construção, e vale escrever por quê,
// senão alguém vai "consertá-la" no lugar errado: o catálogo dela
// (`instalacao_requisito`) mora DENTRO do banco e é preenchido pelas migrations.
// Um banco parado na 0150 tem o catálogo da 0150; ele não pode conhecer um
// requisito que só a 0156 escreveu. `fn_instalacao_conferir()` responde "o que
// ESTE banco sabe que deveria ter, está aqui?" — e a pergunta que faltava é a
// outra ponta: **"o que o REPOSITÓRIO chama, está aqui?"**. Essa só o
// repositório pode fazer, porque só ele conhece o código que vai rodar.
//
// A TERCEIRA É A QUE JUSTIFICA O DESENHO. `fn_reconciliar_por_documento`
// EXISTE na 0150 — a 0152 lhe acrescentou `p_escopo`. Um conferidor que só
// perguntasse "existe função com este nome?" a daria por presente, e a rodada
// morreria nela do mesmo jeito. Por isso o que se confere aqui é a CHAMADA, com
// `PREPARE`: o Postgres resolve nome e tipos de argumento e recusa o que não
// casa.
//
// É a mesma família de defeito da `0131` e do portão do `Supabase/README.md`:
// entre "corrigido no git" e "corrigido em produção" há um passo manual, e o
// sintoma de ele não ter acontecido é indistinguível de tudo estar bem.
//
// COMO USAR
//
//   # contra o banco de teste local (é o que o CI faz)
//   CONFERIR_DB=tdf_test node Supabase/test/conferir-chamadas.mjs
//
//   # ANTES DA RODADA REAL, contra produção — é para isto que ele serve
//   CONFERIR_PSQL="psql 'postgresql://…@…supabase.co:5432/postgres'" \
//     node Supabase/test/conferir-chamadas.mjs
//
// TRÊS SAÍDAS, e a terceira é a que costuma faltar num portão:
//   0 = tudo o que foi conferido resolve
//   1 = achei chamada que não resolve (a rodada morreria nela)
//   2 = NÃO CONSEGUI CONFERIR — que não é "passou"
//
// É SEGURO APONTAR PARA PRODUÇÃO, e a garantia é estrutural, não boa-fé: toda
// consulta vai dentro de `start transaction read only`, e consulta com mais de
// um comando é RECUSADA antes de chegar ao banco. A revisão desta mudança
// mostrou por que as duas travas são necessárias — `prepare X as <consulta>`
// com um `;` no meio faz o psql executar o segundo comando de verdade, e o
// arranjo medido gravou um `update` no banco apontado. Hoje nenhum dos nós tem
// `;` embutido; a trava é o que impede que amanhã tenha.
//
// O QUE ELE NÃO CONFERE, e a linha de sucesso repete isto em vez de dizer
// "tudo" (regra 1 aplicada ao próprio portão): COLUNAS de `.select(...)`,
// as ASSINATURAS das chamadas do portal (o PostgREST resolve por nome de
// argumento, e aqui só se confere presença) e as POLÍTICAS de RLS. Privilégio
// de `authenticated` é conferido para função e tabela — é a classe da `0028`.
// E resolver não é "a migration foi aplicada corretamente": um
// `create or replace` sobre um corpo velho mantém nome e assinatura. Quem
// confere COMPORTAMENTO é a suíte. O que este arquivo garante é o
// contrapositivo, que é a parte cara: **chamada que não resolve é rodada que
// morre**, e agora ela morre aqui, em segundos, e não depois de 38 uploads.

import { readFileSync, readdirSync, statSync } from "node:fs";
import { join, relative } from "node:path";
import { fileURLToPath } from "node:url";
import { execSync } from "node:child_process";
import { nosPostgresDosWorkflows, NaoConsegui } from "./nos-postgres.mjs";

// `fileURLToPath`, e não `new URL(...).pathname`: este repositório tem
// `Dados de Teste/`, `Arquitetura do Sistema/` e `Verificação/` — caminho com
// espaço e acento é a regra aqui, não a exceção, e `.pathname` os devolve
// percent-encoded (`com%20espa%C3%A7o`), fazendo o `readdirSync` morrer com
// ENOENT num checkout perfeitamente válido.
const RAIZ = fileURLToPath(new URL("../..", import.meta.url));
const PSQL = process.env.CONFERIR_PSQL ?? "psql";
const DB = process.env.CONFERIR_DB ?? "";
const ALVO = `${PSQL}${DB ? ` -d ${DB}` : ""}`;

// Declarados ANTES de `desistir`, que os lê: com `const` depois, a primeira
// desistência (a da prova de conexão) morreria em ReferenceError pela zona morta
// temporal — um portão que estoura em vez de dizer o que houve.
const achados = [];
const naoConferidos = [];

/**
 * "não consegui conferir" tem código próprio, e nunca se confunde com "passou".
 *
 * E ELA PUBLICA O QUE JÁ SE SABIA. Desistir no meio descartava, calado, os achados
 * que as etapas anteriores já tinham colhido — a revisão mediu o caso exato: contra
 * um banco de produção atrasado a que faltasse UMA tabela do portal, o arquivo saía
 * com "não consegui conferir os objetos do portal" e engolia as TRÊS chamadas de nó
 * quebradas que ele existe para denunciar. Achado colhido é resposta dada; só o que
 * falta é que ficou sem medir.
 */
function desistir(...linhas) {
  if (achados.length) {
    console.error(`O QUE JÁ TINHA SIDO ACHADO ANTES DE PARAR (${achados.length}):\n`);
    for (const { origem, detalhe } of achados) console.error(`  ${origem}\n      ${detalhe}`);
    console.error("");
  }
  for (const l of linhas) console.error(l);
  process.exit(2);
}

/**
 * Roda SQL pela ENTRADA PADRÃO — sem citação para o shell errar — dentro de uma
 * transação SOMENTE LEITURA.
 *
 * O retorno distingue as duas falhas que um portão não pode misturar: `erroDoServidor`
 * (o Postgres respondeu `ERROR:`, então a pergunta CHEGOU e a resposta é "não resolve")
 * e a ausência dele (não chegou — conexão, senha, pooler cheio).
 *
 * E NUNCA se devolve `erro.message` do `execSync`: ele começa com a LINHA DE COMANDO
 * inteira, e `CONFERIR_PSQL` carrega a URL do Supabase COM SENHA. A revisão mediu isso
 * — `Command failed: psql "postgresql://usuario:SENHA@…"` saindo num relatório que
 * alguém cola num PR. Só `stderr` do psql sai daqui.
 */
function perguntar(sql) {
  try {
    return {
      ok: true,
      saida: execSync(`${ALVO} -qAt -F'|' -v ON_ERROR_STOP=1`, {
        encoding: "utf8",
        input: `start transaction read only;\n${sql}`,
        stdio: ["pipe", "pipe", "pipe"],
      }),
    };
  } catch (erro) {
    const stderr = String(erro.stderr ?? "");
    // O DISCRIMINADOR É O CÓDIGO DE SAÍDA DO PSQL, NÃO O TEXTO DA MENSAGEM.
    //
    // Ele é documentado e estável: 3 = erro no script com `ON_ERROR_STOP` (o
    // servidor RESPONDEU, e a resposta é "não resolve"), 2 = a sessão não subiu
    // ou caiu (socket, senha, banco inexistente, pooler cheio), 0 = tudo certo.
    // Medido aqui nos quatro casos antes de escrever esta linha.
    //
    // A primeira versão procurava o literal `ERROR:` no stderr, e a revisão
    // acertou o defeito: o Postgres TRADUZ isso (`ERRO:` num servidor pt_BR),
    // e um "function does not exist" de verdade sairia como "PERDI A CONEXÃO".
    // A correção que eu tinha escrito — forçar `lc_messages=C` via `PGOPTIONS`
    // — estava ERRADA por duas medições feitas na verificação:
    //
    //   1. o `sudo` DESCARTA o ambiente, e `CONFERIR_PSQL` começa com
    //      `sudo -u postgres` no comando canônico do CLAUDE.md — `printenv
    //      PGOPTIONS` através dele volta vazio, então a correção era inerte
    //      justamente onde eu a estava exercitando;
    //   2. `lc_messages` é GUC de contexto `superuser` (conferido em
    //      `pg_settings`). Numa conexão de produção cujo papel não seja
    //      superusuário, pedi-lo faz a CONEXÃO falhar — a "correção"
    //      transformaria uma conferência que funciona num exit 2.
    //
    // O código de saída não depende de locale, atravessa o `sudo` e não pede
    // privilégio nenhum. O texto continua sendo usado, mas só para MOSTRAR o
    // motivo ao humano — nunca para decidir.
    const linhaDoErro =
      stderr.split("\n").find((l) => /\b(ERROR|ERRO|FEHLER|ERREUR):/.test(l)) ??
      stderr.split("\n").find((l) => l.trim());
    const erroDoServidor =
      erro.status === 3 ? (linhaDoErro?.replace(/^.*?(?:ERROR|ERRO|FEHLER|ERREUR):\s*/, "").trim() || "erro no servidor") : undefined;
    return { ok: false, stderr: stderr.trim(), erroDoServidor };
  }
}

// ---------------------------------------------------------------------------
// A CONEXÃO SE PROVA UMA VEZ, E O RELATÓRIO DIZ CONTRA QUAL BANCO ELE É VERDE.
//
// Sem a prova, um banco inalcançável faz todo `PREPARE` falhar e o relatório sai
// como quinze chamadas quebradas, mandando aplicar migration quando o que houve
// foi senha errada. E sem o NOME DO BANCO na saída, "CHAMADAS OK" do CI (contra
// `tdf_test`) e "CHAMADAS OK" de produção são byte a byte a mesma linha — um
// colado num handoff não é evidência de nada.
// ---------------------------------------------------------------------------
const prova = perguntar(
  "select current_database(), coalesce(host(inet_server_addr()), 'socket local')," +
    " exists(select 1 from pg_roles where rolname = 'authenticated');",
);
if (!prova.ok) {
  desistir(
    "NÃO FOI POSSÍVEL PERGUNTAR AO BANCO — e isso não é 'passou'.",
    prova.stderr,
    "\nAjuste CONFERIR_PSQL (e CONFERIR_DB) para apontar ao banco que a rodada vai usar.",
  );
}
const [BANCO, SERVIDOR, TEM_AUTHENTICATED] = prova.saida.trim().split("|");
const confereGrant = TEM_AUTHENTICATED === "t";


// ---------------------------------------------------------------------------
// PARTE A — OS NÓS POSTGRES DOS WORKFLOWS, conferidos como CHAMADA.
//
// Varrer o JSON inteiro com uma expressão regular seria mais curto e estaria
// ERRADO: os nós Code deste workflow citam `fn_documento_preliminar` e
// `fn_autoridade_do_documento` em COMENTÁRIO, explicando de que lado do sistema
// a regra mora. Um portão que confunde comentário com chamada exige no banco
// coisas que ninguém invoca — e o dia em que ele acusar de mentira é o dia em
// que se aprende a ignorá-lo. Só `parameters.query` de nó Postgres é chamada.
//
// UMA CONEXÃO POR NÓ, de propósito. Enviar os quinze `PREPARE` juntos seria mais
// rápido e devolveria os erros SEM o nó a que cada um pertence: pela entrada
// padrão o psql não prefixa arquivo:linha, e o `LINE 1:` que ele ecoa não serve
// de âncora porque duas das consultas têm mais de uma linha. O relatório que
// interessa é "o nó X não resolve", não "algo não resolve" — e quinze conexões
// contra o Supabase custam segundos, uma vez, antes de uma rodada de uma hora.
// ---------------------------------------------------------------------------
let nosPostgres, nosDaFamiliaPostgres;
try {
  const extraido = nosPostgresDosWorkflows(RAIZ);
  ({ nosPostgres, nosDaFamiliaPostgres } = extraido);
  naoConferidos.push(...extraido.naoConferidos);
} catch (erro) {
  if (erro instanceof NaoConsegui) desistir(...erro.linhas);
  throw erro;
}

// ESTE CONFERIDOR TEM DE PROVAR QUE ELE PRÓPRIO ESTÁ LIGADO.
//
// Regra 7 do CLAUDE.md aplicada a ele mesmo: "estágio que não rodou tem a mesma
// aparência de estágio que rodou e não achou nada". A extração depende do tipo do
// nó e do nome do parâmetro, e o dia em que uma exportação nova trocar qualquer um
// dos dois a lista vem vazia e o portão fica verde sem medir nada.
if (nosDaFamiliaPostgres === 0) {
  desistir(
    "NÃO ACHEI NÓ POSTGRES NENHUM nos workflows — a extração quebrou.",
    "Zero chamada não é 'nada quebrado': é este conferidor deixando de conferir.",
    "Confira o tipo do nó e o nome do parâmetro em N8N/workflow*.json.",
  );
}
// E a mesma armadilha um passo adiante: achar os nós e não conseguir conferir
// NENHUM (todos em modo expressão, todos multi-statement) chegaria ao fim com
// "CHAMADAS OK" e zero chamada conferida. Declarados um a um, mas o veredito
// final diria que está tudo bem sobre coisa nenhuma.
if (nosPostgres.length === 0) {
  desistir(
    `ACHEI ${nosDaFamiliaPostgres} nó(s) Postgres e não consegui conferir NENHUM:`,
    ...naoConferidos.map(({ origem, porque }) => `  ${origem}\n      ${porque}`),
    "Isso não é 'passou' — é o conferidor sem nada para medir.",
  );
}

// A PROVA DE VIDA ENTRA NA MESMA FILA DAS CHAMADAS DE VERDADE, e a primeira
// versão dela não entrava — ela chamava `perguntar()` por fora e conferia o
// retorno. Isso prova que o psql relata erro; **não** prova que o erro relatado
// vira achado no relatório. Medi a diferença: com a linha `achados.push(...)`
// trocada por um comentário, aquela versão dava `exit 0` e "CHAMADAS OK" sobre o
// banco na 0150 — verde, com o caminho de detecção morto.
//
// Uma chamada que TEM de falhar, percorrendo o laço inteiro e cobrada no fim,
// é o que separa "o portão rodou" de "o portão está ligado" (regra 7). Ela sai
// da lista antes do relatório: é instrumento, não achado.
const CANARIO = "«prova de vida deste conferidor»";
nosPostgres.push({ origem: CANARIO, consulta: "select fn_que_nao_existe_de_proposito($1::int)" });

for (const [i, { origem, consulta }] of nosPostgres.entries()) {
  const r = perguntar(`prepare conferir_${i} as ${consulta};`);
  if (r.ok) continue;
  if (!r.erroDoServidor) {
    // O psql não chegou a falar com o banco (pooler cheio, queda transitória). Isso
    // é "não consegui conferir" e sai com 2 — a `provarConexao` inicial só prova o
    // instante dela, e tratar isto como achado produziria "aplique as migrations"
    // para um problema de rede.
    desistir(`PERDI A CONEXÃO conferindo ${origem} — e isso não é 'passou'.`, r.stderr);
  }
  achados.push({ origem, detalhe: r.erroDoServidor });
}

// O CANÁRIO É COBRADO AQUI, depois de ter percorrido exatamente o mesmo laço que
// as chamadas de verdade. Se ele não virou achado, o caminho de detecção está
// morto e nenhum verde deste arquivo vale nada.
nosPostgres.pop();
const indiceDoCanario = achados.findIndex(({ origem }) => origem === CANARIO);
if (indiceDoCanario === -1) {
  desistir(
    "A PROVA DE VIDA NÃO VIROU ACHADO: uma chamada a função inexistente passou pelo laço sem ser relatada.",
    "O caminho de detecção está quebrado — o verde deste conferidor não vale nada até isto voltar a falhar.",
  );
}
achados.splice(indiceDoCanario, 1);

// ---------------------------------------------------------------------------
// PARTE B — O PORTAL: `.rpc("fn_x")` e `.from("tabela")`.
//
// Aqui a conferência é de PRESENÇA e de PRIVILÉGIO, não de assinatura, e a
// diferença é honesta em vez de preguiçosa: o portal monta a chamada em tempo de
// execução (o cliente do Supabase manda os argumentos como JSON ao PostgREST),
// então não existe, no repositório, um texto SQL para dar ao `PREPARE`. A linha
// de sucesso declara esse limite em vez de dizer "tudo".
//
// O PRIVILÉGIO ENTRA PORQUE ELE É A `0028`, e o conferidor roda como DONO
// enquanto o portal roda como `authenticated`: função presente sem
// `grant execute` e tabela presente sem policy respondem "permission denied" ou
// zero linha em produção, com o objeto ali, existindo. 66 migrations deste
// repositório emitem `grant execute … to authenticated` justamente por isso.
//
// Tabela entra junto com função porque o modo de falhar é o mesmo e o sintoma é
// PIOR: o PostgREST responde 404 na relação ausente e o cliente devolve
// `{ data: null, error }`. Uma tela que trate `data` como lista vazia mostra
// "nenhum documento" — o corte silencioso de leitura.
// ---------------------------------------------------------------------------
const doPortal = new Map(); // `${tipo}:${nome}` → Set de arquivos

function exigir(tipo, nome, onde) {
  const chave = `${tipo}:${nome}`;
  if (!doPortal.has(chave)) doPortal.set(chave, new Set());
  doPortal.get(chave).add(onde);
}

// `Array.from(lista)` e `Buffer.from(x)` não são tabelas. Hoje os quatro
// `Array.from` do portal têm argumento não-literal e nenhum casaria, mas o
// portão não pode depender disso: exigir uma relação `public.abc` por causa de
// um `Buffer.from("abc")` é acusar de mentira.
// `supabase.storage.from("documentos")` também não: é o BUCKET do Storage, não uma
// relação do Postgres — a rota "Ver no original" (28/10/2026) fez o portão exigir
// `public.documentos` e reprovar com o bucket existindo. Casa SÓ o `.storage.from(`
// (receptor exatamente `storage` e precedido de ponto): um sufixo `storage$` no
// regex acima calaria também `const storage = supabase; storage.from("caso")` ou
// `admstorage.from(…)`, e a tabela real deixaria de ser exigida sem ruído
// (revisão do PR #265).
const NAO_SAO_TABELAS = /(?:Array|Buffer|Object|Date|String|Number|Promise)$/;
const ehBucketDoStorage = (fonte, m) => m[1] === "storage" && /\.\s*$/.test(fonte.slice(0, m.index));

function varrer(dir) {
  for (const entrada of readdirSync(dir)) {
    const caminho = join(dir, entrada);
    if (statSync(caminho).isDirectory()) {
      varrer(caminho);
      continue;
    }
    // `.js`/`.jsx`/`.mjs` entram junto com o TypeScript: uma rota escrita em JS
    // sairia da varredura sem ruído nenhum, encolhendo o conjunto conferido com o
    // portão continuando verde. É a mesma armadilha da Parte A, um andar abaixo.
    if (!/\.(ts|tsx|mts|js|jsx|mjs)$/.test(entrada)) continue;
    const fonte = readFileSync(caminho, "utf8");
    const onde = relative(RAIZ, caminho);
    for (const m of fonte.matchAll(/\.rpc\(\s*["'`]([a-z0-9_]+)["'`]/g)) exigir("funcao", m[1], onde);
    for (const m of fonte.matchAll(/([A-Za-z_$][\w$]*)\s*\.from\(\s*["'`]([a-z0-9_]+)["'`]/g)) {
      if (!NAO_SAO_TABELAS.test(m[1]) && !ehBucketDoStorage(fonte, m)) exigir("relacao", m[2], onde);
    }
  }
}
try {
  varrer(join(RAIZ, "portal", "src"));
} catch (erro) {
  desistir(`NÃO CONSEGUI LER portal/src — ${erro.message}`);
}

const lista = [...doPortal.keys()].sort();

// Mesma razão do bloco equivalente da Parte A: a varredura depende da forma
// `.rpc("…")`/`.from("…")` no fonte, e lista vazia aqui é a extração quebrada,
// não um portal que não fala com o banco.
if (lista.length === 0) {
  desistir(
    "NÃO ACHEI CHAMADA NENHUMA em portal/src — a varredura quebrou.",
    "Zero chamada não é 'nada quebrado': é este conferidor deixando de conferir.",
  );
}

function lit(s) {
  return `'${s.replace(/'/g, "''")}'`;
}

// `to_regclass` devolve NULL no objeto ausente em vez de levantar exceção — é o
// que a `0131` escolheu, pela mesma razão. Para função NÃO se usa `to_regproc`:
// ela ERRA em nome sobrecarregado, e sobrecarga existe aqui
// (`fn_reconciliar_por_documento` ganhou `p_escopo` na 0152). Daí o `pg_proc`.
const sql = lista
  .map((chave) => {
    const [tipo, nome] = chave.split(":");
    const acha = `from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace where ns.nspname = 'public' and p.proname = ${lit(nome)}`;
    return tipo === "funcao"
      ? `select ${lit(chave)} as k, exists(select 1 ${acha}) as existe, ` +
          (confereGrant
            ? `exists(select 1 ${acha} and has_function_privilege('authenticated', p.oid, 'EXECUTE')) as pode`
            : `true as pode`)
      : // O PRIVILÉGIO PERGUNTA PELO OID, NÃO PELO NOME, e a diferença não é estilo:
        // `has_table_privilege('authenticated', 'public.x', 'SELECT')` LEVANTA
        // `relation "public.x" does not exist` quando a tabela falta, e o `coalesce`
        // não pega exceção. Como as ~50 linhas vão num `union all` só, UMA tabela
        // ausente derrubava a Parte B inteira: o arquivo saía com "não consegui
        // conferir os objetos do portal", exit 2, engolindo as outras ausências E as
        // chamadas de nó já achadas. Contra um banco de produção atrasado — o caso
        // que este arquivo existe para cobrir — a resposta virava "não sei".
        // Na forma de OID, `to_regclass` devolve NULL e a função devolve NULL sem
        // levantar; a coluna `existe` já responde por esse caso.
        `select ${lit(chave)} as k, to_regclass('public.' || ${lit(nome)}) is not null as existe, ` +
          (confereGrant
            ? `coalesce(has_table_privilege('authenticated', to_regclass('public.' || ${lit(nome)}), 'SELECT'), false) as pode`
            : `true as pode`);
  })
  .join("\nunion all\n");

const rPortal = perguntar(sql);
if (!rPortal.ok) {
  desistir("NÃO FOI POSSÍVEL CONFERIR OS OBJETOS DO PORTAL — e isso não é 'passou'.", rPortal.stderr);
}

for (const linha of rPortal.saida.trim().split("\n")) {
  const [chave, existe, pode] = linha.split("|");
  const [tipo, nome] = chave.split(":");
  const origem = [...(doPortal.get(chave) ?? [])].sort().join(", ");
  if (existe !== "t") achados.push({ origem, detalhe: `${tipo} ${nome} não existe neste banco` });
  else if (pode !== "t") {
    achados.push({
      origem,
      detalhe: `${tipo} ${nome} existe, mas 'authenticated' NÃO tem privilégio — é a 0028: o portal recebe 'permission denied'`,
    });
  }
}

// ---------------------------------------------------------------------------
console.log(`banco: ${BANCO} @ ${SERVIDOR}`);
console.log(
  `${nosPostgres.length} chamada(s) de nó Postgres conferida(s) por PREPARE · ` +
    `${lista.length} objeto(s) que o portal invoca conferido(s) por presença` +
    (confereGrant ? " e privilégio" : " (papel 'authenticated' não existe aqui: privilégio NÃO conferido)"),
);

if (naoConferidos.length) {
  console.log(`\n${naoConferidos.length} chamada(s) NÃO CONFERIDA(S) — não são "passou":`);
  for (const { origem, porque } of naoConferidos) console.log(`  ${origem}\n      ${porque}`);
}

if (achados.length === 0) {
  console.log(
    `\nCHAMADAS OK em ${BANCO} — as chamadas de nó resolvem e os objetos do portal existem.` +
      "\n(NÃO conferidos: colunas de .select, assinaturas das chamadas do portal, políticas de RLS.)",
  );
  process.exit(0);
}

console.error(`\nNÃO RESOLVEM EM ${BANCO}: ${achados.length}\n`);
for (const { origem, detalhe } of achados) {
  console.error(`  ${origem}`);
  console.error(`      ${detalhe}`);
}
// A RECEITA TEM DE CASAR COM O ACHADO. Mandar "aplique as migrations" para um
// achado de privilégio é a mesma acusação errada que o modo expressão produzia:
// o objeto está lá, e quem lê a receita vai reaplicar o que já aplicou.
console.error(
  "\nO que não resolve mata a rodada no primeiro nó que chamar — objeto ausente com\n" +
    "'does not exist', privilégio faltando com 'permission denied'.\n" +
    "Aplique as migrations pendentes (a lista de comandos está em Supabase/README.md)\n" +
    "e rode este conferidor de novo antes de subir documento.",
);
process.exit(1);
