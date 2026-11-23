---
id: autopilot-para-no-pr-verde
tipo: doutrina
toca:
  - .claude/commands/autopilot.md
  - .claude/commands/rodada.md
  - .claude/commands/revisar.md
  - .claude/commands/fechar.md
---

# /autopilot encadeia rodada → revisar → fechar → PR, e para no PR verde

Criado em 23/11/2026 a partir da ideia de um comando único que roda sempre o mesmo processo.
Ele **não descreve trabalho novo**: cada etapa segue o arquivo do comando que já existia, e o
autopilot só acrescenta o que nenhum dos três cobria — abrir o PR, esperar CI e Sonar, revisar o
PR, e a limpeza depois do merge.

Três decisões do dono que uma sessão futura não deve "melhorar":

- **O merge é do dono.** O autopilot para em "PR verde, pronto para merge" e só faz merge e
  limpeza quando o dono manda, na conversa — nunca por CI verde ou aprovação no GitHub.
- **Revisão em até 3 ciclos**, parando antes quando nenhum CRÍTICO/ALTO sobrevive. Não 3 a 5:
  o painel de 5 revisores foi cortado para 2 em 16/09/2026 porque repetiam achados.
- **Regra copiada para dentro do autopilot é defeito.** Se uma etapa muda, muda no arquivo do
  comando dela; o autopilot aponta, não repete.
