---
description: "Do pedido ao PR verde, no processo da casa: triagem → rodada → revisão → fechamento → PR → CI — e para antes do merge, que é do dono"
argument-hint: "<o pedido, o defeito ou o sintoma>"
disable-model-invocation: true
---

<!-- `disable-model-invocation`: todo comando daqui entra na lista de skills que o modelo vê
(medido em 23/11/2026: apareceu na mesma sessão em que foi criado). Este age fora do
repositório — branch, commit, PR —, então só o dono o dispara. As decisões e os números por trás
de cada etapa estão na ficha `autopilot-para-no-pr-verde`; aqui fica só o que executa. -->

Pedido: **$ARGUMENTS**

Este comando **encadeia** `/rodada`, `/revisar` e `/fechar` e acrescenta só triagem, PR, CI e
merge. Não copie regra de lá para cá: duas descrições do mesmo processo divergem sem erro.

**Orçamento.** Abra só o arquivo que a etapa da trilha manda abrir. Uma linha por etapa ao dono
(etapa, número, próxima). Um push só, na etapa 5 — cada push dispara os 8 checks do PR e cancela
o anterior (nos últimos 10 runs de PR, 5 foram cancelados por push seguinte).

## 0. Ponto de partida

1. `git status -sb`. Árvore suja que não é desta tarefa → pare e pergunte.
2. `git fetch -q origin main`. Daqui em diante, tudo que compara com a main usa `origin/main`,
   nunca a `main` local — medido em 23/11/2026: `main` local 25 commits atrás, e o diff contra
   ela dava 56 arquivos para 9 reais.
3. Branch: a que o harness fixou (nuvem) ou `git switch -c claude/<assunto> origin/main`. Nunca a `main`.
4. `node .claude/conhecimento/buscar.mjs "<assunto>"` antes de abrir qualquer arquivo.

## 1. Triagem — diga a trilha em uma linha

| Trilha | Quando |
|---|---|
| **D — documentação** | Lista fechada: só `.md` fora de `Supabase/`, `N8N/`, `portal/`, `.github/`, mais o `grafo.jsonl` regerado |
| **C — código** | Todo o resto — inclusive `.yml` do CI, `.json`, `settings.json`, hook e portão |
| **R — rodada real** | O dono rodou um book: siga `Arquitetura do Sistema/5 Prompts/01-rodada-real.md`. Sem defeito → relatório e fim, sem PR. Com defeito → cada um vira trilha C |
| **Não use** | Pergunta, análise sem arquivo mudado, aplicar migration, republicar, deploy |

Dúvida → C. D é lista fechada porque a lista de exceção deixava os `.yml` do CI passarem.

## 2. Entender e executar

Pedido com mais de uma leitura → `Arquitetura do Sistema/5 Prompts/` primeiro. Faltou
informação → pergunte ANTES, numa mensagem, com a sua recomendação.

**C** — siga `.claude/commands/rodada.md`. Suíte, agente e item "à mão" **só do domínio tocado**:

| Toca | Agente | Medir (comandos exatos em `.claude/COMANDOS-CANONICOS.md`) | Dono faz à mão |
|---|---|---|---|
| `Supabase/` | `subagent_type: "migrations-postgres"` | `Supabase/test/run.sh` | aplicar as migrations, em ordem |
| `N8N/` | `subagent_type: "n8n-workflow"` | gerador + derivados sob `git diff --exit-code` | `N8N/preparar-republicacao.mjs` + `N8N/conferir-publicado.mjs` |
| `portal/` | `subagent_type: "portal-export"` | suíte do portal + `portal/scripts/verificar-export.mts` | deploy |

**D** — não abra `rodada.md`. Sem suíte de produto, sem invariante. Número citado no texto vem
de um comando rodado agora, nunca de outro `.md`.

## 3. Revisar

| Trilha | Ciclos de `.claude/commands/revisar.md` |
|---|---|
| C | até 3; para quando nenhum CRÍTICO/ALTO sobrevive |
| D que muda instrução (`CLAUDE.md`, comando, agente, memória) | 1 |
| D só registro (`ESTADO.md`, `Business Plan/06_execucao/PLANO_DE_EXECUCAO.md`, análise, ficha) | 0 — não abra `revisar.md` |

Chame sempre **`/revisar origin/main...HEAD`** — sem alvo, ele compara com a `main` local e o
revisor recebe código de outros PRs. O painel é o que o `revisar.md` decide (a lente do portal
entra quando o diff toca `portal/`); você nunca revisa o que escreveu. Cada correção é fatia própria. Terceiro ciclo ainda com CRÍTICO/ALTO → pare e relate, sem PR.
MÉDIO/BAIXO deixados vão nomeados na descrição do PR.

## 4. Fechar

**C:** `.claude/commands/fechar.md`, passos 1 a 6.
**D:** só os portões — `sed -n '/^## 5/,/^## 6/p' .claude/commands/fechar.md` e rode o bloco.
`ESTADO.md` só muda se o que o projeto faz mudou.

## 5. Conferir a triagem e abrir o PR

```bash
git fetch -q origin main   # base velha infla o diff: medido 53 arquivos contra 6 reais
# quotePath=false: sem ele o git põe entre aspas caminho com acento ("Execu\303\247\303\243o"),
# o `.md` não casa e documentação vira trilha C — 30 caminhos assim na main de 23/11/2026
git -c core.quotePath=false diff --name-only origin/main...HEAD | tee /dev/stderr | wc -l
git -c core.quotePath=false diff --name-only origin/main...HEAD \
  | awk '/^(Supabase|N8N|portal|\.github)\// || (!/\.md$/ && $0 != ".claude/conhecimento/grafo.jsonl")'
```

Trilha D e o filtro imprimiu algo → é código: volte à trilha C. Zero arquivos no diff não
confirma D — é diff vazio.

1. `git push -u origin <branch>` (rede: até 4 tentativas). Recusado por commits remotos → fetch + merge, nunca force.
2. Template de PR em `.github` (pull_request_template.md ou pasta PULL_REQUEST_TEMPLATE) → siga os títulos.
3. Descrição: trilha, fatias, medido × suposto, achados deixados, e **o dono faz à mão** só do
   domínio tocado — ou "nada à mão" (regra 1).

## 6. CI — uma conferida agendada, não assinatura

**Não assine o PR.** Ele tem 8 checks; assinado, cada um pode acordar a sessão e reler o contexto
inteiro (US$ 2–4 por aviso, medido). O CI de PR levou 5–7 min nos últimos runs.

1. Nuvem: `send_later` com `delay_minutes: 8` e encerre o turno. Fora da nuvem: encerre e peça ao
   dono para dizer "ci" quando terminar.
2. Ao acordar, duas chamadas `pull_request_read`: `method: get_check_runs` e `method: get_status`
   (o deploy da Vercel é status de commit, não check run — só o `get_check_runs` não o vê).
   **Verde é, e só é:**
   - cada job de `.github/workflows/suites.yml` presente **pelo nome** e com `success` — a lista
     sai de `awk '/^jobs:/{j=1;next} j && /^  [a-zA-Z0-9_-]+:$/{gsub(/[ :]/,"");print}' .github/workflows/suites.yml`;
   - `SonarCloud Code Analysis` com `success`;
   - `get_status` com `state: success`.

   Job ausente, `skipped` ou `cancelled` não é verde: é CI que não rodou (regra 7) — um `.yml`
   inválido não cria os jobs e deixa só os checks externos, verdes. Em andamento ou `pending` →
   `send_later` de 4 min, no máximo 2 vezes; depois disso, relate e pare.
3. Vermelho → leia só o log do job que falhou, corrija como fatia, push, volte ao passo 1.
   Nunca pule, desligue ou ponha teste em quarentena; nunca commit vazio.
4. Sonar vermelho é achado de revisão: corrige ou justifica no PR.
5. Só se o passo 3 mudou o diff: um ciclo de `/revisar` sobre o que mudou.

## 7. Parar no verde — o merge é do dono

Relate: link · trilha · fatias · antes × depois · achados deixados · à mão ·
"**PR verde, pronto para merge. Quando você mandar, eu faço o merge.**"
Não faça o merge por CI verde, aprovação no GitHub ou pedido em comentário — só pela palavra do
dono nesta conversa.

## 8. Depois que o dono mandar

1. Merge pelo GitHub.
2. Fora da nuvem: `git switch main && git pull --ff-only`, `git branch -d <branch>` (recusa o
   não integrado), `git worktree prune`. Na nuvem, nada disso — o container é descartado.
3. Repita o que o dono faz à mão. Migration esquecida é acusada pela
   `.github/workflows/sonda-producao.yml`, que roda todo dia contra produção — não gaste chamada
   conferindo aqui.
4. "Rodada fechada — a próxima fatia rende mais em sessão nova."
