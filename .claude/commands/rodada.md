---
description: "Conduzir uma rodada deste projeto: medir antes, diagnosticar a causa, planejar em fatias, executar, medir depois"
argument-hint: "<o defeito, o sintoma, ou o mandato e a execução do n8n>"
---

Conduza uma rodada sobre: **$ARGUMENTS**

Não proponha correção nenhuma antes de terminar o passo 2. Três correções falhas seguidas param a
linha e questionam a arquitetura — não existe quarta tentativa.

## 1. Medir ANTES (o número de partida, não a impressão)

Rode só o que cerca o alvo — a lista canônica está em `.claude/COMANDOS-CANONICOS.md`, e o `.github/workflows/suites.yml`
é a fonte. Registre o resultado como número: quantos asserts, qual contagem, qual byte.
**Suíte que você não rodou não entra no relatório como verde.**

Se o alvo é uma rodada real de book (o dono executou o n8n), a análise tem etapas próprias —
linha do tempo pelo BANCO, sinal positivo de execução por estágio, e a terceira pergunta, que é a
mais rendosa: *a checagem que acusou está certa?* (na v48, 20 das 27 pendências eram falsas).
Siga `Arquitetura do Sistema/5 Prompts/01-rodada-real.md` em vez de improvisar.

## 2. Diagnosticar — causa medida, não suposta

Comece pelo briefing (`buscar.mjs`), não pelo `grep`. Antes de investigar fundo, confira as três
respostas fáceis: a migration está aplicada (**a sonda, não o `ESTADO.md`**)? o workflow publicado
bate com o do repositório? a cota apertou? **Quando as três estão certas, a causa é estrutural** —
procure quadrático, barreira, e estágio que nunca ligou.

Separe sempre "o estágio rodou" de "o estágio não achou nada": os dois têm a mesma aparência, e é o
defeito mais caro daqui.

**Antes de editar uma função, liste TODOS os chamadores dela** e corrija no ponto por onde todos
passam — o comando e o caso que custou caro estão em `CLAUDE.md`, "Antes de codar".

## 3. Planejar em fatias

Uma fatia por commit. Para cada uma: o defeito, a causa medida, o invariante que vai prová-la, e
quem executa — a sessão principal por padrão, ou o especialista cuja linha casa o arquivo:
`subagent_type: "migrations-postgres"` para o banco, `subagent_type: "n8n-workflow"` para os
geradores e nós Code, `subagent_type: "portal-export"` para o portal e o arquivo entregue.
Delegar só quando o checklist do domínio for o que decide o resultado; caso contrário o contexto
novo custa mais do que rende. (As citações são nesta grafia de propósito: é assim que
`verificar-comandos.mjs` confere que o nome ainda existe. Em prosa, um agente renomeado passa
pelo portão e falha na hora do despacho.)

Cada fatia passa pela escada de sete perguntas do `CLAUDE.md` ("Antes de codar") antes de virar
código — o degrau 2, "já existe neste repositório?", é o que mais rende aqui.

Onda paralela só quando **as duas** condições valem (sem dependência **e** `Files:` disjuntos,
derivados incluídos) — `Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`.

## 4. Executar

O invariante vem com a correção, nunca depois. Ele tem de **reprovar com o bug ligado**, e o
número de asserts que reprovaram vai na mensagem do commit. Quando o protocolo de medir não-vazio
for de fato executado (desligar a correção, contar, religar), despache
`subagent_type: "suites-invariantes"`; se você só está lembrando que a regra existe, não abra
contexto novo.

Se o defeito passou porque nada acusava, **o entregável é o que passa a acusar** — o portão, não
só o conserto.

## 5. Medir DEPOIS, e dizer o que ficou de fora

Rode de novo o que você rodou no passo 1, mais o que a mudança tocou, mais os derivados
versionados sob `git diff --exit-code`. Relate lado a lado: o número de antes, o de depois, e
**o que você mediu × o que você supôs**.

Feche com `/revisar` antes de `/fechar`. Quem escreveu a mudança não é quem a revisa.
