# Redesenho do portal — decisões, fases e o que ficou arquivado

> Aprovado pelo dono em 27/10/2026. A proposta visual completa (38 itens com
> prévia desenhada) foi publicada como página privada para o dono; este arquivo é
> a versão que mora no repositório e que as sessões seguem.

## Por que

O inventário das 13 telas (27/10/2026) mediu o problema, não o supôs:

- Dentro do mandato **não havia abas**. Revisão só era alcançável por uma faixa
  que aparece quando existe pendência; Apresentação só pela Modelagem; cada
  subtela tinha um "voltar" diferente (**cinco** formas).
- A página do mandato tinha **12 ações** e **7 seções** empilhadas (846 linhas);
  a Modelagem, **18 ações** e o export em **4** variações de botão.
- Cerca de **35 explicações** viviam só em `title=` (dica de mouse), que não
  existe no toque — e o celular é a cena de uso 3 do `PRODUCT.md`.
- A tela mostrava ao usuário números de migration (0120, 0205, 0208, 0212),
  nomes de função (`fn_*`), `notify pgrst`, um `select * from …` e erro em JSON
  cru — e nenhuma tela tinha `loading`/`not-found`; só a Modelagem tinha `error`.

## Decisões do dono

| # | Pergunta | Decisão |
|---|---|---|
| 1 | Trocar os nomes de engenharia na tela? | **Sim** — ver a tabela em `PRODUCT.md` |
| 2 | Custo por mandato fica no Início? | **Não**, sai; não é argumento comercial |
| 3 | Outras casas vão assinar? | **Sim, no futuro** — arquivado |
| 4 | O cliente acessa o portal? | **Sim, no futuro**, o mandato da própria empresa — arquivado |
| 5 | Papéis de acesso? | **Sócio · Analista · Leitura** (29/10/2026). Sócio: tudo, em todos os mandatos, inclusive aprovar, fechar, excluir e gerir a equipe. Analista: lê e escreve só nos mandatos em que está alocado, e cria mandato (fica alocado nele). Leitura: só lê os mandatos em que está alocado. Sem papel: nada |
| 6 | Que itens de login entram? | **Só "Recuperar senha"** (29/10/2026). MFA e SSO Microsoft ficaram fora — arquivados |

## A navegação-alvo

- **Barra lateral:** `+ Novo mandato` · Início · Mandatos · (recentes) ·
  Administração (Qualidade da automação).
- **Barra superior:** trilha (Mandatos › Caso › Aba) e conta. Busca ⌘K, avisos
  e modo discrição entram nas fases 2 e 4.
- **Dentro do mandato, abas fixas na ordem do trabalho:** Visão geral ·
  Documentos · Pendências · Perguntas ao cliente · Grupo econômico · Modelagem ·
  Entregáveis. Régua de etapas no cabeçalho.

## Fases

| Fase | O que entrega | Itens |
|---|---|---|
| **1 · Estrutura** | Barra lateral nova com ícones próprios e só os recentes; trilha e conta no topo; fim da abertura animada e do rodapé fixo; abas fixas do mandato com régua de etapas; `loading`/`error`/`not-found`; renomes; jargão de engenharia fora da tela; cabeçalhos padronizados | 01–06, 14, 15, 25, 26, 28, 35 |
| **2 · Redistribuir** | Visão geral enxuta com "Próximo passo"; aba Pendências única (absorve Revisão e as 4 seções); Documentos com painel lateral; Entregáveis (3 arquivos + campos da apresentação); Modelagem com uma barra de salvar; Início com 4 indicadores e fila filtrável; Mandatos em tabela com menu ⋯; explicações visíveis no lugar de `title=`; busca ⌘K | 08–10, 12, 16–18, 20, 21, 27 |
| **3 · O que vende** | Histórico do mandato; "Ver no original" (CONFERIR antes se o arquivo original está guardado); Grupo econômico em organograma; perguntas em lote; novo mandato em 2 passos; Administração | 13, 19, 22–24, 33 |
| **4 · Acabamento** | Imagem de fundo (do dono) no login e na faixa do Início; indicadores refinados; movimento; celular; modo discrição; avisos; modo escuro | 07, 11, 31, 32, 36–38 |
| **5 · Comercial** | Papéis e acesso por mandato **no banco primeiro**; tela de equipe; recuperar senha. MFA e SSO Microsoft: arquivados em 29/10 | 29, 30 |

## Estado da execução — 29/10/2026 (rodada fechada)

> Fases 1 a 5 concluídas. Todo o trabalho está commitado em
> `claude/friendly-lamport-22ctle`, PR #265 (rascunho). Nenhum agente está
> rodando e não há nada em andamento. Cada fatia passou `tsc`, `eslint`,
> `next build` e os `verificar-*.mts` da época; as regras novas têm invariante
> medido não-vazio (o número de asserts que reprovaram está na mensagem de
> cada commit). Os números medidos nesta rodada estão na sessão 113 do
> `ESTADO.md`.
> **Nenhuma tela autenticada foi vista em navegador** — o container não tem
> sessão Supabase. A conferência visual é no preview da Vercel, e é o primeiro
> item de "O dono faz à mão".

### Finalizado

| Bloco | Commits | O quê |
|---|---|---|
| Decisões | `e4cade0` | PRODUCT/DESIGN/este arquivo; multiempresa e área do cliente arquivadas |
| **Fase 1** | `bdbbb6f`..`b9c44b8`, `95a447e` | Casco (barra com ícones e recentes, trilha, menu de conta), abas fixas + régua + menu ⋯, loading/erro/não encontrado, recusa do export em página, renomes, jargão em "Detalhes técnicos" |
| **Vidro** | `ea05123`, `f42fc77`, `e813d53` | Foto "ORIA DIGITAL" na tela inteira, barra e topo suspensos em vidro escuro, folha creme sem backdrop-filter; diálogos por portal; contraste medido |
| **Fase 2** | `17b1116`, `e4baac2`, `f40e4b3`, `91cd0d5`, `25154ab`, `d8185d1`, `8350713`, `ff36ad6`, `459f21a` | Entregáveis; Visão geral com Próximo passo; Documentos com painel lateral; Pendências única; Início com 4 indicadores e fila; Mandatos em tabela; Modelagem com barra de salvar; explicações visíveis; busca ⌘K |
| **Fase 3** | `805c759`, `53360e2`, `87b44fe`, `a2881c2`, `37b07c5`, `277b672`, `1b25441`, `24a8bf6`, `68dd476` | "Ver no original"; perguntas em lote com e-mail ao cliente; novo mandato em 2 passos; Grupo econômico em organograma; Administração (Qualidade da automação + Custos); Histórico do mandato (migration **0215** + tela pelo menu ⋯) |
| **Fase 4** | `bc0d1cf`, `28b5908`, `57f89ec`, `b90a05d`, `0275cc6`, `49408ff` | Modo discrição (borra valores financeiros; proteção só visual, limite declarado) e barra inferior no celular (`bc0d1cf`); avisos de processamento concluído no sino da barra superior (`28b5908`); modo escuro nos tokens, com contraste medido (`57f89ec`); correções da revisão da fase (`b90a05d`, `0275cc6`) e do script do `<head>` do casco (`49408ff`). As correções da revisão da Fase 4 (que cobre `bc0d1cf`) estão em `b90a05d` |
| **Fase 5** | `8aad1bb`, `b73cf15`, `ba91872`, `cf24d86`, `e6a6049`, `6e68c1e`, `96df48d` | Recuperar senha (`8aad1bb`). Papéis e RLS por mandato no banco: migration **0216** (`b73cf15`), corrigida antes de qualquer aplicação pela revisão independente (`ba91872`: alocação indevida pelo ON CONFLICT, nome de mandato duplicado, falhas órfãs). Telas: equipe com e-mail e "Aguardando liberação" (`cf24d86`, `e6a6049`), ações por papel e correções da revisão (`6e68c1e`). Envio de arquivos com token assinado por mandato, conferido no n8n antes de gravar (`96df48d`) |
| Correções | `9339d71`, `81aca9c`, `4813605`, `0e0f8f2`, `71f8a63`, `9fa4fe2` | Achados das revisões; Sonar; conferidor de chamadas reconhece o bucket do Storage; estado na pausa pedida pelo dono |

### Em andamento

Nada.

### O dono faz à mão

Ordem de deploy. Cada item diz de onde vem a instrução. Nada disto é feito
pelo repositório: correção que não chega ao ar não é correção.

**a. Aplicar a 0215 e conferir.** Depois da 0214 (aplicada em produção em
20/10/2026). Conferir: `select chave, presente, detalhe from fn_instalacao_conferir() where migration = '0215' and not presente;` → zero linhas. Fonte: `Supabase/README.md`.

**b. Antes e depois da 0216** (cabeçalho da `Supabase/migrations/0216_o_acesso_que_so_o_portal_decidia.sql` e `Supabase/README.md`):
1. Nomes de mandato duplicados. A 0216 **aborta** se houver:
   `select lower(btrim(nome)), count(*), array_agg(id) from caso group by 1 having count(*) > 1;`
   Renomeie ou funda antes.
2. Quem vira Sócio. A migration promove **todo** usuário que existe em `auth.users` no momento da aplicação. Conferir: `select id, email from auth.users`. Remova ou desative em Authentication > Users quem não deve ver tudo (convidado externo, conta de teste) **antes** de aplicar. Usuário criado depois nasce sem papel e não vê nada.
3. Aplicar a 0216 pelo mesmo caminho da 0215 (`Supabase/README.md`).
4. Ler os `WARNING` da migration. Se aparecer "policy de storage.objects que NÃO é deste repositório e foi mantida" e ela cobrir o bucket `documentos`, derrube-a à mão (o cabeçalho diz como).
5. Conferir o catálogo: `select chave, presente, detalhe from fn_instalacao_conferir() where migration = '0216' and not presente;` → zero linhas. E quem entrou: `select u.email, m.papel from membro m join auth.users u on u.id = m.usuario_id;`
6. Conferir que `postgres` e `service_role` têm BYPASSRLS. O n8n depende disso (ele grava pela conexão de serviço): `select rolname, rolbypassrls from pg_roles where rolname in ('postgres','service_role');`. **NÃO medido em produção** nesta rodada; esperado, pelo cabeçalho, os dois `true`.

**c. Segredo do envio** (`96df48d`; `portal/README.md`, `portal/.env.example`, `N8N/README.md`):
1. Gerar: `openssl rand -hex 32`.
2. Pôr o **mesmo valor** em `N8N_INTAKE_SEGREDO` na Vercel e no n8n. No n8n o workflow lê `$env.N8N_INTAKE_SEGREDO` e, se vier vazio, `$vars.N8N_INTAKE_SEGREDO` (`N8N/build-workflow.mjs`, linhas 810–811). Por padrão o n8n bloqueia `$env` em nó Code. Duas saídas: (i) `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`, com o trade-off de qualquer nó Code ler variável de ambiente; ou (ii) definir a Variable `N8N_INTAKE_SEGREDO` no n8n, que é o caminho sem o trade-off. Sem o segredo o n8n recusa todo envio (fail closed).
3. Ordem: segredo → deploy do portal (sem `N8N_INTAKE_SEGREDO` ele responde 503 "envio desligado") → republicar o workflow de ingestão pela Action "Republicar workflow no n8n".
4. Na republicação, o `republicar.sh` passa pelo `preparar-republicacao.mjs`, que restaura `onError`, `retryOnFail` e o `multipleFiles` do campo "Arquivos". **Conferir no editor** que "Arquivos" está com múltiplos arquivos marcado. Republicar pela API perdeu esse campo em 26–27/08 (`.claude/memory/republicacao-do-n8n-perde-toggles.md`).
5. O campo do token no Form se chama "Token do envio" (`N8N/build-workflow.mjs`, linha 2543), que é o padrão do portal. Nada a configurar.
6. **Pendente de 15/10/2026:** o secret `N8N_API_KEY` do GitHub dava 401 na Action de republicação. Sem atualizá-lo, a Action falha, e a republicação é à mão com `N8N/republicar.sh`. **NÃO CONFERIDO** se foi atualizado depois.

**d. Supabase Auth** (`portal/src/lib/recuperar-senha.ts`, commit `8aad1bb`). O repositório não declara estas configurações; o que o código espera está abaixo.
- **Site URL:** a produção.
- **Redirect URLs:** `/auth/confirmar**` de produção, de preview da Vercel e de localhost. Sem isto, o link do e-mail não volta ao portal.
- **Modelo de e-mail de recuperação:** o link tem de chegar a `/auth/confirmar`, com `token_hash` e `type=recovery`, ou com `code` (PKCE). Não há o modelo no repositório: **NÃO CONFERIDO**.
- **Mínimo de senha:** o portal já exige 10 caracteres no código (`SENHA_MINIMA = 10`). Ajustar o mínimo no painel do Auth é opcional.
- **SMTP próprio:** opcional. Sem ele, o envio usa o padrão do Supabase, com limite de envios.
- O teste ponta a ponta de recuperação é no preview, depois destas configurações.

**e. Olhar o preview da Vercel nas telas novas.** Nenhuma tela autenticada foi vista em navegador: Ver no original, Perguntas em lote, Novo mandato, Grupo econômico, Administração/Custos, Histórico, modo discrição, o celular, o sino de avisos, o modo escuro, a equipe (`/administracao/equipe`) e o login de recuperar senha (`/login/recuperar`). Conferir também que cada papel vê só o que a decisão 5 manda.

### Pendências conhecidas (curtas; não bloqueiam)

Status de cada uma: **CONFERIDO** = visto no código nesta rodada; **NÃO CONFERIDO** = relatado, sem medição nesta rodada.

- **n8n ainda roteia por nome do mandato** (CONFERIDO no cabeçalho da 0216). Trocar por `caso_id` é outra rodada.
- **Tooltip com o resumo vaza no modo discrição** (CONFERIDO: `portal/src/app/casos/[id]/documentos/(lista)/page.tsx:335`, `title={doc.resumo}` num elemento `valor-sensivel`). Não medido se o resumo traz valor financeiro.
- **`createSignedUrl` com objeto ausente não exercitado** no Storage real (NÃO CONFERIDO). Se assinar sem erro, o clique cai num 404 do Storage.
- **Novo mandato sem Produto e Responsável** (CONFERIDO: `portal/src/components/novo-mandato-passo1.tsx:9`). `fn_upsert_caso` grava só o nome, e responsável exige coluna nova.
- **"Tempo até aprovar" sem coluna** (CONFERIDO: nenhuma migration tem `aprovado_em`/`aprovada_em`). O indicador pedido precisa dessa coluna; hoje o painel mede "tempo médio de ingestão".
- **`fn_membros_da_equipe` não pagina** (CONFERIDO: o corpo, em `Supabase/migrations/0216…`, linhas 911–921, não tem `limit` nem `offset`). O teto de 1000 linhas é o do PostgREST, que o próprio código reconhece em `portal/src/lib/linhas-por-versao.ts`; o efeito numa equipe grande não foi medido.
- **~88 observações de estilo do Sonar** (NÃO CONFERIDO nesta rodada: sem acesso ao Sonar). Quality Gate passando na última medição.
- Herdadas da pausa de 28/10, não reconferidas: funções puras sem teste (`escolherRecentes`, `iniciaisDoEmail`, `passosDaTrilha`, `etapaDoMandato`, `mensagemDeLogin`); ramo da 0215 que tira da vinculação as linhas do lote sem assert (0 de 49); marca nas premissas da Modelagem no modo discrição não medida; `viewport-fit=cover` não declarado (CONFERIDO por grep: só aparece num comentário, `portal/src/components/barra-inferior.tsx:35`).

### Ainda a fazer

Nada no código. O que resta é o que está em "O dono faz à mão" e as pendências acima.

## Arquivado (decidido, não agendado)

Nenhuma tela pode antecipar estes itens: interface que sugere separação de
acesso que o banco não garante é pior que nenhuma interface (`PRODUCT.md`,
"RLS por caso não existe ainda"). Esse trecho do `PRODUCT.md` é anterior à 0216 e
precisa ser reescrito à luz dela.

1. **Multiempresa — outras casas assinando o portal.** Exige isolar os dados de
   cada assinante no banco (organização acima do caso, RLS por organização),
   o que é maior que a Fase 5 e muda a ordem do roadmap. Reabrir quando houver
   o primeiro assinante em vista.
2. **Área do cliente.** O cliente acessa só o mandato da própria empresa, para
   subir documentos (contra o Kit Básico) e acompanhar o andamento. Pré-requisito:
   papéis e RLS por caso (Fase 5, agora feitos no banco pela 0216) e uma superfície
   externa isolada da interna — o cliente nunca vê pendência, premissa nem nota interna.
3. **MFA no login.** Decisão do dono em 29/10/2026: fora do redesenho. Sem código e sem migration.
4. **SSO Microsoft no login.** Decisão do dono em 29/10/2026: fora do redesenho. Sem código e sem migration.
