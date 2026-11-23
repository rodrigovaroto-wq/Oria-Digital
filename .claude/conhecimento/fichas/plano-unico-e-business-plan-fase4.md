---
id: plano-unico-e-business-plan-fase4
tipo: doutrina
toca:
  - Business Plan/README.md
  - Business Plan/06_execucao/PLANO_DE_EXECUCAO.md
  - Business Plan/07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.3.html
  - Business Plan/03_agentes/AGENTES.md
  - Business Plan/04_regras_de_negocio/REGRAS_E_DEFINICOES.md
  - Business Plan/08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md
substitui: []
---

# O plano em vigor é um só, e o negócio mora em `Business Plan/` (Fase 4, 23/11/2026)

Termos de busca: plano de execução, plano em vigor, roadmap, o que falta, próximo passo, piloto,
Oria Partners, v1, portão G0, G1, G2, G3, agentes, Supervisor, Auditor, Conferidor, registro de
decisões, v0.1.3, decisão, K6, R2, estudo de infraestrutura, business plan, modelo de negócio,
pendências, riscos, MAPA_DE_EXECUCAO, PLANO_MVP, superado.

**O que surpreende quem chega:**

1. **Os planos de `Arquitetura do Sistema/3 Estado e Execução/` estão superados** (MAPA_DE_EXECUCAO,
   PLANO_MVP_2026-11, PLANO_DE_EXECUCAO_2026-11, PRONTIDAO_POR_ESTAGIO, PLANO_LINHA_A_LINHA e o roadmap
   do ARQUITETURA_ALVO). Ainda são citados em ~50 comentários de migration e de código como origem de
   uma fatia — isso é histórico, não instrução. O que falta está em
   `Business Plan/06_execucao/PLANO_DE_EXECUCAO.md` (decisão K1), e é ele que o `estado-e-handoff` e o
   `/fechar` atualizam.
2. **O plano não tem datas** (K2): só sequência, dependências e critério de pronto. Não reponha datas.
3. **Nenhum agente do produto existe** (19/11/2026). Os 7 de `.claude/agents/` são do desenvolvimento.
4. **A infraestrutura não está decidida** (R2): LangGraph, Cloud Run, Supabase, n8n e Langfuse são
   candidatos de um estudo com ≥ 5 opções por item, que é o item 0.1 e vem antes do primeiro mandato.
5. **Decisão nunca se edita:** mudança vira registro v0.1.4 (ver `Business Plan/07_decisoes/README.md`).
6. **Uma fonte por assunto:** negócio em `Business Plan/`, técnica em `Arquitetura do Sistema/`, deck
   derivado em `Apresentações/` (K5). Não copie conteúdo entre elas; aponte.

**Riscos urgentes medidos na Fase 4** (itens 0.2–0.7): banco sem backup fora do provedor; n8n com a
chave `service_role`; `0041_dial_manda.sql:419` põe a extração em N2 sem medição; proteção do `main`
não conferida; sem contrato de dados com o provedor de IA.
