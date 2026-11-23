#!/usr/bin/env node
// PORTÃO: todo `subagent_type` citado por um comando de barra existe como agente
// instalado neste repositório.
//
// POR QUE ELE EXISTE. Despacho para `subagent_type` inexistente falha em tempo de
// execução, e o comando só descobre isso quando alguém o usa — no meio de uma
// tarefa. Na importação de 02/09 os 52 comandos vieram de um MARKETPLACE de
// plugins, onde o nome do agente é qualificado pelo plugin
// (`security-scanning-security-auditor`, `c4-architecture::c4-code`). Fora do
// marketplace, NENHUM desses nomes resolve. MEDIDO na primeira execução deste
// portão, contra os 52 comandos importados e os 7 agentes do projeto:
//
//     57 citações não resolviam, 30 nomes distintos, em 13 comandos
//
// E o catálogo escrito à mão do README errava a lista: marcava `debug-trace` e
// `error-analysis`, que não despacham para agente nenhum, e NÃO marcava
// `c4-architecture`, que despacha para quatro. Catálogo à mão erra; este arquivo
// não, porque ele lê os comandos.
//
// Desde 23/11/2026 responde também "o caminho citado existe?" — ver a seção dos caminhos.
//
// O que este portão NÃO faz: julgar se o agente é bom, ou se o comando faz
// sentido aqui. Só responde "o nome resolve?".
//
// Uso:  node .claude/verificar-comandos.mjs
// Saída: exit 0 = todos resolvem; exit 1 = lista os que não resolvem.
import { existsSync, readdirSync, readFileSync, statSync } from 'node:fs';
import { dirname, join, resolve } from 'node:path';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { cabecalho } from './conhecimento/cabecalho.mjs';

// `fileURLToPath`, não `.pathname`: o pathname codifica espaço como `%20`, o `existsSync` não
// acha nada, e o portão lia ZERO comandos e ZERO agentes e saía verde. Medido na revisão de
// 23/11/2026, com o repositório copiado para um diretório "Oria Digital".
const RAIZ = fileURLToPath(new URL('.', import.meta.url));

// Diretório ausente é ZERO arquivos, não erro. MEDIDO em 16/09/2026: ao remover os 52
// comandos importados, o `git rm` levou o diretório junto e este portão morreu com um
// stack trace de ENOENT — a forma mais inútil de falhar, porque não diz nada sobre
// citação nenhuma. Portão que quebra por ausência é pior que portão nenhum.
function md(dir) {
  const saida = [];
  if (!existsSync(dir)) return saida;
  for (const nome of readdirSync(dir)) {
    const caminho = join(dir, nome);
    if (statSync(caminho).isDirectory()) saida.push(...md(caminho));
    else if (nome.endsWith('.md')) saida.push(caminho);
  }
  return saida;
}

// --- o que existe -----------------------------------------------------------
// O nome do agente vem do `name:` do frontmatter; o nome do ARQUIVO não decide
// nada. É por isso que os importados podem se chamar `importado.*.md` sem que
// isso mude o despacho.
const agentes = new Set();
for (const f of md(join(RAIZ, 'agents'))) {
  const nome = cabecalho(readFileSync(f, 'utf8'))?.name;
  if (nome) agentes.add(nome);
}
// Embutidos do Claude Code. Não são deste repositório e não podem ser conferidos
// contra arquivo nenhum — a lista é a que o próprio erro de despacho imprime.
for (const n of ['general-purpose', 'Explore', 'Plan', 'claude', 'statusline-setup',
                 'claude-code-guide']) agentes.add(n);

// --- o que é citado ---------------------------------------------------------
const achados = [];
let citacoes = 0;
for (const f of md(join(RAIZ, 'commands'))) {
  const texto = readFileSync(f, 'utf8');
  // Duas grafias, e as duas aparecem nos comandos importados:
  //   subagent_type: "x"   (YAML, nos blocos de exemplo)
  //   subagent_type="x"    (prosa)
  for (const m of texto.matchAll(/subagent_type["']?[:=] ?["']([^"']+)["']/g)) {
    citacoes += 1;
    const nome = m[1];
    if (agentes.has(nome)) continue;
    const linha = texto.slice(0, m.index).split('\n').length;
    achados.push({ comando: f.slice(RAIZ.length), linha, nome });
  }
}

// --- os caminhos citados ----------------------------------------------------
// Segunda pergunta, do mesmo tipo da primeira: o arquivo que o comando manda abrir ou rodar
// existe? Comando que cita script renomeado não erra — a sessão procura, não acha, e improvisa.
//
// A primeira versão (300b191) só lia caminho que fosse a crase INTEIRA e começasse numa pasta
// da raiz. A revisão independente mediu o buraco: `node .claude/x.mjs` e todo bloco ``` ficavam
// de fora — 6 invocações reais sem conferência, `fechar.md` e `revisar.md` com 0 caminhos —, e
// renomear `buscar.mjs` deixava o portão verde. Agora:
//   1. lê crase de linha, bloco cercado e alvo de link markdown;
//   2. dentro de cada um, o trecho inteiro (pega caminho com espaço, "Arquitetura do Sistema/…")
//      e, se ele não for caminho, cada palavra e cada string entre aspas;
//   3. caminho com `/` tem de começar numa pasta da raiz (`./` aceito); nome solto
//      (`ESTADO.md`, `buscar.mjs`) tem de existir em algum lugar do que o git versiona;
//   4. fica de fora, por não ser deste repositório ou não ser caminho: absoluto (`/tmp/…`),
//      com `..`, dentro de `node_modules/` (o CI deste job não instala o portal), glob,
//      placeholder (`<x>`, `{x}`, `$X`, `NNN`, `XXXX`) e URL.
const REPO = resolve(RAIZ, '..');
const EXT = /\.(md|mjs|mts|cjs|js|ts|tsx|sql|sh|ya?ml|jsonl?|py|toml|properties|xlsx|xlsm|csv|pdf|html|txt)$/i;

let versionados;
try {
  versionados = execFileSync('git', ['ls-files', '-z'], { cwd: REPO, encoding: 'utf8', maxBuffer: 64 << 20 })
    .split('\0').filter(Boolean);  // -z: sem ele o git escapa acento ("Execu\303\247\303\243o") e o nome não casa
} catch (e) {
  // Sem a lista, nome solto não teria contra o que ser conferido e passaria calado (regra 7).
  console.error(`*** git ls-files falhou em ${REPO}: ${e.message} ***`);
  process.exit(1);
}
const nomesSoltos = new Set(versionados.map((v) => v.split('/').pop()));

function limpar(t) {
  return t.trim().replace(/^[("'\[]+|[)"'\],;.]+$/g, '').replace(/:\d+(-\d+)?$/, '').replace(/#.*$/, '');
}
function placeholder(t) {
  return /[*<>{}$]|NNN|XXXX|^https?:/.test(t);
}
// Devolve null quando `t` não é caminho deste repositório; senão { tipo, ok }.
function conferir(t, baseLink) {
  t = limpar(t);
  if (!t || placeholder(t) || t.startsWith('/') || t.includes('node_modules/')) return null;
  if (t.split('/').includes('..') && !baseLink) return null;
  const diretorio = t.endsWith('/');
  const comExt = EXT.test(t) && !/^\.[a-z]+$/i.test(t.split('/').pop());  // `.md` solto é extensão, não arquivo
  if (baseLink) {
    const alvo = resolve(baseLink, t);
    if (!alvo.startsWith(REPO)) return null;
    return { ok: existsSync(alvo) };
  }
  const rel = t.replace(/^\.\//, '');
  if (!rel.includes('/')) return comExt ? { ok: nomesSoltos.has(rel) } : null;
  const raiz = rel.split('/')[0];
  const raizExiste = existsSync(join(REPO, raiz)) && statSync(join(REPO, raiz)).isDirectory();
  // Pasta da raiz que existe: confere com ou sem extensão (`N8N/lib`, `Supabase/`).
  // Pasta da raiz que NÃO existe: com extensão conhecida ainda é caminho — renomeada ou com erro
  // de digitação. A versão de abe4d7a pulava esse caso calada: medido na 2ª revisão, `N8N` →
  // `n8n` deixava o portão verde com 51 de 55 caminhos. Pasta citada com `/` no fim (`N8N/`)
  // também é caminho. Sem extensão e sem `/` no fim (`origin/main`) não é.
  if (!raizExiste) return comExt || diretorio ? { ok: false } : null;
  const alvo = join(REPO, rel);
  return { ok: existsSync(alvo) && (!diretorio || statSync(alvo).isDirectory()) };
}
function candidatos(trecho) {
  // O trecho inteiro vale como UM caminho quando existe, ou quando não tem espaço. Com espaço e
  // inexistente, pode ser caminho com espaço quebrado ("Arquitetura do Sistema/x.md") OU vários
  // caminhos na mesma crase ("N8N/a.mjs e N8N/b.mjs"): as palavras decidem — se alguma delas é
  // caminho, valem elas; se nenhuma é, o trecho inteiro é o caminho quebrado.
  const inteiro = conferir(trecho);
  if (inteiro && (inteiro.ok || !/\s/.test(trecho.trim()))) return [[trecho.trim(), inteiro]];
  const saida = [];
  const aspas = [...trecho.matchAll(/"([^"]+)"|'([^']+)'/g)].map((m) => m[1] ?? m[2]);
  const resto = trecho.replace(/"[^"]*"|'[^']*'/g, ' ');
  for (const t of [...aspas, ...resto.split(/\s+/)]) {
    const r = conferir(t);
    if (r) saida.push([limpar(t), r]);
  }
  // Nenhuma palavra existe e o trecho inteiro tem cara de caminho: é UM caminho quebrado com
  // espaço ("Arquitetura do Sistem/5 Prompts/x.md"), e a mensagem mostra ele inteiro.
  if (inteiro && !saida.some(([, r]) => r.ok)) return [[trecho.trim(), inteiro]];
  return saida;
}

let caminhos = 0;
const porComando = [];
const comandos = md(join(RAIZ, 'commands'));
for (const f of comandos) {
  const texto = readFileSync(f, 'utf8');
  const linhaDe = (i) => texto.slice(0, i).split('\n').length;
  const trechos = [];
  // Blocos cercados primeiro; depois as crases de linha só no texto fora deles.
  const semBlocos = texto.replace(/```[^\n]*\n([\s\S]*?)```/g, (m, corpo, i) => {
    corpo.split('\n').forEach((l, k) => trechos.push([l, linhaDe(i) + 1 + k]));
    return m.replace(/[^\n]/g, ' ');
  });
  for (const m of semBlocos.matchAll(/`([^`\n]+)`/g)) trechos.push([m[1], linhaDe(m.index)]);
  const lidos = [];
  for (const [trecho, linha] of trechos) {
    for (const [c, r] of candidatos(trecho)) lidos.push([c, r, linha]);
  }
  for (const m of semBlocos.matchAll(/\]\(([^)\s]+)\)/g)) {
    const r = conferir(m[1], dirname(f));
    if (r) lidos.push([m[1], r, linhaDe(m.index)]);
  }
  for (const [c, r, linha] of lidos) {
    caminhos += 1;
    if (!r.ok) achados.push({ comando: f.slice(RAIZ.length), linha, nome: `caminho inexistente: ${c}` });
  }
  porComando.push(`${f.slice(RAIZ.length).replace('commands/', '')} ${lidos.length}`);
}

// Piso (regra 7): portão que não leu nada tem a mesma cara de portão que leu tudo e achou
// tudo certo. Zero comandos, zero agentes do repositório ou zero caminhos é falha de leitura.
const agentesDoRepo = md(join(RAIZ, 'agents')).length;
const vazios = [];
if (comandos.length === 0) vazios.push('0 comandos lidos em .claude/commands/');
if (agentesDoRepo === 0) vazios.push('0 agentes lidos em .claude/agents/');
if (caminhos === 0) vazios.push('0 caminhos lidos nos comandos');
if (vazios.length) {
  console.error(`*** o portão não leu nada — isso não é verde: ${vazios.join('; ')} (raiz: ${RAIZ}) ***`);
  process.exit(1);
}

const subagentes = achados.filter((a) => !a.nome.startsWith('caminho inexistente'));
const quebrados = achados.length - subagentes.length;
if (achados.length === 0) {
  console.log(`comandos OK — ${citacoes} citações de subagent_type, ${agentes.size} agentes conhecidos; ${caminhos} caminhos citados existem (${porComando.join(', ')})`);
  process.exit(0);
}
console.error(`*** ${subagentes.length} subagent_type que não resolvem, ${quebrados} caminhos citados que não existem ***\n`);
for (const a of achados.sort((x, y) => x.comando.localeCompare(y.comando) || x.linha - y.linha)) {
  console.error(`  ${a.comando}:${a.linha}  →  ${a.nome}`);
}
console.error(`\nsubagent_type: instale o agente em .claude/agents/ ou aponte para um que exista.`);
console.error(`caminho: corrija-o no comando — não tire as crases para calar o portão.`);
process.exit(1);
