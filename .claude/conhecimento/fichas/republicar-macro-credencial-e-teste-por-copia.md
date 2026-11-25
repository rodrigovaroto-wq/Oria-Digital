---
id: republicar-macro-credencial-e-teste-por-copia
tipo: armadilha
toca:
  - N8N/republicar.sh
  - N8N/preparar-republicacao.mjs
  - N8N/build-workflow-macro.mjs
prova: N8N/test/*.test.mjs
ancora: N8N/preparar-republicacao.mjs#idsDeCredencialDoAmbiente
ancora_sha: 43c37c348932
substitui: []
---

# Republicar o macro: a credencial nova trava pelo nome, e o teste real só sai por uma cópia com webhook

Termos de busca: republicar, macro, credencial, REPLACE, N8N_CRED_IDS, Supabase Postgres,
Postgres (Trat. Dados), D7NYaWY1UYKy2vBc, nó novo, executar, disparar, webhook, cópia temporária,
teste ponta a ponta, produção, UGhv57BU3YNukVxV.

## O que surpreende quem chega aqui

- **Nó Postgres NOVO trava a republicação.** O gerador do macro nomeia a credencial "Supabase
  Postgres"; a instalação a chama "Postgres (Trat. Dados)" (id `D7NYaWY1UYKy2vBc`, a mesma da
  ingestão). Nó que já existia herda o id do publicado; nó novo procura pelo NOME e não acha. Medido
  em 25/11/2026: os 5 nós "Registrar Consulta*" ficaram em REPLACE e o `republicar.sh` abortou no
  passo 4. Destrava por ambiente, sem tocar no editor:
  `N8N_CRED_IDS='{"Supabase Postgres":"D7NYaWY1UYKy2vBc"}'`.
- **A Action "Republicar workflow no n8n" só publica a ingestão** (o `N8N_WORKFLOW_ID` do secret).
  O macro (`UGhv57BU3YNukVxV`) sai pelo `republicar.sh` local, com `N8N_URL`,
  `N8N_WORKFLOW_ID=UGhv57BU3YNukVxV` e `N8N_ARQUIVO_REPO=N8N/workflow.macro.json`, a partir da
  `main` atualizada (o script recusa árvore atrás de `origin/main`, então: merge antes).
- **A API pública do n8n não dispara execução**, e o gatilho do macro é agendado. O teste ponta a
  ponta de 25/11 foi uma CÓPIA do workflow publicado com o gatilho trocado por um Webhook (POST),
  ativada, chamada uma vez, lida por `/executions/<id>?includeData=true` e apagada no `finally`.
  Ela grava em produção o mesmo que a execução das 06h gravaria (consultas reais e upsert
  idempotente nos índices). Resultado: execução 10048 `success` em 16 s, 37 consultas `encontrado`.
- **O webhook da cópia dá 404 logo depois de ativar** (registro atrasado). Medido em 25/11/2026 na
  sessão 140: a 1ª chamada deu 404 e nada rodou; com espera de 3 s e até 5 tentativas, deu 200
  (execuções 10051 e 10052, `success` em 12 s cada). A causa exata NÃO foi medida; o que foi
  medido é que esperar e repetir deu 200.

## O que NÃO se testa assim

O caminho "falhou" (derrubar uma fonte de propósito). `consulta_externa` é imutável: um "falhou"
fabricado ficaria para sempre no histórico da fonte. Esse caminho é provado pelos testes
(`N8N/test/workflow-macro-sim.test.mjs` e `Supabase/test/a_fonte_que_caia_e_parecia_nao_ter_nada.test.sql`).
