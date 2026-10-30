#!/usr/bin/env node
// PORTÃO: `.claude/COMANDOS-CANONICOS.md` (até 30/10/2026, um bloco do `CLAUDE.md`) é ESPELHO do `.github/workflows/suites.yml`.
//
// POR QUE ELE EXISTE, e os números que o justificam. O `CLAUDE.md` é lido por TODA sessão e é dele
// que sai a lista do que se roda aqui. Quando ele fica para trás do CI, ele não fica silencioso:
// manda a próxima sessão rodar MENOS do que o portão cobra, e a sessão relata "baseline completa"
// sobre uma medição que não existe. Já aconteceu três vezes, todas achadas por acidente:
//
//   • sessão 82 — o CI rodava SEIS suítes de verificação e o CLAUDE.md listava QUATRO: 18 asserts
//     ficaram fora de uma "baseline completa";
//   • sessão 86 — os dois MEDIDORES rodavam no CI e não estavam no CLAUDE.md;
//   • sessão 93 (F0) — a REGENERAÇÃO DAS FIXTURES do book (`gerar_fixture.py` e
//     `gerar_fixture_canastra.py`) rodava no CI e não estava no CLAUDE.md. Este portão, na sua
//     primeira versão, NÃO a pegava: ele conhecia quatro famílias fixas de caminho, e o que não
//     casasse nenhuma delas era invisível. Portão que só enxerga o que já se sabia é decoração.
//
// COMO ELE FUNCIONA AGORA. Sem famílias: ele extrai TODO caminho de script (`.mjs`, `.mts`, `.sh`,
// `.py`) citado em COMANDO dos dois lados e exige que os dois conjuntos sejam iguais.
//
// As três regras de normalização, e cada uma nasceu de um erro medido em 16/09/2026:
//
//   1. COMENTÁRIO NÃO É COMANDO, dos DOIS lados. No YAML, comentário explica o passo; no bloco
//      ```bash do CLAUDE.md, comentário explica o comando. Contar comentário deixou o portão
//      verde com a linha apagada (o nome ainda aparecia na prosa ao lado), e também produziu
//      dois falsos positivos (`run.sh` e `medir-regua-cobertura.mjs` citados em comentário).
//   2. `../` É PREFIXO DE NAVEGAÇÃO, NÃO PARTE DO NOME. O CI faz `cd "Dados de Teste"/book-vertentes`
//      e chama `../../Supabase/test/gerar_fixture.py`. A medição que não normaliza isso não
//      encontra o arquivo, e — este foi o erro caro — PULA O CANDIDATO EM SILÊNCIO, reportando
//      "0 divergências" com duas divergências reais na frente. Ausência apresentada como dado,
//      dentro do próprio medidor.
//   3. GLOB CONTINUA GLOB. `.claude/hooks/test/*.test.mjs` roda por glob nos dois lados; o que
//      tem de existir é o DIRETÓRIO, não um arquivo com asterisco no nome.
//
// O que ele NÃO faz: julgar se a suíte é boa, ou se a ordem no CLAUDE.md é a melhor. Só responde
// "os dois lados mandam rodar exatamente o mesmo conjunto, e cada arquivo citado existe?".
//
// Uso:  node .claude/verificar-espelho-claude-md.mjs
// Saída: exit 0 = espelho em dia; exit 1 = lista o que falta de cada lado.
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';

// Caminhos ancorados na RAIZ do repositório, nunca no diretório de onde se chamou: o bloco
// canônico deixa a sessão dentro de `portal/` (o `npm ci` é lá) e o `/fechar` chama este portão
// logo depois. Com caminho relativo ao cwd ele morria com stack trace de ENOENT.
const RAIZ = join(dirname(fileURLToPath(import.meta.url)), '..');
// TODOS os workflows, não só o `suites.yml`. MEDIDO em 16/09/2026 antes de decidir: incluir os
// outros dois custa exatamente DUAS linhas novas no CLAUDE.md (`sonda-producao.mjs` e
// `republicar.sh`) — e as duas são coisas que uma sessão precisa saber rodar e não estavam
// escritas em lugar nenhum. Um portão que enxerga um arquivo e ignora os vizinhos volta a ser o
// portão de famílias fixas, com outro nome.
const CI_DIR = '.github/workflows';
// O bloco morava no `CLAUDE.md` até 30/10/2026; saiu para um arquivo próprio porque eram 9.100
// dos 18.116 caracteres que TODA sessão carrega. O nome deste portão ficou, para não mexer no CI.
const DOC = '.claude/COMANDOS-CANONICOS.md';

// O `\.?` do começo existe porque metade dos portões mora em `.claude/`: sem ele o token vinha
// como `claude/verificar-comandos.mjs` e o portão acusava "não existe" em arquivo que existe.
const SCRIPT = /\.?[A-Za-zÀ-ÿ0-9_][A-Za-zÀ-ÿ0-9_./*-]*\.(?:mjs|mts|sh|py)\b/g;

/** Tira as linhas de comentário — o `#` vale para o YAML e para o bloco bash do CLAUDE.md. */
const semComentario = (texto) =>
  texto.split('\n').filter((l) => !l.trimStart().startsWith('#')).join('\n');

/** `../../Supabase/test/x.py` e `Supabase/test/x.py` são o MESMO arquivo. */
const normalizar = (tok) => {
  let c = tok;
  while (c.startsWith('../')) c = c.slice(3);
  return c;
};

const ler = (p) => readFileSync(join(RAIZ, p), 'utf8');
const citados = (texto) => new Set([...semComentario(texto).matchAll(SCRIPT)].map((m) => normalizar(m[0])));

const workflows = readdirSync(join(RAIZ, CI_DIR)).filter((f) => f.endsWith('.yml')).sort();
const noCi = citados(workflows.map((f) => ler(join(CI_DIR, f))).join('\n'));
// Do DOC só valem os blocos de comando; prosa explicativa não faz ninguém rodar nada.
const noDoc = citados((ler(DOC).match(/```bash\n[\s\S]*?```/g) ?? []).join('\n'));

const problemas = [];
for (const f of noCi) if (!noDoc.has(f)) problemas.push(`o CI roda \`${f}\` e o ${DOC} não cita`);
for (const f of noDoc) if (!noCi.has(f)) problemas.push(`o ${DOC} manda rodar \`${f}\` e o CI não roda`);

// E os dois lados podem concordar apontando para um arquivo que a renomeação levou embora — foi
// assim que as regras do `lembrar-derivados` morreram.
for (const f of new Set([...noCi, ...noDoc])) {
  const alvo = f.includes('*') ? dirname(f) : f;
  // Nome sem barra (`gerar.py`) é chamado depois de um `cd` e não resolve da raiz: os dois lados
  // citam o mesmo token, e é só isso que dá para exigir dele.
  if (!alvo.includes('/')) continue;
  if (!existsSync(join(RAIZ, alvo))) problemas.push(`\`${f}\` é citado mas não existe no repositório`);
}

if (problemas.length === 0) {
  console.log(`espelho OK — ${noCi.size} scripts, os mesmos nos ${workflows.length} workflows do CI e no ${DOC}`);
  process.exit(0);
}
console.error(`*** o ${DOC} e os workflows do CI divergem em ${problemas.length} ponto(s) ***\n`);
for (const p of problemas.sort()) console.error(`  ${p}`);
console.error(`\nEspelho que fica para trás é pior que espelho nenhum: ele manda a próxima sessão\nrodar diferente do portão. Acerte o lado que está errado — nunca apague a linha do CI\npara o espelho fechar.`);
process.exit(1);
