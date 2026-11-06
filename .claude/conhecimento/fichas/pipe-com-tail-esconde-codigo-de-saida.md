---
id: pipe-com-tail-esconde-codigo-de-saida
tipo: armadilha
toca:
  - .claude/COMANDOS-CANONICOS.md
---

**Armadilha (S117, 04/11/2026):** o commit `285dc9b` passou com o portão do conhecimento
VERMELHO. O comando era `node .claude/conhecimento/conferir.mjs | tail -5`. Num pipe, o código
de saída que o shell devolve é o do ÚLTIMO comando, e o `tail` sai com 0. O portão reprovou e
ninguém viu: a saída cortada não mostrava a linha da reprovação.

É a regra 7 em forma de shell: um portão que reprovou fica com a mesma cara de um que passou.

**Como rodar portão:**
1. Sem pipe, com a saída num arquivo, e o código de saída impresso logo em seguida:
   `cmd > "$SCRATCH/log" 2>&1; echo "rc=$?"`. Depois leia o arquivo com `tail` ou `grep`, à parte.
2. Se precisar de pipe, use `set -o pipefail` ou confira `${PIPESTATUS[0]}`.
3. Só declare "verde" com o `rc=0` à vista. "A saída parecia limpa" não conta.
