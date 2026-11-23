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
- **Triagem antes de tudo** (C código · D documentação · R rodada real · não usar). Medido:
  150 de 327 commits (23/09–23/11/2026) tocaram só documentação, e lá suíte de produto e painel
  de revisão não acham nada. A triagem é revista contra o diff antes do PR: D com código vira C. **D é a lista
  fechada** (`.md` fora das pastas de código); a versão que listava o código deixava os `.yml` do
  CI passarem como documentação.
- **Só o dono dispara** (`disable-model-invocation: true`): o comando age fora do repositório.
- **Tokens: só o necessário.** Sem assinatura do PR (8 checks = até 8 despertares relendo o
  contexto inteiro); uma conferida agendada aos 8 min (CI de PR levou 5–7 min nos runs de
  23/11) e no máximo mais duas de 4 min. Um push só (dos 10 últimos runs de PR, 5 cancelados
  por push seguinte). Trilha D não abre `rodada.md` nem `revisar.md` e lê de `fechar.md` só o
  passo 5 (393 de 3.130 bytes). O comando caiu de 10.252 para 6.448 bytes; os porquês moram
  aqui, não lá. Migration esquecida é da `sonda-producao.yml` diária, não de chamada da sessão.
- **Caminho citado em comando é conferido** pelo `verificar-comandos.mjs` (desde 23/11/2026):
  crase de linha, bloco cercado e link; com `/` a partir de uma pasta da raiz, nome solto contra o
  que o git versiona. A 1ª versão só lia a crase inteira e deixava `node .claude/x.mjs` de fora —
  a revisão independente mediu 6 invocações sem conferência. Lia 14 caminhos; lê 55.
- **Regra copiada para dentro do autopilot é defeito.** Se uma etapa muda, muda no arquivo do
  comando dela; o autopilot aponta, não repete.
