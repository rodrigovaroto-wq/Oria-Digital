# Prompts — o roteiro, não o estado

Cada arquivo aqui é um prompt colável. **Nenhum deles guarda número, PR ou nome de branch.**

Essa regra tem causa: o antigo `PROMPT_CONTINUACAO.md` (removido em 18/11/2026) virou uma fotografia da sessão 19 —
mandava trabalhar na branch `claude/handoff-next-steps-6k88f2`, no PR #69, contra 160 testes e 32
migrations. Nada disso era verdade 50 sessões depois, e o prompt continuava mandando começar
errado. **Um prompt que cita estado envelhece; um prompt que aponta para quem mede o estado, não.**

| Prompt | Quando usar |
|---|---|
| [`00-continuacao.md`](00-continuacao.md) | Abrir uma sessão nova de trabalho autônomo |
| [`01-rodada-real.md`](01-rodada-real.md) | Depois que o dono rodou um book de verdade |
| [`02-revisao-multilente.md`](02-revisao-multilente.md) | Antes de fechar qualquer fatia não trivial |
| [`03-onda-paralela.md`](03-onda-paralela.md) | Transformar um plano em ondas de execução seguras |
| [`04-defeito-sem-erro.md`](04-defeito-sem-erro.md) | Um estágio "está verde" e você não confia |
| [`05-gate-de-fase.md`](05-gate-de-fase.md) | Entrar ou sair de uma fase do roadmap |

## Um roteiro externo de 9 guias já está atendido aqui — não o reexecute do zero

Um pipeline genérico de auditoria → arquitetura → fase → red team → review → commit → checkpoint →
retomada → gate foi avaliado em 16/09/2026. **Oito dos nove já tinham dono neste repositório**, e
rodá-los como se fossem novos produziria uma segunda descrição do mesmo estado — o defeito que
este projeto chama de lente central.

| Etapa do roteiro externo | Quem já responde por ela aqui |
|---|---|
| Auditoria do estado | `Arquitetura do Sistema/4 Análises e Auditorias/` — a próxima produz o **delta**, não outra varredura do zero |
| Plano e roadmap | `Business Plan/06_execucao/PLANO_DE_EXECUCAO.md` (plano único em vigor, portões G0–G3). Referência técnica: `3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md` — inclui as 23 camadas, os 5 gates, o dependency graph, o MVP, o DO NOT BUILD YET e o mapeamento contra a numeração de fases proposta (seção 7) |
| Execução de uma fase | `/rodada` |
| Red team | `04-defeito-sem-erro.md` + `revisor-defeito-silencioso` |
| Code review | `/revisar` |
| Commit / PR | `/fechar` passo 1, sobre a regra 6 |
| Checkpoint | `/fechar` |
| Retomada após interrupção | `00-continuacao.md` |
| **Gate entre fases** | **`05-gate-de-fase.md`** — era a única sem dono |

Quem responde pelo estado, sempre: `ESTADO.md` (onde estamos) · `Business Plan/06_execucao/PLANO_DE_EXECUCAO.md` (o que
falta) · `fn_instalacao_conferir()` (o banco) · `.claude/memory/MEMORY.md` (o que já custou caro).
