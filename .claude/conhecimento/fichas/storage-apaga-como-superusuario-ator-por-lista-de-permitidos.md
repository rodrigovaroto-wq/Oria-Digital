---
id: storage-apaga-como-superusuario-ator-por-lista-de-permitidos
tipo: armadilha
toca:
  - Supabase/migrations/0224_o_original_que_o_analista_apagava_sem_trilha.sql
  - Supabase/test/original_apagado.test.sql
  - Supabase/README.md
prova: Supabase/test/run.sh
---

**Armadilha (S118, 06/11/2026, migration 0224):** um gatilho em `storage.objects` NÃO vê quem
apagou pelo `auth.uid()`. A API do Storage apaga em duas etapas:

1. testa a RLS como o usuário, numa transação que é DESFEITA;
2. apaga de verdade como superusuário (`role = service_role`, `request.jwt.claim.sub = ''`).

O gatilho que dispara na etapa 2 grava "sistema" para toda exclusão, inclusive a do Analista. A
suíte não via porque fazia `DELETE` direto como `authenticated`, um mecanismo suposto (regra 3).

**O que funciona, medido em produção:** o Storage repassa os cabeçalhos do chamador em
`request.headers` e o nome da operação da rota em `storage.operation`. Exclusão real de uma
Analista em 06/11: `ator = e-mail dela`, `ator_origem = cabecalho_jwt`,
`storage_operation = storage.object.delete`, `papel_sessao = service_role`.

**A segunda armadilha, mais cara: lista de proibidos sobre texto do cliente.** Foram sete
revisões independentes até zero achado:
- a rota S3 (`/s3/*`) autentica por assinatura AWS e NÃO verifica o `Authorization`, mas o
  repassa. Um Bearer forjado atribuía a exclusão ao Sócio. O protocolo S3 está LIGADO no projeto;
- a guarda "o path tem /s3" foi burlada por `%73%33`, porque o roteador decodifica e a guarda não.

A terceira correção da mesma guarda trocou o desenho: **lista de PERMITIDOS sobre um valor que o
servidor define.** O JWT do cabeçalho só vale quando `storage.operation` é
`storage.object.delete` ou `storage.object.delete_many`, as rotas sob `registerJwtAuth`. Fora
disso, o ator é `storage:nao_identificado` com `ator_motivo`, nunca "Sistema" (regra 1).

**Regra geral:** quando uma guarda de segurança precisa de uma terceira correção, ela está
lendo a coisa errada. Troque o que é lido, não o padrão.

**Também na 0224:**
- a policy de INSERT de `evento_auditoria` exclui a ação, senão o Analista forjava a linha direto
  pelo REST;
- as sondas de policy contam QUALQUER outra policy permissiva (`anon` tem UPDATE em
  `storage.objects`);
- **limite declarado:** quem tem acesso SQL ao banco forja a trilha. Nenhuma trilha dentro do
  próprio banco impede isso.
