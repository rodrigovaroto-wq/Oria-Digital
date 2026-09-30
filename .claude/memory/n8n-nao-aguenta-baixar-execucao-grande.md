---
name: n8n-nao-aguenta-baixar-execucao-grande
description: `GET /executions/<id>?includeData=true` de uma execução com planilha de dezenas de milhares de linhas derrubou a instância do n8n (502 por ~2 min, 30/09/2026) — o dado não chega e a produção para; use `execucao_falha`/`evento_auditoria` no banco
metadata:
  type: feedback
tipo: ambiente
toca:
  - N8N/republicar.sh
---

**MEDIDO em 30/09/2026.** Para diagnosticar as execuções 7883 e 7886 (estouro de pilha no Merge),
tentei baixar o dado delas com `includeData=true`. A resposta não veio em 5 minutos, e o n8n (uma
instância pequena na pikapod) passou a responder **502 por uns 2 minutos**. Ele voltou sozinho, e
nenhuma execução estava rodando naquela hora.

**O que usar no lugar**, e é suficiente:
- `execucao_falha` e `evento_auditoria` no banco, só leitura pela API de gerenciamento do Supabase.
  Eles têm a etapa, a mensagem e a mensagem do orçamento com o nome de cada arquivo.
- Para a TOPOLOGIA do problema, o fonte do nó em `n8n-nodes-base`, baixado do npm (no caso,
  `Merge/v3/actions/mode/append.js`).
- `includeData=true` só em execução PEQUENA, com `timeout` no curl. Uma execução de 14 PDFs
  (1,9 MB de JSON) desceu sem problema.
