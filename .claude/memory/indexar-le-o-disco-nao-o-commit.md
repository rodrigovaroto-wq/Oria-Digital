---
name: indexar-le-o-disco-nao-o-commit
description: o indexador do conhecimento lê a árvore de trabalho, não o git — gerar o grafo com edição não commitada (ou arquivo novo não ignorado) deixa o CI vermelho; gere num worktree limpo em HEAD
metadata:
  type: architecture
---

`indexar.mjs` lê o repositório pelo disco: `readdirSync` e `readFileSync` (linhas 76, 96 e 134). O que
o git só lista (`ls-files -i`) entra apenas para decidir o que ignorar. Consequência: uma edição de
agente ainda não commitada, ou um arquivo novo que o git não ignora, muda o `grafo.jsonl` local. O CI
faz checkout do commit, regera, e o `git diff --exit-code` reprova: "o grafo commitado diverge".

Para gerar sem essa contaminação: `git worktree add --detach <tmp> HEAD`, rode o `indexar.mjs` lá e
copie o `grafo.jsonl`. Medido em 29/10/2026: o grafo gerado num worktree limpo em `96df48d` é
byte a byte igual ao commitado (`cmp`). O worktree é removido depois (`git worktree remove`).
