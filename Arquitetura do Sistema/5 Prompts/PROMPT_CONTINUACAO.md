# PROMPT DE CONTINUAÇÃO — aposentado

> **Este arquivo não é mais o prompt de continuação. Use
> [`Arquitetura do Sistema/5 Prompts/00-continuacao.md`](prompts/00-continuacao.md).**

## Por que ele foi aposentado, e a razão vale mais que o arquivo

O conteúdo que estava aqui era uma **fotografia da sessão 19** (31/07/2026), e envelheceu sem que
nada acusasse. Ele mandava, ainda em 31/08:

- trabalhar na branch `claude/handoff-next-steps-6k88f2`, no **PR #69** — mergeado 117 PRs atrás;
- rodar quatro suítes com **160 / 198 / 32 migrations / 18** — os números reais já eram outros em
  toda linha;
- executar cinco frentes (o bloco "REFERÊNCIAS MACRO", a dupla contagem no total do grupo, as
  cinco pré-condições do v33, **montar o CI**) — todas fechadas, e o CI existe desde a sessão 20;
- e afirmava "**Não existe CI**" como fato do projeto.

Um prompt que guarda estado é uma cópia do estado que ninguém atualiza junto — o mesmo defeito que
travou o cabeçalho do `HANDOFF.md` por 17 PRs em "PR #70, migrations até `0034`". A causa não é
descuido: é que a parte que muda toda rodada morava no arquivo que quase nunca se edita.

**A correção é estrutural: o prompt novo não guarda estado nenhum — ele manda medir.** Onde este
arquivo dizia "as suítes estão em 160", o novo diz "rode as suítes com os comandos de `.claude/COMANDOS-CANONICOS.md`,
antes de mudar qualquer coisa". Prompt que aponta para quem mede o estado não envelhece.

## O que sobreviveu, e para onde foi

| O que era | Onde está hoje |
|---|---|
| As regras invioláveis do projeto | `CLAUDE.md`, seção "As sete regras" |
| Os comandos canônicos das suítes | `.claude/COMANDOS-CANONICOS.md` (o CI é a fonte; saiu do `CLAUDE.md` em 30/10/2026) |
| As armadilhas conhecidas | `.claude/memory/` — uma por arquivo, indexadas em `MEMORY.md` |
| O roteiro de abertura de sessão | `Arquitetura do Sistema/5 Prompts/00-continuacao.md` |
| A lista do que executar | `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` — que tem dono e critério de pronto |

O histórico das sessões que rodaram a partir deste arquivo continua no `HANDOFF.md`.
