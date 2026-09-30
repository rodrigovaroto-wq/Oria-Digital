---
name: credencial-do-n8n-quebra-sem-deixar-rastro
description: a credencial Postgres do n8n ficou inválida entre 17/09 e 30/09 e NADA acusou — o workflow de erros grava pela MESMA credencial, então a falha não chega a `execucao_falha`; sonda e conferidor seguem verdes porque falam com o banco por outro caminho
metadata:
  type: feedback
tipo: ambiente
toca:
  - N8N/build-workflow-erros.mjs
  - Supabase/test/sonda-producao.mjs
---

**MEDIDO em 30/09/2026.** O mandato de teste subiu pelo portal, o n8n aceitou, e o caso não apareceu no
banco. A execução mostrava `Upsert Caso (Postgres)` com `password authentication failed for user
"postgres"`. O nó tem `onError: continueRegularOutput`, então o fluxo SEGUIU: classificou e mandou
os 14 documentos à IA, gastando token, sem gravar nada. Último sucesso da ingestão: 17/09.

## Por que ninguém viu

- O `Reportar Erros` (errorWorkflow) grava em `execucao_falha` pela MESMA credencial. Ele também
  falhou (execução 8311), e por isso a tabela de falhas não recebeu linha nenhuma.
- A sonda (`fn_instalacao_conferir`), o `conferir_chamadas.sql` e o workflow agendado
  `sonda-producao.yml` falam com o banco pela API de gerenciamento ou por `SONDA_DB_URL`. Todos
  ficaram verdes com o n8n cego. **Verde neles não diz que o n8n alcança o banco.**

É o `estagio-desligado-parece-limpo.md` na forma mais pura: o estágio que registra a falha é o que
falhou.

## Como conferir e corrigir

- **Conferir:** as últimas execuções do n8n (`GET /api/v1/executions?workflowId=...`), e no dado de
  UMA execução PEQUENA procurar a mensagem em `Upsert Caso`. Nunca baixe execução grande (ver
  `n8n-nao-aguenta-baixar-execucao-grande.md`).
- **Corrigir:** `PATCH /api/v1/credentials/<id>` com `{"data":{"password":...},"isPartialData":true}`.
  Isso troca só a senha; host, usuário e porta ficam. A versão da instância aceita
  `isPartialData`; numa versão sem ele, a validação recusa o corpo parcial em vez de sobrescrever.
- **Provar:** reenviar um lote e ver o caso nascer no banco.
