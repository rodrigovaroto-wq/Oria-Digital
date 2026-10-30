---
id: redesenho-portal-fases-1-a-5
tipo: doutrina
toca:
  - Supabase/migrations/0216_o_acesso_que_so_o_portal_decidia.sql
  - portal/src/lib/supabase/acesso.ts
  - portal/src/lib/supabase/equipe.ts
  - portal/src/lib/assinatura-do-envio.ts
  - N8N/lib/assinatura-do-envio.mjs
  - N8N/build-workflow.mjs
  - portal/src/components/botao-discricao.tsx
  - portal/src/components/form-de-acao.tsx
  - Arquitetura do Sistema/7 Marca/REDESENHO_DO_PORTAL.md
prova: Supabase/test/run.sh
ancora: portal/src/lib/assinatura-do-envio.ts#VALIDADE_DO_TOKEN_S
ancora_sha: 0c58656bdb31
substitui: []
---

# O redesenho do portal (fases 1 a 5): o que um agente precisa saber antes de mexer

**Antes de tudo, o que NÃO foi visto.** Nenhuma tela autenticada foi aberta em navegador
(o container não tem sessão Supabase). O que está provado é o banco (`run.sh`, 217 asserts de
`acesso_por_caso.test.sql`) e o código (`tsc`, `eslint`, os `verificar-*.mts`). Qualquer afirmação
sobre como a tela se comporta é leitura de código, não observação.

## Acesso por mandato é do BANCO, não da tela (0216)

Até a 0216, toda policy de `authenticated` era `using (true)`: qualquer usuário logado lia e
escrevia todos os mandatos, e o portal só escondia o que a interface não mostrava. Eram 65
policies em `public` mais 1 em `storage.objects`, todas `using (true)` exceto uma. A 0216 troca
por policy por mandato, com três papéis: **Sócio** (tudo), **Analista** (lê e escreve onde está
alocado, cria mandato), **Leitura** (só lê onde está alocado). Sem papel, nada.

- A decisão de papéis é do dono (29/10/2026), não da sessão. Ela está em `REDESENHO_DO_PORTAL.md`.
- O n8n e o SQL Editor **não** são afetados: ligam com `postgres` (BYPASSRLS) ou `service_role`,
  e as guardas deixam passar a conexão de serviço (`fn_conexao_de_servico`). Isso está confirmado
  **no repositório**; em produção, não medido.

**Armadilha que custou uma correção:** UPDATE ou DELETE negado por policy afeta **zero linhas e
não dá erro**. Uma função que "aprova" ou "exclui" respondia sucesso depois de não mudar nada.
Medido na primeira versão da 0216, com `fn_mudar_dial`: gravava `mudanca_dial` na trilha sem mudar
o dial. Por isso a operação reservada ao Sócio (aprovar, fechar, excluir mandato, dial, equipe) é
**guarda em gatilho**, não policy.

**Bootstrap perigoso:** a 0216, ao ser aplicada com `membro` vazia, promove a Sócio **todo**
usuário de `auth.users`. Quem é convidado externo vira Sócio. Isso não é um detalhe de deploy; é o
primeiro passo do dono.

**Recusa como valor.** A server action devolve `{ erro }`, não lança. Em produção o Next redige a
mensagem de um erro lançado (ver o comentário de `portal/src/components/form-de-acao.tsx`). Quem
lança vê uma mensagem genérica no lugar da frase que o banco mandou.

## Token do envio: o Form do n8n é público, então a URL não basta (96df48d)

O Form de ingestão tem URL única para todos os mandatos. Antes, um Analista alocado só em um
mandato pegava a URL e postava com outro nome de mandato, e o n8n gravava pela conexão de serviço.
Agora `/api/intake` emite um token `v1.<exp>.<usuario>.<HMAC-SHA256(segredo, mandato|exp|usuario)>`
com validade de 30 minutos (`VALIDADE_DO_TOKEN_S`, `portal/src/lib/assinatura-do-envio.ts`). O n8n
confere o token antes de criar mandato ou gravar documento.

- **Fail closed:** sem `N8N_INTAKE_SEGREDO` no portal, responde 503 "envio desligado"; sem o
  segredo no n8n, recusa todo envio.
- O segredo tem de ser o **mesmo** nos dois lados. O n8n lê `$env` e, se vazio, `$vars`
  (`N8N/build-workflow.mjs`, 810–811). Por padrão o n8n bloqueia `$env` em nó Code.
- **A prova deste ponto é a suíte do n8n** (`N8N/test/assinatura-do-envio.test.mjs`, dentro dos 693),
  não a `run.sh` que está declarada acima. Esta ficha só declara uma prova; o token tem outra.

## Modo discrição é proteção VISUAL, e tem um vazamento conhecido

O modo discrição borra os valores financeiros (`botao-discricao.tsx`, classe `valor-sensivel`). A
proteção é só visual, e o limite está declarado na própria tela. Vazamento **conhecido e não
corrigido**: `title={doc.resumo}` em `portal/src/app/casos/[id]/documentos/(lista)/page.tsx`, na
linha 335, fica no mesmo elemento marcado como sensível. Não medido se o resumo traz valor. Nenhuma
suíte cobre o modo discrição.

## Os números que esta ficha afirma

O número de 30 minutos é do token e está ancorado em `VALIDADE_DO_TOKEN_S`. Se ele mudar, esta
ficha fica SUSPEITA e tem de ser relida: o TTL é o que limita um token vazado a um mandato.

Para o estado do que falta, a fonte é `REDESENHO_DO_PORTAL.md`, seção "Pendências conhecidas". Esta
ficha não repete a lista para não envelhecer junto com ela.
