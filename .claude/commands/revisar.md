---
description: "Revisar um diff sob a lente deste projeto: defeito silencioso + fidelidade do número, e a lente do portal só quando o diff toca portal/"
argument-hint: "<o diff, o número do PR, ou vazio para git diff origin/main...HEAD>"
---

Revise: **$ARGUMENTS** (vazio → `git fetch -q origin main` e `git diff origin/main...HEAD`).

Nunca contra a `main` local: ela não anda sozinha. Medido em 23/11/2026, 25 commits atrás, e o
diff contra ela dava 56 arquivos para 9 reais — o revisor recebia código de outros PRs.

**Não revise você mesmo primeiro.** Quem escreveu a mudança não a revisa — é a única razão de esta
revisão custar um contexto separado.

## 1. Descubra o que o diff toca, antes de decidir o painel

```bash
git diff --name-only <alvo>
```

## 2. Despache o painel — numa mensagem só

Duas lentes fixas, uma condicional. O painel era de cinco até 16/09/2026; duas das cinco ("banco"
e "chegada ao ar") repetiam, palavra por palavra, as perguntas 3 e 5 do próprio
`revisor-defeito-silencioso` — quatro revisores lendo o mesmo diff produziam uma lista quatro
vezes mais longa e uma síntese que gastava o ganho deduplicando.

1. **`subagent_type: "revisor-defeito-silencioso"`** (obrigatório) — as seis perguntas da lente central.
   Elas já cobrem banco, derivado versionado e chegada à produção; **não abra revisor separado
   para isso.**
2. **Fidelidade do número** (lente, sem agente próprio) — algum caminho fabrica, arredonda ou soma
   o que não se soma? o total informado está sendo somado junto com as componentes que ele já
   inclui? premissa ausente virou zero em vez de branco com nota? Esta é aditiva: é a única que
   olha a aritmética que chega ao cliente.
3. **TypeScript/Next — SÓ se o passo 1 listou algum arquivo em `portal/`.** Se não listou, diga
   "não se aplica" e não despache. Endereço de célula é contrato: `spliceRows` desloca
   `linhaCabFocus` e cada INDEX/MATCH passa a apontar uma linha acima, em silêncio.

Cada achado sai como:
`arquivo:linha — severidade — a afirmação em uma frase — o cenário de falha concreto`.

**Achado sem cenário de falha não é achado, é palpite: o próprio revisor descarta.**

## 3. Sintetize

1. **Deduplique** — o mesmo problema apontado duas vezes vira uma entrada.
2. **Filtre** — confira contra o diff antes de descartar, e não aceite a alegação do revisor por fé
   em nenhuma das duas direções. Pendência falsa que muda de nome não é correção.
3. **Ordene** — CRÍTICO (número errado chega ao cliente, ou perda de dado) → ALTO → MÉDIO → BAIXO.

## 4. Cobre o que o relatório tem de conter

- o número de asserts que reprovam com a correção **desligada** — sem ele, o invariante não foi
  medido e pode ter nascido vazio;
- o invariante afirma **comportamento**, não mecanismo;
- os derivados versionados regerados e sob `git diff --exit-code`;
- se a mudança chega à produção sozinha, ou depende de apply de migration / republicação / deploy
  que ninguém vai lembrar de fazer.

Dizer **"nada sobreviveu à síntese"** é um resultado válido e útil — não é falha em achar algo.
