# Prompt para a sessão da Fase 4 — Oria Digital

> Cole o texto abaixo (a partir de "ORIA DIGITAL — FASE 4") como primeira mensagem de uma sessão nova do
> Claude Code neste repositório. Ele é autossuficiente: aponta para os arquivos que contêm todo o contexto.

---

ORIA DIGITAL — FASE 4: PLANO DE EXECUÇÃO E PASTA `Business Plan`

Atue como arquiteto sênior de sistemas multiagentes, especialista em IA, engenharia de software, estratégia
empresarial e reestruturação financeira. Esta é a **Fase 4** de um trabalho de quatro fases. As Fases 1 a 3 já
foram feitas e **aprovadas por mim** numa sessão anterior (PR rodrigovaroto-wq/Oria-Digital#304). Não refaça
nem reabra o que já foi decidido: construa em cima.

## 1. Leia primeiro (nesta ordem; é aqui que está todo o contexto)

1. `CLAUDE.md` — regras do projeto (estilo de resposta, as sete regras, `buscar.mjs` antes de abrir arquivo,
   uma fatia por commit, agentes especialistas, PR e CI). Valem para tudo o que você fizer.
2. **Registro de decisões v0.1.3** — `Business Plan/_trabalho_fase1/registro_de_decisoes/oria_digital_decisoes_e_pendencias_v0.1.3.html`.
   As seções 1–18 são o registro v0.1.2 preservado; a **seção 19** traz as 88 decisões da entrevista de
   definição, as revisões da v0.1.2 (19.12), as pendências (19.13), o que saiu do escopo (19.14) e os
   **requisitos técnicos derivados (19.15)**. É a fonte de verdade das decisões.
3. `Business Plan/_trabalho_fase1/03_rascunho_adendo_v0.1.3.md` — o mesmo conteúdo pergunta a pergunta, com a
   minha fala literal e as conferências (útil quando houver dúvida de interpretação).
4. **Workflow v0.3.0** — `Business Plan/_trabalho_fase1/workflow/oria_digital_workflow_v0.3.0.html`
   (e o gerador `gerar_workflow_v030.py`). Cada bloco tem selo de status: EXISTE, EXISTE · EVOLUIR, PILOTO,
   V1, FUTURO, EM ESTUDO.
5. **Business Plan v2** — `Apresentações/Business Plan Oria Digital/` (deck oficial e `DOCUMENTACAO.md`,
   que tem o status real de cada agente na seção 5).
6. `Business Plan/_trabalho_fase1/01_sintese_da_pesquisa.md` — pesquisa da Fase 1 (agentes, extração, dados
   brasileiros, LLMOps, segurança/LGPD, mercado), com fontes.
7. Estado do sistema: `ESTADO.md` (topo) e os planos existentes em `Arquitetura do Sistema/3 Estado e Execução/`
   (`ARQUITETURA_ALVO_E_ROADMAP.md`, `PLANO_MVP_2026-11.md`, `PLANO_DE_EXECUCAO_2026-11.md`,
   `MAPA_DE_EXECUCAO.md`, `PRONTIDAO_POR_ESTAGIO.md`, `DESENHO_QUATRO_FUNCOES_2026-11.md` e outros). **Não
   presuma que estão atualizados nem que o que descrevem está implementado** — confira no código e, para o
   banco, pela sonda `fn_instalacao_conferir()`.

## 2. Decisões que mais pesam no plano (resumo; o detalhe está na seção 19)

- **A1/A2:** evoluir o sistema atual, sem reconstruir; agentes desde já, aos poucos; a **v1 inclui agentes e
  monitoramento**.
- **A3:** Oria Digital e Oria Partners são **empresas separadas**; a Partners é a **primeira cliente piloto**.
- **K6 — primeira entrega da v1 = piloto com a Partners:** book Excel confiável; extração com captação externa
  (SPED, Registrato, OFX) e cruzamento pelo Conferidor; agentes Conferidor, Dívida, Caixa e Mercado, com
  Supervisor e Auditor; todos os dados de mercado captados e atualizados; portal do cliente (envio e
  acompanhamento, link seguro); dossiê de processos e notícias. O restante da v1 vem em entregas seguintes.
- **R2:** o **estudo comparativo de infraestrutura** (≥ 5 opções por item — coordenação/hospedagem dos agentes,
  banco de dados, automação, observabilidade — com custo, complexidade e capacidade) é a **primeira entrega do
  plano** e termina antes do primeiro mandato do piloto. LangGraph, Cloud Run, Supabase, n8n, Langfuse são
  **candidatos**, não decisões (H1, H2, H3, H5).
- **K4:** riscos urgentes (backup, n8n com chave de acesso total, contrato de dados com a IA, extração aceitando
  linhas sem medição, proteção do repositório) resolvidos **em paralelo** ao piloto; contrato com a IA, backup
  provisório (H1-1) e **RIPD (I5)** prontos antes do primeiro mandato do piloto.
- **D3 (revisada):** extração por código primeiro, IA só onde falhar, IA revisora em PDF/imagem; captação externa;
  cruzamento com o dado externo como referência e **os dois valores guardados**.
- **B2/B4/B5/B3b-1:** agentes nunca calculam; o motor recalcula; o Auditor revisa a execução; até 3 tentativas;
  Supervisor decide só baixo impacto (< 1% da linha e < 0,5% do EBITDA ou da dívida).
- **D6:** autonomia N2 exige ~300 amostras (parte cega) e ≥ 98%; a extração volta a N1 até medir.
- **E1/R1/E2:** segundo revisor humano para o que vai para fora (no piloto, um analista da Partners); papel
  **Técnico** separado; quem propõe não aprova.
- **F1–F6:** autoaprimoramento só propõe (prompts e regras) até ≥ 50 erros validados pelo Auditor em ≥ 3
  etapas e ≥ 60% de propostas aprovadas; publicação por tipo; reversão por chave liga/desliga; backtest
  anonimizado; gabarito com parte oculta.
- **H4/H6/H7/H8/I2:** isolamento por organização (RLS), trilha com hash, metas de recuperação, três ambientes,
  retenção em três camadas.
- **J1/J2/J6:** cobrança por mandato + assinatura + licença + bônus variável; valores depois do piloto; o
  sistema mede dias, horas, custo, erros e achados em R$ por mandato.
- **K1:** um **plano de execução único e novo**; os planos antigos ficam como histórico, com nota "superado por …".
- **K2:** o plano **não tem calendário**: sequência, dependências e critérios de pronto.
- **K3:** hoje constroem o dono + Claude (Claude implementa, revisa e documenta, nunca aprova); o plano marca o
  que depende de pessoas que ainda não existem (Técnico, segundo revisor).
- **K5:** `Business Plan/` = fonte oficial de **negócio e produto**; `Arquitetura do Sistema/` = fonte oficial
  **técnica**; referências cruzadas, sem cópia; `Apresentações/` = o deck, derivado.

## 3. O que a Fase 4 entrega

### 3.1 Plano de execução (único, novo)
- Adapte o planejamento existente à arquitetura e às decisões aprovadas.
- Para cada item: fase, tarefa, prioridade, dependências, responsável (papel) e **critério de pronto** medível.
- Diga, item a item, o que **já está implementado**, o que **precisa ser corrigido** e o que **ainda será
  desenvolvido** — com evidência (arquivo, migration, suíte), sem confundir planejado com implementado.
- Sequência eficiente, com **paralelismo** onde não houver dependência nem arquivos em comum.
- Separe **piloto (primeira entrega da v1)**, **restante da v1**, **evolução operacional** e **arquitetura final**.
- Sem datas (K2). O estudo de infraestrutura vem primeiro (R2).

### 3.2 A pasta `Business Plan/` (fonte central do negócio)
Organize em subpastas e arquivos com nomes claros, com um `README.md` índice e referências cruzadas:
business plan; workflow e arquitetura; estrutura e responsabilidades dos agentes; regras de negócio e
definições operacionais; memória, autoaprimoramento e governança; modelo de negócio, proposta de valor e
estratégia comercial; plano de execução e roadmap; **histórico versionado das decisões**; pendências, riscos e
questões futuras; e o que mais for estrutural para construir e operar o sistema.
- **Uma fonte oficial por assunto**, com links nos demais lugares — nada de copiar o mesmo conteúdo em dois arquivos.
- O material provisório (`_trabalho_fase1/`, `_trabalho_fase3/`) é **reorganizado**, não perdido: históricos
  (registros v0.1.2 e v0.1.3, workflows v0.1/v0.2.0/v0.3.0, lotes da entrevista, comparativos) ficam
  preservados num lugar de histórico.
- **Não apague nenhum arquivo existente sem a minha autorização.** Mover/renomear também pede autorização.

### 3.3 Validação final de consistência
- Business Plan, workflow, registro de decisões e plano de execução dizem a mesma coisa?
- Toda funcionalidade planejada tem requisito, dependência e critério de implementação?
- Liste o que depende de testes, de fornecedores (integrador de dados, Open Finance, registradoras, provedores
  de IA, plataformas do estudo) ou de decisões futuras (seção 19.13).
- Apresente a estrutura final da pasta e um resumo das alterações.

## 4. Regras desta sessão

1. **Antes de escrever qualquer arquivo**, me apresente: (a) a estrutura proposta da pasta `Business Plan/`,
   (b) o esqueleto do plano de execução (fases e marcos, sem datas) e (c) a lista de arquivos que serão
   criados, movidos ou marcados como superados. **Aguarde minha aprovação.**
2. Se faltar informação relevante, **pergunte**, uma pergunta por vez, com alternativas e a sua recomendação.
   Não tome decisões estratégicas por conta própria e não reabra decisões da seção 19 sem motivo forte (se
   achar um, aponte e pergunte).
3. Preserve todas as decisões anteriores. Mudança = revisão registrada (nova versão do registro, v0.1.4), nunca
   sobrescrita.
4. **Não modifique código funcional nem infraestrutura de produção.** Só documentação.
5. Siga o `CLAUDE.md`: `buscar.mjs` antes de abrir arquivo; uma fatia por commit com mensagem que conta o
   motivo; `node .claude/conhecimento/conferir.mjs` antes de cada commit; branch própria e PR em rascunho;
   CI e SonarCloud verdes.
6. Use os agentes do projeto quando fizer sentido (por exemplo, `explorador` para mapear o que está
   implementado, `revisor-defeito-silencioso` para revisar a consistência) e pesquise na web quando precisar
   de referência atual.
7. Respostas diretas, frases curtas, termo técnico explicado em seguida.

## 5. Pontos ainda em aberto que você vai encontrar

- O estudo de infraestrutura (R2) ainda não foi feito: o plano deve tratá-lo como primeira entrega.
- Valores (teto de dados pagos, teto de IA, preços) dependem do piloto.
- Parcerias: integrador de dados pagos (C2), Open Finance (C4, Res. Conjunta 21/2026), registradoras (C6).
- Parecer jurídico pendente para C3, C7, D1, F4, I2 e I5.
- Quem monta o gabarito de páginas reais (D4); quem tem o papel Técnico além do dono (E2).
- N-C5a (gestão das integrações), B6 (priorização das 31 frentes de diligência) e A6 (primeiro cliente além da
  Partners) seguem em aberto.
- No BP v2, saiu do slide 10 o prazo "3 a 6 meses" e ficou no slide 5 "mais de 30 fontes"; eu não fechei
  esses dois pontos — pergunte se precisar.

Comece lendo os arquivos da seção 1 e me apresente o item 4.1 (estrutura proposta, esqueleto do plano e lista
de arquivos) para aprovação.
