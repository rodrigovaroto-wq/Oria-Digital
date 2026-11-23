# Os comandos e agentes importados — nota histórica

> **Isto não é mais um catálogo operacional.** Os 52 comandos de barra e os 30 agentes
> `importado.*` que este arquivo indexava foram **removidos em 16/09/2026**. O que sobra aqui é
> a procedência e o motivo, para que ninguém os reimporte sem saber o que já foi medido.

## O que existia

- **52 comandos** em `.claude/commands/`, 924.007 bytes, importados em 02/09/2026.
- **30 agentes** `.claude/agents/importado.*.md`, 236.541 bytes, instalados na mesma semana
  **só** para que os 13 comandos que despachavam não morressem em `Agent type not found`.

Origem: [`wshobson/agents`](https://github.com/wshobson/agents) (MIT) — hoje um marketplace de
plugins, de onde vieram 50 comandos e os 30 agentes — e
[`wshobson/commands`](https://github.com/wshobson/commands), de onde vieram `data-validation` e
`deploy-checklist`, que não tinham sucessor no repositório novo.

## Por que saíram

| O que foi medido | Número |
|---|---|
| `description:` dos 30 importados, carregada no system prompt de **toda** sessão | **16.025 bytes** (≈ 4.000 tokens), contra 1.148 bytes dos sete do projeto |
| Boilerplate `IMPORTADO de wshobson…` repetido dentro dessas descrições | 290 B × 30 = **8.700 bytes**, 54% do total acima |
| `description:` dos 52 comandos, também por sessão | **3.414 bytes** |
| Prompt carregado ao invocar um comando que orquestra (comando + corpos dos agentes) | **7,3k a 15,5k tokens** por invocação |
| Comandos que citavam algum caminho deste repositório | **2 de 52** (`code-explain`, `doc-generate`) |
| Menções a eles em `ESTADO.md`, `HANDOFF.md` e `Arquitetura do Sistema/` em 14 dias | **2**, ambas em `POS_RODADA.md` e ambas **desaconselhando** o uso |

E três deles contradiziam regra escrita: `/test-generate` e `/tdd-green` produzem teste que
**passa**, quando a regra 2 exige teste que **reprova com o bug ligado, medido**;
`/sql-migrations` ensina zero-downtime sem citar o catálogo da sonda, que é o que o
`Supabase/test/run.sh` reprova.

## O que ficou no lugar

Três comandos escritos **aqui**, que citam os agentes deste projeto e as sete regras:
`/rodada`, `/revisar`, `/fechar` (em `.claude/commands/`) — e `/autopilot` (23/11/2026), que não
descreve trabalho novo: encadeia os três e acrescenta PR, CI e limpeza pós-merge. Os sete agentes de `.claude/agents/`
continuam sendo o despacho de trabalho, como o `CLAUDE.md` sempre disse.

## Se alguém quiser um de volta

Copiar de `plugins/*/commands/` do `wshobson/agents` e, antes de commitar, conferir os dois
pontos que a importação de 02/09 teve de corrigir à mão: **(a)** `description:` explícito no
frontmatter — sem ele o Claude Code deriva a descrição da primeira linha de conteúdo, e 17
comandos passaram a exibir o mesmo parágrafo no menu; **(b)** modelo por **apelido**
(`sonnet`, `opus`, `haiku`), nunca ID fixado, que envelhece em silêncio. E o nome do agente no
marketplace é qualificado pelo plugin (`security-scanning-security-auditor`,
`c4-architecture::c4-code`) — fora dele **nenhum desses nomes resolve**, que foi o defeito que
`node .claude/verificar-comandos.mjs` passou a medir: 57 citações quebradas, 30 nomes distintos,
em 13 comandos.

**O portão continua valendo** e agora roda contra os comandos escritos aqui:

```bash
node .claude/verificar-comandos.mjs
```
