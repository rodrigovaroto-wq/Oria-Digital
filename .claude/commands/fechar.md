---
description: "Fechar a rodada: estado, mapa, memória, ficha, grafo e o que o dono faz à mão — sem reler ESTADO.md nem HANDOFF.md inteiros"
argument-hint: "<o que entrou nesta rodada, se não estiver óbvio no log>"
---

Feche a rodada. **Pré-requisito: o trabalho já está commitado.** $ARGUMENTS

## 1. Levante o que aconteceu — do git, não da memória

```bash
git log --oneline <base>..HEAD
git status --porcelain
```

As mensagens de commit desta casa já trazem o defeito, a causa e a medição (regra 6); é delas que
sai quase todo o texto abaixo. Não reconstrua de cabeça o que o log já diz.

## 2. Leia só o topo dos documentos de estado

`ESTADO.md` tem ~320 KB e o `HANDOFF.md` ~540 KB — **abrir qualquer um dos dois inteiro é o erro
mais caro deste passo**, e nenhum dos dois precisa ser lido para ser atualizado:

```bash
sed -n '1,60p' ESTADO.md            # a nota do topo é a única parte que muda toda rodada
sed -n '1,25p' HANDOFF.md           # só o cabeçalho; o resto é arquivo morto
node .claude/conhecimento/buscar.mjs "<o assunto da rodada>"
```

Precisou de algo do meio do `HANDOFF.md`? `grep -n`, nunca leitura integral.

## 3. Despache `estado-e-handoff`

Despache `subagent_type: "estado-e-handoff"` — é o agente barato e é o dono deste passo — ele conhece o formato de cada arquivo. Entregue a ele o
log do passo 1 e o topo do passo 2, para que ele **não releia nada**. O que ele atualiza:
`ESTADO.md` (topo), `MAPA_DE_EXECUCAO.md`, `.claude/memory/` quando couber, a ficha e o grafo do
conhecimento, o cabeçalho do `HANDOFF.md`, e a descrição do PR.

**A regra da casa:** nada é "provavelmente feito". Cada item ou tem evidência conferida nesta
rodada, ou está marcado **NÃO CONFERIDO** — que é informação, não omissão. Migration escrita ≠
migration aplicada: quem responde por produção é a sonda.

## 4. A seção que mais se esquece

**O que o dono precisa fazer à mão**: aplicar migrations em ordem, republicar o workflow
(`preparar-republicacao.mjs` + `conferir-publicado.mjs`, e conferir o `multipleFiles`), fazer
deploy do portal. **Correção que não chega ao ar não é correção.**

## 5. Os portões do fechamento

```bash
node .claude/conhecimento/indexar.mjs && git diff --exit-code -- .claude/conhecimento/grafo.jsonl
node .claude/conhecimento/conferir.mjs
node .claude/verificar-comandos.mjs
node .claude/verificar-espelho-claude-md.mjs
```

O grafo é derivado versionado: regerado e não commitado deixa o CI vermelho, igual aos JSON do n8n.

## 6. Relate honestamente

O que não conseguiu, o que ficou meio-feito, e o que você **mediu** × o que **supôs**. Relatório
que esconde o que faltou custa a próxima sessão inteira.

## 7. Último passo: sugerir sessão nova

Depois do commit de fechamento, diga ao dono em uma linha: "Rodada fechada — a próxima
fatia rende mais em sessão nova." Por quê: cada turno relê o contexto inteiro, e sessões
que seguiram depois de fechar chegaram a 450–615k por chamada (medido 05–30/10/2026;
a do portal custou US$ 152). Sessão nova parte de ~78k e do topo do `ESTADO.md`.
