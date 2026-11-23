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
import { join } from 'node:path';
import { cabecalho } from './conhecimento/cabecalho.mjs';

const RAIZ = new URL('.', import.meta.url).pathname;

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
// Nasceu na análise de riscos do /autopilot (23/11/2026), que cita 11 caminhos de outros
// arquivos e nada conferia nenhum deles.
//
// Só confere o que COMEÇA num diretório que existe na raiz (`N8N/x.mjs`, `Arquitetura do
// Sistema/...`). Isso deixa de fora, sem lista de exceção, o comando inteiro entre crases
// (`node .claude/...` — "node .claude" não é diretório), o glob e o placeholder.
const REPO = join(RAIZ, '..');
let caminhos = 0;
for (const f of md(join(RAIZ, 'commands'))) {
  const texto = readFileSync(f, 'utf8');
  for (const m of texto.matchAll(/`([^`*<>{}$&|"']+\/[^`*<>{}$&|"']+\.[a-z]{1,5})`/g)) {
    const caminho = m[1];
    const raiz = caminho.split('/')[0];
    if (!existsSync(join(REPO, raiz)) || !statSync(join(REPO, raiz)).isDirectory()) continue;
    caminhos += 1;
    if (existsSync(join(REPO, caminho))) continue;
    const linha = texto.slice(0, m.index).split('\n').length;
    achados.push({ comando: f.slice(RAIZ.length), linha, nome: `caminho inexistente: ${caminho}` });
  }
}

const distintos = new Set(achados.map((a) => a.nome));
if (achados.length === 0) {
  console.log(`comandos OK — ${citacoes} citações de subagent_type, ${agentes.size} agentes conhecidos, ${caminhos} caminhos citados existem`);
  process.exit(0);
}
console.error(`*** ${achados.length} citações não resolvem (${distintos.size} nomes distintos) ***\n`);
for (const a of achados.sort((x, y) => x.comando.localeCompare(y.comando) || x.linha - y.linha)) {
  console.error(`  ${a.comando}:${a.linha}  →  ${a.nome}`);
}
console.error(`\nInstale o agente em .claude/agents/ ou aponte a citação para um que exista; caminho inexistente → corrija o caminho no comando.`);
process.exit(1);
