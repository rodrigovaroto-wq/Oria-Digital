# P3 — o envio passa a ser roteado pelo `caso_id`

**Data:** 04/11/2026, sessão 117 · **Decisões do dono (04/11):** produção autorizada na sequência inteira; mandato
FECHADO recusa envio; nome divergente é aceito e auditado.

## O defeito

Hoje o n8n acha o mandato pelo **nome** que chega no Form (`fn_upsert_caso($1::text)`). Se o mandato for
renomeado entre a emissão do token e o envio, o nome antigo ficou livre, e o `fn_upsert_caso` **cria um mandato
novo e vazio** com ele. Os documentos vão para lá, sem erro nenhum.

Há uma segunda porta para o mesmo defeito: o portal deixa o Sócio receber token para **qualquer** nome
(`portal/src/lib/supabase/acesso.ts:45`), e o primeiro envio cria o mandato.

## A regra nova

1. **Só o passo 1 ("Novo mandato") cria mandato.** O envio nunca cria.
2. O portal identifica o mandato pelo `casoId` (`/destino?caso=<id>`), e o token só sai para um caso que o
   portal acabou de ver existir.
3. O `caso_id` vai **dentro do token**. O Form do n8n não muda de campo.
4. O nome que chega no Form vira só rótulo. Se divergir do nome atual, o envio é aceito e grava 1 evento de
   auditoria com os dois nomes.

## O token v2

`v2.<exp>.<usuario_uuid>.<caso_uuid>.<hmac>`, com o HMAC sobre **`v2|<caso_id>|<exp>|<usuario>`** e os dois
uuids em minúsculas.

**A etiqueta `v2|` é obrigatória.** Sem ela, a mensagem do v2 coincide com a do v1
(`normalizar(nome)|exp|usuario`). Um Analista criaria um mandato chamado `<uuid de outro caso>`, pediria um
token v1 para ele e o reescreveria como v2 do outro caso, com o mesmo HMAC.

## O que o banco passa a conferir (`fn_conferir_envio`, migration 0222)

Mesma assinatura e mesmas colunas de saída, para o nó publicado do n8n não mudar. No v2, nesta ordem:

| Ordem | Motivo da recusa | Por quê |
|---|---|---|
| 1 | `sem_segredo`, `sem_token`, `malformado`, `assinatura` | como hoje; a assinatura vem antes de qualquer consulta, para quem não tem o segredo não descobrir se um id existe |
| 2 | `expirado` | como hoje |
| 3 | `caso_inexistente` | o caso foi apagado |
| 4 | `caso_fechado` | decisão do dono: mandato fechado não recebe documento |
| 5 | `sem_acesso` | no momento do envio, o usuário não é Sócio nem Analista alocado (papel ou alocação removidos dentro dos 30 min derrubam o envio) |

A regra de acesso não é duplicada: `fn_pode_escrever_caso_de(usuario, caso)` recebe o corpo de hoje, e
`fn_pode_escrever_caso(caso)` passa a delegar a ela com `auth.uid()`.

## Implantação, sem janela que recuse envio legítimo

| Fatia | O quê | Produção |
|---|---|---|
| **F1** | `N8N/lib/assinatura-do-envio.mjs`: `mensagemAssinadaV2`; a conferência de referência aceita v1 e v2 | — |
| **F2** | Migration **0222**: v1 igual a hoje; v2 com as conferências acima; `fn_caso_do_envio(caso, nome)` (falha fechada e auditoria do nome) | aplicar 0222 |
| **F3** | n8n: o `Upsert Caso` usa o `caso_id` do v2; um v1 em voo ainda cai no nome; o nó passa a falhar fechado | republicar |
| **F4** | Portal: só emite v2, `casoId` em todo o caminho, acompanhamento do lote por id | deploy do portal |
| **F5** | Depois de 30+ min sem nenhum v1 aceito: migration **0223** recusa o v1; o n8n perde o caminho por nome | aplicar 0223 e republicar |

**Ordem errada e o custo:** portal antes da 0222 faz **todo** envio ser recusado como `malformado`.

## O invariante (regra 2)

Renomear o mandato entre a emissão do token e o envio. O lote tem de cair no **mesmo** `caso_id`, nenhum caso
pode ser criado, e 1 auditoria registra o nome antigo. O controle é o próprio defeito: `fn_upsert_caso('nome
antigo')` cria um caso a mais. O teste vai em duas camadas: SQL (`conferir_envio.test.sql`) e n8n
(`workflow-sim.test.mjs`), com o número de asserts que reprovam no roteamento antigo.

## Riscos que podem quebrar em silêncio (regra 7)

- **O caminho por nome da transição nunca ser removido.** A F5 tem critério próprio e um teste que reprova se
  `fn_upsert_caso` aparecer no workflow depois dela.
- **Upsert com `continueRegularOutput`:** um caso apagado entre a conferência e o upsert seguiria com
  `caso_id` vazio. Por isso o nó passa a falhar fechado.
- **Republicar o n8n perde toggles** (`.claude/memory/republicacao-do-n8n-perde-toggles.md`). São duas
  republicações, F3 e F5.
- **`null` cru no `queryReplacement`** desloca parâmetros: usar `?? ''` com `nullif`.
- **Uuid em maiúsculas** reprova a assinatura sem motivo aparente: minúsculas dos dois lados.
- **A sonda não vê a versão do n8n publicado.** O pronto da F3 é medido no n8n publicado, não só no JSON.
- **`fn_pode_escrever_caso` reescrita** está em várias policies: `acesso_por_caso.test.sql` tem de passar inteira.
