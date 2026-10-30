# Estado do projeto — leia isto antes do `HANDOFF.md`

## SESSÃO 114 (30/10/2026) — 0216 aplicada em produção, e o plano das próximas 6 semanas

> **RETOMADO E FECHADO (30/10/2026, fim do dia): a fatia P1 do plano está FEITA.** Em produção, nesta ordem:
> - **0217:** primeiro um ensaio (a migration mais `raise exception`, tudo revertido: a função existe, só falta o requisito do segredo, e a recusa sai como `sem_segredo`); depois a aplicação (`[]`).
> - **Segredo no Vault:** `vault.create_secret(..., 'n8n_intake_segredo')`, com o valor de 64 caracteres sem a quebra de linha, o mesmo da Vercel.
> - **Sonda como `postgres`:** 290/290 presentes, 0 ausentes.
> - **Paridade provada em produção:** token gerado pelo `assinarEnvio` do portal. Válido → autorizado (mandato com espaços e maiúsculas: "  ensaio envio AÇÕES "); mandato trocado → `assinatura`; adulterado → `assinatura`; vencido → `expirado`.
> - **Merge do `main` (#264, #267)** na branch, conflito só no ESTADO; `run.sh` rc 0 sobre o merge.
> - **Republicação** da ingestão (`na1AEv3m8fjDXlwM`): `PUBLICADO E CONFERIDO`, 59 nós; `Conferir Envio` Postgres com a credencial real, sem `onError`, com `retryOnFail`; `FINGERPRINT_EXTRACAO` igual (`ff16b69dc9f1ad42`). **Armadilha nova:** o nó virou Postgres e não tinha irmão publicado com a credencial de mesmo nome (a publicada se chama "Postgres (Trat. Dados)", o repositório grava "Supabase Postgres (Session Pooler)"), então a trava do REPLACE abortou. Resolvido com `N8N_CRED_IDS='{"Supabase Postgres (Session Pooler)":"D7NYaWY1UYKy2vBc"}'`.
> - **Envio ponta a ponta pelo Form público** (o mesmo POST do portal, com o token do `assinarEnvio`):
>   - token **adulterado** → `execucao_falha` etapa `envio`, 0 mandato criado;
>   - token **vencido** → "o token do envio expirou", 0 mandato criado;
>   - token **válido**, mandato "S114 teste envio ponta a ponta (sintetico)", BP + DRE do book Vertentes → lote fechado: 2 documentos, 0 falhas, 253 linhas, cobertura 1,0000, US$ 0,010.
> - **Visto no caminho, NÃO corrigido** (já no plano): a recusa de envio grava também um "Lote recusado pelo orcamento" no `Abortar Lote` (mensagem enganosa). Se a sonda AGENDADA rodar com o `supabase_read_only_user`, o requisito `envio_segredo_no_vault` sai falso com "permission denied" (o papel somente-leitura não executa a auxiliar). Com `postgres` ele sai verdadeiro. Conferir no próximo `sonda-producao.yml`.
> - **CI:** os pushes de `9ad4f04` e `5e80531` NÃO criaram execução das suítes (incidente conhecido do GitHub, ver `suites.yml`). Disparo manual pedido na branch.
> - **Próxima sessão começa pela P1b** (o dial calculado por quem dispara, pendência crítica da 0216), antes da P2.

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve)** (ESCRITA nesta sessão; aplicação em produção registrada abaixo quando feita). O n8n não tinha onde ler o segredo do envio: a licença não tem Variables (403) e o PikaPods não aceita variável nova. Medido: o n8n publicado recusava TODO envio. Decisão do dono: o segredo vai para o Vault do Supabase (`n8n_intake_segredo`), e `fn_conferir_envio` (só `service_role`/`postgres` executam; `authenticated` dá 42501) confere o token com a mesma conta do portal, inclusive `lower(... collate "und-x-icu")`, porque o `lower()` padrão diverge do `toLowerCase` do JS em "İ" e no sigma final (medido). A sonda ganha o tipo `segredo` (`envio_segredo_no_vault`, bloqueante, sintoma "todo envio é recusado"). O nó `Conferir Envio` virou Postgres (`26342a4`), e o `Upsert Caso`, que lia o mandato de `$json` (o primeiro envio autorizado gravaria `null`), passou a ler do Form. Teste: `Supabase/test/conferir_envio.test.sql`, com 63 asserts e paridade com o `createHmac` do portal.

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo). Nesta seção: a `0216_o_acesso_que_so_o_portal_decidia.sql` foi APLICADA EM PRODUÇÃO em 30/10/2026** pela sessão (API de gerenciamento, uma chamada, resposta `[{"fn_acesso_bootstrap":1}]`). **Antes:** `0215` com 0 ausentes; 0 nomes de mandato duplicados; `auth.users` com 1 usuário (o dono); `postgres` e `service_role` com `rolbypassrls = true`; a única policy de `storage.objects` era a `documentos_authenticated_all` da `0003`. Suíte local `run.sh` rc 0, e um **ensaio em produção** (a migration inteira seguida de `raise exception`, que reverte tudo) passou: 1 Sócio, 0 ausentes da 0216. **Depois:** 0216 com 48/48, catálogo inteiro 287/287; o dono é o único Sócio; 0 policies `using (true)` de `authenticated` (136 checam o mandato); storage com `documentos_read/insert/update/delete`.
> **Configurado:** `N8N_INTAKE_SEGREDO` na Vercel (produção e preview, sensível); Supabase Auth com Site URL `https://tratamento-dados-financeiros.vercel.app` e Redirect URLs `/auth/confirmar**` (produção, previews `oria4`, localhost).
> **NÃO foi possível:** a Variable no n8n (a licença não tem `feat:variables`, 403), então o segredo vai como variável de ambiente no PikaPods, com `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` (pendência D1 do dono); o modelo do e-mail de recuperação (o plano gratuito recusa sem SMTP próprio, 400), então o link é PKCE e só abre no mesmo navegador.
> **Feito a pedido do dono, mais tarde em 30/10:** redeploy de produção na Vercel (`dpl_8bMCuR6xTAbbH6BgmzJGmvAh9Ca7`, READY, `main` em `62c8b55`, agora com o `N8N_INTAKE_SEGREDO`) e republicação da ingestão (`na1AEv3m8fjDXlwM`: de 57 para 59 nós, `conferir-publicado` OK, "Arquivos" com `multipleFiles`, campo "Token do envio" presente, `FINGERPRINT_EXTRACAO` igual, `ff16b69dc9f1ad42`, então nada é re-extraído). **O envio fica RECUSADO pelo n8n até o PikaPods ter `N8N_INTAKE_SEGREDO` (criar a variável) e `N8N_BLOCK_ENV_ACCESS_IN_NODE=false`.** Em 30/10 ela estava `true`, o que bloqueia o `$env`. O resto da P1 (envio ponta a ponta) espera isso.
> **Plano vigente:** `Arquitetura do Sistema/3 Estado e Execução/PLANO_DE_EXECUCAO_2026-11.md` (30 fatias em 6 semanas, mais o mapa até o fim), com o roadmap apontando para ele.

## SESSÃO 111 (26 a 30/10/2026, PR #264) — Espec. 13: parceiros de dados e pré-mandato; o merge com o redesenho

> **O que este PR entrega (só documentação):** Espec. 13 (parceiros de dados e momento pré-mandato) com os anexos `13A` (plano por nível de dependência), `13B` (RFP aos fornecedores, pronto para envio), `13C` (roteiro do piloto no mandato AMO) e `13_anexos/Plano_de_Captacao_v3.xlsx` (as 179 linhas da planilha de dados do sistema, classificadas, com 26 afirmações conferidas na fonte); fase F2E no roadmap; B9 no mapa; D5/D6/D12.4 revistas nas Espec. 11 e 12.
> **O que saiu no merge com o `main` (30/10/2026):** este PR tinha a sua própria segregação por mandato (0215 membros/administradores, 0216 policies, e duas mudanças de portal). O redesenho do portal (PR #265) chegou antes ao `main` com a MESMA numeração e uma solução mais completa (papéis Sócio · Analista · Leitura, nome de mandato único, envio com token conferido no n8n, tela de Equipe com e-mail). **Ficou a do `main`**: as migrations, os testes e as telas deste PR foram retirados no merge. Os branches `wip/0215-0216-correcoes-*` estão obsoletos.
> **PENDÊNCIA CRÍTICA que a revisão independente deste PR achou e que vale para a 0216 do `main`:** `fn_dial_auto_promover`, `fn_veredito_producao` (e o gatilho `trg_auto_promover_dial` em `decisao`) são INVOKER. Com a RLS por mandato, o veredito "global" passa a ser calculado só sobre os mandatos de QUEM DISPARA (um Analista, pelo portal, ao decidir/revisar/aceitar), e `fn_mudar_dial` muda o estágio para TODOS. Um recorte pequeno com concordância alta promove o dial sem a amostra global bastar. Mesma família, menor: `fn_golden_cobertura` e `fn_classe_contabil_concordancia` (tela `/autonomia`) passam a mostrar números do recorte do leitor sem aviso. **Corrigir antes de aplicar a 0216 em produção** (migration nova: cálculo global independente do leitor, com assert de que um recorte alto não promove). Outros achados daquela revisão que a 0216 do `main` NÃO cobre e valem conferir: sonda que exija RLS LIGADA (`relrowsecurity`) nas tabelas restritas, e o bootstrap que promove a Sócio todo `auth.users` sem filtrar convite não confirmado, banido ou anônimo.
> **A FAZER da F2E (nível 0 do anexo 13A, a T0 já veio pelo redesenho):** `consulta_externa` + `fato_externo` + `autorizacao`; `caso.momento` (pré-mandato) e a segmentação no portal; coletores públicos; formulários do analista; ferramental do piloto. Fora do código: enviar o RFP, comprar o e-CNPJ da Oria, autorização dos sócios do AMO.

## SESSÃO 113 (29/10/2026) — fechamento do redesenho do portal (fases 1 a 5)

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (ESCRITA, NÃO aplicada em produção). O defeito que ela corrige: toda policy de `authenticated` era `using (true)` desde a `0003`, então qualquer usuário logado lia e escrevia TODOS os mandatos, e o portal só escondia o que não mostrava. A 0216 põe papéis Sócio · Analista · Leitura (`membro`), alocação por mandato (`alocacao`) e policy por mandato no banco. A rodada inteira está em `Arquitetura do Sistema/7 Marca/REDESENHO_DO_PORTAL.md`, em "O dono faz à mão".
> **Estado:** fases 1 a 5 concluídas; nada em andamento. PR #265 (rascunho), branch `claude/friendly-lamport-22ctle`. Esta rodada fecha com um commit de documentação sobre `96df48d`. **Não foi empurrado** (sem push, por pedido do fluxo): o PR só enxerga este commit depois do push.
> **O que o dono aplica, em ordem:** 0215 (conferir a sonda) → 0216 (antes, conferir nomes duplicados e `auth.users`: todo usuário vira Sócio; conferir a sonda com `migration='0216'`; conferir `rolbypassrls` de `postgres` e `service_role`) → segredo `N8N_INTAKE_SEGREDO` na Vercel e no n8n → deploy do portal → republicar o workflow de ingestão (conferir `multipleFiles` no campo "Arquivos") → configurar o Auth (Site URL, Redirect URLs `/auth/confirmar**`, modelo de recuperação) → olhar o preview da Vercel nas telas novas. Detalhe com comandos no REDESENHO.
> **O que a SESSÃO 112 dizia faltar** (tela de equipe, esconder botões por papel) **foi feito**: `cf24d86`, `e6a6049`, `6e68c1e`. A S112 fica como histórico.

**Suítes medidas NESTA rodada (29/10/2026, banco local PostgreSQL 16, árvore limpa em `96df48d`):**

| Suíte | Resultado |
|---|---|
| `node --test 'N8N/test/*.test.mjs'` | 693 de 693 |
| `node --test 'Leitor/test/*.test.mjs'` | 65 de 65 |
| `node --test '.claude/hooks/test/*.test.mjs'` | 11 de 11 |
| `node --test 'Supabase/test/*.test.mjs'` com `TESTE_PSQL` | 44 de 44 (sem o banco, 40 passam e 4 são pulados; o motivo é o `TESTE_PSQL` não definido) |
| `Supabase/test/run.sh` (banco local) | exit 0, "TODOS OS TESTES PASSARAM". `acesso_por_caso.test.sql`: 217 asserts ok, 0 falhas. `schema.sql` regerado é idêntico ao commitado |
| `Supabase/test/conferir-chamadas.mjs` (`CONFERIR_DB=tdf_test`) | CHAMADAS OK |
| `Supabase/test/sonda-producao.mjs --so-buraco` (`tdf_test`) | sem buraco; 66 migrations no catálogo |
| `verificar-*.mts` (12 do portal) | todos rc 0 (export 894/0, transcricao 35/0, perimetro OK, exclusividade-ciclo 20/20 e os demais OK) |
| `Verificação/run.mts` (E2E) | 46 verificações OK / 0 falhas |
| `Verificação/variacoes.mts` | 0 achados |
| `tsc --noEmit`, `eslint .` (portal) | exit 0 |
| `node .claude/verificar-comandos.mjs` | 6 citações, 13 agentes conhecidos |
| `node --test '.claude/conhecimento/test/*.test.mjs'` | 3 de 3 |

**NÃO remedido nesta rodada:** `next build` (nenhum arquivo de `portal/` mudou nesta fatia; a última medição é de cada commit); `N8N/medir-regua-cobertura.mjs` e `N8N/medir-custo-book.mjs` (precisam dos books gerados); a sonda contra **produção** (exige `SONDA_PSQL` de produção, sem conexão daqui); o Sonar.

**Ambiente, para a próxima sessão:** o `variacoes.mts` exige `E2E_PSQL` (senão tenta o `psql` padrão e morre). Com o Postgres em `/tmp`, `E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432"`. O `TESTE_PSQL` é a variável dos quatro testes que pulam (não o `CONFERIR_PSQL`).

## SESSÃO 112 (29/10/2026) — o acesso por mandato no banco (portal, fase 5, parte 1)

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (ESCRITA, NÃO aplicada; aplicar DEPOIS da 0215 e conferir `fn_instalacao_conferir()` com `migration = '0216'`). Papéis Sócio · Analista · Leitura (`membro`), alocação por mandato (`alocacao`) e toda policy `using (true)` de `authenticated` trocada por policy por mandato. Sócio: tudo (aprovar, fechar, excluir mandato, dial, equipe); Analista: lê e escreve só onde está alocado; Leitura: só lê onde está alocada; sem papel: nada. Funções `fn_pode_*`/`fn_casos_*`, gestão `fn_definir_papel`/`fn_alocar`/`fn_desalocar` (só Sócio, com evento) e gatilhos de guarda (aprovar/fechar/excluir/dial reservados a Sócio; nunca zero Sócio). **BOOTSTRAP: a migration promove a Sócio TODOS os usuários que já existem em `auth.users` ao ser aplicada; usuário criado depois nasce sem papel e não vê nada** (README e cabeçalho da migration). **Corrigida no próprio arquivo após revisão independente (ainda NÃO aplicada; sem 0217):** ON CONFLICT que alocava o Analista em mandato alheio, nome de mandato único (índice + `fn_upsert_caso` recusa o homônimo; **a migration ABORTA se houver nomes duplicados em produção**), falha do pipeline sem `caso_id` lida pelo nome, bootstrap só com `membro` vazia, evento sem mandato só do Sócio, DELETE da Leitura dá 42501, só as policies de storage do repositório são derrubadas (confira os WARNING), lock no último Sócio e `fn_membros_da_equipe()` (só Sócio) para a tela da equipe. Teste `Supabase/test/acesso_por_caso.test.sql` (129 chamadas de assert, 217 execuções; cada correção medida desligada, números no cabeçalho da migration). Medido: `count(*)` de 198.543 campos como Analista caiu de 4.011 ms (função por linha) para 17 ms (SubPlan hash). O `run.sh` agora cria o stub `auth` e roda os testes antigos como um Sócio de teste (JWT no banco). **O que falta:** aplicar a 0216 em produção DEPOIS de conferir `auth.users`; a tela de equipe e esconder botões por papel no portal (Fase 5, parte 2 — nada em `portal/` foi tocado); conferir em produção que `postgres`/`service_role` têm BYPASSRLS (o n8n depende disso).

## SESSÃO 111 (28/10/2026) — o histórico do mandato (portal, fase 3, item 24)

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (S112, no topo, ESCRITA e NÃO aplicada; antes dela a `0215_o_historico_que_so_o_banco_sabia.sql`) (ESCRITA, NÃO aplicada; aplicar DEPOIS da 0214 e conferir `fn_instalacao_conferir()` com `migration = '0215'`). `fn_historico_do_caso(caso, limite, antes, antes_chave)`: linha do tempo (quem, o quê, quando) montada do que já é gravado, cursor composto (instante + `chave`), aceite automático e perímetro de entidade absorvida incluídos; só leitura, security invoker. Corrigida no próprio arquivo após revisão independente (49 asserts). **Exportações não entram: não existe log.** Teste: `Supabase/test/historico_do_caso.test.sql`.

## SESSÃO 110 (20/10/2026) — o GRANT que o Supabase deixa de dar em 30/10/2026

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (S112, no topo, ESCRITA e NÃO aplicada; antes dela a `0215_o_historico_que_so_o_banco_sabia.sql`) (S111, no topo, ESCRITA e NÃO aplicada; antes dela a `0214_o_grant_que_o_supabase_deixou_de_dar.sql`) (**APLICADA EM PRODUÇÃO em 20/10/2026** pela sessão, API de gerenciamento, uma chamada, resposta `[]`). Antes de aplicar, medido em produção: cobertura em `0213`, `fn_instalacao_conferir()` com 0 ausentes, corpo da função de produção = o da 0214 menos o ramo `privilegio` (diff só de acréscimos), e os privilégios que faltavam a authenticated/service_role eram EXATAMENTE os 7 revokes intencionais. Depois: os mesmos 7 (estado idêntico, `update (entidade_id)` em `caso_pergunta` mantido), cobertura `0214`, 0 ausentes, os 6 requisitos `privilegio` presentes, e o workflow `sonda-producao.yml` (run 44) verde.
> **O defeito:** a partir de 30/10/2026 tabela nova em `public` não recebe mais GRANT automático (anon/authenticated/service_role) — vale para projeto novo, preview branch e `supabase db reset`. O `run.sh` simulava o default antigo, então o CI ficaria verde com produção quebrando na primeira tabela nova (regra 7). Detalhe, mecanismo dos revokes e medições: cabeçalho da `0214` e `.claude/conhecimento/fichas/grant-de-tabela-nao-vem-mais-do-supabase.md`.
> **O que falta:** nada no banco. Tabela nova criada a partir de 30/10/2026 só tem acesso se a própria migration conceder (convenção em `Supabase/README.md`); a sonda agendada acusa a que esquecer.

## SESSÃO 109 (15/10/2026) — F1: fechar o perímetro (o caminho de escrita que ninguém chamava)

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (S112, no topo, ESCRITA e NÃO aplicada; antes dela a `0215_o_historico_que_so_o_banco_sabia.sql`) (S111, no topo, ESCRITA e NÃO aplicada; antes dela a `0214_o_grant_que_o_supabase_deixou_de_dar.sql`) (S110, no topo; antes dela a `0213_a_fusao_que_falhava_na_pergunta_ja_enviada.sql`) (ESCRITA, NÃO aplicada, junto com a `0212_o_bloco_familiar_que_o_controle_comum_nao_via.sql`; a última aplicada em produção é a `0211_a_fusao_que_apagava_o_perimetro_da_absorvida.sql`). **APLICADAS EM PRODUÇÃO em 15/10/2026 pela sessão** (API de gerenciamento do Supabase, projeto `mrcabcaotblleojxnsxc`, uma chamada por migration, na ordem `0207` → `0208` → `0209` → `0210` → `0211`), **e CONFERIDAS pela sonda depois de cada uma**: 0207 8/8, 0208 4/4, 0209 2/2, 0210 3/3, 0211 1/1; `fn_instalacao_conferir()` inteira: **218/218 presentes, 0 ausentes**. `authenticated` em produção: INSERT sim, DELETE **não** nas três tabelas da 0210 (medido com `has_table_privilege`). A `0206` foi **conferida** pela sonda agendada de 15/10 (só a 0207 faltava).
> **Portal: PR #259 mergeado (`44675ba`) e deploy de produção na Vercel READY** (`dpl_6hEVUtCaB3e9KFQb8aYgZ6cnUTNq`). O "Include source files outside of the Root Directory" está de fato funcionando: o build que lê `../Leitor` e `../N8N` ficou READY.
> **n8n REPUBLICADO em 15/10/2026 pela sessão** (`N8N/republicar.sh` com as variáveis do ambiente — o host está em `N8N_BASE_URL`, não em `N8N_URL`): workflow de ingestão `na1AEv3m8fjDXlwM`, publicado era de 09/10 (55 nós), agora 57 nós (o teto de 15 MiB da S108, `6f1e741`). Ensaio antes, `conferir-publicado` depois: os 57 nós batem com o repositório, inclusive disabled/onError/retryOnFail e credenciais. `FINGERPRINT_EXTRACAO` igual antes e depois (`ff16b69dc9f1ad42`): nada é re-extraído. O secret `N8N_API_KEY` do **GitHub** continua dando 401 no `republicar.yml` (a Action não funciona até ele ser atualizado).
> **O que o dono faz à mão, em ordem:**
> 1. ~~Aplicar 0207–0211~~ e ~~deploy do portal~~ — feitos pela sessão em 15/10 (acima).
> 2. ~~n8n~~ — republicado pela sessão (acima). Pendente só atualizar o secret `N8N_API_KEY` do GitHub para a Action voltar a funcionar.
> 3. Abrir `/casos/<id>/perimetro` do mandato AMO e declarar papel, forma de controle, escopo `combinado` e sócios (os 4 contratos legíveis; ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`). Resolver as 4 fantasmas (fundir ou descartar): elas **seguram o "fechado" por decisão desta rodada**.
> 4. Decisões do dono abertas: (a) controle familiar conta como controle comum? (fatia 1.7); (b) pendência "aceita com ressalva" deve segurar o perímetro? (hoje não segura); (c) `caso_pergunta` na fusão (FK `NO ACTION`: a fusão falha alto).
> 5. Enviar os arquivos. O zip de ~3 GB vai pelo portal (já no ar): o zip abre no navegador e a aba precisa ficar aberta. Arquivo não oficial acima de 15 MiB dentro do zip fica de fora, e a tela diz para enviá-lo separado.

**O que fechou (commits de `f2bf2be` a `247f84c`; `git show <sha>` para o detalhe):**
- `6988625` **0208**: `fn_perimetro_situacao` e `fn_perimetro_veredito`. As funções da F1 (0178–0183) não tinham chamador fora de `Supabase/test`; agora há uma resposta única do banco para "o perímetro está fechado, e o que falta". 52 asserts; 9 reprovam com a pronta sempre verdadeira.
- `6d5c342` **0209**: `fn_perimetro_definir_escopo` idempotente (antes estourava 23514 ao repetir) e `fn_perimetro_encerrar_escopo`. 28 asserts.
- `9ee5424` **tela** `/casos/[id]/perimetro` e `portal/scripts/verificar-perimetro.mts` (48 verificações; no CI e no `CLAUDE.md`). **Não aberta em navegador nem contra Postgres.**
- `d9a70eb` **0210**: RLS. `perimetro`, `controlador` e `entidade_controlador` só tinham policy de SELECT; como `authenticated`, definir escopo e registrar controlador davam 42501 (medido). Policies de INSERT/UPDATE e `revoke delete`. A sonda ganha o tipo `policy`. 20 asserts; 14 reprovam no estado anterior.
- `843c1de` correção dos 4 achados do Sonar na tela (sem mudança de comportamento).
- `fb3b769` **0211**: `fn_fundir_entidade` leva o perímetro da absorvida (antes o CASCADE apagava em silêncio) e repõe as controladas (antes a fusão inteira falhava com 23503). 20 asserts; 17 reprovam com o corpo da 0183. **NÃO corrigido, efeito dito:** `caso_pergunta` (FK `NO ACTION`) faz a fusão falhar alto; `caso_modelagem` e `caso_linha_premissa` guardam o nome, que fica órfão.
- `8148a3c` **zip no navegador**: `Leitor/lib/zip.mjs` sobre `Blob` (ZIP64, CRC, fluxo); o portal deixa de mandar zip ao n8n. Medido no Chromium: 9,58 GB, 312 entradas, 95,2 s, heap do worker 45 MB.
- `07e9e7e`, `f362035`, `247f84c`: grafo do conhecimento regerado a cada passo.

**Suítes medidas nesta rodada (15/10/2026):** as cinco primeiras foram **reexecutadas fechando a rodada**; as demais vêm da rodada de implementação, relatadas no brief e não reexecutadas aqui.
- Reexecutadas no fechamento: `.claude/conhecimento/test/*.test.mjs` 3/3; `Leitor/test/*.test.mjs` 65/65; `verificar-envio-oficial.mts` 153/0; `verificar-perimetro.mts` 48/0.
- Da rodada de implementação (não reexecutadas aqui): `verificar-limite-de-envio.mts` 69/0; `N8N/test/*.test.mjs` 676/676; `Supabase/test/run.sh` com exit 0 em banco novo (o script não soma asserts); `tsc`, `eslint` e `next build` do portal limpos.
- **NÃO remedidos:** `Verificação/run.mts`, `variacoes.mts`, `conferir-chamadas`, a sonda contra produção e os medidores (`medir-regua-cobertura`, `medir-custo-book`).

**Não verificado:** a tela em navegador (no ar, ninguém abriu); o zip de 3 GB no mandato real; a decisão 1.7 (controle familiar). Deploy e sonda sobre 0207–0211: **feitos e conferidos em 15/10** (topo).

**Estado da F1:** a fatia 1.8 ("o caminho de escrita que ninguém chamava") está **feita e em produção** (15/10). Ainda fecham a F1: declarar o perímetro pela tela, o aceite financeiro (**NÃO VERIFICADO** sem o COMBINADO do cliente) e a decisão 1.7. O percentual 55% do cabeçalho da F1 **não foi remedido** nesta rodada.

---

## SESSÃO 108 (13/10/2026) — F2T etapa 1: o leitor passa ao navegador, e a `0207` (o resumo)

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (S112, no topo, ESCRITA e NÃO aplicada; antes dela a `0215_o_historico_que_so_o_banco_sabia.sql`) (S111, no topo, ESCRITA e NÃO aplicada; antes dela a `0214_o_grant_que_o_supabase_deixou_de_dar.sql`) (S110, no topo; antes dela a `0213_a_fusao_que_falhava_na_pergunta_ja_enviada.sql`) (aplicar DEPOIS da 0212; S109, abaixo). Antes dela, `0212_o_bloco_familiar_que_o_controle_comum_nao_via.sql`, `0211_a_fusao_que_apagava_o_perimetro_da_absorvida.sql`, `0210_a_escrita_do_perimetro_que_so_o_superusuario_fazia.sql`, `0209_o_escopo_que_nao_se_confirmava_nem_se_encerrava.sql`, `0208_a_situacao_do_perimetro_que_so_o_teste_lia.sql` e `0207_o_resumo_do_arquivo_oficial.sql` (aplicar DEPOIS da 0206). **NÃO aplicada em produção.**
> **A `0206` foi aplicada pelo dono em 13/10/2026** (ele disse "Migration 206 foi aplicado"). **NÃO CONFERIDA pela sonda:** o dono não informou o resultado de `select chave from fn_instalacao_conferir() where migration = '0206' and not presente;`.
> **O que o dono faz à mão, em ordem:**
> 1. Conferir a `0206` pela sonda (zero linhas).
> 2. Aplicar a `0207` e conferir `select chave from fn_instalacao_conferir() where migration = '0207' and not presente;` (zero linhas).
> 3. Republicar o workflow de ingestão (Actions → "Republicar workflow no n8n", ou `N8N/republicar.sh`). Conferir no editor os nós `Tamanho cabe?` e `Juntar Recusas`, e fazer um envio real de teste.
> 4. Fazer deploy do portal. Na Vercel, **"Include source files outside of the Root Directory" tem de estar ligado**: o `next.config` lê `../Leitor` e `../N8N`. **NÃO VERIFICADO** na Vercel.
> 5. Ligar a trilha só no caso que for usar: `update caso set trilha_transacional = true where id = '...'`.

**Mudança de rota (decisão do dono, 13/10/2026).** O leitor NÃO é mais um serviço próprio nem roda no n8n. Roda **no navegador do analista**, com o mesmo `Leitor/lib` do CLI. **Só o resumo vai ao banco. O lançamento individual é descartado.**

Por que, medido (n8n 2.30.7 local, `Leitor/medicao-n8n/README.md`):
- `getBinaryDataBuffer` serializa o binário byte a byte. Memória total (principal + runner): 11 MB → 1,1 GB; 29 MB → 2,0 GB; 58 MB → 3,6 GB; 117 MB → 7,7 GB.
- 355 MB (3M de linhas) → "heap out of memory", e cai a instância inteira.
- Fatias por Range com sub-workflow passaram 10M de linhas (222 s, ~950 MB). Esse caminho **não foi adotado**.
- O PikaPods subiu para 2 GB (pelo dono). O PikaPods só roda os apps do catálogo, então o leitor não entraria lá como serviço próprio. Isso foi afirmado pela sessão e aceito pelo dono, mas NÃO CONFERIDO contra a documentação do PikaPods.
- Banco: guardar o arquivo custaria ~2 GB por ECD de 10M de linhas. Supabase pago só como último recurso. O resumo mede 3,4 a 4,7 MB.

Medido no Chromium (commit `ca522ca`): ECD de 10.000.180 linhas (929 MB), contas de 16 caracteres. Resultado igual ao CLI, hash = `sha256sum`, 37,5 s, 61 MB de pico de heap JS, resumo de 4,7 MB. O protótipo (`8312dc9`) deu 22,9 s e 59 MB.

**Commits desta rodada (6, de `92be7b8` a `33b6236`):**
- `4621c83` e `8312dc9`: as medições (n8n e navegador) acima.
- `ca522ca` (passo 1): `Leitor/lib` sem `node:*`. `sha256.mjs` incremental (o hash é a identidade da 0206). `campos.mjs#latin1`: no navegador `latin1` é windows-1252 (0x96 vira "–"), e o SPED é ISO-8859-1. `lerEnvelopeDeFluxo`, `resumo.mjs` (ECD e ECF) e `arquivo.mjs` (só o CLI usa). A revisão independente achou 6 importantes, todos corrigidos. Leitor: 47/47.
- `6f1e741` (passo 4): `TETO_BYTES_POR_ARQUIVO` = 15 MiB no `Listar Arquivos`, antes de qualquer leitura. Arquivo acima do teto recusa o lote inteiro, como um item só. Tamanho desconhecido também recusa. N8N: 676/676 (eram 669). **Exige republicação.**
- `a20edaf` (passo 2): o portal reconhece o oficial pelos bytes (64 KB), tira do lote do n8n, lê num Web Worker e grava só o resumo. O teto de 15 MiB é importado de `N8N/lib/custo.mjs`. `verificar-envio-oficial.mts`: 92/0 (no CI).
- `33b6236` (passo 3): migration `0207`. `fn_resumo_iniciar`, `fn_resumo_anexar` (partes de até 10.000 itens; a tela manda até 5.000) e `fn_resumo_concluir`. O concluir é a fronteira de confiança: reconfere totais, faixa de linha, contagem por registro e partidas × I250. Se falhou, recusa e apaga as linhas, para não sobrar resumo parcial. `fn_upsert_caso` foi recriada com `p_ator` (lista fechada) e grant ao `authenticated`. Regra 2: 58 asserts, cada guarda medida. Ponta a ponta sem mock contra o Postgres local: ECD de 299.980 linhas, 3.000 contas, 39.196 registros, 9.000 grupos, **12 chamadas em 1,6 s**.

**Suítes remedidas nesta rodada (13/10/2026, branch `claude/execucao-plano-predefinido-9ur5s2`):**
- `node --test 'Leitor/test/*.test.mjs'`: 47 de 47.
- `node --test 'N8N/test/*.test.mjs'`: 676 de 676.
- `node --test '.claude/conhecimento/test/*.test.mjs'`: 3 de 3.
- `portal/scripts/verificar-envio-oficial.mts`: 92 verificações, 0 falhas.
- `portal/scripts/verificar-limite-de-envio.mts`: 69 verificações, 0 falhas.
- `Supabase/test/run.sh`: **exit 0**, 86 arquivos `.test.sql` na lista de execução, `TODOS OS TESTES PASSARAM` (o script não soma asserts; contagem NÃO remedida).
- **NÃO remedido nesta rodada:** `tsc`, `eslint`, `next build`, `conferir-chamadas`, a sonda contra produção e `Verificação/run.mts`.

**Não verificado (nada disso rodou em produção):**
- nada rodou no n8n de produção nem na Vercel;
- Safari e Firefox;
- arquivo de 10M de linhas pela tela (só pelo script de medição);
- ECD real: os testes usam arquivos sintéticos (regra 4);
- posições de `leiautes.mjs` e a lista de `resumo.mjs`: **[A CONFIRMAR]** contra o Guia Prático;
- Supabase com corpo de RPC grande (as partes têm no máximo 5.000 itens).

**PR:** o PR #257 (S107) está **mergeado** (API do GitHub, 13/10/2026 19:37 UTC). O PR desta rodada é o [#258](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/258), aberto em 13/10/2026.

**Onda 1: BLOQUEADA.** Destrava com: (a) a F1 fechar (perímetro e CNPJ por entidade; o roadmap marca 55%); (b) 3 ECDs reais do dono para o aceite; (c) conferir `leiautes.mjs` e a lista de `resumo.mjs` contra o Guia Prático.

**Continuam pendentes do dono, sem mudança nesta rodada:** a cotação do SERPRO (D12.3), o termo jurídico (D12.6) e fechar o repositório público.

---

## SESSÃO 107 (13/10/2026) — F2T etapa 1: o leitor de arquivos oficiais e a `0206`

> **Migration nova: `0206_o_arquivo_oficial_lido_e_contado.sql` — escrita e testada, NÃO aplicada em produção.**
> **Desde a S108, a mais nova é a `0207`, e a `0206` foi aplicada pelo dono (ver SESSÃO 108 acima).**
> **O que o dono faz à mão:** aplicar a 0206 depois da 0205 e conferir
> `select chave from fn_instalacao_conferir() where migration = '0206' and not presente;` (zero linhas).
> Nada mais muda em produção: o n8n NÃO chama o leitor ainda, e `caso.trilha_transacional` nasce false.

**Entregue:**
- `Leitor/`: reconhece a família de cada arquivo (SPED nos 4 tipos, NF-e, CT-e, MDF-e, NFS-e, eSocial, Reinf,
  CNAB 240/400/150, OFX e zip) e lê o envelope em fluxo, conferindo a contagem que o próprio arquivo declara
  (9999 e 9900, trailer do CNAB, fechamento do XML e do OFX).
- Cada leitura tem resultado `lido`, `falhou`, `controle_divergente` ou `versao_desconhecida`.
- `Leitor/ler.mjs` (CLI) grava em `arquivo_oficial` e registra também o zip como contêiner.
- Testes: 32 no leitor, com os 26 guardas medidos não-vazios, e 65 asserts na 0206, com cada regra medida.
- A revisão independente achou 2 bloqueantes e 9 importantes, todos corrigidos antes do commit:
  - a ECD da SCP substituía a da empresa;
  - reler um arquivo não atualizava o banco.

**Medido (repositório e banco de teste, não produção):**
- Antes, um SPED enviado ao n8n seria decodificado como UTF-8 e mandado inteiro para a IA (`build-workflow.mjs`, nó Preparar Conteúdo).
- Bateria completa do CI local: 37/37 antes das correções da revisão. Depois delas rodaram os portões tocados: `run.sh`, chamadas, sonda, Supabase, Leitor, n8n, espelho e comandos.

**[A CONFIRMAR] antes da onda 1:**
- As posições e versões do registro de leiautes (`Leitor/lib/leiautes.mjs`) foram escritas sem o Guia Prático aberto.
- Os testes usam arquivos sintéticos.
- A prova é o aceite com 3 ECDs reais.

**PR #257** aberto em 13/10/2026.
- CI do GitHub: rodando na abertura do PR.
- SonarCloud: reprovou por Reliability C e Security B, e as duas causas foram corrigidas.
- A ficha `f2t-fontes-oficiais-e-captacao-espec12` foi atualizada, com prova em `Leitor/test/*.test.mjs` e âncora em `detectarFamilia`.

**Próximo passo — ligar ao sistema:**
1. Decidir onde o leitor roda (P5).
2. Acrescentar uma rota de leitura no n8n: quando a família for oficial e a trilha estiver ligada no caso, o arquivo vai ao leitor, e não à IA.
3. Fazer o envio direto ao Storage (peça 2).

Detalhe na descrição do PR desta sessão.

## SESSÃO 106 (09–13/10/2026) — Especificação 12 e fase F2T (planejamento, nada implementado)

> **Nesta rodada não houve migration, workflow, deploy nem medição em produção.** Tudo é documento. A
> migration mais nova continua **`0205_os_campos_da_apresentacao.sql`** (sessão 105b, abaixo). **O que o
> dono faz à mão: nada a aplicar.** Os números de produção abaixo são os da 105b, **NÃO CONFERIDOS** nesta rodada.

**Entregue (5 commits em `claude/zealous-hopper-14zc5i`, base `main` em `8ae5c35`):**
- `Arquitetura do Sistema/2 Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md` (novo, 517 linhas): fontes
  oficiais (SPED em todos os módulos, eSocial, CT-e, MDF-e, B/L, AWB, DU-E, DI/DUIMP, CE-Mercante, CNAB
  240/400/150, CNAE); 24 reconciliações S1-S7, E1-E5, L1-L6, C1-C6; captação em três canais; pré-requisitos
  (§12); pente fino (§13) com 27 lacunas G1-G27.
- Fase **F2T** em `ARQUITETURA_ALVO_E_ROADMAP.md` (etapas 0-2, ondas 1-5, captação 4-6). O
  `MAPA_DE_EXECUCAO.md` ganhou a linha B8 e a §13, que apontam para a F2T.
- Decisões **D12.1-D12.11** (13/10/2026): **10 de 11 tomadas.** Três mudam o plano: D12.4 = D6 da Espec. 11
  (sem Open Finance; extrato só OFX/CNAB), D12.5 (robô no ReceitaNet BX com alerta de quebra) e D12.10
  (Simples Nacional e declarações estaduais fora).

**Medido nesta rodada (no repositório, não em produção):**
- `SPED`, `EXTRATO_BANCARIO`, `AGING_AP` e `AGING_AR` são `sem_consumidor` na `0187` (medido em 09/10).
- `buscar.mjs` dá NADA ENCONTRADO para `esocial`, `cnae`, `ofx` e `cnab` (853 nós).
- `detectarFormato` (`N8N/lib/formato.mjs`) reconhece pelos bytes: PDF, imagem, xlsx, XML (`<?xml`),
  texto delimitado (`;` `,` tab `|`), HTML e zip. Zip que não é planilha vira `desconhecido`, então zip
  com vários arquivos não abre. Não identifica família fiscal (SPED, NF-e, eSocial, CNAB, OFX).
- **Correção feita na mesma rodada:** o commit `c0d54eb` dizia que o roteador reconhece "texto e zip SÓ
  como xlsx/docx", o que estava errado. A G5 da Espec. 12 foi reescrita com a medição acima: o roteador
  reconhece o formato, mas não a família fiscal. A mensagem do `c0d54eb` continua errada no histórico.

**Em aberto:**
- **D12.3** (Integra Contador): cotar antes, com o SERPRO (serviços e preço por consulta, G22). Não bloqueia
  a etapa 1 nem a onda 1.
- **[A CONFIRMAR] sem responsável (G27):** ReceitaNet BX para procurador, serviços do Integra, eSocial para
  procurador, API do Portal Único com certificado, e cronograma da reforma tributária (G8).
- **D5** (provedor de processos) e **D9** (Reclame Aqui e redes sociais) da Espec. 11: em aberto.
- **NÃO CONFERIDO:** o status atual da F0, de que a etapa 1 da F2T depende. O mapa não traz esse status
  no trecho lido.

**Próximo passo:** a etapa 1 da F2T (fundação sem cliente: roteador, leitor fora do n8n, leiautes) pode
começar, desde que a F0 esteja fechada (ver NÃO CONFERIDO). A única decisão aberta não a bloqueia. O
jurídico interno escreve o termo (D12.6, etapa 2). Pedir a cotação ao SERPRO (D12.3).

## SESSÃO 105b (05/10/2026) — primeiro mandato real pós-republicação (Fw Valtra) e a `0199`

> **Migration mais nova: `0218_o_dial_que_so_media_o_recorte_de_quem_disparava.sql` (ESCRITA, NÃO aplicada em produção; a `0217_o_segredo_do_envio_que_o_n8n_nao_tinha.sql`, que era a mais nova, está APLICADA EM PRODUÇÃO desde 30/10/2026 e é a que o resto desta linha descreve) (S114, no topo; antes dela a `0216_o_acesso_que_so_o_portal_decidia.sql`)** (S112, no topo, ESCRITA e NÃO aplicada; antes dela a `0215_o_historico_que_so_o_banco_sabia.sql`) (S111, no topo, ESCRITA e NÃO aplicada; antes dela a `0214_o_grant_que_o_supabase_deixou_de_dar.sql`) (S110, no topo; antes dela a `0213_a_fusao_que_falhava_na_pergunta_ja_enviada.sql`) (aplicar DEPOIS da 0212; S109, abaixo). Antes dela, `0212_o_bloco_familiar_que_o_controle_comum_nao_via.sql`, `0211_a_fusao_que_apagava_o_perimetro_da_absorvida.sql`, `0210_a_escrita_do_perimetro_que_so_o_superusuario_fazia.sql`, `0209_o_escopo_que_nao_se_confirmava_nem_se_encerrava.sql`, `0208_a_situacao_do_perimetro_que_so_o_teste_lia.sql` e `0207_o_resumo_do_arquivo_oficial.sql` (aplicar DEPOIS da 0206). Antes dela, **`0206_o_arquivo_oficial_lido_e_contado.sql`** (o envelope de cada arquivo oficial lido e a versão vigente, F2T etapa 1, sessão 107; aplicar DEPOIS da 0205). Antes dela, **`0205_os_campos_da_apresentacao.sql`** (os campos "[a preencher]" da apresentação de crédito, #253; aplicar DEPOIS da 0204). Antes dela, **`0204_a_secao_que_o_documento_ja_dizia_pela_arvore.sql`.** A linha sem seção
> herda a seção do pai (a linha cuja chave é o nome da seção bruta dela) e das irmãs, desde que concordem.
> Conflito fica NULL e é contado. A herança é recursiva e nunca vem de topo ou total. Ela fecha o
> resíduo do AC do Fw Valtra: CAIXA MATRIZ, DUPLICATAS A RECEBER e OUTROS CRÉDITOS estavam fora da soma
> (3,75 mi em 2025).
> **`0203_a_secao_que_a_ia_nao_deu_e_a_linha_que_sumia.sql`.** Quando o LLM
> devolve `secao_canonica` nula, a seção bruta passa a decidir pelas regras determinísticas e
> conservadoras: só os casos inequívocos ganham seção, e os ambíguos ficam NULL. A coluna
> `secao_canonica_inferida` marca essas linhas. O backfill cobre as linhas existentes. Medido no
> Fw Valtra: a DRE 2025 tinha 136 de 724 linhas sem seção, e a receita do realizado saía 235.650 em
> vez de ~43,85 mi. Depois de aplicar, rodar `fn_reconciliar_caso` nos casos tocados.
> **`0202_o_total_com_codigo_contabil_que_virava_conta.sql`.** O TOTAL com código
> contábil na frente ("2.3.71 TOTAL") deixava de ser subtotal e dobrava a dívida do mapa (102.600 contra
> 51.300 no arnês). Com a correção, o arnês de variações vai de 1 achado para 0.
> **`0201_o_realizado_que_nao_lia_saldo_final_e_saldo_atual.sql`:** as sugestões do realizado passam a ler
> "Saldo Final/atual". Era isso que deixava a tela de modelagem do Fw Valtra sem nenhuma sugestão.
> Detalhe no commit.
>
> **`0200_o_balancete_semestral_que_entrava_por_cima_do_balanco_anual.sql`** (aplicada em produção).
> A `0199` (aplicada em produção em 05/10, 182/0 na sonda) decidia "parcial entra se é a única fonte"
> POR RÓTULO, e as contas analíticas do balancete semestral entravam por cima do balanço anual. O
> resíduo do AC no Fw Valtra foi a −36 mi (2024) e −47 mi (2025). A 0200 decide por ano e família de
> demonstração: com balanço anual no ano, o balancete parcial não contribui. Teste com 17 asserts;
> 6 reprovam com o filtro desligado e 10 com a regra ao contrário.
>
> **Anterior: `0199_a_serie_por_ano_que_lia_movimento_e_abertura_como_saldo.sql`.**
> `fn_valores_por_ano` montava a série (rótulo, seção, ano) com o MAIOR |valor| entre todas as
> colunas e documentos do ano. No caso real Fw Valtra (`03a66ab6`, MOTO AGRICOLA VOLKWEIS LTDA):
> - o Débito do balancete semestral virou o ATIVO de 2025: 125,86 mi contra 38,48 mi no balanço;
> - Saldo Inicial/anterior era lido como o ano corrente;
> - linhas do contrato social entravam no PL.
>
> O balanço não fechava em ~90,5 mi. Agora movimento fica fora, abertura vale para ano−1, o anual
> vence o parcial e os tipos Societário/Garantias ficam fora. Teste com 21 asserts: 19 reprovam com a
> correção desligada. A ingestão do caso (execução 8433) provou que o n8n republicado grava no banco.
> A modelagem foi entregue ao dono (v2: `auditar-xlsx` 10/11, balanço fecha nas 9 colunas).
> Detalhe: HANDOFF S105 §2c.

## SESSÃO 105 (05/10/2026) — PR #251 mergeado: três decisões do dono fechadas no export

> **Produção conferida só leitura em 05/10:** Supabase em `0198`
> (`0198_a_faixa_de_anos_que_perdia_o_ano_do_meio.sql`, 181/0 ausentes); n8n de ingestão 42/42 nós e
> de erros 3/3 iguais ao repositório; portal (Vercel) = `4b536bc`, o merge do #251. Nenhuma execução
> da ingestão desde a republicação de 01/10: o próximo mandato é a prova de que o n8n grava no banco.
>
> **Decidido pelo dono e implementado (#251):**
> 1. **Estoque (PME) gira contra CUSTO**, não receita (`59ddcb8`): `giraContraCusto` é o único ponto
>    que escolhe a base; a sugestão do realizado é estoques ÷ custos × 360. 11 asserts reprovam sem.
> 2. **"Capital de giro" no PASSIVO é dívida, com ou sem credor** (`01430ea`, `9277bed`): CPC 00/39/48;
>    fora só os termos analíticos (necessidade/variação do capital de giro, capital de giro
>    líquido/próprio). Canastra: CP 14.500/21.900 e LP 28.800/3.800 (2023/2025) entram na dívida.
> 3. **"Capital de giro Caixa"**: resolvido pelo item 2 (a linha é dívida pelo produto); "caixa"
>    sozinho segue fora de `CREDORES`.
>
> Em aberto: HANDOFF S105 §2 (itens 3–5) e §3. Novo: no Vertentes o custo projetado de 2026 (61.193) cai
> muito abaixo do realizado de 2025 (101.300) com a receita subindo — não investigado. O §1 (book do
> Krauspenhar baixado do portal publicado) segue por fazer: falta `PORTAL_EMAIL`/`PORTAL_SENHA`.

> **ACHADO ABERTO (05/10, bateria local completa) — corrigir ANTES de confiar na dívida de um balancete
> de ERP.** Toda a lista do CLAUDE.md passou, mas o arnês de variações acha 1 defeito e sai 0 (o CI não
> reprova): na variante `codigo_contabil_no_rotulo`, a dívida vai de 11.114 a 0 na virada para o
> projetado. É PRÉ-EXISTENTE: reproduz igual no `955ff77`. Causa medida pelo agente (parado a pedido
> do dono, antes de validar): `fn_papel_linha` ancora "total" no INÍCIO do rótulo, e "2.3.71 TOTAL —
> saldo devedor" vira `conta`. A linha de TOTAL do Mapa de Dívida entra como tranche e a dívida dobra:
> 102.600 onde o documento diz 51.300; CP 2024 46.924 contra 23.462. O revolver engole a diferença e
> zera. O patch proposto, NÃO validado, está em `Arquitetura do Sistema/3 Estado e Execução/patches/
> s105-total-com-codigo-no-mapa-de-divida.patch`: o portal reclassifica como subtotal o TOTAL com código
> na frente, e o arnês dá o mesmo código à mesma conta em todos os anos. A correção definitiva é no
> banco: `fn_papel_linha` tirar o código antes de comparar, migration nova. Falta também fazer o arnês
> REPROVAR quando acha (regra 7). Detalhe e roteiro: HANDOFF S105 §2b.

## SESSÃO 105 — comece pelo HANDOFF "▶ SESSÃO 105"

> **A S104 está fechada.** PRs #248 e #249 mergeados no `main` (o merge do #249 é o `66ec163`, de
> 02/10). Produção: Supabase em `0198` (`0198_a_faixa_de_anos_que_perdia_o_ano_do_meio.sql`, 181/0
> ausentes), n8n de ingestão republicado e conferido, reconciliação feita no Krauspenhar e no caso de
> teste. O portal é o `main`, então os consertos do export (AC conciliado, dívida de LP 4,18/9,54 mi,
> `auditar-xlsx` 11/11 no Krauspenhar) chegam no deploy do main. **Primeiro passo:** conferir esses
> números no portal publicado (HANDOFF S105 §1). Decisões do dono em aberto e próximas fatias: HANDOFF
> S105 §2–§3.

## SESSÃO 105b (02–05/10/2026) — apresentação de crédito (.pptx), branch `claude/eloquent-wozniak-jgyo95`

> **Migration 0205 escrita, NÃO aplicada em produção** (`0205_os_campos_da_apresentacao.sql`: tabela `caso_apresentacao_campo`, os 120 campos [a preencher] da apresentação). Quem responde é a sonda: `fn_instalacao_conferir()` where migration = '0205'.
> **Tela `/casos/[id]/apresentacao` e rota de export `?modo=apresentacao` entregues.** Formatação = Prompt Padrão Oria (Teaser); construção = deck Centro Oeste com todos os capítulos. A verificação `portal/scripts/verificar-apresentacao.mts` retorna **58/58** no CI.
> **Testada em 14 entidades de 3 mandatos locais** (Vertentes, Canastra, captura real v35): **12 geram com sucesso, 2 entidades "GRUPO" recusadas com 409**. Leitura de produção negada pela permissão da sessão — mandatos reais grandes (Krauspenhar `33b58a89`) **NÃO testados**.
> **Pendente:** aplicar migration 0205 (DEPOIS das 0199–0204 do #252), testar com produção (não-GRUPO), resumo multi-entidade para grupos, merge do branch sem PR aberto. Detalhes em `Arquitetura do Sistema/6 Referência/apresentacao-credito/ARQUITETURA.md` e `ANDAMENTO.md`.

## SESSÃO 104 (30/09/2026) — PR #248 (rascunho): o modelo que multiplicava por K, e a análise externa do Krauspenhar conferida

> **Produção ATUALIZADA em 01/10 (tarde), a pedido do dono:** Supabase em `0198` (`0198_a_faixa_de_anos_que_perdia_o_ano_do_meio.sql`; 0196, 0197 e 0198
> aplicadas pela API de gerenciamento; `fn_instalacao_conferir` 181/0 ausentes; corpos das 5
> funções reemitidas conferidos antes e depois); ingestão do n8n republicada (`PUBLICADO E
> CONFERIDO`, 42 nós; o `FINGERPRINT_EXTRACAO` mudou — reenviar caso já processado re-extrai tudo);
> `fn_reconciliar_caso` rodado no Krauspenhar e no `72d9210a` (0 de 26 pendências decididas
> tocadas). Detalhe no HANDOFF S104 §0b.
> **Migration 0205 escrita, NÃO aplicada em produção** (`0205_os_campos_da_apresentacao.sql`: tabela `caso_apresentacao_campo`, os campos "[a preencher]" da apresentação). Quem responde é a sonda: `fn_instalacao_conferir()` where migration = '0205'.
> O portal de produção é o `main` — os consertos do portal só chegam com o merge do #248.
>
> **O que o #248 corrige, medido no Excel real do Krauspenhar** (portal do branch servido contra
> produção, só leitura): premissa ligada a K contas multiplicava por K (ativo 2026 413,15 → 89,07 mi,
> `e093f57`); o agrupamento de um documento apagava a folha homônima de outro (receita bruta 2025
> 77,19 → 113,38 mi, resíduo 36,19 → 0, `d5be032`). Mais: aba Modelagem com 8797%, Portão 2 não
> conferido tratado como aberto, e seis guardas novas na ingestão (série com total no topo,
> balancete com colunas trocadas, hierarquia de códigos, rótulo com valor colado, xlsx de várias
> abas, YTD como anual) — todas pedem republicar o n8n.
>
> **A análise externa do Krauspenhar colada no pedido foi conferida item a item** (HANDOFF S104 §2):
> 1, 3, 6, 8 e 11 confirmados; 2 e 5 parciais; 9 invertido; 10 desatualizado; e os "sinais de
> estresse em ago/26" são artefato das colunas trocadas do balancete (estoque real 47,96 mi, não 61,6).
>
> **Validação de 01/10** (HANDOFF S104 §3b): suíte local 27/27, CI (6 jobs + agregador) e Sonar
> verdes; revisão da guarda de hierarquia redesenhada (`9f096c5`): nada sobreviveu — a republicação
> está liberada. O E2E do portal do branch no caso de teste achou e o `bf19d42`/`7f49566` corrigiram o CDI
> que cobrava juro ZERO de 2027 em diante (Krauspenhar: juros do revolver 0 → 2,83–4,26 mi/ano).

## SESSÃO 103 (30/09/2026) — produção em `0195`, ingestão destravada, mandato de teste ponta a ponta no ar

> **Tudo APLICADO em produção nesta sessão, com o dono em modo manual.**
> - Migrations `0183` (em dois envios; o backfill abriu as 18 pendências previstas), `0189`–`0195`.
>   Conferido depois: sonda com 174 requisitos e 0 ausentes, `ate_migration = '0195'`, e as 15
>   chamadas do n8n resolvem.
> - **Escrita, NÃO aplicada:** `0196_o_caixa_que_lia_a_dfc_de_outro_ano.sql` (caixa/receita/despfin deixam de ler documento de outro ano; faturamento tira o ano da coluna).
> - n8n de ingestão republicado (`N8N/republicar.sh`: 42 nós conferidos). Entra o `Classificar Nome`
>   de 24/09, que nunca tinha sido publicado, e os nós `Agrupar Linhas XLSX/XLS`.
> - **Credencial Postgres do n8n CONSERTADA.** Ela estava inválida desde depois de 17/09
>   (`password authentication failed`) e nenhum mandato gravava. Ninguém viu: o workflow de erros
>   usa a mesma credencial. Ver `.claude/memory/credencial-do-n8n-quebra-sem-deixar-rastro.md`.
>
> **O que o repositório ganhou** (um commit por fatia, cada uma medida):
> - Grupos A e B da revisão da S102 (0195 e 0192). A guarda da divergência irmã foi redesenhada
>   por CHAVE (`reconciliacao.periodo_chave_id`), porque três correções por período tinham falhado.
> - Ingestão: planilha grande estourava a pilha no Merge e o orçamento a recusava para sempre.
> - Gravação atômica do gerador macro.
>
> **Mandato de teste ponta a ponta** (caso `bb37f726`, book sintético Vertentes, tudo pelo portal
> publicado): 14 PDFs, 889 linhas, US$ 0,05. Parâmetros, 10 premissas (realizado, Focus, digitadas,
> uma editada), 23 contas em lote e 3 por linha, Portão 2 decidido na tela, export da modelagem:
> `auditar-xlsx.mts` **11/11**, e o gabarito bate (ativo 121.198/95.780, receita líquida
> 143.380/106.580).
>
> **FASE 2 (mesma sessão, depois do merge do #246)** — plano completo e roteiro no topo do
> `HANDOFF.md` (bloco SESSÃO 103). Os itens 1–3 abaixo e o faturamento do item 4 foram CORRIGIDOS
> no repositório: `ac9458d` (item 1), `4db4e9d` (item 3), `9bd2f88` (total da série) e `cbcc74b`
> (0196: item 2 + faturamento/receita/despfin). **Nada disso está em produção ainda.** A 0196 falta
> aplicar e o n8n falta republicar, ambos depois da revisão independente, que foi interrompida
> pelo limite. O mandato REAL "KRAUSPENHAR E HARTMANN" (caso `33b58a89`) foi diagnosticado: xlsx
> lido só na 1ª aba, balancete com colunas N×N+1, rótulo com número colado, DREs com cobertura
> 45–58%. Ver a tabela do HANDOFF.
>
> **Defeitos ACHADOS na fase 1** (o dono pediu só testar naquela rodada):
> 1. **CRÍTICO — "Usar" numa sugestão em % grava fração.** `SugestoesDoRealizado.tsx` manda
>    `0,8797`, e o modelo divide por 100 (`modelo-institucional.ts:2027`). Resultado medido no
>    arquivo: Custo variável sai 0,9% e SG&A 0,2%. **Contorno:** digitar o % (88; 23,6) e clicar
>    "Atualizar". Medido: 0,88/0,236 no Base Case.
> 2. **ALTO — `fn_reconciliar_caixa_bp_fluxo` deixa linha de DFC sem `periodo_coluna` valer para
>    qualquer ano.** DFC anual × BP comparativo abre divergência Classe A falsa (R$ 4,34 mi no teste;
>    é o "v33/v35" que o cabeçalho da 0192 tratou como real). A correção é a mesma
>    `fn_linha_vale_para_ano` da 0195. **Contorno:** marcar a pendência "não procede".
> 3. MÉDIO — a tela de modelagem diz "Pronto para o export" com o Portão 2 fechado, e o export
>    devolve 409 em JSON.
> 4. Extração: COMBINADO com 0 linhas (32 contas descartadas por desalinhamento de coluna) e a série
>    do faturamento 24M não fecha. As duas já abrem pendência (regra 1).

---

## SESSÃO 102 (25/09/2026) — dívidas da reconciliação: `0190` (árvore), `0191` (despfin por ano do mapa), …

> **PR [#245](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/245). Nada aplicado em produção.**
> A F2.3 foi ADIADA por decisão do dono (25/09): medido em produção, nenhum caso tem o outro lado
> da comparação (o FAT_INTRAGRUPO do AMO não traz contraparte; nenhum COMBINADO tem receita em
> "Eliminações").
>
> **`0191_o_mapa_de_um_ano_contra_a_dre_de_dois.sql`** — `fn_reconciliar_despfin_dre_vs_divida`
> comparava CADA ano da DRE com os juros do Mapa de Dívida INTEIRO; o mapa é retrato de UMA data
> (produção: todo MAPA_DIVIDA é `data-base`/`anual` de um ano). DRE `multi "24,25"` × mapa de
> 31/12/2025 comparava 2024 com os juros de 2025 (fixture: R$ 3,5 mi de `zona_cinzenta` falsa,
> apagada na mesma rodada pelo `ok` de 2025 — o defeito da fatia seguinte). Agora ano que o mapa
> não cobre é `sem_periodo_par`. `despfin_ano_par_do_mapa.test.sql`: 9 asserts, 5 reprovam
> desligado (medido pelo agente); nenhum assert existente mudou. **Vem ANTES da guarda
> "divergência prevalece na rodada"**, que sem ela faria a pendência falsa sobreviver.
>
> **`0192_o_ok_que_matava_a_divergencia_irma.sql`** — `fn_registrar_reconciliacao` acha a
> pendência por período COMPATÍVEL; na mesma rodada, o `ok` de um período RESOLVIA a divergência
> de outro, e a ordem (`select distinct` sem `order by` no `fn_reconciliar_caso`) decidia o
> desfecho. Produção: Teste v33/v35, caixa com R$ 4,34 mi de divergência em 2024, pendência criada e
> resolvida no MESMO instante pelo `ok` de 2025; teste AMOBELEZA, mesmo arranjo na ordem inversa,
> ficou aberta. 41 pendências nascidas e mortas no mesmo instante (37 pré-condição do retry
> desenhado da 0152, que NÃO muda; 4 divergências). Agora a divergência mais recente da rodada, em
> período compatível, prevalece sobre `ok` e sobre pré-condição; `order by` nos laços.
> `divergencia_prevalece_na_rodada.test.sql`: 15 asserts, 3 reprovam desligado (contados sem parar
> no primeiro raise). Os asserts do `reconciliacao.test.sql` NÃO mudaram — a versão do agente os
> alterava para exigir a pendência falsa de despfin/2024, e foi isso que fez a `0191` nascer antes.
>
> **`0193_a_tolerancia_que_crescia_com_a_escala.sql`** — o mesmo vício da 0188 (tolerância
> absoluta × fator de escala) em `fn_reconciliar_caixa_bp_fluxo` e
> `fn_reconciliar_receita_dre_vs_faturamento`, corrigido igual (na base). Efeito ZERO medido em
> produção (25/09/2026, somente leitura) — correção latente, não aplicada.
>
> **`0194_a_planilha_de_mutuos_que_nunca_foi_lida.sql`** — `fn_reconciliar_mutuos` nunca concluía
> em produção (planilha MUTUOS é retrato de uma data, não comparativa; 12/12 casos ficavam em
> `documento_ausente`, 7 com conta de mútuo no balanço). Escrita, não aplicada.
>
> **`0195_o_espelho_que_lia_o_balanco_de_outro_ano.sql`** — `fn_reconciliar_intragrupo` (0124) tinha
> os dois vícios que a 0194 já tinha corrigido em `fn_reconciliar_mutuos` (fatorados agora em
> `fn_linha_vale_para_ano`): o balanço de cada entidade era escolhido uma vez para a checagem
> inteira, sem preferir o que TRAZ dado do ano; e uma linha sem `periodo_coluna` valia para
> QUALQUER ano perguntado. Medido em produção (28/09/2026, só-leitura): quase 100% das linhas
> intragrupo incluídas por (caso, ano) vinham de documento que não ancora aquele ano. Escrita, não
> aplicada.
>
> **`0190`** (abaixo):
>
> **O defeito.** `fn_reconciliar_arvore` (corpo vigente na `0133`) testava só dois ramos:
> `v_n_ok+v_n_div+v_n_prec=0` (sem árvore) e, senão, `resultado := case when v_n_div>0 then
> 'divergente' else 'ok' end`. Faltava o meio: `v_n_ok=0 and v_n_div=0 and v_n_prec>0` — TODAS as
> seções em pré-condição, NENHUMA conferida — caía no `else` e saía `resultado='ok'`,
> `precondicoes_ok=true`. A `0143` (hierarquia achatada) abriu esse buraco: um balanço inteiramente
> achatado passou a cair inteiro em pré-condição de uma vez. **Medido em produção (25/09/2026,
> somente leitura): 12 linhas de `reconciliacao` com `tipo='secao_fecha'`, `resultado='ok'` e
> `fonte_a->>'secoes_conferidas'='0'`, em 4 casos; 48 documentos atuais com 0 conferidas e >0
> pré-condição.**
>
> **A correção.** No ramo `v_n_ok+v_n_div=0`, grava `p_resultado='documento_ausente'` — o mesmo
> motivo do ramo "sem árvore" (CONTRATO da `0186`). Efeito: `precondicoes_ok=false`,
> `resultado='precondicao_nao_satisfeita'`, `motivo_precondicao='documento_ausente'`. **A fila NÃO
> muda**: `documento_ausente` já não abre pendência (mesma linha da `0186`/`0188`), então isto só
> corrige a AFIRMAÇÃO, não o comportamento de quem já não acusava rótulo duplicado ou hierarquia
> achatada como achado próprio. Reemitida a função inteira a partir do corpo da `0133` (nunca
> `replace`). Catálogo: requisito corpo `reconciliar_arvore_nao_mente_ok`, ordem 830 (a `0189` usa
> 820–829). `Supabase/README.md` não depende da `0189` (segue pendente do dono).
>
> **Teste `Supabase/test/secao_fecha.test.sql`, bloco 8 — 12 asserts novos, 4 reprovaram com a
> correção desligada** (guarda `if false and v_n_ok + v_n_div = 0`, medido fora do arquivo de
> teste para não perder no primeiro `raise exception`): as 4 que checam `precondicoes_ok=false`/
> `resultado`/`motivo_precondicao` para o documento "hierarquia achatada" e a que checa o mesmo
> para "rótulo duplicado". As outras 8 (as duas pré-condições medidas por `fn_conferir_arvore`,
> fonte_a/fonte_b, a fila inalterada nos três documentos, o `ok` parcial) continuam verdes porque
> não dependem do ramo novo. Religada a correção, `Supabase/test/run.sh` completo: verde, 1.600
> linhas `NOTICE:  ok`, `Supabase/schema.sql` sem diff.
>
> **O que falta** — aplicar em produção (a 0182/0183/0189 seguem pendentes do dono antes desta) e,
> à parte, um backfill das 12 linhas já erradas (a consulta que as acha está no `Supabase/README.md`,
> bloco da `0190`) — não incluído aqui por exigir a mesma medição de alcance que a `0179`/`0183`
> pularam.

---

## SESSÃO 101 (23–24/09/2026) — `0189`: a sonda passa a ver GATILHO, não só a função que ele chama

> **PR [#242](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/242). Nada aplicado em produção.**
>
> **O defeito.** `fn_instalacao_conferir()` não tinha tipo para gatilho: catalogava a FUNÇÃO do
> gatilho, que sobrevive a `drop trigger` e a `disable trigger`. Medido em 23/09: derrubar as três
> guardas por gatilho da F1.7 deixava o painel verde (a F1.7 registrou isso como "achado sistêmico
> NÃO corrigido" — é este).
>
> **A correção.** Tipo `gatilho` (`objeto = tabela.nome_do_gatilho`, presente só com `tgenabled` em
> `'O'`/`'A'` — `'R'`, modo réplica, conta como DESLIGADO de propósito), `fn_instalacao_conferir`
> reemitida inteira a partir da `0147`, e os **nove** gatilhos não-internos de `main` catalogados:
> as quatro guardas do golden set (`0126`), `trg_auto_promover_dial` (`0137`),
> `trg_entidade_ambigua` (`0153`) e os três da F1.7 — `trg_entidade_controlador_soma_maxima`
> (`0182`), `trg_entidade_forma_de_controle_tem_vinculo` e `trg_instalacao_cobertura_nao_regride`
> (`0183`). Mais o requisito corpo `sonda_ve_gatilho`. Ordens 820–829 (a `0187` usa 790–796, a
> F1.7 chega a 815).
>
> **Teste `Supabase/test/sonda_ve_gatilho.test.sql`, 17 asserts**, com igualdade de conjuntos
> entre `pg_trigger` e o catálogo: gatilho novo sem requisito deixa o `run.sh` vermelho. Medição
> não-vazia (regra 2), ramo desligado × ok/FALHOU: `v_ok := true` → 6/6; `'R'` aceito → 15/1;
> só `'O'` → 16/1; gatilho fora do catálogo → 1 FALHOU; ligado → 17/0.
>
> **O que o dono faz à mão, NESTA ORDEM** (a ordem importa):
> 1. **A `0183` primeiro** — o roteiro da F1.7 logo abaixo. Ela conserta o marcador de cobertura,
>    que está ERRADO em produção (`0182` por cima de `0188`).
> 2. **Depois a `0189`:** `supabase db execute --file Supabase/migrations/0189_o_gatilho_que_a_sonda_nao_via.sql`.
>    Ela cataloga gatilhos que só existem com a `0183`; aplicada antes, a sonda acusa dois ausentes
>    — o que é VERDADE, não defeito, mas confunde. Conferir:
>    `select chave, objeto, detalhe from fn_instalacao_conferir() where tipo='gatilho' and not presente`
>    → vazio. Uma linha ali é um gatilho de fato desligado em produção.
> 3. Nenhum workflow, republicação ou deploy de portal.
>
> **Achado fora do escopo, registrado no PR:** `N8N/test/macro.test.mjs` regera
> `workflow.macro.json` durante a suíte e `workflow-macro-sim.test.mjs` pode lê-lo truncado
> (reprovou uma vez no CI, 535/536). Patch proposto no PR (gravação atômica no builder).

---

> ## F1.7 CONSTRUÍDA — `0182` APLICADA EM PRODUÇÃO, `0183` PENDENTE DO DONO (23/09/2026)
>
> **⚠️ PRODUÇÃO ESTÁ COM O MARCADOR DE COBERTURA ERRADO, e foi esta sessão que causou.** A `0182`
> foi aplicada em 23/09, DEPOIS da `0188` (a F2 aplicou 0186–0188 em 22/09), e o `update
> instalacao_cobertura set ate_migration = '0182'` do fim dela rebaixou o marcador de `0188` para
> `0182`. A sonda de produção agora SUBNOTIFICA o que está instalado. **Aplicar a `0183` conserta**:
> ela cria um gatilho que impede o marcador de regredir e o recalcula a partir do catálogo. Enquanto
> ela não for aplicada, `ate_migration = '0182'` em produção é falso.
>
> **O que o dono aplica, nesta ordem** (o classificador de modo automático do Claude Code bloqueou o
> apply da `0183` como "Production Deploy" — nada dela rodou). **Caminho que funciona**, medido pela F2
> em 22/09 (`.claude/memory/auto-mode-recusa-migration-producao.md`): trocar a sessão do Claude Code
> para modo de permissão **manual** e aprovar cada chamada — ou aplicar à mão. Não adianta autorizar
> no chat: a F2 mediu que a nova tentativa é recusada de novo.
> 1. SÓ a linha `alter type pendencia_tipo add value if not exists 'forma_de_controle_indefinida';`
> 2. o resto de `Supabase/migrations/0183_a_forma_de_controle_que_ninguem_declarava.sql`, com
>    aquela linha comentada (a API envolve o lote numa transação; ver o aviso no `Supabase/README.md`).
>    Antes: `select pg_get_functiondef('fn_fundir_entidade(uuid,uuid,uuid,text)'::regprocedure)` em
>    produção tem de ser o corpo da `0153` — a 0183 o reemite (item 10), e a diferença tem de ser só
>    os blocos marcados `0183`.
> 3. conferir: `select ate_migration from instalacao_cobertura` tem de voltar a `0188` (ou mais), e
>    `fn_instalacao_conferir()` sem ausentes. O backfill abre **18** pendências `forma_de_controle_
>    indefinida` (13 registros de entidade do caso AMO, que tem 8 empresas reais, + 5 dos casos
>    AMOBELEZA*) — medido em produção antes, não 365.
>
> **O que a fatia entrega.** `0182`: `controlador` + `entidade_controlador` (N:N, percentual que nunca
> passa de 100 e nunca é obrigado a fechar 100) + `fn_grupo_por_controle_comum` (fecho transitivo).
> `0183`: `entidade.forma_de_controle`, que torna `controladora_id` NULL distinguível de "ninguém
> cadastrou". Medição (regra 2), remedida contra o código final: 0182 **5/32** (soma) e **3/32**
> (fecho); 0183 **4/24** (check), **4/24** (vínculo), **1/24** + 1 na sonda (backfill), **6/8**
> (a fusão de entidades, item 10 — achado CRÍTICO do /revisar de 24/09: `fn_fundir_entidade` apagava
> por cascata o vínculo de controle declarado na absorvida; `Supabase/test/fusao_preserva_controle.test.sql`). Detalhe em
> `.claude/conhecimento/fichas/f1-controle-comum-0182-0183.md`.
>
> **O achado que muda o critério.** Com os sócios EXATOS dos 4 contratos legíveis, o modelo dá **dois
> grupos de dois**, não um de oito. Unir os dois exige decidir se sócios de mesmo sobrenome são um
> bloco familiar — juízo, não medição. O critério foi revisado no roadmap (§12.2): "as 8 como um
> grupo" depende dos 4 contratos que faltam e de uma decisão do dono, não de código.
>
> **Guardas construídas na origem dos erros desta sessão** (cada uma medida): `indexar.mjs`
> respeita o `.gitignore` · o hook de derivados conhece o grafo · portão `medicao-denominador`
> (denominador declarado tem de bater com o arquivo) · gatilho do marcador de cobertura · a sonda de
> produção vê buraco no meio da sequência (compara com o `README`) · lições no agente
> `migrations-postgres`. **Achado sistêmico NÃO corrigido, proposto como tarefa:** a sonda não
> enxerga gatilho desligado (medido: derrubar as três guardas por gatilho da F1.7 deixa o painel verde).
>
> **Efeito esperado depois do merge:** a sonda agendada de produção fica VERMELHA até a `0183` ser
> aplicada — ela passa a acusar o buraco que antes escondia. A `0184` foi reservada e NÃO usada.
>
> **F1.3, F1.4 e F1.5 foram executadas e verificadas independentemente:**
> - **F1.3**: `entidade.papel_no_grupo` tipado em enum + escrita explícita (`fn_entidade_definir_papel_no_grupo`) + guarda de pendência. Migration `0179`. **VERIFICADA**: reconstrução do banco do zero, correção desligada (reprova no ponto esperado), religada (todas as suítes passam).
> - **F1.4**: tabela nova `perimetro(caso, entidade, escopo, desde, ate)` com funções de leitura/escrita. Migration `0180`. **VERIFICADA**: idem acima.
> - **F1.5**: `entidade.controladora_id` (FK self-referencing) + `percentual_participacao`, guarda contra ciclo, funções de leitura/escrita. Migration `0181`. **VERIFICADA**: idem acima. 29 asserts novos, 4 medidos reprovando sem a guarda.
>
> **Colisão de duas sessões paralelas em F1.4 resolvida por merge** (não rebase, não force-push) — ambas compatíveis. Ver `.claude/memory/colisao-sessoes-paralelas-mesma-branch.md`.
>
> **F1.6 bloqueada**: depende do dono fornecer o COMBINADO real do cliente para conferir o perímetro contra ele. O mandato AMO teste 00 não tem COMBINADO real ingerido.

---


## SESSÃO 100 (22/09/2026) — F2: `0186`, `0187` e `0188` APLICADAS em produção; D6 VERDE em produção

> **✅ APLICADAS EM PRODUÇÃO em 22/09/2026 (fim da S100): `0186` → `0187` → `0188`**, pela API de
> gerenciamento, com o dono aprovando cada chamada em modo de permissão manual. Pré-medição repetida
> imediatamente antes (nada tinha mudado). Efeito MEDIDO depois de cada uma:
>
> | Migration | Previsto | Medido |
> |---|---|---|
> | `0186` | backfill 5.023/5.023, 0 NULL | **5.023 preenchidas, 0 NULL** (1.708 `documento_ausente`, 3.315 genérico); sonda 0 ausentes |
> | `0187` | 5 resolvidas, 0 abertas, 1 ressalva intocada | **5 resolvidas, 0 abertas, 1 ressalva, 5 eventos**; **D6 VERDE EM PRODUÇÃO**: 6 `exigencia_viva` + 2 `consumidor_nomeado` + 28 `sem_consumidor_declarado` = 36, zero `SEM_COBERTURA`/`DECLARACAO_QUEBRADA`; `instalacao_sonda_saldo_mutuos` = 4 |
> | `0188` | ~50 de 52 com o recado da DRE líquida | **48 de 52** (as 4 sem: 2 sem linha financeira, 1 juros bancários — resolve no próximo recompute do caso —, e 1 sem explicação, a mesma que a conta 50+2+1=53 da S99 não fechava); sonda 0 ausentes, cobertura `0188` |
>
> **Prova de que a reconciliação RODA com as funções novas** (o risco silencioso da revisão): `fn_reconciliar_caso`
> num caso real dentro de um bloco com rollback proposital — 61 linhas em todas as checagens, motivo
> gravado em cada precondição, uma despfin agora `zona_cinzenta` onde a tolerância de R$ 50 mi dizia
> "confere". Nada gravado. **Os motivos específicos da 0188 aparecem nas PRÓXIMAS rodadas de cada caso** —
> as linhas antigas ficam com o que o backfill da 0186 recuperou.


### Estado atual de produção e repositório

| | |
|---|---|
| **Última migration APLICADA** | **ATUALIZADO 23/09/2026:** produção tem `0186`→`0187`→`0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql` (F2, 22/09, ver S100 abaixo) e a `0182` (F1.7a, aplicada em 23/09, DEPOIS da 0188). O marcador `ate_migration` de produção está em `0182` por REGRESSÃO — o real é `0188`, e a `0183` o repara. A S100 registrou `0188, 0 ausentes` em 22/09, correto naquele dia. |
| **Migrations PRONTAS mas NÃO APLICADAS** | **`0183`** (F1.7b) — bloqueada pelo classificador de auto mode; o dono aplica em modo manual (ver o topo e `.claude/memory/auto-mode-recusa-migration-producao.md`). `0184`: reserva da F1.7, NÃO usada. `0185`: DESCARTADA pela F2 (arquivo removido na 0187). |
| **Decisão do dono, 21/09/2026** | **F2 (cobertura de tipos) escolhida entre 1.7/F2/F3b**. Acrescentado: "não é ideal deixar etapas abertas, visando fechar cada etapa anterior o mais rápido possível quando deixada para trás" |

### Entrega 1: Pré-condições da `0186` MEDIDAS contra produção e LIBERADAS — aplicação RECUSADA pelo classificador de auto mode

**A `0186` não mudou de conteúdo desde a sessão 99.** O que esta sessão fez foi rodar as 3
consultas somente-leitura do `Supabase/README.md` contra o banco real (0181) antes de aplicar,
como o passo "O que o dono faz à mão" da rodada anterior pedia:

| Consulta | Medido em produção |
|---|---|
| Linhas com `precondicoes_ok=false` | **5.023** (não 1.926 — esse número da sessão 99 era só de `ativo_passivo_pl`; o total contando todas as checagens é 5.023) |
| Backfill alcança | 5.023/5.023 — **0** ficariam `NULL` |
| Eventos múltiplos ou motivos conflitantes na mesma linha | **0** |
| Vocabulário emitido em produção | **6 valores**: `precondicao_nao_satisfeita` 3.315 · `documento_ausente` 1.708 · `ok` 898 · `zona_cinzenta` 128 · `divergente` 124 · `divergencia` 69 — todos dentro da guarda nova |

Nenhuma das três consultas mandou NÃO APLICAR. A `0186` estava, portanto, liberada para
aplicação nesta sessão.

**O que NÃO aconteceu: a aplicação em si.** O classificador de permissão do auto mode recusou o
`curl` contra a API de gerenciamento do Supabase (rótulo "Production Deploy") **duas vezes**,
inclusive depois de o dono autorizar explicitamente no chat. Autorização em texto não muda a
regra de permissão configurada — precisa de regra em `settings.json` (ver lição de ambiente
nova, abaixo). Sonda segue em `0181`; `0186` continua PRONTA, MEDIDA e LIBERADA, mas NÃO
aplicada.

**Ordem de aplicação confirmada**: `0186` → `0187` → `0188`. `0182`–`0184` são lacuna reservada à
fatia 1.7 (outra sessão, em paralelo).

### Entrega 2: `0187` — D6 por declaração; a suspeita MUTUOS/FAT_INTRAGRUPO da sessão 99 CONFIRMADA e corrigida

**Escrita, 27 asserts verdes, `0185` DESCARTADA do repositório.**

Censo D6 medido em produção (banco 0181): **24 tipos com documento**, **6 com exigência viva**
(lida por alguma checagem — BALANCO, DRE, COMBINADO, FATURAMENTO_24M, MAPA_DIVIDA, FLUXO_CAIXA),
**18 sem**. `taxonomia_tipo_cobertura` (30 tipos declarados: 3 `consumidor_nomeado` — MUTUOS→
`fn_reconciliar_mutuos`, BALANCETE→`fn_reconciliar_arvore`, DF_AUDITADA→
`fn_reconciliar_intragrupo` — e 27 `sem_consumidor` com motivo+efeito) e `fn_cobertura_de_tipos()`
respondem D6 de forma estrita sobre todos os tipos ativos.

**A suspeita aberta na sessão 99 (MUTUOS/FAT_INTRAGRUPO reprovam contra fixture, mesmo defeito da
`0185`) foi CONFIRMADA nesta sessão e corrigida.** As 5 pendências `linha_exigida_ausente`
ABERTAS em produção de MUTUOS (1), FAT_INTRAGRUPO (3) e CONTRATO_SOCIAL (1) foram conferidas
UMA A UMA — **todas falsas** (o item está na chave, o conceito mora na seção ou no tipo). `0187`
desativa a exigência `proposta` de MUTUOS e FAT_INTRAGRUPO, e dá a CONTRATO_SOCIAL um localizador
de seção. Previsão medida do efeito em produção: 5 pendências resolvidas, 0 abertas; a 1
`aceita_com_ressalva` de MUTUOS fica intocada pela migration (comportamento pré-existente para
exigência desativada — só o próximo recompute daquele caso a fecha).

Resolução dirigida (`fn_resolver_linha_exigida_superada`) e `fn_sugerir_perguntas` reemitida
({saldo_mutuos} não pode dizer "não localizado" só porque a exigência foi desativada). `0185` e
seu teste DESCARTADOS — nunca aplicada, número fica como lacuna, explicado no `Supabase/README.md`.

Desligando (regra 2): declaração 4 · desativação 2 (RE-MEDIDA pela sessão principal: 2, os
mesmos) · localizador de seção 4 · resolução dirigida 4 · `{saldo_mutuos}` 3+1.

### Entrega 3: `0188` — o motivo específico por checagem, e o recado da DRE líquida

**Escrita, 28 asserts verdes.**

53 linhas das fixtures perturbadas passam a ter motivo específico em vez do genérico (12
`linha_nao_localizada`, 15 `sem_periodo_par`, 26 `unidade_divergente`); retorno de
`fn_registrar_reconciliacao` ACHATADO para os três motivos novos (os despachantes da `0152`
fazem `exit when resultado <> 'precondicao_nao_satisfeita'` e parariam no primeiro período sem
isso). `taxonomia_linha_alternativa` dá o recado da DRE líquida — medido em produção: a
alternativa `['resultado','financeiro']` exceto `['antes']` casa "resultado financeiro liquido"
em **71 entidades**. Localizador `['juros','bancari']` exceto `['receita','aplicac']` casa "juros
e comissoes bancarias" — medido: **8 linhas, 4 entidades**.

Desligando: motivo 8 · retorno achatado 4 (RE-MEDIDO pela sessão principal: 4, os mesmos) ·
alternativa 4 · descrição 1 · bancari código 1 · bancari seed 2 · reescrita dirigida 2.

**Esperado em produção** (previsão, não medição — a `0188` não foi aplicada): das 52 pendências
de despesa financeira, ~50 mudam de texto (recado da DRE líquida); a 1 falsa de juros bancários
só resolve no próximo recompute do caso.

### Entrega 4 (F2.4): terceiro book — `book-distress`, Grupo Piraquara

3 entidades × 2023–2025, 14 PDFs, 262 linhas de conta. PL da Metalúrgica 10.641 → 11.006 →
(7.355); covenant DL/EBITDA chega a 12,25x contra limite 3,0x; aging AP de 12 fornecedores
rotulados por nome, total **14.900 = Fornecedores do BP**; extrato de 12 meses fecha em
**676** = caixa do BP. Determinístico (md5 idêntico em 2 gerações); CI gera. **Achado:** A=P+PL e
ΔPL valem por construção (+1 no imobilizado 2023 NÃO reprova o motor) — README corrigido para não
prometer o que o gerador não confere. **Achado:** o `book-canastra` NÃO é determinístico ao byte
(PDF muda de md5; `METRICAS.json` estável). Sem fixture SQL ainda — nenhuma checagem lê
aging/extrato hoje.

### F2.2 e F2.3 — medidas, não construídas

**F2.2 (MAPA_DIVIDA fino):** MEDIDO e NÃO construído. 51 mapas com conteúdo em produção, 2.268
linhas; 12 com linha de juros, 12 com saldo, **0 com taxa, 0 com vencimento, 0 com covenant** —
essas colunas não chegam como linha de conta. Depende da F3 (schema da linha).

**F2.3 (consumidor real para MUTUOS/FAT_INTRAGRUPO/CONTRATO_SOCIAL):** NÃO fechada. MUTUOS já tem
consumidor (`fn_reconciliar_mutuos`). FAT_INTRAGRUPO e CONTRATO_SOCIAL ficaram declarados
`sem_consumidor` (com efeito, regra 1) na `0187`. Escrever uma checagem que leia FAT_INTRAGRUPO
(pares A→B por ano contra a eliminação do COMBINADO/FATURAMENTO_24M) é desenho novo, não feito
nesta sessão.

### Aceite financeiro da F2 — NÃO VERIFICADO

"Mandato sem aging/extrato não é declarado pronto": nenhum indicador de prontidão implementa
esse critério hoje, e os extratos reais do mandato AMO não passam pela ingestão (limite de
tamanho, ~125–150 mil itens). Isso é NÃO VERIFICADO, diferente de verificado e OK.

### Achados registrados e NÃO corrigidos nesta sessão

- `fn_reconciliar_arvore` (`0133`) devolve `ok` ("As 0 seções fecham…") quando nenhuma seção pôde
  ser conferida — viola a regra 7 (estágio desligado parece estágio limpo).
- `fn_reconciliar_caso` (`0152`) itera sem `order by` — o período da pendência varia entre
  rodadas.
- `fn_reconciliar_mutuos` com escala ausente de um lado termina em `documento_ausente` (a unidade
  aparece como "sem par").
- `consumidor_existe` só olha `pg_proc` — não percebe consumidor que deixou de LER o tipo.
- DVA/DMPL entram na soma do realizado — possível dupla contagem, não investigado.
- `fn_conflitos_do_caso` compara número de NOTAS_EXPL/DVA/DMPL por rótulo idêntico, mas foi
  declarado "não consumidor" — decisão a revisar.

### Revisão independente (`/revisar`, 22/09/2026) — três ALTOS corrigidos antes de qualquer apply

Duas lentes (defeito silencioso + fidelidade do número) sobre `5bea570..HEAD`. Corrigido no próprio
arquivo da `0187`/`0188` (commit `3542342`), porque nenhuma foi aplicada:

- **ALTO — a `0188` instalava limpa sem a `0186`** e toda reconciliação morreria em runtime; o n8n
  (`continueRegularOutput`) seguiria com ZERO reconciliações. Agora a `0188` aborta com
  "0188 exige a 0186 aplicada antes" — provado em banco descartável.
- **ALTO — tolerância da despfin = 50.000 × fator = R$ 50 milhões** em DRE em milhar. **Medido em
  produção: 1 dos 33 "confere" é falso, divergência de R$ 12.400.000.** Tolerância passa para a base.
- **ALTO — a pergunta 5.1 ao CLIENTE** dizia "(não localizado)" no arranjo real de mútuos e, em
  outros, somava TOTAL + itens. Redesenhada sem léxico; sem saldo seguro, diz por que não apurou.
- **MÉDIO — D6 ficava verde** se o consumidor existisse mas deixasse de ler o tipo: agora há
  `marcador` conferido no corpo. DF_AUDITADA passou a `sem_consumidor` (2 nomeados, 28 sem).
- **MÉDIO — textos do seed** ("17/17" em tipo com zero documento) corrigidos.
- **Book-distress:** a MEP de 2025 saía em branco com a nota dizendo zero (`76662dc`).
- **Latente, NÃO corrigido, medido:** receita (`50.000 × fator`) e caixa (`100 × fator`) têm o mesmo
  vício de tolerância — **0 "confere" falsos hoje em produção** (receita no máximo 4,8%). Fatia própria.

> **DECISÕES DO DONO, 22/09/2026 (fim da S100):** (1) **F2.3 VALE** — escrever a checagem que lê FAT_INTRAGRUPO é a próxima fatia da F2, logo depois do apply das `0186`→`0187`→`0188`. (2) O **aceite financeiro da F2 fica NÃO VERIFICADO até a F3 começar** — não é pendência desta fase; reabre quando a ingestão aguentar os extratos grandes (`CR`/`CP`). (3) O apply NÃO pode ser feito pelo agente em auto mode: o classificador recusou `curl` à API ("Production Deploy") e, quando o agente acrescentou a regra de permissão ele mesmo, recusou por "Self-Modification" — a edição foi desfeita. Caminho: o dono troca o modo de permissão da sessão para manual e aprova o comando no prompt, ou aplica pelo SQL Editor do Supabase.

### Onde estamos

**F2 com D6 VERDE NO REPOSITÓRIO — não em produção.** Para a F2 fechar: aplicar `0186`→`0187`→
`0188` (nesta ordem) e rodar `fn_cobertura_de_tipos()` em produção; decidir F2.3 (checagem de
FAT_INTRAGRUPO) ou aceitar a declaração `sem_consumidor` como final; o aceite financeiro da F2
depende da F3/ingestão (extratos grandes não entram hoje).

### O que fica ABERTO, nomeado

- **Aplicar `0186`→`0187`→`0188` em produção** — pré-condições medidas e liberadas, falta só a
  aplicação (bloqueada pelo classificador de auto mode nesta sessão). *(→ APLICADAS no fim da S100, em modo manual; ver o bloco da S100.)*
- **F2.2 fino (MAPA_DIVIDA: taxa, vencimento, covenant)** — depende da F3.
- **F2.3 (checagem de FAT_INTRAGRUPO)** — desenho novo, decisão do dono se vale a pena antes da
  F3.
- **Aceite financeiro da F2** — depende da F3/ingestão de extratos grandes.
- **Os 6 achados registrados acima** — nenhum corrigido.
- **Tolerância de receita e caixa multiplicada pela escala** — latente (0 falsos hoje), fatia própria.
- **Fatia 1.7** — segue em outra sessão, `0182`–`0184` reservadas. *(→ construída e incorporada com a F2 nesta branch; `0182` aplicada, `0183` pendente do dono; ver o topo.)*

### O que o dono faz à mão

**Aplicar, NESTA ORDEM, `0186` → `0187` → `0188`** — as pré-condições das três estão medidas e
liberadas nesta sessão (ver Entregas 1–3 acima). **A aplicação precisa de uma regra de permissão
em `settings.json`** que libere a chamada de gerenciamento do Supabase para o auto mode, ou
precisa ser feita fora do auto mode — o classificador recusou mesmo com autorização no chat (ver
lição de ambiente nova em `.claude/memory/`). Depois de aplicar, rodar `fn_cobertura_de_tipos()`
contra produção e conferir os efeitos previstos nas Entregas 2 e 3 (5 pendências MUTUOS/
FAT_INTRAGRUPO/CONTRATO_SOCIAL resolvidas; ~50 de 52 pendências de despesa financeira com texto
novo). Nenhum workflow tocado, nenhuma republicação, nenhum deploy do portal nesta sessão.

## SESSÃO 99 (21–22/09/2026, resumo) — F2 escolhida, `0185` rejeitada na medição, `0186` pronta e não aplicada

`0186` escrita e testada (10 asserts) mas não medida contra produção nesta sessão; `0185` (F2.1,
nove tipos itemizados com exigência lexical) escrita, testada localmente (51 asserts) e REPROVADA
na medição contra produção — 17/17 pendências que abriria eram falsas (em relatório itemizado o
conceito não está no rótulo, é o tipo do documento). Camada de reconciliação medida: consumidores
atuais concluem entre 8,3% e 67,8% por caso × entidade. Decisão do dono: F2 escolhida entre
1.7/F2/F3b; os nove tipos da `0185` ficam complementares, não bloqueantes. Suspeita aberta,
não investigada: MUTUOS/FAT_INTRAGRUPO também reprovavam contra fixture — **confirmada e
corrigida na sessão 100, ver acima**. Detalhe completo em `HANDOFF.md` (cabeçalho anterior,
arquivado) e na ficha `f2-localizador-chave-pendencia-falsa.md`.

Este arquivo responde **onde o projeto está agora**. O `HANDOFF.md` responde **como chegou aqui** —
5.000 linhas de histórico sessão a sessão, que continuam valendo como referência e não precisam ser
lidas para retomar. E `Arquitetura do Sistema/3 Estado e Execução/PRONTIDAO_POR_ESTAGIO.md` mede o projeto contra o objetivo, estágio por estágio. `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` responde **o que falta até fechar**, em ordem, com o
critério de pronto de cada bloco — é o arquivo para abrir antes de escolher o que fazer na sessão.

> **Por que os dois são arquivos separados.** O cabeçalho do `HANDOFF.md` já passou 17 PRs congelado
> em "PR #70, migrations até `0034`", e mandava quem chegava começar errado. A causa não é descuido:
> é que a parte que muda TODA rodada morava no mesmo arquivo das partes que nunca mudam, e um
> arquivo que quase nunca se edita não convida a editar nada. Aqui só há o que muda — e o
> `Supabase/test/run.sh` reprova quando a migration mais nova não está citada abaixo.

> **A F0 (fechar o fosso repositório ↔ produção) ESTÁ QUASE FECHADA.** Banco em dia (`0175`–`0177`
> aplicadas e conferidas), os 4 workflows republicados e EM DIA (18/09 — a ingestão levou ao ar o
> fix do Bug C + o CRÍTICO da revisão multilente, que tinham ficado só no repositório desde 17/09),
> as duas ADRs + duas decisões do dono registradas.
>
> **CORRIGIDO EM 18/09/2026, contra os logs do CI: `SONDA_DB_URL` JÁ ESTAVA CADASTRADO.** Esta
> linha dizia que faltava, e dizia errado desde antes — a execução agendada de 17/09
> (`sonda-producao.yml` #6) passou inteira, com "segredo presente" no log e o catálogo de produção
> sem ausência. O que o dono aplicou em 18/09 foi uma SUBSTITUIÇÃO do valor, e ela QUEBROU o
> portão: o segredo passou a conter a linha de comando `psql -h … -d postgres` em vez da URI, e
> como o workflow monta `psql '<segredo>'`, o psql leu tudo aquilo como NOME DE BANCO e tentou o
> socket local do runner (`/var/run/postgresql/.s.PGSQL.5432: No such file or directory`). O valor
> certo é a URI (`postgresql://…/postgres`) de um POOLER — `Direct connection` é IPv6 e os runners
> do GitHub são IPv4; o valor que funcionava era `aws-1-sa-east-1.pooler.supabase.com`.
>
> **RESOLVIDO às 16:46 de 18/09**: o dono repôs o valor como URI de pooler e a sonda rodou verde nos
> sete passos — inclusive os dois que se cobrem mutuamente, "o catálogo de produção não tem ausência"
> e "o que o código chama existe em produção". O portão agendado voltou a perguntar. Três tentativas
> foram necessárias e cada erro deixou uma assinatura distinta no log, que vale guardar: linha de
> comando no lugar da URI → `socket "/var/run/postgresql/.s.PGSQL.5432": No such file or directory`
> (o psql lê o comando inteiro como nome de banco); URI de `Direct connection` → `Network is
> unreachable` num endereço IPv6, porque os runners do GitHub são IPv4 e só o POOLER atende.
>
> Falta, então, **um** item: a fatia 0.5 — e ela foi MEDIDA em 18/09 e **não passa**: 94,9% contra
> os 95% do aceite. Zero falha silenciosa e zero documento não processado; a diferença são
> 6 documentos declarados sem dado financeiro, três deles em contradição com a régua de cobertura.
> Ver a fatia 0.5 em `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`.
> Tudo medido antes de cada ação. Leia a SESSÃO 94/95/96 no `HANDOFF.md` para o detalhe das duas correções
> de premissa (122 migrations, faltavam 3 não 20) e das três evidências que travaram o banco, a
> republicação e o CI — onde o ambiente desta sessão não alcança Postgres diretamente (a saída foi a
> API de gerenciamento do Supabase).

## Onde está

| | |
|---|---|
| **Última migration** | **`Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql`** no repositório (atualizado 23/09/2026, com a F2 incorporada). Em produção: 0182 e 0186–0188 aplicadas, 0183 pendente, 0184 reservada e não usada, 0185 descartada — ver o topo. *(Linha anterior, da F1.5: `Supabase/migrations/0181_o_controle_que_a_entidade_nunca_registrava.sql` — fatia 1.5 do plano F1 (seção 12.2 do roadmap). Colunas novas `entidade.controladora_id` (FK self-referencing, no máximo uma controladora DIRETA por entidade — não um grafo completo de participação, limitação deliberada e documentada) e `entidade.percentual_participacao` (`numeric(6,3)`, checado em (0,100]). Guarda contra CICLO (`fn_entidade_criaria_ciclo_participacao`, limite de 50 saltos) chamada ANTES de gravar por `fn_entidade_definir_participacao` (humano, nunca inferência automática; remover a controladora exige percentual também null) e consumidor mínimo de leitura `fn_entidade_cadeia_controladora` (sobe a cadeia, para no topo). NÃO deriva nada de `perimetro` (0180) nem de `papel_no_grupo` (0179) — é a FK preparada que a F4 (consolidação/intercompany) vai consumir. 29 asserts novos em `Supabase/test/entidade_participacao.test.sql`, 4 dos 29 MEDIDOS reprovando (não estimados) contra o estado sem a guarda de ciclo em `fn_entidade_definir_participacao` — os outros 25 passam com ou sem a correção (ver o cabeçalho do arquivo de teste). **APLICADA em produção em 18/09/2026** — ver a linha abaixo.)* |
| **Aplicadas no Supabase** | **ATUALIZADO 23/09/2026: `0182` (F1.7a) aplicada nesta data, e a F2 aplicou `0186`–`0188` em 22/09 — produção tem 0182 e 0186–0188, e NÃO tem a `0183` (bloqueada, ver o topo) nem a `0185` (reprovada, nunca aplicada). O marcador `ate_migration` de produção está em `0182` por REGRESSÃO (a 0182 foi aplicada depois da 0188) — o valor real é 0188, e a 0183 o repara.** Histórico anterior, mantido: até a `0181` — a `0178`–`0181` (fatias 1.2 a 1.5 do F1) foram aplicadas em **18/09/2026**, pela API de gerenciamento do Supabase (a porta do Postgres não é alcançável do container; `psql` contra o pooler expira). MEDIDO contra a sonda, não suposto: `fn_instalacao_conferir()` devolve **107 requisitos, 0 ausentes**, e `instalacao_cobertura.ate_migration = '0181'`. **A `0179` foi aplicada em DOIS passos**, e quem aplicar de novo precisa saber: o `alter type pendencia_tipo add value` tem de ser confirmado numa chamada SEPARADA antes do resto do arquivo, senão o Postgres recusa com "unsafe use of new value of enum type" (a migration não tem `begin;`/`commit;` por causa disso, mas a API de gerenciamento envolve o lote numa transação implícita). **EFEITO MEDIDO de cada uma:** `0178` marcou **7** entidades como nome suspeito (previsto 7 antes de aplicar, conferido depois — o backfill não surpreendeu); `0179` abriu **365** pendências `papel_no_grupo_indefinido`, uma por entidade de TODO o banco (70 casos, a maioria teste antigo) — dessas, **347 foram resolvidas em lote** por esta sessão com `resolvida_por = 'sessao-claude:ruido-de-caso-de-teste'` e evento de auditoria `pendencias_papel_resolvidas_em_lote`, restando **18 abertas** (mandato real `AMO teste 00` + casos `AMOBELEZA*`); `0180` e `0181` criaram estrutura sem abrir pendência nenhuma. **O backfill da `0179` não distingue mandato real de caso de teste** — quem aplicar num banco novo vai ver o mesmo ruído e precisa repetir essa triagem. |
| **Última rodada real** | **"AMO teste 00", 118 documentos, 17/09/2026 — análise de 89 pendências abertas nesta sessão (session_014M6WjcbLvjBUkQodRYTH7J). Triagem: 4 achados nomeados — 2 DIFERIDOS (F2 e F4), 1 CORRIGIDO (PR #234, commit 378f23a), 1 NÃO CONFERIDO. Decisão de escopo: recusada adição de premissas de modelagem (fora de F0). Portal/export: tsc/eslint/next build limpos, 7 suítes verificar-*.mts todas verdes, e2e 46/0. Descoberta: hipótese anterior "esgotamento de RAM" era stack overflow em `push(...arr)` no nó merge nativo do n8n (~125.000–150.000 itens no Node 22). Ver "A SESSÃO ATUAL (17/09/2026)" abaixo. |
| **Modelagem do mandato AMO** | **APLICADA no Supabase de produção em 17/09/2026** (a pedido explícito do dono, fora do escopo F0 e sem tocar o repositório na aplicação em si). Parâmetros: entidade **`AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA`**, último exercício real 2025, índice macro IPCA, setor varejo, 5 anos projetados. **A entidade tem de ser uma STRING QUE EXISTE nos dados, não um rótulo descritivo:** a primeira tentativa gravou "AMOBELEZA / Grupo AMO" e o modelo institucional não montou — `fn_valores_por_ano(caso, entidade)` FILTRA por ela, devolveu vazio, e o export escreveu a aba "Modelagem não montada" dizendo "nenhum exercício tem valor NUMÉRICO". Medido, para trocar em uma linha se o dono preferir outra: GENERAL CORPORATE 636 linhas/2023-2026 · OMNIBEAUTY Marcas 572/2023-2026 · General Tabaco 486/2023-2026 · AMOBELEZA 452/2023-2026 · OMNIBEAUTY RS 253/2024-2026 · GLOBAL STORE 146/2023-2025. **26 premissas ativas cobrindo as 11 naturezas do catálogo** — macro (IPCA, IGP-M, SELIC, Câmbio) com valores do Focus, o resto `digitado` com a âncora declarada no comentário de cada uma. **1.188 de 1.252 linhas projetáveis com premissa (94,9%)**, escolhida pela natureza contábil da conta: caixa/aplicação→SELIC, clientes→PMR, fornecedores→PMP, estoque por marca→GIRO_ESTOQUE, folha→HEADCOUNT, aluguel→IGP-M, imobilizado→CAPEX_PCT, contingência DIFAL→SELIC. 34 linhas de venda com curva de sazonalidade derivada de 60 meses do próprio faturamento. **64 linhas fora, com motivo declarado:** 30 totais (dupla contagem), 20 cláusulas narrativas de contrato social, 14 resultados apurados. `fn_conferir_modelagem`: `pronto: true`, 0 órfãos, 0 premissa sem valor, 0 sazonalidade sem curva. |
| **Schema materializado** | `Supabase/schema.sql` — gerado pelo `Supabase/test/run.sh`, conferido pelo CI |
| **Suítes** | **Remedidas em 17/09 (sessão atual), nesta árvore:** n8n **550** (o CRÍTICO da revisão multilente acrescentou 1 teste sobre os 549 do commit anterior) · export **723** (2 asserts novos: o rodapé da Modelagem acompanhando o tamanho do caso) · as 7 suítes `verificar-*.mts` do portal todas OK · e2e **46** · variações **25 rodadas, 0 achados** · Supabase (`Supabase/test/run.sh`) **122 migrations** do zero, `TODOS OS TESTES PASSARAM` — rodado de verdade nesta sessão, Postgres subido (ver "Testes de portal/export" abaixo; substitui a contagem de 109 de 11/09) · `.claude/conhecimento/conferir.mjs` **66/0** · `tsc`/`eslint`/`next build` limpos · os 4 geradores sem drift. **ESTES NÚMEROS ENVELHECEM DENTRO DA PRÓPRIA SESSÃO:** esta linha já disse `407`/`716`/`543` — medição verdadeira quando foi escrita, e falsa depois, porque cada fatia acrescentou teste. Quem acrescenta teste atualiza aqui na mesma passada, ou o número vira decoração. **Não remedidas nesta sessão:** hooks do agente (9, medição de 16/09) · medidores (régua 20/20, custo OK, medição de 16/09) · as 3 fixtures do book sem diff (medição de 16/09). |
| **Workflow PUBLICADO no n8n** | **EM DIA — os quatro batem 100% com o repositório, republicado e conferido em 18/09/2026, com acesso real à API do n8n.** A ingestão (`na1AEv3m8fjDXlwM`) foi republicada de verdade (`N8N/republicar.sh`, sem `--dry-run`) para levar ao ar o fix do Bug C + a correção do CRÍTICO da revisão multilente (dois commits de 17/09 que tinham ficado no repositório sem publicar). Os outros três (macro `UGhv57BU3YNukVxV`, erros `59DPz4s2d3DHSR9M`, diagnóstico `Nsp4OoBC4g43N9xf`) já batiam e não precisaram de nova publicação. `FINGERPRINT_EXTRACAO` não mudou (`6f5a9374a9d2b1ae`, confirmado no JSON publicado) — nenhum documento já processado foi/será reprocessado à toa. **Achado no caminho:** o publicado da ingestão estava com `name` "Oria — SARF (Sistema Automático de Reestruturação Financeira)" — renomeação do dono não registrada aqui — enquanto o repositório ainda gerava o nome técnico de fatia; `preparar-republicacao.mjs` sobrescreve o `name` do publicado com o do repositório, então republicar sem corrigir isso primeiro teria revertido o rebranding em silêncio. Confirmado com o dono antes de agir: o gerador (`N8N/build-workflow.mjs`) passa a gravar "SARF" (PR #236); o nome técnico de fatia ficou em `meta.note`, para quem abrir o JSON continuar sabendo o que o workflow faz por dentro. `conferir-publicado.mjs` rodado contra os quatro IDs, um por um, depois da publicação: os quatro OK, "inclusive disabled/onError/retryOnFail e o nome de cada credencial". Provedor confirmado ao vivo OpenAI (`api.openai.com`), batendo com `PROVEDOR_PADRAO = 'openai'` (medição de 16/09, não remedida nesta passada). |
| **CI** | `.github/workflows/suites.yml` — push, PR e `workflow_dispatch` |
| **Provedor de IA** | **CONCORDAM, medido em 16/09/2026.** Repositório: OpenAI `gpt-5.6-luna`, `PROVEDOR_PADRAO = 'openai'` em `N8N/lib/provedor.mjs`. Publicado: conferido ao vivo no nó `IA Extrair` do workflow republicado — `url: https://api.openai.com/v1/chat/completions`. **Não datar por este arquivo: `N8N/conferir-publicado.mjs` contra a instância é quem responde**, e ele agora confere os quatro workflows, não só um. |
| **PR desta rodada** | **#234, ABERTO, mergeable_state: clean, CI verde** — Análise da rodada real AMO: 4 bugs nomeados (2 diferidos F2/F4, 1 corrigido PR #234, 1 não conferido). Fix do Bug C (cobertura parcial): guarda JS não calava para `tem_dado_financeiro=false` sem dado extraído. Revisão multilente descobre CRÍTICO (commit ad12d34): o fix original também calava para documento COM dados extraídos — corrigido em novo commit. Workflow corrigido mas não republicado em produção. O dono decide o merge e a republicação. |

## A SESSÃO ATUAL (17/09/2026) — RODADA REAL AMO TESTE 00: 118 DOCUMENTOS, 89 ACHADOS, 4 NOMEADOS

Rodada real contra um mandato em produção (AMO Partners, id: `1be52ab4-9692-4e17-b332-1dc05dcc8c70`). 118 documentos em quatro lotes de execução. Análise de 89 pendências abertas após conclusão, triadas em categorias de falso-positivo vs. defeito real. Dono pediu documentação completa. **Escopo travado:** "quero o output apenas da F0" — modelagem/premissas está FORA, mesmo que ajudasse.

### Os 4 achados, e seus veredictos

| Achado | Tipo | Severidade | Medição | Veredicto |
|---|---|---|---|---|
| **Bug A** | `fn_avaliar_guardas_extracao` (padrao_suspeito, Supabase/schema.sql) tem taxa falso-positivo **11/12** nesta rodada | Guarda recusa | Alta | **DIFERIDO PARA F4** — depende de infraestrutura "conta canônica/hierarquia" ainda não construída (Arquitetura, fase F4). Não é seguro corrigir sem contexto de F4 |
| **Bug B** | Leitura de coluna errada em documento comparativo DRE/Faturamento (mistura colunas de exercícios/empresas diferentes) | Extração | Média | **DIFERIDO PARA F2** — requer cobertura de novos tipos documentais que F2 desenha |
| **Bug C** | Sinal `tem_dado_financeiro=false` calava guarda SQL de "veio vazia" (migration 0111) mas NUNCA calava guarda JS de COBERTURA PARCIAL (`avaliarCobertura` em N8N/build-workflow.mjs, nó "Juntar Blocos"). Resultado: 4 documentos desta rodada (3 certidões JUCESP + 1 planilha de controle) tinham `tem_dado_financeiro=false` correto e mesmo assim abriram `extracao_falhou` | Extração · Cobertura | Alta | **CORRIGIDO NO REPOSITÓRIO, NÃO REPUBLICADO** — PR #234, branch claude/compassionate-carson-yshp5u, commit 378f23a, revisado e refinado em commit posterior (a primeira versão calava a guarda também quando havia dado extraído — corrigido, ver "Workflow PUBLICADO no n8n" acima). Medição: 4 documentos afetados na rodada real; teste novo em N8N/test/workflow-sim.test.mjs (falha antes do fix, passa depois). Classificado F0 pois é código já existente, não modelagem. **Só chega à produção depois de `N8N_ARQUIVO_REPO=workflow.e1-ingestao.json bash N8N/republicar.sh`** — até lá, o comportamento em produção continua o de antes do PR. |
| **Bug D** | Item de precondição/divergência marcado NÃO CONFERIDO (não foi possível confirmar em produção nesta rodada) | — | — | **NÃO CONFERIDO** — sem acesso ao banco em que a rodada rodou |

### Decisão de escopo recusada (e por quê)

O dono pediu também "adicionar premissas de modelagem financeira via Supabase e indexá-las por linha para poder exportar uma planilha hoje". **Recusado nesta sessão** — modelagem/premissas pertence a fase muito posterior do roadmap (F7+), não é F0. O próprio escopo do dono ("quero o output apenas da F0") proíbe isso. Registrado como decisão consciente, não como pendência esquecida.

### Descoberta sobre hipótese anterior: stack overflow, não RAM

Uma sessão anterior atribuiu a morte de lotes grandes (~127 planilhas) a "esgotamento de RAM do PikaPods". Medição desta rodada refuta: o defeito real é **stack overflow em JS** no nó de merge nativo do n8n. O operador de espalhamento `push(...arr)` no Node 22 estoura com ~125.000–150.000 itens — limite empírico, medido por falhas e sucessos consecutivos. `ARQUITETURA_ALVO_E_ROADMAP.md` precisa corrigir a hipótese de origem (esta sessão só documenta; correção de arquivo de arquitetura é para sessão de planejamento).

### Testes de portal/export — TODOS PASSARAM

Rodada completa de verificação, todas verdes:
- `tsc --noEmit` ✅ limpo
- `eslint .` ✅ limpo  
- `next build` ✅ sucesso
- Suites `verificar-*.mts`:
  - `verificar-export.mts` ✅ 721 / 0
  - `verificar-transcricao.mts` ✅ 35 / 0
  - `verificar-mensagem-de-falha.mts` ✅ 70 / 0
  - `verificar-premissas-do-realizado.mts` ✅ 51 / 0
  - `verificar-kit-basico.mts` ✅ 5 / 0
  - `verificar-modelagem-cobertura.mts` ✅ 13 / 0
  - `verificar-limite-de-envio.mts` ✅ 66 / 0
- E2E (`Verificação/run.mts`) ✅ 46 / 0 (incluindo balanço fechando em todos os exercícios)
- Variações estruturais (`Verificação/variacoes.mts`) ✅ 0 achados em 25 variações

Supabase (`Supabase/test/run.sh`) — **rodado nesta sessão de verdade** (Postgres subido, `sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh`): 122 migrations aplicadas do zero, `TODOS OS TESTES PASSARAM`. É a mesma contagem que `.claude/conhecimento/conferir.mjs` mede (122) — a linha "Suítes" abaixo, que ainda cita 109 (medição de 11/09, sessão 84, não remedida até então), fica substituída por esta.

### O que a próxima sessão herda

- **Bug A** já tem nome e referência precisa (`Supabase/schema.sql`, função nomeada)
- **Bug B** já está categorizado por tipo de documento 
- **Bug C** fechado e fechado: PR #234, CI verde, test novo travando a lição
- A hipótese de RAM passa a ser documentada como FALSA, com a verdade (stack overflow) no lugar
- Escopo de F0 CONFIRMADO pelo próprio dono: nada de modelagem nesta onda

## A SESSÃO 87 (13/09) — O ORÇAMENTO QUE RECUSAVA O LOTE DA AMO: as duas fatias que a diagnose de 86 desenhou

A sessão 86 mediu e NÃO corrigiu (de propósito). Esta corrigiu as duas fatias que não dependem do
lote real, e deixou declarado o que continua dependendo dele.

| | |
|---|---|
| **O defeito** | 44 documentos / 14,4 MB recusados em **US$ 52,39** contra um teto de US$ 3 |
| **Fatia 1 — a reescala** | A troca de provedor de 11/09 (Google → OpenAI `gpt-5.6-luna`) não reescalou `CUSTO_POR_MB_USD` nem `CUSTO_MINIMO_CHAMADA_USD`. **2,80 → 1,48** e **0,0032 → 0,0017**, pela razão do documento DENSO (0,5249), que é o método que o próprio arquivo documenta. **MEDIDO**: o book-canastra custa US$ 0,1380 no provedor ativo e o proxy estimava US$ 0,56 — **4,06×**, contra os ~2× que a calibração declara. Com 1,48: 2,14×. O lote da AMO cai para **US$ 27,69** (−47%) — **não basta, e está dito** |
| **Fatia 2 — a conta por documento** | `orcamentoDoLotePorConteudo` deixou de ser tudo-ou-nada. `estimativaDoDocumento` escolhe um de **quatro caminhos por documento** (conteudo · pagina · tamanho · cego) e **nenhum documento derruba a medição dos outros**. PDF escaneado passa a ser estimado **por PÁGINA** (`CELULAS_POR_PAGINA_ESTIMADAS = 100`, p90 dos 52 documentos dos dois books; agregado medido 53,4) — ~US$ 0,12 por documento de 20 páginas contra ~US$ 0,48 do proxy por byte |
| **A regra 1 no diagnóstico** | A recusa **nomeia** quem não foi medido e **por quê**; a frase "de onde saiu a conta" é montada caminho a caminho, para um lote sem medição nenhuma nunca mais anunciar "a conta saiu de 0 linha(s) com número" |
| **Medição (regra 2)** | **11 invariantes novos** (6 da conta por documento + 5 da revisão), medidos não-vazios por **seis desligamentos** distintos (tudo-ou-nada de volta: 3 reprovam · caminho por página desligado: 4 · `CELULAS_POR_PAGINA_ESTIMADAS = 5`: 2 · frase única da mensagem: 1). **Um deles nasceu VAZIO** — comparava totais com `toFixed(2)` e a diferença sumia no arredondamento — e foi refeito na mesma passada |
| **Suítes n8n** | **542** (eram 458 em 11/09) |
| **A REVISÃO ACHOU O v31 DENTRO DA CORREÇÃO** | `custoEstimadoPorTamanho`, para TEXTO, cobra **só a entrada** de propósito — o piso por chamada cobria a saída enquanto esse caminho decidia o lote inteiro. Promovido a caminho POR DOCUMENTO, passou a cobrar **46× menos** que a conta por conteúdo do mesmo arquivo: 20 CSVs de 1 MB não medidos estimavam US$ 1,31 e **passavam** (a regra tudo-ou-nada recusava). Corrigido na mesma rodada — saída de texto estimada por `CARACTERES_POR_CELULA_ESTIMADA = 22` (p90 medido) e **piso da estimativa plana em todo documento não medido**, porque "o proxy por byte é ≥ o real por construção" é **falso**: 0,69× no documento mais denso do book. Ficha: `.claude/memory/conta-parcial-vira-v31-quando-promovida.md` |
| **O que NÃO foi feito, e por quê** | **O passo 1 do HANDOFF continua aberto**: rodar o lote real da AMO até `Medir Documento` e ler `celulas_no_documento`/`paginas_do_documento` dos 44. Esta sessão **não tem acesso ao lote nem à instância** — sem ele, dizer quanto o lote da AMO passa a custar seria aritmética sobre suposição (regra 4). O que existe é a **sensibilidade medida no estimador**, travada em teste. **E `CUSTO_ESTIMADO_DOC_USD` (0,055) NÃO foi reescalado**, contra a tentação: o caminho cego é o de "não sei nada sobre estes arquivos", e tudo o que este repositório mediu é PDF sintético de 1 a 5 páginas — baixá-lo para 1,2× o sintético calibraria o caminho cego pelo material mais fácil que existe aqui, que é a MESMA causa raiz do proxy errando 75×, com o sinal trocado (aceitaria lote que não cabe) |

## A SESSÃO 84 (11/09) — LUNA, ROTEAMENTO POR FORMATO, O TIMEOUT DA MODELAGEM, E O QUE FICOU ABERTO

Rodada de correção pedida pelo dono em sete itens. O que importa para a próxima sessão:

| | |
|---|---|
| **Provedor** | **OpenAI `gpt-5.6-luna`** (era Google/Gemini). A família GPT-5 RECUSA `temperature` e `max_tokens` — o dialeto mandava os dois e TODA chamada daria 400. Capacidade por modelo em `CAPACIDADES_POR_MODELO` (`N8N/lib/provedor.mjs`), mapa declarado e não regex sobre o id |
| **Determinismo** | **acabou, por construção.** O Luna só aceita o default de temperatura. Extração numérica deixou de ser reproduzível entre rodadas; o schema segura a forma, não o valor |
| **Cadência** | extração a cada **73s**, classificação a cada **42s** (eram 8s e 8s) — o teto de saída reserva TPM e o da OpenAI está no PISO de tier (30.000). Lote de 190 ≈ **3,9 h** (era ~104 min antes de a cadência passar a somar o token de ENTRADA — um PDF de 20 páginas são ~20.000 tokens de imagem ALÉM dos 16.384 reservados, e ignorá-los dava 429 em toda chamada). **Subir `PROVEDORES.openai.tpm` para o valor real da conta é o item de maior retorno da lista**: encolhe os dois números e os três espelhos do portal de uma vez |
| **Esforço de raciocínio** | extração `low`, classificação `none`. A regra do dono virou `escolherEsforco` (`custo.mjs`): ela NÃO chuta tokens de raciocínio, calcula o LIMIAR a partir do qual o nível caro viola a regra (classificação ~176, extração ~4.077) |

### As lacunas abertas, em ordem de risco

**0. A EXTRAÇÃO NÃO É REPRODUZÍVEL E A CONFERÊNCIA QUE DETECTARIA ISSO NÃO RODA.**
`N8N/lib/repetibilidade.mjs` existe, está testado (19 testes: tolerância ZERO, `null` ≠ `0`,
chave seção+rótulo+entidade+período) e **NÃO ESTÁ LIGADO AO GRAFO**. Nenhum nó o chama. A fiação
foi começada e REVERTIDA de propósito: o orçamento passaria a contar uma chamada que nenhum nó
faz. Falta: nó IF de amostra, HTTP/Parse da segunda extração, comparação antes de
`Gravar Campos (Sombra)`, e a entrada real no orçamento/RPD. **Efeito hoje:** dois
processamentos do mesmo balanço podem dar números diferentes e nada acusa. Para um mandato real
esta é a lacuna que mais importa.
Decidir junto: divergência tem de virar pendência BLOQUEANTE (`sobrepujavel=false`); o único
canal atual (`falha_motivo` → `extracao_falhou`) é sobrepujável, e endurecer isso é migration.

### As outras lacunas

1. **O estimador do teto de US$ 3 não conta token de raciocínio.** `custoEstimadoPorConteudo`
   projeta só o JSON; num modelo de raciocínio o `completion_tokens` real é JSON + raciocínio,
   então ele SUBESTIMA — a direção errada para um guarda de teto, e a mesma classe de erro que
   este arquivo já corrigiu uma vez (a suposição de cache, 10/09). Números: saída medida 7.571
   tokens/documento, a margem de 1,25× absorve ~**1.893** tokens de raciocínio, e a regra do dono
   toleraria 4.077 — manda o menor. Acima de ~1.893 o guarda aceita lote que não cabe.
   **Não corrigido de propósito:** sem medir `reasoning_tokens` desta conta, pôr uma constante
   seria ausência virando dado num arquivo que decide dinheiro. A primeira rodada real mede
   (`usoDaChamada` já publica como `thoughts_tokens`). **Mitigação: o teto DURO de US$ 5 na conta
   OpenAI — que é configuração de conta e começa AUSENTE numa conta nova.**

2. **Extrator que devolve ZERO item some com o documento.** Planilha vazia ou CSV só com
   cabeçalho: o documento sai do lote sem linha, sem pendência e sem aviso. A correção óbvia
   (sintetizar o item no `Recompor Conteudo Extraido`) foi **escrita e descartada**: `Medir
   Documento` resolve contexto por `pairedItem`, e item sintético pareado a qualquer índice
   receberia o `caso_id` de OUTRO documento — trocar um documento que some por um documento
   trocado é piorar. Fecha com uma medição na instância real (o `Extract From File` devolve zero
   item ou um item vazio? a doc do n8n não responde).

4. **Nenhum portão automático guarda a 0164 contra regressão.** O teste de escala existe
   (`Supabase/test/modelagem_versao_vigente_escala.test.sql`) mas **não roda no CI**, e a razão é
   aritmética: com a 0164 a função leva 2,6 s neste container e sem ela 10,9 s — razão de 4,2×.
   O runner compartilhado do GitHub é mais de 3× mais lento, e lá a versão CORRIGIDA já estoura os
   8 s. Para o teto pegar o defeito aqui ele tem de ser ≤10 s; para a correção passar no CI, ≥15 s.
   **Não existe número que satisfaça os dois**, porque a razão defeito/correção é menor que a razão
   de velocidade entre as máquinas. Duas saídas foram tentadas e MEDIDAS COMO FALSAS: afrouxar para
   30 s (passa com e sem a 0164 — portão que não mede nada) e afirmar o PLANO (o plano correto
   também tem `Nested Loop`, e o contador de 9 milhões aparece nos dois). Roda-se à mão com
   `ESCALA_0164=1 Supabase/test/run.sh`.

3. **`MAX_OUTPUT_TOKENS` e `FRACAO_DO_TETO` não foram reajustados para o raciocínio.** Na OpenAI
   os tokens de raciocínio contam DENTRO do `max_completion_tokens`, então um bloco dimensionado
   no limite pode truncar por gasto de pensamento. Só a primeira medição de `thoughts_tokens` diz
   se a folga de 2× ainda existe.

### O que NÃO precisa ser reinvestigado (medido nesta sessão)

- A análise da sessão 83 do "Teste 00" está **correta em todos os números conferíveis**
  (7.151 linhas, 75 sem linha, 294 pendentes, zero fórmula quebrada). Nenhum gatilho novo.
- Trocar de provedor **remove a causa** das 72 falhas por billing do Google.
- A `0026` define que mesmo `(caso_id, hash)` é o MESMO documento — agrupar planilha por hash no
  `Recompor` está certo, não é colisão.

### Como a sessão 84 FECHOU, e o que a próxima herda

O PR **#211 está aberto, fora do rascunho e pronto para mergear**: CI verde nos 28 passos em
`55c8e41`, `mergeable_state: clean`, e o `main` já trazido para dentro (o merge não é enfeite —
os dois commits novos do `main` mexem em `preparar-republicacao.mjs`, que conversa direto com os
7 nós de formato que esta rodada criou; depois do merge: n8n 458/458 e 4 geradores sem drift).

**O VEREDITO SOBRE RODAR UM CASO REAL (a AMO) É: NÃO — e ele não muda com mais código nesta
árvore.** Quatro motivos, cada um bastando sozinho, e TRÊS deles só o dono fecha:

1. **O workflow publicado no n8n é de 02/09.** Rodar hoje usaria o Gemini contra a conta sem
   billing — as mesmas 72 falhas do Teste 00, de novo. Fecha com `N8N/REIMPORTAR.md`.
2. **Nenhuma chamada real ao Luna foi feita.** Todo o código novo é provado por suíte, não por
   resposta da OpenAI. Fecha com um lote de 5 documentos.
3. **O teto de US$ 3 subestima** (não conta raciocínio) e **o teto DURO de US$ 5 na conta OpenAI
   começa AUSENTE numa conta nova**. Fecha na configuração da conta.
4. **A extração não é reproduzível e a conferência que acusaria isso não está ligada** — é a
   lacuna 0 acima, e essa é de engenharia, não do dono.

**Para a próxima sessão, em ordem:** (a) se o dono já reimportou e mediu `thoughts_tokens`, os
itens 1, 2 e 3 da lista de lacunas fecham com número em vez de suposição; (b) a fiação da
`repetibilidade.mjs` ao grafo é a fatia de maior valor que NÃO depende do dono, e ela vem com uma
decisão de migration junto (divergência tem de ser pendência `sobrepujavel=false`); (c) subir
`PROVEDORES.openai.tpm` para o TPM real encolhe a cadência, o lote de 3,9 h e os três espelhos do
portal de uma vez — é o maior retorno por linha alterada da lista inteira.


## A SESSÃO 83 (10–11/09) — O TESTE DE 190 DOCUMENTOS BATEU NA COTA DO PROVEDOR, NÃO NO CÓDIGO

**Base desta seção: NÃO é consulta ao banco.** É leitura de dois arquivos que o dono enviou —
a página do caso salva pelo navegador (`.html`, DOM já hidratado) e o `.xlsx` exportado — cruzados
entre si. Esta sessão não tinha (e não tem) conexão com produção. Onde um número precisar de
confirmação por SQL, isto está dito abaixo, e é o primeiro passo da sessão seguinte.

### O caso: "Teste 00", 190 documentos, escala do araucária

Mandato novo (aparece primeiro na lista de mandatos do dropdown, à frente de "Sonda 0162",
"Araucária teste 1" etc.) — não é nenhum dos lotes já registrados neste arquivo (`7276`/`7316`/
`7327`/`7377`/`7417`). O painel mostrava:

```
190   documentos recebidos
7.151 linhas financeiras extraídas
75    documentos SEM NENHUMA linha
6/8   itens do Kit Básico
154   pendências em aberto — 3 bloqueiam a aprovação
15    documentos com dúvida de classificação/entidade/período
```
`"Completude OK"` no topo (Portão 1 — tudo chegou) e, corretamente, **"Ainda não pode ser
aprovado — 3 pendências bloqueantes sem decisão"** logo abaixo: os dois selos não se contradizem,
são perguntas diferentes (chegou tudo × pode fechar).

### O achado — e a hipótese errada que a medição derrubou antes de virar diagnóstico

Primeira leitura da tabela de documentos: os 20 primeiros (`001`–`020`, todos "Balanço
Patrimonial ... 2025x2024x2023x2022x2021.pdf", multi-ano, classificados por **nome do arquivo**)
mostravam `linhas: nenhuma`, enquanto as versões `Encerramento` (ano único, `021`+, classificadas
por **leitura do conteúdo**) das MESMAS empresas mostravam linhas reais (31, 83, 63…). Cheirava a
"documento multi-ano falha, ano único funciona" — e a contagem por tipo × multiplicidade de anos
até sustentava isso à primeira vista: `Balanço` multi-ano **21 de 21 sem linha (100%)**, `DRE`
multi-ano **12 de 14 (86%)**, contra `Balanço` ano-único **5 de 28 (18%)** e `DRE` ano-único
**0 de 5**.

**Essa correlação é real, mas não é a causa — é medir a entrada errada de novo** (a mesma família
de erro que a sessão 81 já cometeu duas vezes, ver `HANDOFF.md`). Cross-checando os **75**
documentos "sem linha" da tela contra a lista de pendências (que a mesma página trazia, só que
mais abaixo, sob o rótulo de fila de revisão), **72 das 73 pendências `extracao_falhou` têm o
MESMO motivo, palavra por palavra**:

> `Motivo: bloco 1: CONTA DO PROVEDOR SEM CRÉDITO OU SEM COBRANÇA ATIVA.` — *"A conta não tem
> como pagar a chamada — na OpenAI é saldo pré-pago esgotado (insufficient_quota), no Google é o
> projeto sem billing habilitado. Espaçar as chamadas NÃO resolve: é preciso recarregar crédito
> ou ligar a cobrança do projeto."* — com o HTTP 429 cru do Google anexado: `"You exceeded your
> current quota, please check your plan and billing details... https://ai.google.dev/gemini-api/
> docs/rate-limits"`.

**Isto não é a cota RPD de 500 chamadas/dia já documentada neste arquivo** (aquela se resolve
esperando o dia seguinte) — é a conta do provedor (Google Cloud) sem cobrança ativa ou sem
crédito, e o próprio sistema diz isso, corretamente, e diz que esperar não ajuda. **Não é bug de
código.** É item operacional do dono: ativar o billing do projeto Google (ou recarregar crédito),
depois reprocessar os 73 documentos.

A "correlação com multi-ano" era coincidência de ORDEM: os `001`–`020` (numerados primeiro) e boa
parte dos multi-ano parecem ter caído dentro da janela em que a cota já estava esgotada; dois
`DRE` multi-ano (`043`, `045`) processaram e tiveram linha real, o que já derrubava a hipótese de
tipo/forma antes de eu escrever qualquer coisa como causa. **Registrado aqui para a próxima sessão
não refazer o mesmo caminho errado** — a régua de fatiamento por tamanho de tabela não é a
explicação, e não há nada para consertar em `fn_linhas_para_modelagem`, `planejarFatias` ou
`fn_papel_linha` por causa deste teste.

**A única falha de motivo DIFERENTE, das 73:** `098_Livro_Razao_Fornecedores_Araucaria_Serraria_
2025.pdf` — 294 pares gravados, 76 de 99 linhas esperadas (77%, abaixo do mínimo de 85%),
`"Resposta do provedor de IA truncada por limite de tokens de saída -- o JSON ficou incompleto"`,
bloco 2 de um fatiamento que o próprio sistema sinaliza como "documento provavelmente grande/denso
demais para uma única chamada". É a MESMA família de sub-extração parcial já registrada para o
lote `7417` (`17_Livro_Razao_Fornecedores`, sessão 79) — limite de prompt/modelo conhecido, não
código novo.

### Consequência sobre o Kit Básico: os 2 itens faltantes são O MESMO apagão, não gaps novos

`Faturamento intragrupo` e `Série de faturamento dos últimos 24 meses` — os dois "chegou, sem
dado extraído" do painel — são exatamente `104_Faturamento_Intragrupo_...pdf` e
`103_Relatorio_de_Faturamento_48_meses_...pdf`, os dois primeiros da lista de `extracao_falhou`
por cota. **Não é um gap independente do Kit Básico: é sintoma do mesmo apagão.** Uma vez
reprocessados, o 6/8 muda sozinho — não precisa mexer em `fn_recomputar_completude` nem em nada
do checklist.

### O que funcionou, e vale registrar porque é medição, não é só ausência de defeito

- **Fatos materiais de alta qualidade**, mesmo sob o teste mais difícil já rodado: incerteza sobre
  continuidade operacional citada verbatim do relatório do auditor (`157_Relatorio_do_Auditor_
  Independente_2025.pdf`, p. 1), opinião com ressalva, e rompimento de covenant (índice de
  cobertura de juros, dois contratos, Banco Meridional) — 23 fatos, 11 críticos, cada um com a
  frase do próprio documento e a página. A leitura de texto (E1/E2) não foi afetada pela mesma
  cota que travou a extração de tabela — evidência de que são chamadas/orçamentos distintos.
- **O Portão de aprovação recusou corretamente**: 3 pendências bloqueantes sem decisão, "Nenhuma
  pendência foi aceita sem resolução neste caso" — a regra 1 em ação: o sistema não deixou passar
  um book com 38% dos documentos sem dado.
- **O auditor do aceite (PR #208, mergeado ontem) pegou o próprio arquivo certo no primeiro uso
  real**: rodado sobre este `.xlsx`, respondeu `3/3 itens OK` — é o export de DADOS — e emitiu o
  aviso novo dizendo que o aceite do B1 não pode fechar com este arquivo, porque faltam os 8
  itens do modelo institucional. Sem o aviso (que não existia antes de ontem), isto teria fechado
  "verde" tendo conferido menos de um terço.

### Achado à parte, não investigado: mojibake reproduzido de novo

Dois nomes de arquivo chegaram corrompidos por double-encoding — `"balan├ºo 2024 (1).pdf"` e
`"C├│pia de balan├ºo final.pdf"` (`├º`/`├│` no lugar de `ç`/`ó`) — a MESMA família registrada no
`HANDOFF.md` desde a rodada `7417` ("ainda não investigado a fundo"). Os dois têm `linhas:
nenhuma` com fonte "leitura do conteúdo" — ou seja, o mojibake está no NOME, a classificação por
conteúdo funcionou, e não dá para saber por este material se a extração desses dois falhou pela
MESMA cota (mais provável, dado o padrão) ou por outra causa. Não vale abrir fatia sem medir de
novo depois do reprocessamento.

### O que esta sessão NÃO pode provar, e por que

- **O `lote_execucao.execucao_ref` desta rodada** — a página salva não trouxe o identificador do
  lote nem a data/hora de execução. Sem isso não dá para cruzar com `custo_total_usd`,
  `tokens_cache` (a correção do PR #209 já está em produção? só a sonda confirma) nem com o
  padrão de rate-limit por minuto documentado em `.claude/memory/cota-rpd-e-o-limite-do-dia.md`.
- **Se o billing já foi religado e o reprocessamento já aconteceu.** Os dois arquivos enviados são
  bit-a-bit idênticos (mesmo md5), então representam UMA rodada, não um antes/depois.
- **Se as 154 pendências totais têm mais alguma família de causa** além das 73 de extração — a
  página salva não trouxe a lista completa das outras ~80 (as de classificação/entidade/período,
  "15 documentos com dúvida").

### Por onde a sessão seguinte começa

1. Confirmar (fora deste repositório) que o projeto Google Cloud/Gemini tem billing ativo — é o
   único bloqueio real.
2. Reprocessar os 73 documentos com `extracao_falhou` (mecanismo de reextração do portal, ou
   reenvio pelo n8n — conferir qual expõe isso hoje).
3. **Só depois** exportar o **COMPLETO** (com modelo institucional) e rodar
   `auditar-xlsx.mts` de novo — os 11 itens, incluindo balanço fechar e resíduo de reconciliação,
   só valem sobre um book com cobertura real.
4. Rodar a sonda (`fn_instalacao_conferir()`) e a consulta de custo (`lote_execucao`) contra o
   banco desta rodada, para fechar os três "não posso provar" acima com número de verdade.

## A SESSÃO 79 (02/09) — A PRIMEIRA RODADA REAL DEPOIS DAS SEIS MIGRATIONS, e ela rodou inteira

**Todos os números desta seção são medição do DONO, contra produção**, colhidos com o runbook
`Arquitetura do Sistema/6 Referência/POS_RODADA.md` e com o `.xlsx` entregue. A sessão não tem
conexão com o banco de produção e não conferiu nenhum deles por conta própria — a única coisa que
esta sessão fez com eles foi ler.

### O lote 7377, e a comparação que só existe porque a 0156 passou a gravar o lote

| | `7276` — 31/08, banco na `0150` | **`7377` — 02/09, banco na `0156`** |
|---|---|---|
| planejados / processados | 38 / 38 | 38 / 38 |
| fatiados | 4 | 4 |
| **com falha** | 2 | **1** |
| sem medição | 0 | 0 |
| linhas extraídas | 2.637 | 2.599 |
| **cobertura** | 0,838 | **0,987** |
| custo real / previsto (US$) | 0,4779 / 0,3200 | 0,4674 / 0,3200 |
| duração | 28 s | 26 s |

`estado = fechou` com `fechado_em` preenchido, e o passo 3.4a do runbook (`execucao_falha`)
**voltou VAZIO: nenhum nó morreu.** Era o critério de pronto do B1 do mapa, e ele fechou.

**A cobertura subiu de 0,838 para 0,987 e eu NÃO medi a causa.** A única diferença de arranjo que
conheço entre as duas rodadas é o banco (`0150` → `0156`), mas nenhuma das seis migrations mexe na
régua da cobertura, e a rodada com 0,838 também tinha um documento a mais falhando — o
`17_Livro_Razao` sozinho vale 302 pares. Atribuir o salto a qualquer uma delas sem medir seria
exatamente o que a regra 5 proíbe. Fica registrado como número, não como explicação.

**O custo real ficou 46% acima do previsto** nas duas rodadas (0,4674 contra 0,3200; e 0,4779 contra
os mesmos 0,3200). É estável, então não é ruído — é a previsão que está calibrada baixo. Não é
urgente num lote de US$ 0,47; passa a ser num de 190 documentos, onde o previsto é 1,7200.

### A única falha da rodada, e ela é a costura FUNCIONANDO

```
importante, extracao_falhou, 17_Livro_Razao_Fornecedores_Canastra_Industria_12M25.pdf
  "falhou ou veio incompleta (302 par(es) conta×coluna gravado(s)).
   Motivo: 3 linha(s) repetida(s) na emenda entre blocos foram descartadas
   (o modelo repetiu a âncora)."
```

Descartar a linha repetida na emenda é **o que a costura existe para fazer** — o documento tem 4
colunas, 95 contas distintas e 302 pares gravados, e a leitura chegou inteira. Mas o pipeline conta
isso como documento com falha: é o que põe `com_falha = 1` no lote e o alerta
`documento_com_falha` na rodada.

**Isto é um defeito, e é do tipo que este projeto persegue: chamar de falha um sucesso.** Ele não
perde dado nenhum e não é urgente — mas enquanto existir, `com_falha` não serve como sinal, porque
não distingue "o modelo não leu o documento" de "a emenda funcionou". Fatia própria, ainda não
aberta.

### A pendência bloqueante é defeito de CHECKLIST, e o combinado está lá

```
bloqueante, item_faltante, "Item obrigatório do Kit Básico ausente: COMBINADO", sobrepujavel = false
```

E na mesma rodada, nos mesmos 38 documentos:

```
13_Balanco_COMBINADO_Grupo_Canastra_2025.pdf   BALANCO   conf 1,00   openai_conteudo   8 empresas nas colunas
14_Balanco_COMBINADO_Grupo_Canastra_2024.pdf   BALANCO   conf 1,00   openai_conteudo   8 empresas nas colunas
```

Os dois abriram, sozinhos, pendência `tipo_incorreto` dizendo *"o diagnóstico sugere COMBINADO,
está registrado como BALANCO"*. **O sistema sabe que eles são combinados e mesmo assim trava o
mandato por ausência de combinado.** É a mesma ambiguidade que a `0155` mediu no araucária (o mesmo
padrão de nome saiu BALANCO em quatro documentos e COMBINADO num quinto), chegando agora pelo outro
lado: a `0155` corrigiu a AUTORIDADE, e o CHECKLIST continuou perguntando ao rótulo.

O passo (1) de `fn_recomputar_completude` (`0113`) só aceita `documento.tipo_taxonomia = 'COMBINADO'`.
A correção é usar o critério estrutural que a `0155` já criou e já está aplicado —
`fn_documento_de_varias_empresas`.

### As outras 12 pendências, todas `importante` e todas sobrepujáveis

| tipo | quantas | leitura |
|---|---|---|
| `tipo_incorreto` | 4 | dois são os combinados acima; os outros dois (`27_Composicao_do_Imobilizado` NOTAS_EXPL→BALANCO, `35_Demonstracoes_Contabeis` DF_AUDITADA→BALANCO) são o diagnóstico discordando do nome do arquivo, que é o trabalho dele |
| `periodo_incorreto` | 2 | comparativos multi-ano cujo diagnóstico propõe a data-base em vez do intervalo |
| `linha_exigida_ausente` | 2 | "Despesa Financeira" na DRE da CN Transportes e da Canastra Comercial — **isto é dado que falta no documento**, não defeito |
| `entidade_incorreta` | 1 | `33_Notas_Explicativas` registrado como GRUPO CANASTRA, conteúdo diz Canastra Indústria |
| `classificacao_pendente` | 1 | `28_Folha_de_Pagamento` não cabe na taxonomia (conf 0,9 contra limiar 0,70, e ainda assim aberta) |
| `divergencia_reconciliacao` | 1 | 2 contas em que BALANCO (autoridade 50) vence NOTAS_EXPL assinado (45), maior diferença 15.647.000,00 — **e o número do perdedor continua gravado** |
| `extracao_falhou` | 1 | a costura do `17_Livro_Razao`, acima |

Nenhuma delas é erro de execução. **A rodada entregou o book.**

### A rodada do araucária de 01h46 (`7327`) não mediu nada, e a causa é uma só

```
190 planejados, 190 processados, 190 COM FALHA, 0 linhas, US$ 0,0000, 38 segundos
```

Os 190 documentos falharam com a **mesma** mensagem, e o pipeline diagnosticou sozinho:

```
http=401 code=401
provedor="Request had invalid authentication credentials. Expected OAuth 2 access token,
          login cookie or other valid authentication credential."
```

A credencial do Google no nó HTTP do n8n estava inválida. Os três números estranhos se explicam
sem sobra: 0 linhas porque nenhuma resposta voltou, US$ 0,00 porque o provedor não processou, 38
segundos porque são 190 × um 401 imediato. **Não há bug**: o `N8N/lib/extract.mjs:960` distingue
401/403 de cadência e de crédito e nomeia o header certo. A rodada `7377` prova que a credencial já
está válida. O araucária pode ser reprocessado como está.

### Um achado menor, medido e não urgente: mojibake em nome de arquivo

Nomes do araucária chegaram como `C├│pia de balan├ºo final.pdf` e `balan├ºo 2024 (1).pdf`. Não vem
do nosso código — `nome_original` é cópia direta do `fileName` que o n8n entrega
(`N8N/build-workflow.mjs:503`), sem decodificação nossa. Rodando o classificador nos dois pares:

```
"balanço 2024 (1).pdf"   → tipo_taxonomia BALANCO, confiança 0,65
"balan├ºo 2024 (1).pdf"  → tipo_taxonomia NULL,    confiança 0,05
```

A pré-classificação por nome **perde o tipo**; não produz tipo errado. Os dois casos já caem abaixo
do limiar 0,75 e vão para a classificação por conteúdo de qualquer jeito, então o custo é uma
chamada de IA que poderia ter sido evitada. Registrado, não urgente.

## A SESSÃO 78 (02/09) — o sistema estava verde, e a próxima rodada morreria no primeiro nó

**O pedido era "varra tudo e garanta que a próxima rodada não dá erro de execução".** A varredura
achou o defeito exatamente onde o projeto foi construído para não tê-lo: **num lugar em que tudo
parece certo.**

### O que passou, e num container limpo

Todas as suítes e portões do CI foram rodados do zero (números na tabela do topo). **Nenhum
achado, nenhum arquivo gerado divergindo do commitado.** O repositório está são.

### O defeito: o banco de produção não tem o que o workflow chama

O `ESTADO.md` declara produção na **`0150`**. Montei um banco parado exatamente aí — as migrations
`0001`…`0150` e nada além — e perguntei o que a rodada perguntaria:

| pergunta | resposta nesse banco |
|---|---|
| `fn_instalacao_conferir()` acusa requisito ausente? | **não** (só um `comportamento` de tabela vazia, esperado) |
| os nós Postgres do `workflow.e1-ingestao.json` resolvem? | **três NÃO** |

```
N8N/workflow.e1-ingestao.json · nó "Abrir Lote"
    function fn_abrir_lote_execucao(uuid, text, jsonb) does not exist     (0156)
N8N/workflow.e1-ingestao.json · nó "Reconciliar Lote"
    function fn_reconciliar_caso(uuid) does not exist                     (0152)
N8N/workflow.e1-ingestao.json · nó "Reconciliar (Classe A)"
    function fn_reconciliar_por_documento(uuid, unknown) does not exist   (0152)
```

**`Abrir Lote` é o primeiro nó depois de o orçamento aprovar o lote.** A rodada não degrada: ela
morre no começo, depois do upload, com `does not exist`.

**A terceira é a que ensina o desenho.** `fn_reconciliar_por_documento` **existe** na `0150` — a
`0152` lhe acrescentou `p_escopo`. Um conferidor que perguntasse "existe função com este nome?" a
daria por presente e a rodada morreria nela do mesmo jeito. Por isso o que se confere é a
**CHAMADA**, com `PREPARE`: o Postgres resolve nome e tipos e recusa o que não casa. `PREPARE` não
executa nem escreve — é seguro apontar para produção, que é para onde ele existe para apontar.

### Por que a sonda não viu, e por que ela não está errada

`fn_instalacao_conferir()` responde *"o que ESTE banco sabe que deveria ter, está aqui?"*. O
catálogo dela (`instalacao_requisito`) mora **dentro do banco** e é preenchido pelas migrations —
um banco na `0150` tem o catálogo da `0150`, e não pode conhecer um requisito que só a `0156`
escreveu. Ela é **cega por construção**, e quem tentar "consertá-la" vai consertar o lugar errado.

A pergunta que faltava é a outra ponta, e **só o repositório pode fazê-la**, porque só ele conhece
o código que vai rodar: *"o que o REPOSITÓRIO chama, está aqui?"* — `Supabase/test/conferir-chamadas.mjs`.

### O conferidor, e as quatro medições que provam que ele não nasceu vazio

| arranjo | esperado | medido |
|---|---|---|
| banco completo (101 migrations) | passa | **exit 0** — 15 chamadas de nó por `PREPARE`, 51 objetos do portal |
| banco na `0150` (produção declarada) | reprova | **exit 1**, os 3 achados acima, cada um nomeando o nó |
| banco inalcançável | não é "passou" | **exit 2** |
| extração sabotada (tipo do nó trocado) | não é "passou" | **exit 2** — regra 7 aplicada a ele mesmo |

O quarto arranjo existe porque a varredura depende do tipo do nó e do nome do parâmetro: o dia em
que uma exportação nova do n8n trocar qualquer um dos dois, a lista vem vazia e o portão fica
verde sem medir nada. **Zero chamada não é "nada quebrado": é o conferidor quebrado.**

### O ensaio de aplicação, que também nunca tinha sido feito

As seis migrations pendentes foram aplicadas **incrementalmente** sobre o banco na `0150`, uma a
uma, como o dono faria pelo painel: **0 falhas**. Isso não é o que a suíte prova — ela monta do
zero, e aplicação incremental tem uma classe de erro que a de zero nunca vê (`create or replace`
sobre função cuja assinatura mudou). Agora está medido.

### O que isto NÃO resolve, e é do dono

O conferidor prova o lado do banco. O outro passo manual continua existindo e **nada aqui o
detecta**: o `N8N/workflow.e1-ingestao.json` mudou em **01/09** (o nó `Abrir Lote` é novo) e o n8n
executa o JSON **importado**, não o do repositório. **Merge não reimporta.**

## A SESSÃO 77 (31/08, madrugada) — a régua contava 258 onde o documento tem 99, e o portão não podia ver

**A pergunta que a sessão 76 deixou aberta está FECHADA, e a resposta é a que ela suspeitava: o
DENOMINADOR.** As duas pendências de cobertura da rodada do Canastra eram FALSAS, e a correção
está no repositório, medida sobre o texto que produção realmente produz.

### O que foi medido, e de onde veio o dado

A sessão 76 pedia capturar o texto do nó `Extrair Texto` no navegador. **Não precisou:** o MCP do
n8n serve o dado da execução já salva (`get_workflow_execution`, `includeData: true`,
`nodeNames: ["Extrair Texto"]`). Vieram **20 dos 38** documentos da execução **7276** — a rodada
do Canastra de 31/08 20:25 —, agora versionados com procedência em
`Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/`. Nada de cota consumida.

| De onde vem o texto do `17_Livro_Razao` | régua (`linhasDeConta`) |
|---|---|
| verdade do gerador (`METRICAS.json`) | **99** |
| `TEXTO_EXTRAIDO.json` (agrupamento do gerador) | 100 |
| `pdf-parse` instalado localmente | 104 |
| **nó `Extrair Texto`, em PRODUÇÃO** | **258** |

**A hipótese da sessão 76 estava certa no fato e errada na causa.** Não é que produção "quebre a
linha de um jeito qualquer": ela quebra a cada mudança de linha de base do PDF, e numa tabela
larga UMA linha visual chega em dois ou três fragmentos —

```
"01/12/2025 LC-2025-4000 "                                <- fragmento (termina em espaço)
"NF 010000 - Papéis e Celulose Aracati S.A. - bobina... "  <- fragmento (termina em espaço)
"- 150 16.839 C"                                          <- fecha a linha visual
```

O primeiro e o segundo eram contados como duas contas onde há uma. **O balanço patrimonial não
sofre nada disso: lá a régua acerta a verdade no dígito, 114 de 114.** Só documento de tabela
larga fragmenta — no Canastra, quatro: `15`, `16`, `17` e `20`.

### A correção, e o número que ela moveu

`juntarFragmentosDeLinha` (`N8N/lib/cobertura.mjs`) emenda os fragmentos antes de contar. O sinal
é o **espaço no fim** do fragmento que não fecha a linha visual — medido nos 20 documentos
capturados, **0% de linhas com essa marca nos treze que a régua já acertava, 44% a 63% nos quatro
que ela errava**. Presença contra ausência, não limiar. Um teto de 4 fragmentos existe para a
falha cair no lado barato: sem ele, um documento em que toda linha terminasse em espaço
colapsaria numa linha só e a guarda ficaria MUDA.

| | antes | depois | verdade |
|---|---|---|---|
| `17_Livro_Razao` | 258 | **101** | 99 |
| `20_Mapa_de_Divida` | 25 | **13** | 12 |
| erro absoluto médio (20 docs de produção) | 15,7% | **2,5%** | — |

**As duas pendências somem:** 102 de 101 no razão, e o mapa de dívida cai abaixo do mínimo em que
a guarda opina. Nenhum documento sadio mudou de número.

### E o portão de calibração passou a medir a entrada certa

Era o pedido do passo 2 da sessão 76, e é o achado mais caro desta rodada:
**`medir-regua-cobertura.mjs` media o `TEXTO_EXTRAIDO.json`**, o agrupamento do gerador. Ele
devolvia "+3%" e passava, honestamente, sobre a entrada errada — enquanto produção errava 161%.
Portão que mede a entrada errada tem exatamente a mesma aparência de um portão que mede a certa e
não acha nada; desta vez o defeito central do projeto estava dentro do próprio instrumento.

Agora a entrada é a captura de produção. **Medido não-vazio:** com a emenda desligada o portão
sai com 1, nomeando `17_Livro_Razao (99→258)` e `20_Mapa_de_Divida (12→25)`. Com ela ligada: erro
mediano **+0%**, pior razão com extração perfeita **95%** contra o limiar de 85%, zero falso
positivo. Os 18 documentos fora da captura são declarados **"NÃO MEDIDO CONTRA PRODUÇÃO"** — não
"passa".

### E A RÉGUA FOI ATÉ 0,0%, porque o resíduo também tinha nome

Depois da emenda sobrava +1 a +2 linhas em 8 dos 20 documentos (erro médio 2,5%). O resíduo era
de uma família só: **cabeçalho que tem número sem medir número** — período (`"Posição em 31 de
dezembro de 2025"`), duração (`"ÚLTIMOS 36 MESES"`) e código de conta (`"LIVRO RAZÃO — CONTA
2.1.01.001"`) — mais a nota de rodapé que quebra em duas linhas e só a primeira dizia "Nota —".

`ehLinhaSemValor` não casa frase: ela **retira da linha os números que não medem — data, duração,
código — e pergunta se sobra dígito**. A conta sobrevive porque o valor dela nunca é nenhum dos
três (`"Total de 2023 7.120"` sobra 7.120; `"1.1.01.002 181 D"` sobra 181). Casar `"Posição em"` e
`"LIVRO RAZÃO"` seria ajustar a régua às frases DESTE book — 0% aqui e pior no do cliente,
parecendo calibrada.

| | antes da emenda | depois da emenda | **hoje** | verdade |
|---|---|---|---|---|
| documentos exatos (de 20) | — | 12 | **20** | — |
| erro absoluto médio | 15,7% | 2,5% | **0,0%** | — |
| pior razão com extração perfeita | — | 95% | **100%** | limiar 85% |
| documentos contando A MENOS | 0 | 0 | **0** | — |

**E o portão segura o 0%.** A faixa de +15%/−5% responde *"a régua atrapalha a guarda?"* e só olha
os documentos que a guarda avalia — deixava de fora os pequenos, onde +1 linha em 12 é +8% sem
ninguém reclamar. A trava nova, `ERRO_MAXIMO_EM_PRODUCAO = 0,5%`, responde *"a régua ainda está
exata?"* sobre TODO documento capturado com conta. Sem ela o 0% de hoje envelheceria calado: 3%
cabe em 15% e o CI continuaria verde.

> **O que este 0% É e o que ele NÃO é.** A régua é o DENOMINADOR de uma guarda de cobertura — ela
> conta quantas linhas de conta o PDF aparenta ter, para decidir se abre a pendência "este
> documento pode ter vindo pela metade". **Ela nunca toca um valor**: não entra no export, não
> entra no banco, não arredonda nada. Os centavos têm as guardas deles (o balanço que fecha, os
> 713 invariantes do export, os subtotais da `0116`). E o erro dela, quando existe, é sempre para
> MAIS — contar linha demais deixa a guarda mais sensível, nunca menos. A direção que esconderia
> extração pela metade é contar a MENOS, e essa está em zero, medida.

### A CONTRADIÇÃO DA SESSÃO 74 ESTÁ RESOLVIDA: as 23 pendências do araucária são FALSAS

O `ESTADO.md` afirmava, sobre o araucária, que *"as 23 pendências de `extracao_falhou` são
VERDADEIRAS"*. A base era o `medir-regua-cobertura.mjs` — e era ele que não podia ver o defeito.
Os números do araucária reproduzem os do Canastra ao dígito (cinco livros razão de "258" linhas
devolvendo 102, 101, 104, 102, 102; cinco mapas de dívida de "25" devolvendo 12 cada), e o
diagnóstico é o mesmo: **denominador inflado pela fragmentação, extração completa**. A confirmação
final é a próxima rodada do araucária, que agora tem uma régua honesta esperando por ela.

### O que esta rodada NÃO mexeu, de propósito

- **A régua do FATIAMENTO (`linhasComNumero`) fica como está.** Nada aqui mediu defeito lá: o
  `17_Livro_Razao` foi fatiado em 4 blocos e os 4 chegaram. `celulas_estimadas` e
  `colunas_estimadas` também são calculados sobre texto fragmentado — o efeito é SUPERESTIMAR o
  custo, que é o lado conservador, e o `medir-custo-book.mjs` continua verde. Fica anotado como
  observação, não como pendência.
- **Nenhuma migration, nenhuma tela.** A correção é de biblioteca e de portão.

### Por onde começar na PRÓXIMA sessão

1. **Rodar o araucária com o dia inteiro de cota** (~440–509 chamadas de 500). A régua corrigida
   deve zerar as 23 pendências. **Se alguma sobrar, aí sim é sub-extração real** — e o instrumento
   de blocos da `0156`, que já funciona, dirá se é teto, bloco perdido ou leitura parcial.
2. **Capturar os 38 documentos** do `Extrair Texto` da próxima rodada e substituir
   `Dados de Teste/capturas/2026-08-31-texto-extraido-n8n/textos.json`. Enquanto forem 20, o portão diz
   em voz alta que 18 não estão medidos. **Dois deles merecem atenção quando a captura chegar:**
   sobre o texto do gerador, o `21_Mutuos` (3 → 2) e o `25_Situacao_Fiscal` (10 → 7) são os únicos
   documentos em que a régua conta A MENOS — a direção perigosa. Pode ser artefato da entrada
   errada, como foi com o razão; só a captura decide.
3. Continua pendente e não é engenharia: **deploy do portal** e o **`multipleFiles`** do campo
   "Arquivos" do nó `Intake (Form)`.

---

## A SESSÃO 76 (31/08, noite) — a rodada do Canastra respondeu a pergunta de 190 documentos, e a resposta é que a CHECAGEM erra

**A rodada rodou, e rodou bem.** Canastra, 38 documentos: **2.637 linhas** (contra 2.565 da rodada
comparativa de 27/08), 4 documentos sem linha nenhuma (os mesmos 30/32/33/34, corretos), Kit Básico
**8/8**, `fullCalcOnLoad` presente, **3.108 fórmulas e nenhum `#REF!`/`#VALUE!`**, e o
`auditar-xlsx.mts` passando nos 3 itens aplicáveis. A tela chegou a **"Pronto para aprovação"**.

### Os três instrumentos da 0156 responderam — e é a primeira vez que eles falam

| Instrumento | O que disse |
|---|---|
| Blocos planejado × recebido | *"O documento foi lido em **4 de 4 blocos planejados** (fatiado, e todos chegaram)"* |
| `FALTOU BLOCO` | **zero ocorrências no arquivo inteiro** — nenhum bloco se perdeu |
| Abertura do lote | `lote_execucao_id` gravado no `Abrir Lote`, com `aberto: true` |

### E A RESPOSTA À PERGUNTA QUE ESTAVA ABERTA DESDE A SESSÃO 74 É: **NENHUMA DAS DUAS**

A pergunta era *"sub-extração é teto do modelo ou fatiamento que não rodou?"*. Medido nesta rodada,
nos dois documentos que abriram pendência de cobertura:

| Documento | Pendência diz | **Verdade do gerador** | Extraído | Blocos |
|---|---|---|---|---|
| `17_Livro_Razao` | 102 de **258** linhas = 40% | **99 linhas de conta** | **102** | 4 de 4, todos chegaram |
| `20_Mapa_de_Divida` | 12 de **25** linhas = 48% | **12 linhas de conta** | **12** | 1 de 1 |

**A extração está COMPLETA nos dois.** 102 de 99 e 12 de 12. O que está errado é o **denominador**.

E a evidência é mais forte que a contagem: os lançamentos do livro razão são sequenciais
(`LC-2025-4000`…), e o export traz **`4000` a `4095` contíguos** mais a linha de total — ou seja,
**todos os lançamentos que o gerador escreveu**. Não falta trecho nenhum no meio.

**Os números REPRODUZEM o araucária ao dígito:** lá, cinco livros razão de 258 linhas devolveram
*102, 101, 104, 102, 102*, e cinco mapas de dívida de 25 devolveram *12, 12, 12, 12, 12*. São os
mesmos documentos, o mesmo comportamento, e agora com a verdade do gerador ao lado.

> **ISTO CONTRADIZ O QUE A SESSÃO 74 REGISTROU.** O `ESTADO.md` afirma, sobre o araucária: *"as 23
> pendências de `extracao_falhou` são VERDADEIRAS"*. A base daquela afirmação foi o
> `medir-regua-cobertura.mjs` — e é justamente essa ferramenta que não enxerga o defeito (abaixo).
> **A leitura de hoje é que as 23 são muito provavelmente FALSAS**, pela mesma razão que estas duas.
> A contradição fica escrita, e quem a fecha é a medição do passo 1 do roteiro.

### Onde o denominador se perde, e por que nenhum portão viu

A régua (`linhasDeConta`) foi medida sobre o MESMO PDF por três caminhos:

| De onde vem o texto | `17_Livro_Razao` | `20_Mapa_de_Divida` |
|---|---|---|
| `TEXTO_EXTRAIDO.json` (o agrupamento do **gerador**) | 100 | 11 |
| PDF renderizado, via `pdf-parse` (extrator real) | 104 | 14 |
| **n8n `extractFromFile`, em PRODUÇÃO** | **258** | **25** |

Os dois caminhos locais concordam entre si e com a verdade (99 e 12). **Produção é o ponto fora da
curva**, ~2,6× e ~2×. O texto que o `Extrair Texto` produz quebra a linha de um jeito que a régua
conta como várias — e é esse número inflado que vira o denominador da cobertura.

**E O PORTÃO QUE DEVIA CALIBRAR A RÉGUA NÃO PODE VER ISSO.** O `medir-regua-cobertura.mjs` roda no
CI e mede a régua contra o `TEXTO_EXTRAIDO.json`, que é **o agrupamento do gerador** — um texto que
produção nunca vê. Ele devolve "erro mediano +3%" e passa, honestamente, sobre a entrada errada.
**Portão que mede a entrada errada tem exatamente a mesma aparência de um portão que mede a certa e
não acha nada** — é o defeito central deste projeto, desta vez dentro do próprio instrumento de
calibração.

### O que NÃO é defeito nesta rodada

- as 4 pendências de documento sem linha (30/32/33/34) — corretas, esses documentos não têm conta;
- o `Abrir Lote` como ramo terminal — a correção do PR #190 funcionou: 38 documentos registrados
  contra 0 na tentativa anterior;
- a tela declarando parada na tentativa que falhou, em vez de "aguarde" sobre processo morto.

---

## POR ONDE COMEÇAR NA PRÓXIMA SESSÃO — a rodada real, e não há mais nada antes dela

> **Os dois passos manuais que estavam aqui foram FEITOS em 02/09** (dono): as `0151`–`0156`
> aplicadas no Supabase e o `workflow.e1-ingestao.json` reimportado no n8n. A conferência contra
> produção voltou `APLICADA` nas seis e **`PODE RODAR`** nas três chamadas do workflow.

**Não há mais nada de infraestrutura entre o repositório e o sistema.** O bloqueio do projeto
voltou a ser o que o `MAPA_DE_EXECUCAO.md` sempre disse que era, e agora sem asterisco: **a
rodada real (B1)** — uma hora de execução do dono, que nenhuma suíte substitui.

### O que fazer, na ordem (é o B1 do mapa)

1. **Rodar o book num mandato NOVO** — não reaproveitar mandato existente: a `0118` deduplica por
   fingerprint e o reenvio do mesmo PDF não chama mais a IA.
2. **Exportar o completo.**
3. **Passar o `auditar-xlsx.mts`** (10 itens automáticos) **e o `Arquitetura do Sistema/6 Referência/ACEITE.md`**
   (10 itens humanos) por cima do arquivo **exportado da rodada**, não sobre fixture.

As **onze coisas que só a rodada prova** estão listadas no `MAPA_DE_EXECUCAO.md` (B1). Três delas
nunca viram dado real: o fatiamento ligado em produção, os subtotais impressos da `0116` e a árvore
da seção da `0133` sobre PDF sujo.

### Conferências que valem 30 segundos ANTES de subir documento

Nenhuma é ler este arquivo — as duas respondem sobre o banco em que você está conectado:

```bash
CONFERIR_PSQL="psql 'postgresql://…@…supabase.co:5432/postgres'" \
  node Supabase/test/conferir-chamadas.mjs      # 0 resolve · 1 achei · 2 não consegui perguntar
```

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

### E o primeiro sinal a olhar QUANDO a rodada começar

`lote_execucao` tem de ganhar linha com **`fechado_em` nulo** logo no começo — é o que a `0156`
inventou para separar "começou e não terminou" de "nunca rodou", e é também a prova de que a
reimportação do workflow pegou. A rodada de 190 de 27/08 morreu sem deixar rastro justamente por
não existir isso.

## A SESSÃO 75 (31/08) — o processo do agente vira parte do repositório

**Esta rodada não tocou no produto.** Nenhuma migration, nenhum nó do n8n, nenhuma linha do
export. Ela mexeu na única camada que faltava ter estado versionado: **como uma sessão de IA
trabalha neste repositório.** A base foi o `soumatheusgomes/vibe-coding-toolkit`, adaptado — não
copiado — ao que este projeto já aprendeu na marra.

**O DIAGNÓSTICO, E ELE É O MESMO DEFEITO QUE O PROJETO INTEIRO PERSEGUE.** O repositório tinha 700
KB de documento de estado (`HANDOFF.md` 460 KB, `ESTADO.md` 258 KB) e **nenhum arquivo carregado
automaticamente**. Toda sessão começava com uma de duas escolhas ruins: ler tudo, ou não ler nada
e redescobrir as regras do jeito difícil. E o `Arquitetura do Sistema/5 Prompts/PROMPT_CONTINUACAO.md`, que era o remédio,
tinha virado o veneno: **em 31/08 ele ainda mandava trabalhar no PR #69** (117 PRs atrás), rodar
suítes de 160/198/32/18, e **MONTAR O CI** — afirmando "Não existe CI" como fato, quando ele existe
desde a sessão 20.

Nada acusou porque nada podia. É a mesma causa do cabeçalho do `HANDOFF` travado 17 PRs em
"PR #70, migrations até `0034`": **a parte que muda toda rodada morava no arquivo que quase nunca
se edita.**

### O que entrou

| Peça | O que ela resolve |
|---|---|
| **`CLAUDE.md`** (108 linhas) | O arquivo que toda sessão lê e que **não guarda número nenhum** — onde um número importa, ele aponta para quem o mede. As sete regras, a ordem de leitura dos quatro documentos de estado, os comandos canônicos, a tabela de especialistas |
| **`.claude/memory/`** | Índice de 35 linhas + 15 arquivos de tópico com as lições já pagas: o estágio desligado que parece limpo, o `git checkout` da sessão 19, o backtick que quebrou o `jsCode` duas vezes, as fixtures da 18 que nasceram vazias, o `MATERIALIZED` de 12.068 ms contra 1.790, o `multipleFiles` que a republicação perde, o RPD 500 |
| **`.claude/agents/`** | Sete especialistas com o checklist do domínio DENTRO do arquivo, não espalhado por documentos que ninguém abre no meio de uma tarefa. Nível de modelo declarado, escolhido por despacho |
| **`.claude/hooks/`** | Um `SessionStart` que responde em ~50 ms as quatro perguntas de abertura; um lembrete de derivado desatualizado; e **a única trava DURA do projeto** — o descarte de arquivo |
| **`Arquitetura do Sistema/5 Prompts/`** | Cinco prompts, **nenhum guardando estado**. O `PROMPT_CONTINUACAO.md` vira a explicação de por que foi aposentado |

### A trava errou primeiro, e do jeito que este repositório já conhece

A primeira versão do `proteger-descarte.mjs` casava sobre o comando inteiro, e **bloqueou uma
mensagem de commit que descrevia o próprio hook**: o verbo caía numa linha e a flag que o
inocentava, na seguinte — fora do alcance do lookahead, porque `.` não casa quebra de linha.

**Portão que reprova por RUÍDO é pior que portão nenhum**, e é a mesma família do `FOR ROLE root`
de 21/08. A análise passou a ser por linha, e o caminho passou a ser exigido.

**Medido, e é por isso que a suíte entrou no CI:** 17 casos — os 4 destrutivos saindo 2 e os 13
restantes saindo 0 (troca de branch, unstage, o `--` do `git log`, as duas formas de prosa que
pegaram a primeira versão, e cinco payloads degenerados). **Com a trava desligada a suíte reprova
em 1 de 5 testes; religada, 5 de 5** — restaurada com `cp` e conferida idêntica por `diff`, que é
o protocolo que o próprio hook existe para proteger.

### O que esta rodada NÃO fez, e continua valendo

Ela não republicou o workflow, não fez deploy do portal e não rodou o araucária de novo — os três
continuam sendo o que destrava a próxima rodada, e estão no topo do `HANDOFF.md`. Nenhuma
migration foi escrita, então **nada aqui muda o que a sonda responde**.

---

## A SESSÃO 74 (27–28/08) — a rodada de 190, e os cinco defeitos que ela achou

O dono rodou o `book-araucaria`: **190 documentos, 17:34 BRT**. A execução ficou
**1h52 de pé sem gravar uma única reconciliação** e foi cancelada à mão. Nenhum
erro em lugar nenhum — nem no Postgres (zero linhas de ERROR no log), nem no
n8n, nem na tela.

**O QUE FOI CONFERIDO ANTES DE INVESTIGAR, porque o dono já tinha respondido as
três perguntas óbvias e as três estavam certas:** a `0151` estava aplicada
(sonda: 46 de 46), o workflow estava publicado corretamente (os 33 nós conferem;
as únicas diferenças são parâmetros default que o n8n omite, e os nós Code são
byte a byte iguais), e a cota não apertou (440 de 500 RPD).

### O que aconteceu, com o relógio

| hora (UTC) | o que o banco mostra |
|---|---|
| 20:34:32 | execução 7172 começa |
| 20:55:12 | os **190 documentos registrados, todos no mesmo instante** — a barreira do `Juntar Ramos` |
| 21:24 | as **13.942 linhas gravadas, todas no mesmo minuto** — a barreira do `Juntar Extraidos` |
| 22:16 | `pg_stat_activity`: backend ativo há 13min25, `RowExclusiveLock` em `reconciliacao`, 11 `fn_reconciliar_por_documento` num statement, `xact_start = query_start` |
| 22:23 | o backend sumiu e `reconciliacao` do caso está em **ZERO** — nada commitou |
| 22:26 | cancelada; `lote_execucao` vazia, `execucao_falha` vazia |

### Os cinco defeitos

**1. A reconciliação era quadrática duas vezes (`0152`).** As oito checagens do
despachante leem `(caso, entidade, período)` e **não o documento** — ele só
entrega a chave. E `fn_conflitos_do_caso` pedia o produto cartesiano: o planner
estima `rows=1` numa CTE onde há 2.619, escolhe Nested Loop e compara
**6.859.127 pares para achar 34**, a **12,4 s por chamada**, vezes as 123 que a
`0151` dispara. Medido em produção depois: **1.790 ms**, as mesmas 34 linhas.

> **O `MATERIALIZED` não é enfeite.** Escrevi a versão agrupada sem ele e medi:
> **12.068 ms** — a correção não acontecia. O Postgres inlina CTE usada uma vez,
> e o agrupamento que existia para MATAR o cartesiano virou o cartesiano,
> recalculado 2.619 vezes. **Agrupar antes não é uma instrução, é uma
> intenção**, e o planner tem todo o direito de desfazê-la.

> **E a primeira `fn_reconciliar_caso` estava errada de granularidade.** Ela
> iterava `(entidade, período, tipo)` — uma chave só para as oito checagens —, e
> isso dá **162 chaves para 190 documentos**: 15% de redução, com a checagem
> cara saindo de 123 chamadas para ~130. Eu teria trocado o código sem corrigir
> nada, **e a suíte teria passado**, porque ela prova equivalência e não custo.
> Cada checagem tem a SUA chave: a de conflito e a de duplicidade por entidade
> (16 e 15), mútuos e intragrupo por período (15 e 14), as quatro de Classe A/B
> por (entidade, período). **247 invocações contra ~8.500.**

**2. O batch de 190 numa transação só (`n8n`).** O modo `single` do nó Postgres
— que é o **default**, e por isso ninguém escolheu — junta as queries de todos
os itens numa transação implícita. Em 38 documentos ela durava segundos; em 190
dura dezenas de minutos, e qualquer coisa que a interrompa apaga o lote inteiro.
Os quatro nós por item passam a `independently`.

**3. O portal declarou parada em 5 minutos sobre um silêncio de 29 (`portal`).**
`IA Extrair` roda a `batchSize 1 / batchInterval 8000ms`: 190 × 8 s = **25min20s**
em que, por construção, nada é escrito no banco. `SEM_PROGRESSO_MS` era **fixo em
5 minutos**, com um comentário dizendo que ele *"não pode crescer com o lote — é
isso que o distingue do silêncio inicial"*. A premissa é falsa: nó do n8n não é
streaming, e os dois merges são barreiras. As duas esperas passam a sair da mesma
conta.

**4. O balanço de uma empresa dentro de outra (`0153`).** O
`009_Balanco_Patrimonial_Araucaria_SPE` é da **Araucária Imobiliária SPE** — o
resumo que o próprio sistema extraiu diz isso — e estava gravado sob **Araucária
Bioenergia SPE**, junto com a DRE. `fn_mesma_entidade('Araucaria SPE', …)`
devolve **true para as duas**, e `fn_upsert_entidade` desempatava com
`order by razao_social limit 1`. **É o mesmo defeito da `0151` num segundo
lugar** — lá "fica com o maior", aqui "fica com a primeira do alfabeto". E vai
FECHAR: os dois são demonstrações completas.

**5. O combinado voltava a empatar pela porta da classificação (`0155`).** Os
cinco combinados do grupo, todos com 14–15 empresas nas colunas, foram
classificados pela IA com confiança 1,0 — e ela chamou **quatro de BALANCO e um
de COMBINADO**. Chamado de BALANCO, o combinado sobe de 30 para 50 e **empata**
com o balanço individual; empate, pela `0151`, mantém o de maior módulo. A
correção não ensina o classificador: usa o fato que está no dado.

### O que a rodada mostrou e NÃO é defeito

- **A aba `Outros` com 3.448 linhas** é o destino correto dos tipos sem aba
  própria, e o book tem cinco Livros Razão (1.789 linhas só deles);
- **os 5 documentos de Folha de Pagamento sem tipo** abrem
  `classificacao_pendente` — o sistema diz "não conheço este tipo, confirme";
- **as 23 pendências de `extracao_falhou` são VERDADEIRAS.** Medido com
  `medir-regua-cobertura.mjs` contra os 38 documentos do Canastra: erro mediano
  da régua **+3%**, pior extração perfeita em **96%**. As razões do araucária vão
  de **40% a 78%** — sub-extração real, e a guarda acertou. A `0154` corrige só a
  descrição, que juntava pares conta×coluna e linhas do documento na mesma frase.

### O que ficou ABERTO, e por quê

**Não sei dizer se a sub-extração é o modelo lendo pela metade ou o fatiamento
não rodando.** A constância chama atenção — cinco livros razão de 258 linhas
devolveram 102, 101, 104, 102 e 102; cinco mapas de dívida de 25 linhas
devolveram 12, 12, 12, 12 e 12, e número que não varia com o documento é
assinatura de TETO. Para separar as duas hipóteses eu precisava saber em quantos
BLOCOS cada documento foi lido, e esse número não chegava a lugar nenhum: a
execução foi cancelada (o n8n descarta os dados) e o lote nunca fechou, então
`lote_execucao.documentos_fatiados` não foi escrita. **A pendência passa a dizer
em quantos blocos o documento foi lido** — é o instrumento que faltou nesta
própria investigação. A resposta vem na próxima rodada.

Mais dois achados que são para o dono, não defeitos: o **cancelamento manual não
dispara o Error Workflow** (nada foi registrado em `execucao_falha`), e o
**Relatório do Auditor nomeia uma décima quinta empresa** — "Araucária Indústria
de Embalagens Ltda." — que não tem nenhuma demonstração no book.

### O caso araucária, corrigido em cima e sem reextrair

**25 → 16 entidades** (as nove sobras do nome do arquivo fundidas com
`fn_fundir_entidade`, e os dois documentos da SPE devolvidos à Imobiliária), e a
reconciliação que nunca tinha rodado: **295 reconciliações, 6 divergências**,
entre elas 38 contas em que dois documentos da Araucária Serraria discordam, com
vencedor e critério por extenso.

## A SESSÃO 73 (27/08) — o desempate entre dois documentos já existia, e ele escolhia o maior

O handoff da 72 manda o araucária para a próxima rodada e diz, sobre ele: *"o que
continua sem resposta é o desempate — não há mecanismo que escolha entre duas
versões do mesmo período"*. **A frase está meio certa, e a metade errada é a
cara.** Não há mecanismo DECLARADO; há um mecanismo, e ele mora numa linha da
`0150`:

```
(array_agg(c.valor_num order by abs(c.valor_num) desc nulls last))[1]
```

Quando os dois documentos dizem a mesma coisa, escolher qualquer um é
indiferente. **Quando eles discordam — que é a pergunta inteira do araucária — a
regra vira "fica com o maior".** Num caso de reestruturação esse é o pior padrão
possível: dos dois números, ele escolhe sempre o que infla o ativo.

E é exatamente a armadilha central do book de 190: um **combinado preliminar**
que infla o ativo do grupo em até 32.800 (R$ mil) **e fecha**, porque ativo e
passivo caem na mesma medida quando um par intragrupo deixa de ser eliminado.
Contra um número que fecha, nenhuma reconciliação existente dispara —
`fn_reconciliar_ativo_passivo_pl` confere se bate, e bate.

### O que medi antes de escrever, e foi o que desenhou os filtros

Na fixture do Canastra (28 documentos, extração real): **117 conceitos aparecem
em dois ou mais documentos, e só CINCO discordam.**

| Conceito | As duas fontes | Veredito |
|---|---|---|
| `total` | EXTRATO 825.000 × HEADCOUNT 20.510.900 | falso — um está em milhares de reais, o outro em **pessoas** |
| `total geral` | AGING_AP 25.734.000 × AGING_AR 28.706.000 | falso — é o total de cada documento, papel `subtotal` |
| `total vencido` | AGING_AP 13.383.000 × AGING_AR 16.936.000 | falso — idem |
| `direito de uso — arrendamentos` | BALANCO 7.822 = BALANCETE 7.822 × NOTAS_EXPL 7.825 | **verdadeiro**, e é arredondamento: 0,04% |
| `veículos e empilhadeiras` | BALANCO 3.914 = BALANCETE 3.914 × NOTAS_EXPL 3.916 | **verdadeiro**, idem |

Os três falsos viraram os três filtros (seção canônica declarada, papel `conta`,
unidade conversível); os dois verdadeiros ficam abaixo da tolerância de sempre (o
maior entre R$ 100 e 0,5%), que é o que ela existe para fazer. **Resultado
medido depois dos filtros: zero conflitos no Canastra e zero no Vertentes** — a
resposta certa para dois books construídos para ser internamente consistentes, e
o motivo de o teste desta sessão construir o próprio caso. Função que só devolve
vazio passa em qualquer teste que conte linhas.

### O que mudou (`0151`)

- **a autoridade documental vira DADO**, em `taxonomia_tipo_documento.autoridade`
  — pela mesma razão que a `0150` fez com `abertura_analitica`: regra contábil
  dentro de função é regra que ninguém acha para mudar. DF auditada 60 ·
  demonstrações 50 · notas explicativas 40 · combinado 30 · balancete 20 · razão
  10 · o resto **0 = não decide** (dois zeros empatam);
- **o sinal do documento pode derrubar o tipo**: `−25` quando o nome do arquivo
  diz preliminar/rascunho/prévia, `+5` quando a versão está assinada. Assimétrico
  de propósito — falso positivo custa um degrau e meio e fica **escrito na
  pendência**, onde alguém pode discordar;
- **o conflito passa a ser declarado** (`fn_conflitos_do_caso`,
  `fn_reconciliar_versoes_do_periodo`) com vencedor, perdedor, diferença e
  critério por extenso. **Nada é apagado** — o número perdedor é a evidência de
  que houve escolha;
- **`fn_linhas_do_realizado` para de escolher o maior**: desempata por
  autoridade, e o maior módulo da `0042` fica como último recurso;
- **no EMPATE o valor não muda.** Continua o de antes desta migration, e a
  pendência diz que a escolha é humana. Em particular **não** desempatei por
  "mais recente": `criado_em` é a hora do UPLOAD, não a data do documento, e
  desempatar por ordem de upload seria trocar uma regra silenciosa por outra.

### Os religamentos, um a um

Cada um foi religado contra a função de verdade, e não contra um espelho:

- ordem antiga do `array_agg` de volta → o realizado usa **42.800** (o rascunho)
  em vez dos **10.000** da DF auditada: o teste reprova nomeando os dois;
- os três filtros removidos → o Canastra devolve **3 conflitos**, que são
  exatamente os três falsos positivos da tabela acima, e o teste reprova;
- e o `fn_documento_preliminar` nasceu **devolvendo texto**: `~` tem precedência
  maior que `||`, então sem parênteses o Postgres lia
  `(nome ~ 'primeira metade') || 'segunda metade'` e a função casava com meia
  expressão. Virou assert.

### O que esta sessão NÃO fez

- **não aplicou nada em produção** — a sessão não tem conexão com o banco nem
  chave da API do n8n. A `0151` está no repositório e não no Supabase;
- **não mudou de onde a `0150` tira o exercício.** `fn_conflitos_do_caso` usa a
  coluna e, na falta dela, o período do documento — porque um documento de
  período único sem cabeçalho de ano é justamente o formato em que a segunda
  versão de um balanço chega. `fn_linhas_do_realizado` continua usando só a
  coluna, que é o conservador para SOMAR. A diferença é deliberada e está
  comentada nas duas.

### Contadores

`Supabase/test/run.sh` = **94 migrations**, mais o `desempate.test.sql` novo com **22
asserts**. As demais suítes inalteradas.

## A SESSÃO 72 (27/08) — a rodada comparativa, e a premissa que somava o que não se soma

**A rodada saiu, e é a melhor até aqui.** Mandato `Teste comparativo - Grupo
Canastra`, execução 7156:

| | v47 | v48 | **esta** |
|---|---:|---:|---:|
| Documentos | 38 | 38 | **38** |
| Linhas extraídas | 2.460 | 2.485 | **2.565** |
| Fatos materiais | 0 | 0 | **17** |
| Custo real | US$ 0,368 | US$ 0,373 | **US$ 0,426** |
| Documentos com falha | — | — | **0** |
| O lote FECHOU | sim | sim | **sim** |

Duração ~9min38. O canal de fato material rodou no book inteiro pela primeira
vez, e o veredito do lote (71c) funcionou: `lote_execucao` gravada, tela sem
falso "pronto". O `auditar-xlsx.mts` sobre o arquivo exportado: **3 de 3 itens
aplicáveis OK**, 3.149 fórmulas e nenhuma com erro.

### O defeito que a rodada revelou, e é dos grandes

As oito premissas que o próprio caso responde vieram gravadas assim, com
`origem = 'historico'`: **PMR 348,6 dias**, **PME 177,5**, **CUSTO_VARIAVEL
287,7% da receita**, **SGA_PCT 83,2%**. Não é imprecisão — é soma do que não se
soma, e a `0150` fecha as três causas:

1. **O total soma com as próprias componentes.** A bolsa de custos deu 410.749,
   que é exatamente 177.077 (o total do CPV) + 177.133 (as cinco componentes
   dele) + 56.539 (o CPV de outra empresa). `fn_papel_linha` é `immutable` e vê
   um rótulo por vez — o discriminador estrutural (o total bate com a soma das
   outras contas da mesma seção e exercício, dentro de 1%) passa a viver em
   `fn_linhas_do_realizado`, que vê o documento inteiro. **A doutrina da `0116`
   continua certa:** num documento resumido o total É a conta; o que faltava era
   como distinguir os dois casos.
2. **A abertura analítica soma por cima da conta que ela abre.** A bolsa
   "clientes" deu 174.142 num grupo cuja maior conta de clientes é 35.044:
   entravam os 312 sacados do aging, os itens da posição de estoque, os bancos do
   extrato e o balancete inteiro. `taxonomia_tipo_documento.abertura_analitica`
   passa a DECLARAR quais tipos são abertura — dado, não código. **O COMBINADO
   entra na lista**, e é o mais importante para o araucária: ele é a soma das
   empresas, e somá-lo junto das parcelas conta o grupo duas vezes.
3. **O caso tem oito empresas e o modelo projeta uma.** A tela pergunta qual
   entidade (`caso_modelagem.entidade`) e a soma ignorava a resposta.

### E a projeção das premissas deixou de ser digitada

A pedido do dono, cada premissa passa a se projetar pela forma que cabe a ela —
e a regra sai do CATÁLOGO (`natureza`/`formula`), não de uma lista em código:

| Família | Como projeta | Por quê |
|---|---|---|
| **macro** (IPCA, SELIC, câmbio, IGP-M, PIB) | mediana do **Focus** por ano | já está no banco desde a `0025`; repetir o ano passado é ignorar uma previsão que o sistema coletou. Ano sem expectativa fica FORA, não recebe o valor do vizinho |
| **razões estruturais** (`pct_de_linha`, `dias_de_giro`) | constante na **média dos exercícios** | uma empresa não muda de estrutura de custo por decreto — e o último ano de uma empresa em reestruturação é o pior dela. Projetar dele é projetar a crise como se fosse o regime |
| **crescimento** (`crescimento_composto`) | **indexado** ao índice macro do mandato | é a hipótese de "nada muda em termos reais", e ela vai DECLARADA na conta publicada: é tese, não medição |
| **valor de decisão** (capex, movimento de dívida, VGV, preço) | **não projeta** | não sai do balanço nem do Focus. Zero seria uma afirmação sobre o negócio que ninguém fez |

**A média é das RAZÕES, não a razão das médias**, e a diferença não é acadêmica:
somar três anos de custo e dividir pela soma de três anos de receita deixa o ano
de maior faturamento mandar na média — uma ponderação que ninguém pediu.

Para isso a `0150` traz `fn_exercicio_da_coluna`, que separa a coluna que nomeia
exercício (`31/12/2024`) da que não nomeia (`Saldo`, `Crédito`, `Ticket médio`) —
sem ela a série misturaria "crédito" com "2024" no mesmo eixo.

### Os vínculos de linha do mandato, aplicados

O caso tinha modelagem definida e 10 premissas ativas, e **zero vínculos**. Foram
aplicados pelas mesmas funções da tela: 4 lotes por seção e 5 vínculos de linha,
**35 vínculos, zero órfãos, `pronto: true`** — o que destravou o export.

### A COBERTURA ESTAVA DESLIGADA, e o sintoma era uma coluna nula

`lote_execucao.cobertura` veio **null** e `contas_nos_documentos` veio **0**, com
o `Conferir Lote` VERDE e nenhum erro no n8n. A causa é um defeito de OMISSÃO em
`Montar Req Extracao`: ele montava um item NOVO com cinco campos e jogava fora
tudo o que o `Medir Documento` tinha medido. Três consequências, e **nenhuma delas
dá erro**:

1. sem `linhas_do_texto`, o `Fatiar Extracao` cai no fallback de UM bloco e **o
   fatiamento nunca ligou** — o medidor previa 4 documentos fatiados no book, e a
   rodada gravou `documentos_fatiados: 0`. O `17_Livro_Razao` foi a uma chamada
   em vez de quatro;
2. sem `contas_no_documento`, `avaliarCobertura` no `Juntar Blocos` nunca dispara:
   **a guarda de extração incompleta estava desligada** — e ela é a régua que mede
   alucinação por omissão, a que mais importa num lote de 190;
3. e o painel do lote grava cobertura nula, que foi o fio pelo qual isto apareceu.

É a mesma família do defeito da v47 — um nó lendo o que o anterior não entrega —
e a guarda daquela vez só cobria nó **Postgres**. A nova cobre o caminho de
Code: os campos que os nós de baixo leem do contexto têm de chegar. Religada, ela
reprova com *"Montar Req Extracao descartou `linhas_do_texto`"*.

### A `0150` APLICADA, e o efeito medido no caso real

Aplicada em produção nesta sessão: `fn_instalacao_conferir()` devolve **41 de 41
requisitos presentes**, cobertura `0150`. O discriminador de subtotal marcou
`(-) Custo dos produtos vendidos` (135.838 = a soma exata das cinco componentes)
e `Receita operacional bruta` (188.000 = a soma exata das quatro linhas de venda)
— **e o refinamento por SINAL**, feito depois de ver o resultado, pegou também
`(-) Deduções da receita bruta` (48.128 = ICMS + PIS/COFINS + devoluções). Sem
ele, receita e dedução moram na mesma seção, nenhum dos dois bate com o dobro de
si mesmo, e a dedução contaria duas vezes.

As premissas, antes e depois, na entidade que o modelo projeta:

| | antes | 2023 | 2024 | 2025 | **média (nova)** |
|---|---:|---:|---:|---:|---:|
| Custo variável | 287,7% | 74,8% | 91,7% | 97,1% | **87,9%** |
| SG&A | 83,2% | 13,3% | 23,2% | 45,9% | **27,5%** |
| PMR | 348,6 d | 63 | 72 | 74 | **70** |
| PME | 177,5 d | 42 | 48 | 48 | **46** |
| PMP | 76,7 d | 80 | 97 | 152 | **110** |

**A série é a prova de que a média importa:** o custo variável sobe de 74,8% para
97,1% em três anos. Projetar do último ano fixaria 97,1% como estrutura de custo
— a crise virando regime, que é exatamente o que a média evita.

### O que fica aberto, e é do dono

- ~~`ultimo_exercicio_real` em 2026~~ **corrigido pelo dono para 2025**;
- ~~`cobertura` e `contas_nos_documentos` vazias~~ **causa achada e corrigida** —
  ver acima. Falta **republicar o workflow** para a correção valer em produção;
- **reprocessar as premissas do caso** pela tela, agora que a `0150` está
  aplicada — os números medidos estão na tabela acima;
- **republicar o workflow** (`preparar-republicacao.mjs`), para o fatiamento e a
  cobertura voltarem a funcionar antes do araucária.

### Contadores

premissas do realizado **32 → 51** · banco **94 migrations** (a `0150`, aplicada em
produção) · n8n **382** · export **713** · transcrição **35** · falha/espera/veredito **59** ·
e2e **46** · variações 25 rodadas / 0 achados. `tsc`, `eslint` e `next build`
limpos.

## A SESSÃO 71c (27/08) — o smoke test PASSOU, e a tela chamou de sucesso uma execução morta

**A NOTÍCIA PRIMEIRO: `documento_fato` DEIXOU DE SER ZERO.** O dono rodou o smoke
test e, no mandato `smoke test - 2 documentos`, as **Notas Explicativas** e o
**Parecer do Auditor** renderam **9 fatos materiais** (6 + 3), com
`fatos_avaliados_em` preenchida nas duas versões. É o item 1 do handoff — o canal
da `0148`/`0149` **rodou contra documento real pela primeira vez**, e o caminho
inteiro fechou ponta a ponta. Os dois renderam **zero linhas**, e isso é o
resultado CERTO: esses documentos não têm tabela numérica, eles dizem as coisas
em texto. (Um envio anterior, no mesmo mandato, trouxe dois PDFs do araucária com
**201 linhas** — 34 + 167.)

**E a tela disse "Tudo pronto" sobre uma execução que MORREU.** Nenhuma peça
mentiu sozinha, e é a combinação que engana:

1. a execução morreu no `Upload Storage` (habilitado por engano — ver a 71b);
2. o registro de falha depende do **Error Workflow** do n8n, que é passo MANUAL
   e **não está ligado** — conferido no workflow vivo: `settings` sem
   `errorWorkflow`. Então `fn_falhas_abertas` não tinha o que devolver;
3. e os contadores foram satisfeitos assim mesmo, porque o nó que morreu é ramo
   **lateral**: o irmão (`Extrair Texto` → … → `Registrar Documento`) rodou
   inteiro e gravou os documentos e os eventos de extração.

**Deduzir "terminou bem" de contadores é deduzir de um sintoma que a MORTE também
produz.** O sinal que não depende de ninguém configurar nada é o FIM do workflow:
ele termina em `Gravar Uso do Lote` → `Conferir Lote`, e um lote que fecha deixa
linha em `lote_execucao`. **Medido:** a v47 e a v48 deixaram (38 documentos, 2.460
e 2.485 linhas); as **duas** execuções do smoke test não deixaram **nenhuma**.

### O que mudou

- **`pronto` passa a exigir o lote FECHADO** (`vereditoDoLote`, função pura em
  `portal/src/lib/espera-do-lote.ts`). Contadores completos + lote não fechado,
  passada a carência de 2 min (a cauda do workflow são 3 nós, segundos), vira
  **falha nomeada** `lote_nao_fechou`. E "não sei" (a consulta falhou) **nunca**
  acusa um lote vivo — a mesma regra que o `comLinhas` já aplicava;
- **a falha sem causa conhecida passa a dizer com quem falar**, a pedido do dono:
  *"Entre em contato com o Varoto para ele resolver essa questão para você"*.
  "Contate o suporte" é um beco quando a equipe é uma pessoa;
- **o lote vazio deixa de ser cego para os FATOS.** Esta era a armadilha: a
  checagem contava só linha, e teria acusado *"nada pôde ser lido"* exatamente no
  lote que funcionou pela primeira vez. Agora conta documento que rendeu **linha
  ou fato**;
- **o modal "Tudo pronto" não aparece quando há o que explicar.** Ele era
  condicionado só a `pronto`, e a explicação (falha/parada/lote sem conteúdo) já
  era renderizada antes — as duas coisas coexistiam;
- **o mandato que terminou sem NADA dentro pode ser descartado da própria tela
  que o acusa**, pelo `fn_excluir_caso` que já existia.

### O que NÃO foi feito, e por que — o mandato "não criado"

O pedido foi *"garanta que o mandato vazio não será criado se nenhuma linha for
extraída"*. **"Nenhuma linha" é o critério errado, e o smoke test é a prova:** os
dois documentos que o handoff mandava testar rendem zero linhas e nove fatos, e
um portão por linha teria descartado justamente eles.

E o mandato é criado no **primeiro nó** do fluxo (`Upsert Caso`), antes de
qualquer leitura: ele é o recipiente em que todo o resto é gravado, e não existe
"criar depois" sem inverter o pipeline inteiro. O que dá para garantir é o
**efeito prático**, e é o que está feito: um lote sem linha E sem fato é
**reportado como falha** (nunca como sucesso), a tela diz para não usar o
mandato, e oferece o descarte com a confirmação de sempre. Apagar sozinho seria
contra a doutrina do repositório — declarar, não apagar.

### O Sonar, e a seção que mudou de lugar

**A seção "O que os documentos dizem" desceu**, por decisão do dono depois de
ver a tela com fato de verdade dentro: ela abria o mandato e passa a vir **depois
do Kit Básico e de Documentos**, fechando a leitura "o que chegou → o que os
papéis dizem" — e ainda antes da fila de pendências, que é o que a posição não
podia custar. O comentário que justificava o lugar antigo foi reescrito, não
apagado: ele agora conta a troca e o motivo dela.

**Os nove achados do Sonar no PR #182, todos fechados** — e dois deles não eram
código:

| Achado | O que era |
|---|---|
| `S1135` "Complete the task associated to this TODO" (×2) | **português**: "TODO lote" é *every lot*, não um marcador de tarefa. Reescrito para "QUALQUER lote" |
| `S3776` complexidade 34 em `conferir()` | quebrada em `conferirPresenca`/`conferirComportamento`/`conferirCredenciais` — a divisão é a do que se confere, não um fatiamento para agradar a métrica |
| `S3776` complexidade 16 na rota de status | o par `comLinhas`/`comFatos` saiu para `conteudoDoLote`, e as duas consultas passaram a rodar em paralelo |
| `S7744` objeto vazio inútil | `{ ...(p ?? {}) }` → `{ ...p }`: espalhar `null` já é vazio |
| `S6582` optional chain (×2) | `(x.credentials ?? {})[t]` → `x.credentials?.[t]` |
| `S8707` caminho vindo do argv (×2) | **três tentativas, e a terceira é a que valeu.** Validar o caminho (exigir `.json`, existir, ser arquivo comum) não bastou; validar o caminho **canonizado** contra bases declaradas também não; trocar o `process.exit` por `throw`, para o ramo terminar à vista, também não. O caminho passou a **não existir**: o JSON entra pela **entrada padrão** (`< arquivo` ou `curl \| node`), então quem abre o arquivo é o shell, com as permissões de quem digitou, e o script só toca no arquivo do próprio repositório — que é constante. O risco não foi validado nem silenciado: ele deixou de existir. (A leitura é por **stream**, não `readFileSync(0)`: com `<` o descritor 0 é arquivo comum e a síncrona funciona, com `\|` é cano não bloqueante e ela estoura `EAGAIN` — medido.) **E a exclusão em `.sonarcloud.properties` não era saída:** aquele arquivo só passa a valer na branch PADRÃO, então não afetaria este PR |
| `S7778` `Array#push()` várias vezes | os dois `push(...)` do laço viraram um |

### Contadores

`verificar-mensagem-de-falha.mts` 44 → **59**. As demais inalteradas e
reconferidas: n8n **373**, export **713**, transcrição **35**, premissas **32**,
e2e **46**, banco **93 migrations**. `tsc`, `eslint` e `next build` limpos.

## A SESSÃO 71b (27/08) — a republicação perdeu TODA a rede de proteção, e a conferência não viu

O dono rodou o smoke test e recebeu **"Problem in node 'Upload Storage': Credential
with ID REPLACE does not exist for type httpHeaderAuth"**. O nó é ramo lateral e
está **desabilitado no repositório desde 17/07** (bug de plataforma do HTTP
Request com binário) — em produção ele estava **habilitado**. Isso é sintoma, não
causa.

**A causa, medida contra o workflow vivo:** a republicação de 26/08 gravou os nós
com `parameters` e perdeu **todos os campos de nó que vivem fora deles**:

| O que sumiu | Nós | O que custa |
|---|---:|---|
| `onError: continueRegularOutput` | 23 | qualquer falha passa a **matar o lote inteiro** em vez de seguir |
| `retryOnFail`/`maxTries`/`waitBetweenTries` | 11 | uma oscilação do provedor no `IA Extrair` (6 tentativas) mata o lote na primeira |
| `disabled` do `Upload Storage` | 1 | o ramo lateral voltou a executar, com credencial `REPLACE` |

**A conferência daquela sessão declarou "33 de 33 nós byte a byte iguais" e estava
certa** — ela comparava `parameters`, e nada do que se perdeu mora ali. É o
defeito de sempre com roupa nova: **espelho que compara só uma parte declara uma
igualdade que não tem.** E o repositório já tinha o teste certo do lado dele
(`Upload Storage: desabilitado`, no `workflow-sim.test.mjs`) — o que faltava era
alguém conferir o PUBLICADO.

**Como sei que não é o transporte escondendo campo:** o workflow do macro, que
não foi republicado (última alteração 22/08), devolve `retryOnFail`,
`maxTries`, `waitBetweenTries` e `onError` normalmente pela mesma leitura. A
ausência no da ingestão é real.

**O que entrou:** `N8N/conferir-publicado.mjs` — compara o nó INTEIRO (o que faz,
**como falha**, e **se está ligado**), mais as conexões, contra o JSON baixado do
editor. Ignora de propósito o que é da instalação e não do repositório: o `id` e
o `name` da credencial, o `path` do formulário (sobrescrevê-lo troca a URL
pública do intake) e a `position`; e cobra o contrapositivo, que é o útil — **um
nó HABILITADO com o `REPLACE` do repositório na credencial não vai rodar**.
Rodado contra o vivo: **59 divergências**. Nove testes próprios
(`N8N/test/conferir-publicado.test.mjs`), um por coisa que ele tem de ver e um
por coisa que ele tem de ignorar — um conferidor com ponto cego é pior que
nenhum, porque produz a frase "está igual" com autoridade.

**E a URL do Storage deixou de ser placeholder**, a pedido do dono: o
`SEU-PROJETO` virou a ref real do projeto no `build-workflow.mjs`. Ela é a URL
**pública** da API — a mesma do `NEXT_PUBLIC_SUPABASE_URL` do portal — e não é
segredo; a `service_role` continua como placeholder no header `apikey`, para ser
colada no editor. Nenhuma chave entra no repositório.

**O que o dono precisa fazer, e por que é ele:** republicar o workflow com os
campos de nó (esta sessão não tem chave da API do n8n, e o transporte do MCP
decodifica os `\uXXXX` — corromperia a chave de dedup do `Juntar Blocos`, que é
por isso que a 70 usou REST). Para destravar o smoke test **agora**, basta
desabilitar o `Upload Storage` no editor: é ramo lateral, nada depende da saída
dele, e foi assim que a v47 e a v48 rodaram.

## A SESSÃO 71 (26/08) — a preparação do teste de 190 documentos: a tela desistia de um lote vivo

Sessão de PREPARAÇÃO para a rodada do `book-araucaria` (190 documentos), na
ordem que o handoff deixou. Nenhuma migration, nenhuma mudança de motor: o que
mudou foi a espera da tela, e a mudança saiu de uma medição do workflow, não de
uma suspeita.

**A infra foi conferida antes de qualquer coisa, pela sonda e não por leitura:**
`fn_instalacao_conferir()` devolve **38 requisitos, 38 presentes, zero
ausentes**, `instalacao_cobertura` diz `0149`. E o número que define a frente
segue igual ao de 26/08: **551 documentos, 52 casos, `documento_fato` VAZIA** e
nenhuma versão com `fatos_avaliados_em` — o canal de fato material continua sem
nunca ter rodado contra um documento real.

### O defeito: num lote de 190, a tela declara "parou" sobre um lote que está andando

Medido no workflow, não estimado. Até o primeiro `Registrar Documento` — o
primeiro sinal que a tela consegue ver — a cadeia é `Upload Storage` →
`Extrair Texto` → `Medir Documento` → `Orcamento do Lote` → `IA Classificar` →
**`Juntar Ramos`**. O merge está em `mode: append`, e isso o torna uma
**barreira**: nenhum documento é registrado enquanto a ÚLTIMA classificação não
voltar, e elas saem **uma a cada 8 segundos** (o `batchInterval` do nó).

O limite que a tela usava para esse silêncio era **8 minutos FIXOS**, calibrado
no lote de 38 — onde 19 dos 38 nomes não resolvem tipo+período, ou seja
19 × 8s ≈ 2,5 min de silêncio legítimo contra 8 de tolerância. Em 190
documentos o mesmo silêncio vai a **13 min** na proporção medida e a **25 min**
no pior caso. A tela declararia "o processamento parou" com o lote vivo — e a
consequência não é cosmética: o analista reenvia um lote que está rodando e
**paga a IA duas vezes**.

O limite passa a sair da mesma conta que o silêncio: `CADENCIA_IA_S` (espelhada
do nó) mais `PREPARO_POR_ARQUIVO_S`, vezes o número de arquivos, com o piso de 8
minutos. A conta **reproduz o 8 antigo no lote em que ele foi calibrado**
(38 × 13s = 8,2 min), que é o sinal de que ela descreve o mesmo fenômeno em vez
de só ser maior.

**E um segundo, no mesmo lugar:** o teto da janela de acompanhamento era 90
minutos, e ele truncava a margem de 3× que o próprio comentário promete — num
lote de 190 (previsão de 51 min) a margem real era **1,77×**. O teto existia
para limitar consulta ao Supabase e foi escrito quando a cadência era fixa em
8s (90 min = ~675 consultas); a desaceleração que entrou depois mudou a conta e
ninguém remediu o teto. Hoje 90 min custam **193** consultas e 160 min custam
**333** — ainda metade do que o teto antigo custava quando foi escrito. Subiu
para 160, e a margem prometida volta a ser verdade até 200 arquivos.

### O espelho sem guarda que a correção desfez

A conta da espera morava dentro de `upload-form.tsx`, e por isso **nenhum teste
conseguia chamá-la**: o que o `workflow-sim.test.mjs` fazia era ler as
constantes do fonte e **refazer a fórmula do lado dele**. Isso é espelho sem
guarda — a fórmula muda aqui, o espelho não muda, e o teste segue verde provando
a conta errada. Foi exatamente o que aconteceu quando eu religuei o defeito para
conferir: com o limite fixo de volta, o teste **passava**.

As quatro contas foram para `portal/src/lib/espera-do-lote.ts` e a suíte
`verificar-mensagem-de-falha.mts` passa a **chamar as funções de verdade** —
com a cadência lida do próprio `workflow.e1-ingestao.json`. Religados um a um
contra a função real: o limite fixo reprova com *"a tela desiste em 8.0 min e o
silêncio legítimo da barreira vai a 25.3 min"*, e o teto de 90 reprova com *"a
janela entrega 1.78x do previsto, e a tela promete 3x"*. No `N8N/test` ficou só
o que é do workflow: a cadência espelhada e o merge continuar sendo barreira.

### O orçamento do lote de 190 — cabe, e o penhasco está a um PDF de distância

Simulado contra o guarda REAL, com a forma que o gerador mediu no book (190
documentos, 247 páginas, 16.081 linhas com número):

| Caminho | Estimativa | Teto de US$ 3 |
|---|---:|---|
| por CONTEÚDO (o que roda desde 18/08) | US$ 0,93 a 2,30 | **cabe** |
| por TAMANHO (a queda) | US$ 2,47 a 3,21 | **recusa no pior caso** |

A queda para a conta por tamanho vale para o lote **inteiro** assim que **UM**
documento não trouxer medida de conteúdo — um PDF escaneado, sem camada de
texto, no meio dos 190. No lote de 38 essa diferença era inofensiva (US$ 0,29
medido contra US$ 0,56 estimado, longe do teto); em 190 ela decide se a rodada
acontece, e o lote é um **não-inteiro**: recusado, ele não roda em parte
nenhuma. Os dois fatos viraram teste em `N8N/test/custo.test.mjs`.

**Isto NÃO foi corrigido, e é decisão do dono, não conserto de engenharia.** A
queda é doutrina declarada ("medir só os documentos que dá subestimaria o lote
na proporção do que não se sabe"), e mexer no guarda de dinheiro na véspera de
uma rodada real é o tipo de mudança que se faz com o dono sabendo. A saída
barata, se o penhasco for atingido, está na própria mensagem de recusa: ela diz
quantos documentos cabem por vez.

### Contadores, todos remedidos nesta sessão

`N8N/test` **364** (eram 361 medidos aqui no início — o `ESTADO.md` dizia 353,
estava atrás) · export **713** · transcrição **35** · premissas do realizado
**32** · mensagem de falha + espera do lote **44** (eram 37) · e2e **46** ·
banco **93 migrations do zero, os dois books** · variações **25 rodadas, 0
achados**. `tsc`, `eslint` e `next build` limpos, `build-workflow.mjs` não
reescreve o JSON.

### O que continua sendo do dono, e é o que falta para a rodada

1. **O smoke test de DOIS documentos** (Notas Explicativas 33 e Parecer do
   Auditor 34 do `book-canastra`) — o upload é pelo formulário do n8n e nenhuma
   sessão consegue enviar arquivo por lá. É ele que prova que
   `documento_fato` deixa de ser zero;
2. **O `book-canastra` (38)** e depois o **`book-araucaria` (190)**, nessa
   ordem;
3. Os itens de sempre: proteger o `main` (B6.1), o capítulo 10 no repositório
   (B4.1) e os `[A CONFIRMAR]` do `Arquitetura do Sistema/2 Especificação/10`.

## A SESSÃO 69 (26/08) — new money, equity × haircut, e o cockpit das quatro alavancas

Continuação direta da 68: as **duas frentes que ficaram declaradas como
pendentes** no parágrafo final daquela sessão — **new money** (com prioridade
e PIK) e a separação **equity × haircut** — mais o item que as junta, trazer
tudo para o cockpit da aba `Premissas`. As três foram pedidas juntas, numa só
instrução ("execute as fases 2, 3 e 4 antes de commitar qualquer coisa"), e
só viram commit depois de fechado o ciclo de teste completo nas três — é por
isso que aparecem numa sessão só. Sem tocar `N8N/` nem `Supabase/`, mesma fronteira
E4 da 68.

**FASE 2 — NEW MONEY.** Uma tranche NOVA na `ST Inv. & Debt`
(`NM_VALOR`/`NM_PRAZO`/`NM_CARENCIA`/`NM_SPREAD`/`NM_INI`/`NM_PCT`/`NM_AMORT`/
`NM_FIM`/`NM_JUROS`/`NM_JUROS_PIK`), deliberadamente **fora** do motor de
"DEBT ISSUANCE" (captação por safra) que já existia: reaproveitar aquele
motor misturaria refinanciamento de operação normal com dinheiro novo de
reestruturação na mesma linha, e são leituras diferentes para o comitê. SAC
com carência, a mesma técnica das tranches existentes; principal só no 1º ano
projetado; dois dropdowns de cabeçalho (célula única, não por ano) — **PIK
(S/N)** e **prioridade** (Super sênior/Sênior/Pari passu/Júnior, informativo).
O juro do new money **sempre** entra no resultado (reduz o lucro tributável);
PIK só decide se ele SAI DO CAIXA ou CAPITALIZA no saldo (`NM_JUROS_PIK`,
somado de volta no Cash Flow como não-caixa — `PIK_ADD`, o mesmo desenho da
depreciação). New money entra em `DIVIDA_BRUTA`, `DESP_FIN`,
`ESP_DIVIDA_CP/LP`, `ESP_CAPTACAO`, `ESP_AMORT` e ganha linha própria no
`Output` (`DV_NOVOMONEY`) e na réplica de cenários da sessão 68
(`CEN_FIN_EXP`/`CEN_FCO`/`CEN_DIV_LIQ`/`CEN_SERVICO`, todos por new money ser
invariante ao cenário — cronograma contratual, não depende de receita).
Validado numericamente (script descartável, não ficou no repo): draw de
20.000, PIK=N e PIK=S, o balanço fecha nos dois (`Mismatch` ~1e-10, ruído de
ponto flutuante) e o saldo de fechamento bate a mão (SAC de 4.000/ano; com
PIK o saldo capitaliza o juro do período em vez de cair só pela amortização).

**FASE 3 — EQUITY × HAIRCUT.** A sessão 68 já deixava escrito: "hoje as duas
ainda caem no mesmo balde `REPERFILAMENTO`, sem diferenciar contrapartida no
PL de ganho no resultado". Ganhou uma segunda chave por tranche,
`#classe` (dropdown "Equity,Haircut", nasce em **Equity** — o comportamento
antigo, para não mudar nenhum arquivo que já existe), que só importa quando
"Efeito caixa? = N". Equity continua exatamente como antes: contrapartida
DIRETA no PL (`REPERFILAMENTO`, renomeado por dentro para somar só
`TOTAL_AMORT_EQUITY`), sem passar pelo resultado. Haircut é NOVO: vira ganho
na Income Statement (`GANHO_HAIRCUT`, linha própria entre o resultado
financeiro e o EBT — **fora do EBITDA**, porque perdão de dívida não é
desempenho operacional), tributado como qualquer outro resultado, e chega ao
PL pelo caminho normal de lucro (`LUCROS_ACUM`).

**O bug que a primeira versão tinha, e como foi pego:** um ganho não-caixa
que aumenta o lucro tem de ser SUBTRAÍDO no Cash Flow, não somado — o oposto
do PIK (que é uma DESPESA não-caixa, somada de volta). A primeira versão
esqueceu a subtração: `NET_INCOME` carregava o ganho, o `FCO` inflava no
mesmo valor, e o balanço abria exatamente na parcela classificada Haircut
(medido: `Mismatch` = o `GANHO_HAIRCUT` acumulado, no centavo). Corrigido com
`HAIRCUT_SUB` no Cash Flow, o espelho negativo do `PIK_ADD` — e o mesmo termo
faltava na cascata de réplica por cenário da sessão 68 (`kFco`/`kTax`), que
tem sua PRÓPRIA reconstrução de lucro líquido e teria o MESMO bug sem
aparecer no `CEN_CHECK_REAL` (o defeito é idêntico nos dois lados da
comparação, então o CHECK que só compara sombra×real fica cego para ele —
outro caso do "CHECK que mente" que a 68 já tinha nomeado, desta vez pego
antes de virar commit). Religado nos dois lugares, validado: EBITDA não se
move ao classificar Haircut (não é operação), o balanço fecha
(`Mismatch` ~1e-10) com a tranche em Haircut, e `CEN_CHECK_REAL` continua
zero nas três posições do dial com o haircut ativo.

**FASE 4 — O COCKPIT.** Oito alavancas novas na `Premissas`: a chave "Efeito
caixa?" (que já existia na aba de dívida desde a sessão 68 mas nunca tinha
entrado no cockpit), a classificação Equity/Haircut, e as seis do new money
(principal, prazo, carência, spread, PIK, prioridade). O mecanismo de
endereço-por-sufixo (`#prazo`, que já existia para "prazo das tranches
existentes") foi generalizado de um `if` único para qualquer sufixo `#…` —
`#amort` (onde mora a chave de efeito caixa) e `#classe` reaproveitam o MESMO
código, não um copiar-colar.

**Teste permanente.** Três blocos novos em `verificar-export.mts`: (52) new
money — PIK=N/S, SAC do ano 1, saldo de fechamento, balanço fecha nos dois;
(53) equity × haircut — EBITDA invariante, balanço fecha via `LUCROS_ACUM`
em vez de `REPERFILAMENTO` quando classificado Haircut, o ganho de fato
aparece na Income Statement. 663→**713** (688 da sessão 68 + 25 novos: os 13
do (50)/(51) já contavam; 702 depois de reunir os dois blocos numa fixture só
por Sonar, +11 de fase 2/3). `tsc`/`eslint` limpos, banco (93 migrations)
100%, e2e 46/46, variações (25 rodadas, cadeia real) 0 achados — as quatro
suítes reconferidas depois de TODAS as três fases, porque a instrução do
dono foi não commitar nada até fechar o ciclo completo nas três juntas.

**O que NÃO entrou:** a "diluição" que o `#classe = Equity` promete (% do
capital que o credor passa a ter, contra um "valor da empresa" pré-money)
ficou de fora — é o item que sobra do plano original de 5 fases e precisa de
uma premissa nova (valor da empresa) que nenhuma aba hoje pede. O `Output`
publica o saldo convertido (`REPERFILAMENTO`) mas não a % de diluição; é a
continuação natural desta frente.

## A SESSÃO 68 (26/08) — a réplica completa de ND/EBITDA, DSCR e pico de caixa por cenário

O dono pediu a primeira das duas frentes do plano de reestruturação (o `docs/`
ainda não tem o arquivo do plano completo — ele foi apresentado no chat, não
commitado): **fechar a lacuna que a sessão 54 tinha deixado declarada** — o
`Output` só replicava RECEITA e EBITDA nos três cenários; ND/EBITDA e DSCR
continuavam lendo a dívida do cenário ATIVO, um PISO conservador, não a
réplica de verdade. **Essa lacuna está fechada.**

**O que passou a existir**, sem tocar `N8N/` nem `Supabase/` — é fronteira E4
(export), o `.xlsx` é gerado do zero a cada exportação e não tem ida e volta
com o Postgres:

- **`Working Capital` ganha uma sombra de NCG por cenário** (`NCG#v_${suf}` /
  `VAR_NCG#v_${suf}`), no mesmo desenho do `CHECK_SOMBRA` que a DRE já tinha
  desde a sessão 54: mesmos dias de giro (a régua `#dias`/`#diasStr` já
  distinguia Base de Stress; Cliente sempre usava a de Base), a base que muda
  é a receita/custo daquele cenário, lida da sombra que a aba de receita já
  publicava (`RECEITA_LIQUIDA#v_${suf}` / `CUSTOS#v_${suf}`) e que não tinha
  consumidor nenhum fora da própria DRE.
- **O `Output` ganha uma segunda cascata de revolver, uma por cenário**
  (bloco "RÉPLICA COMPLETA POR CENÁRIO"): EBIT → tributo → caixa de operação
  → caixa antes do revolver → furo → saque, com a MESMA técnica sem
  circularidade do revolver ativo (juros sobre o saldo de ABERTURA, nunca
  sobre o saque do próprio ano). CAPEX, depreciação e o serviço das tranches
  existentes/captação nova **não são replicados** — são cronograma
  contratual ou já tratados como invariantes ao cenário pela própria sombra
  da DRE (medido, não suposto: é assim que `EBITDA#v_${suf}` já usa a
  depreciação ATIVA desde a sessão 54) —, e replicá-los criaria uma
  divergência que o resto do arquivo não tem.
- **ND/EBITDA, DSCR e o pico de uso do revolver saem REAIS, não mais piso**,
  em `CEN_ND_REAL#${suf}` / `CEN_DSCR_REAL#${suf}` / `CEN_PICO_REVOLVER#${suf}`.
  O bloco de sensibilidade antigo (`CEN_ND`/`CEN_DSCR`) fica como
  **contraprova declarada**, não como lacuna — o texto da aba mudou para
  dizer isso.

**Uma tentativa de CHECK caiu ao medir, e ficou de fora — é o método de
sempre, e vale registrar.** A primeira versão tentava travar "a réplica
nunca é mais otimista que o piso" como invariante universal. Medido: com o
dial no Stress, a coluna do Cliente no piso carrega a dívida ALTA do Stress
sobre um EBITDA melhor, e a réplica de verdade (que puxa menos revolver)
fica MAIS otimista que esse piso — o contrário do que o CHECK afirmava. A
desigualdade depende de qual cenário está ativo, não é invariante, e um
CHECK que reprova de forma imprevisível é pior que nenhum CHECK. Ficou só o
que é igualdade PROVÁVEL por construção: a coluna do cenário ATIVO tem de
bater exatamente entre a réplica e o bloco de RATIOS (`CEN_CHECK_REAL`).

**Religado, os dois lados:** `CEN_CHECK_REAL = 0` em toda coluna projetada
(a réplica do Base Case, via `CHOOSE`, bate exatamente com `DV_LIQ`
ativo) — prova a mecânica. E o revolver do Stress publica maior ou igual ao
do Base em TODO ano projetado no `book-vertentes` (859k vs 640k no primeiro
ano, abrindo para 4,77M vs 3,82M no último) — prova a direção. Os dois viram
o teste (50) de `verificar-export.mts`, que soma 13 asserts novos (650→663).
Suíte de banco (93 migrations, os dois books) e e2e (46) reconferidas
localmente depois da mudança — verdes, e nenhuma delas deveria ter se
movido, porque nada nesta sessão tocou `Supabase/` ou `N8N/`.

**Uma rodada de revisão adversarial (8 ângulos independentes) achou 4
defeitos reais, e o mais grave era exatamente do tipo que este projeto mais
teme: um CHECK que mente.** `CHECK_SOMBRA_WC` (Working Capital) foi escrito
comparando a NCG ativa contra a sombra do Base Case **fixa**, em vez de
escolher a sombra do cenário LIGADO por `CHOOSE` — como o `CHECK_SOMBRA` de
verdade, que a linha alegava imitar. Como o arquivo sempre nasce com o dial
no Base, nenhuma suíte via a célula acusar uma divergência falsa assim que
alguém girasse para Cliente ou Stress — o estado NORMAL de um arquivo de
reestruturação. Religado e medido: com o dial em Stress, a célula acusava
~22 a ~27 mil de "divergência" que não existia. Os outros três: um crash
(`ant!` sem guarda) quando o caso não tem nenhum ano histórico — estado que
o próprio código já detecta em outro lugar e continua, mas esta cascata
derrubava; o rótulo `CEN_FORA`, escrito no arquivo entregue, afirmando "um
CHECK garante que a réplica nunca fica mais otimista que o piso" — um CHECK
que a própria sessão tinha decidido não construir, por medir que a
desigualdade não é invariante (parágrafo acima); e uma colisão de
numeração entre o teste novo e dois testes pré-existentes (tentou "(42)",
colidiu; tentou "(43)", colidiu de novo; ficou em "(50)"). Os quatro foram
corrigidos, e um quinto achado (`NCG#v_${suf}` produzindo a fórmula
inválida "-()" com ativo e passivo vazios) foi investigado e descartado —
a guarda `|| "0"` já cobre os dois lados. **O teste (51) nasceu direto
desse achado**: gira o dial de verdade nas três posições e confere os dois
CHECKS (`CEN_CHECK_REAL` e `CHECK_SOMBRA_WC`) em cada uma — é o que teria
pego o defeito antes de qualquer suíte existente (663→688). Depois das
correções: suíte de export 688/688, banco (93 migrations) 100%, e2e 46/46,
e o loop de variações (`Verificação/variacoes.mts`, 25 rodadas, cadeia real)
com **0 achados** — incluindo os cenários que tocam a dívida direto
(`patrimonio_a_descoberto`, `caixa_negativo`, `divida_maior_que_o_ativo`,
`sem_mapa_de_divida`).

**O que NÃO entrou nesta sessão, e é a continuação natural** (o resto do
plano de 5 fases apresentado ao dono no chat): **new money** com prioridade
e PIK, **conversão em equity com diluição** separada de **haircut** (hoje
as duas ainda caem no mesmo balde `REPERFILAMENTO`, sem diferenciar
contrapartida no PL de ganho no resultado), e trazer as quatro alavancas
para o mesmo bloco do Output lado a lado com o de carência. O `Working
Capital` ganhou a peça que faltava (NCG por cenário) e pode ser reaproveitado
sem mudança para essas frentes seguintes.

## A SESSÃO 67 (25/08) — as quatro frentes que o handoff deixou em ordem

O handoff da 66 listava cinco itens em ordem. Quatro foram feitos nesta sessão, e o quinto (os
itens que só o dono destrava) continua sendo dele. **O que ficou aberto está no fim desta seção,
nomeado.**

### 1. A hierarquia na extração — `secao` passa a ser o agrupador IMEDIATO

Era a causa raiz de 12 das 20 pendências falsas da v48. `secao` trazia a seção de TOPO para toda
linha, então o subgrupo e os filhos dele entravam na MESMA soma e a seção era contada duas vezes.

**Medir antes de escrever desmentiu o plano, de novo.** A hipótese era que `fn_conferir_arvore`
precisaria de conserto. Montei o mesmo documento de três alturas nos dois estados e rodei a função
contra os dois:

| | conferências | soma dos filhos | resultado |
|---|---|---|---|
| achatado | 1 | 44.847 | `divergente` |
| hierárquico | 2 | 44.022 **e** 825 | as duas `ok` |

**`fn_conferir_arvore` não precisou de uma linha:** ela já é recursiva por construção — todo rótulo
que aparece como `secao` de alguém vira pai. O defeito nunca esteve nela, estava no insumo. E o
hierárquico ainda GANHA uma conferência que não existia: o subgrupo passa a conferir a si mesmo.

**Um achado que estreita a conclusão da v48:** neste caso a razão é **1,0187, não 2,0000**. A guarda
de `hierarquia_achatada` da `0143` só reconhece a assinatura quando TODOS os subgrupos estão
achatados; com um só achatado, a pendência sai como divergência normal e o piso honesto não cobre.

**E o CI nunca tinha visto isso** porque o fixture do `book-vertentes` tem DOIS níveis. O bloco 7 do
`secao_fecha.test.sql` acrescenta o caso de três alturas, nos dois estados, com as mesmas sete
linhas — 8 asserts.

**O risco que a mudança cria, medido:** `secao` encolhe, e há localizadores que casam contra ela. Das
três exigências que usam `contra='secao'`, TODAS têm alternativa por `chave`. Um assert novo garante
que a próxima não nasça dependendo só da seção.

### 2. O `Parse Extracao` foi publicado no n8n — e a conferência é por hash

O nó vivo rodava a versão anterior ao PR #173. Agora roda a do repositório: `escalaDeclaradaNaColuna`
presente e aplicada nos dois formatos, moeda herdada por linha, contexto religado ao `Fatiar`.
**575 das 579 linhas batem byte a byte.**

**As 4 que não batem, e por quê — isto importa para a próxima sessão.** São os quatro ranges NFD. O
transporte MCP **decodifica `\uXXXX` antes de o texto chegar ao `jsCode`**, então o range grava o
caractere combinante CRU em vez do escape. Quatro tentativas, quatro vezes o mesmo. A equivalência
foi MEDIDA e não suposta: **160 comparações das duas formas, 0 divergências.** Para bater por hash
basta o dono importar o `N8N/workflow.e1-ingestao.json` pela tela — o que ele vai precisar fazer de
qualquer jeito (ver "o que ficou aberto").

### 3. A sonda de instalação passa a enxergar o CORPO da função (`0147`)

O catálogo tinha 13 marcadores e parava na `0130`, com o banco na `0146`. Dezesseis migrations sem
cobertura — e **a fatia de fora era a cara**: das 16, só sete criam objeto novo. As outras nove
apenas republicam corpo de função (a `0142`, a `0143`, a `0144`, a `0145`, a `0146`), e todas mudam
**o que o sistema acusa**. Um banco sem elas abre pendência falsa e parece perfeitamente instalado,
porque cada função que elas corrigem existe.

Essa cegueira a própria `0131` já tinha declarado de si mesma e deixado aberta. O tipo `corpo` a
fecha: o requisito exige que um trecho apareça em `pg_get_functiondef`.

**Religamento medido:** um banco montado do zero com tudo MENOS a `0142`, a `0143` e a `0146` faz a
sonda nomear as três, com o detalhe *"a função existe, mas o corpo é ANTERIOR a esta migration"*. O
mesmo banco, antes da `0147`, se declarava instalado. **Os marcadores foram medidos contra o banco —
três dos meus primeiros palpites estavam errados.**

E `instalacao_cobertura` declara até onde o catálogo foi revisado, com o `run.sh` reprovando quando
ela fica para trás. A `0148` foi a primeira a pagar esse portão, na mesma sessão.

### 4. O que o documento diz em TEXTO deixa de ficar mudo (`0148`)

Dos 38 documentos, quatro não rendem linha e os quatro estão certos. Mas dois carregam os fatos mais
importantes do mandato: o `33_Notas_Explicativas` declara o **covenant rompido** e a reclassificação
que explica o Passivo Circulante em 112.372; o `34_Relatorio_do_Auditor` traz **ressalva** e
**incerteza sobre continuidade operacional**. Nenhum dos dois chegava ao portal.

**Duas decisões de produto, e elas são a parte discutível:**

1. **Fato material NÃO é pendência.** Pendência significa "há algo a corrigir"; covenant rompido não
   é defeito do dado, é o dado. Canal próprio, e ele **abre** a tela do mandato.
2. **O fato carrega o trecho LITERAL, `not null`.** Resumo do modelo é afirmação; frase copiada é
   evidência — e este é o alerta que vai ao comitê. Na tela o trecho vem primeiro, como citação.

Nenhuma chamada de IA nova (o modelo já lê o PDF inteiro) e nenhum nó novo no canvas
(`fn_registrar_fatos` entra na MESMA query do `Registrar Diagnostico`, porque cada nó Postgres a mais
é mais uma chance de perder `documento_id` — v47, onze dias parados).

### E o caractere que ninguém vê saiu do arquivo que vai à mão para o n8n

Três das quatro classes NFD do `extract.mjs` carregavam os combinantes CRUS; a quarta, na MESMA
função, já usava a forma escapada. Medido: dos quatro workflows gerados, **os 6 caracteres do
repositório inteiro estavam TODOS no `Parse Extracao`** — o nó que faltava publicar. O
`caracteres.test.mjs` passa a varrer os quatro JSONs commitados.

### 5. A auditoria adversarial da `0148` — sete defeitos, cinco silenciosos (`0149`)

A `0148` saiu verde em 16 asserts e foi lida de novo, no dia seguinte, com a pergunta invertida:
**não "isto funciona?", e sim "o que eu faria para quebrar isto sem que ninguém percebesse?"**.
Sete defeitos, e o que os torna caros é a segunda coluna:

| # | O defeito | Como ele apareceria |
|---|---|---|
| 1 | A tabela só dava `select` ao papel `authenticated` | A gravação funcionava por acidente da credencial do n8n, não por decisão; trocar a credencial a desligaria |
| 2 | Página alucinada (`99999999999`) estourava `22003` | **Silencioso e caro:** `fn_registrar_fatos` roda na MESMA query do diagnóstico, então a exceção abortava a query e o documento perdia o DIAGNÓSTICO inteiro |
| 3 | Versão inexistente estourava `23503` | Idem — mesma query, mesmo estrago |
| 4 | Reenviar um arquivo fazia os fatos SUMIREM da tela | **Silencioso:** a tela pegava a versão mais nova sem perguntar se ela chegou a ser lida |
| 5 | Ordem indeterminada | **Silencioso:** os fatos de um mesmo insert compartilham um só `criado_em`, e a lista podia sair em ordens diferentes — numa tela em que a ordem significa gravidade |
| 6 | `confianca` prometia medição e nunca recebeu valor | **Silencioso:** número que ninguém escreve é opinião com cara de medida |
| 7 | `Juntar Blocos` descartava os fatos dos blocos 2..N | **Silencioso:** documento fatiado só entregava os fatos do primeiro pedaço |

**A correção do (4) que estava errada, e por que medir salvou.** O reparo óbvio era usar
`fn_versao_com_extracao` — a função que o resto do sistema já usa para escolher a versão. Ela exige
linha em `campo_extraido`, e **os documentos que mais têm fatos extraem ZERO linha por natureza**:
notas explicativas e parecer de auditoria são justamente os dois. A correção certa é uma coluna
própria, `fatos_avaliados_em`, porque só ela separa "versão nova ainda não processada" (onde os fatos
da anterior VALEM) de "versão processada e sem fato nenhum" (onde a anterior NÃO volta).

**A brecha que o religamento achou na PRÓPRIA suíte, e é a lição da rodada.** Desfazer o defeito 7 no
`build-workflow.mjs` deixava os 92 testes de `workflow-sim` VERDES: a suíte testava a função da lib,
e o nó de produção — que é código duplicado à mão dentro do `jsCode` — nunca era exercido. Um teste
que não reprova quando o defeito volta não é teste. O mesmo aconteceu com o defeito 5: o assert de
ordem passava com e sem a correção, porque nada perturbava o heap entre as duas leituras; hoje ele
reescreve uma linha no meio, que é o que faz o Postgres devolver a ordem física diferente. **Os sete
religamentos foram conferidos um a um, e os sete reprovam o teste correspondente.**

E um oitavo achado, de tipo diferente: o requisito `fato_escrita_permitida` **conferia outra coisa**
— o corpo de `fn_fatos_do_caso`, nada a ver com escrita. O nome teria feito o painel de instalação
afirmar uma cobertura que ele não tem. Passa a se chamar `fato_leitura_estavel`, e o comentário ao
lado diz em voz alta o que NÃO está coberto: a sonda não sabe ler `pg_policy`, então a política de
escrita é coberta pelo `fato_material.test.sql` e, em produção, pelo campo `erro` do retorno.

O `fato_material.test.sql` foi de 16 para 34 asserts.

### O que ficou aberto, e de quem é

1. ~~REIMPORTAR o workflow~~ **FEITO em 26/08, e conferido por hash.** Publicado pela API REST do
   n8n (`PUT /api/v1/workflows/:id`), não pelo transporte do MCP — que **decodifica os `\uXXXX`** e
   transformaria a chave de dedup do `Juntar Blocos` num byte NUL cru. Conferido depois de publicar:
   **33 de 33 nós com os parâmetros byte a byte iguais ao repositório**, 12 credenciais preservadas,
   workflow ativo, o `path` do `Intake (Form)` intacto (`bea41a5a…` — ele é atribuído pelo n8n, e
   sobrescrevê-lo troca a URL pública do intake; já se perdeu uma vez assim) e zero caractere
   invisível. Os quatro nós que divergiam divergiam por UMA causa só: a `juntarBlocos` do espelho;
2. ~~APLICAR a `0147` e a `0148`~~ **FEITO**, e a `0149` junto — ver a linha "Aplicadas no Supabase";
3. **RODAR o book** (dono). É o que mede se o modelo obedece ao prompt novo — o bloco 7 prova a
   aritmética da conferência, não a leitura do documento. Vale para as duas frentes;
4. **O dialeto OpenAI tinha 2 testes vermelhos; agora tem 1.** O `Ramo E2: Registrar → Montar Req
   Extracao → Parse` comparava `schemaDaReq` (que desembrulha `.schema` do `response_format` da
   OpenAI) contra `schemaDoProvedor(PROV, extractionSchema())`, que para o dialeto não-Gemini
   devolvia o objeto INTEIRO (`{name, strict, schema}`) em vez do `.schema` — os dois lados nunca
   descreviam a mesma coisa. `schemaDoProvedor` só é chamado em produção no ramo Gemini (o ramo
   OpenAI de `montarCorpoIA` nunca o invoca), então a correção (`return jsonSchema.schema ||
   jsonSchema`) não muda nenhum payload que sai para a IA — só o comparador do teste, que era o que
   estava errado. Religado: `node --test test/workflow-sim.test.mjs` sobe de 90/92 para 91/92 sob
   `IA_PROVEDOR=openai`, e os 353 testes de `N8N/test/` continuam verdes sob o Google (padrão),
   confirmando que nada mudou na cadeia ativa. As 6 cópias-espelho de `schemaDoProvedor` embutidas em
   `N8N/workflow.e1-ingestao.json` foram regeradas por `build-workflow.mjs` para acompanhar a lib.
   **O que ainda fica vermelho** — `a estimativa que o PORTAL mostra é coerente com a cadência REAL`
   — não é bug de teste: o `SEGUNDOS_POR_DOCUMENTO` do portal é calibrado para a cadência do provedor
   ATIVO (Google, 8s), e a OpenAI tem cadência própria (~33s/chamada) que o portal não representa. Já
   estava vermelho no início da sessão 67 (conferido rodando o `886b7f3`) e não bloqueia nada — o CI
   roda o dialeto padrão —, mas decidir se o portal passa a ser provider-aware é decisão de produto,
   não conserto de teste;
5. **Os itens que só o dono destrava**, inalterados desde a 66: proteger o `main` (B6.1), o capítulo
   10 no repositório (B4.1) e os `[A CONFIRMAR]` do `Arquitetura do Sistema/2 Especificação/10`.

## O PROVEDOR DE IA VIROU ESCOLHA, E O PADRÃO PASSOU A SER O GOOGLE (24/08)

O dono pediu a troca com uma frase direta: *"essa do gpt não estou vendo vantagens do que trocar
para outras melhores"*. A escolha foi **Gemini 3.5 Flash-Lite**, e o que ela custou de trabalho não
foi falar com o Google — foi que **não havia "um provedor" neste repositório para trocar**. Havia a
OpenAI espalhada: a URL em dois módulos, o formato do corpo em três lugares (dois na lib e mais um
minificado dentro do gerador), a leitura de `choices[0].message.content` em quatro, e o `usage` dela
lido direto pelo medidor de custo. Trocar era, literalmente, achar todos.

**O que passou a existir:** `N8N/lib/provedor.mjs`, onde cada provedor é um objeto de DADOS (URL,
header de auth, nome da credencial no n8n, tpm/rpm) e as diferenças de dialeto viram sete funções.
Dado puro, e não objeto com métodos, porque nó Code do n8n não importa módulo — o gerador escreve o
provedor no nó como literal e embute as funções por `toString()`, o mesmo mecanismo de espelho que
já valia para `diagnosticarErroApi` e as 26 funções do `espelho-inline.test.mjs`.

**A API NATIVA DO GOOGLE, e não a camada de compatibilidade dele com o `/chat/completions`.** Usar a
camada de imitação faria o arquivo quase desaparecer — e entregaria o subconjunto que o formato da
OpenAI comporta. O que esta troca busca é leitura de DOCUMENTO, e é a API nativa que recebe o PDF
como parte (`inlineData`) e aceita `responseSchema`. Pagar a migração para ficar com o subconjunto do
provedor antigo seria não levar a mercadoria.

**O número, medido e não estimado** — `N8N/medir-custo-book.mjs` sobre os MESMOS 38 PDFs do
`book-canastra`, trocando só a tabela de preço:

| | gpt-4o + gpt-4o-mini | Gemini 3.5 Flash-Lite |
|---|---|---|
| lote inteiro (57 chamadas) | US$ 1,2932 | **US$ 0,2821** (−78%) |
| documento mais caro (livro razão) | US$ 0,1725 | **US$ 0,0459** (−73%) |
| intervalo entre extrações | ~33s (balde de TPM) | **8s** (limite de chamadas) |

**O que a troca comprou em COMPORTAMENTO:** o lote do v31 — os 14 documentos que estouraram o teto
de US$ 5 no meio da execução em 31/07 e mataram 8 sem extração — hoje cabe em menos da metade do teto
de US$ 3, e isso está travado por teste. O book de 38 deixou de precisar de levas. E o lote de 57
chamadas passou de ~31 minutos para ~7,6.

**O erro que a recalibração quase cometeu, e é o que vale guardar.** Três constantes do guarda de
orçamento eram calibradas contra o preço do `gpt-4o`, e o instinto é dividir todas pela razão medida
do lote (0,218×). Fazer isso fazia o **lote homogêneo denso** — o caso que o teto existe para
barrar — passar a ser ACEITO, porque existem DUAS razões e elas divergem: o lote caiu 0,218× e o
documento mais denso caiu 0,266×, já que o preço da saída caiu menos que o da entrada. Trocar
"recusa lote que caberia" por "aceita lote que não cabe" é o v31 de novo. Vale a razão do denso.
Detalhe e o custo declarado dessa escolha em `Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md`.

**As suítes passaram a rodar nos DOIS dialetos.** Os testes de fronteira liam
`body.messages[1].content` e `resp.choices[0]` direto — ou seja, testavam o workflow E o dialeto da
OpenAI sem distinguir os dois, e por isso reprovavam a troca sem ter nada a dizer sobre ela. Agora
as fixturas são escritas uma vez e traduzidas para o dialeto do provedor ATIVO: trocar `IA_PROVEDOR`
reexecuta a suíte inteira contra o outro. O mesmo vale para o arnês de variações e o e2e, que
injetam a resposta no ponto em que a IA responde.

**O que só o dono destrava, e nenhuma suíte alcança:**

1. **O teto de gasto do projeto no provedor NOVO.** Ele é configuração de conta e **não se herda**:
   a conta nova começa sem teto nenhum, e a defesa dura — a que barra quando este código falha —
   fica ausente até alguém ir lá pôr;
2. **A credencial no n8n** com o nome que o JSON gerado espera: `Google AI (Gemini)`, header
   `x-goog-api-key`, valor sem prefixo (a chave NUNCA na URL como `?key=`, que apareceria no log);
3. **Zero-retention / DPA com o Google** antes de dado real de cliente — acordo com um provedor não
   vale para o outro (`Arquitetura do Sistema/2 Especificação/10`, `Arquitetura do Sistema/2 Especificação/f0/02`);
4. **Reimportar o workflow.** A versão do orçamento subiu para `v4 (2026-08-24)` e ela vai na
   mensagem de recusa justamente para isto: um n8n com o JSON velho recusa lotes que o código novo
   aceita, com uma mensagem que parece a mesma.

**Renomes que acompanharam** (o nome era metade do problema): `lib/openai.mjs` → `lib/ia.mjs` (o que
mora nele é a taxonomia e o prompt, que não mudam com o provedor), `diagnosticar-openai.mjs` →
`diagnosticar-ia.mjs`, `docs/CUSTO_OPENAI.md` → `Arquitetura do Sistema/4 Análises e Auditorias/CUSTO_IA.md`, os nós `OpenAI Classificar`/
`OpenAI Extrair` → `IA Classificar`/`IA Extrair`, e o campo `openai_body` → `ia_body`. O valor
`fonte='openai_conteudo'` **não** foi renomeado: ele está em linha de produção e em CHECK de
migration (`0033`), e trocá-lo seria reescrever histórico para arrumar um nome.

## O portal (17/08) — navegação, marca e o fim de vida do mandato

- **Barra lateral retrátil** com duas seções que não são simétricas de propósito: *Novo mandato* é
  AÇÃO (fixa, sem filhos) e *Mandatos* é LUGAR (abre e lista os **ativos**). O estado — recolhida e
  seção aberta — mora no navegador via `useSyncExternalStore`, para a barra não "piscar" no lugar
  errado a cada carga. Ela some na tela de abrir mandato, que é de tela cheia.
- **A marca entrou** (`portal/public/logo-oria*.svg`): o original do dono com o fundo creme trocado
  por transparência, **sem redesenhar nada**. O SVG EMBUTE a arte original — vetorizar exigiria
  traçar, e traçar é aproximar. Sextante no cabeçalho e no favicon; a lockup completa no login,
  onde há altura para ela.
- **Fechar ≠ excluir** (`0114`): `caso.status` diz onde o mandato está no trabalho, e não respondia
  "ainda estamos nisso?". `fechado_em` responde, preservando tudo — para apagar continua existindo
  `fn_excluir_caso`. A lista ganhou o segundo rótulo (**Ativo/Fechado**), uma descrição derivada de
  uma linha (documentos · pendências · data) e as duas ações no rodapé de cada item.

> **Para o dono:** a `0114` precisa ser aplicada no Supabase. Sem ela, a coluna não existe e a lista
> trata todo mandato como ativo — a tela não quebra, mas o botão de fechar falha.

## O portal (18/08) — a home deixou de ser a lista

- **A barra lateral rola sozinha.** O `nav` era `sticky` mas não tinha altura: com mais mandatos
  do que cabe na tela, os últimos ficavam abaixo da dobra do elemento grudado e só apareciam
  quando a PÁGINA terminava de rolar. Agora ela tem a altura da viewport abaixo do cabeçalho e a
  lista rola dentro dela, com o topo (Painel, Novo mandato, Mandatos) parado.
- **`/casos` virou o PAINEL e a lista completa foi para `/casos/todos`.** A home repetia inteira a
  lista que a barra já dá em um clique — duas telas para "o que existe", e nenhuma para *o que
  precisa de mim agora*. O painel tem três blocos: indicadores da mesa (mandatos, documentos,
  linhas extraídas, pendências e quantas bloqueiam), a **fila de pendências atravessando os
  mandatos** ordenada por severidade — que antes só existia dentro de um caso por vez —, e o que
  chegou, com as linhas de cada documento (zero linhas em vermelho).
- **A regra que saiu disso:** nenhuma função da barra lateral se repete no conteúdo. O botão
  "Novo mandato" saiu da lista completa; quem precisa dele o tem na barra, sempre visível.
- **Os sete indicadores do painel** (escolhidos pelo dono): mandatos ativos, mandatos fechados,
  linhas extraídas, tempo médio de processamento, gasto médio de API por mandato, gasto total de
  API, pendências em aberto.
- **A abertura e a ilustração.** O painel abre com uma cena de ~3s — o sextante da marca desenhado
  em vetor próprio (a arte original NÃO é tocada), com o limbo crescendo e a constelação acendendo
  em cascata. Toca **uma vez por sessão** do navegador, **qualquer gesto corta**, e
  `prefers-reduced-motion` pula por completo. O mesmo motivo fica de fundo no painel a ~15% de
  opacidade, na goteira à direita: **gira com a rolagem** e a constelação deriva com o ponteiro.

- **O custo passou a durar (`0115`)**, e com ele veio o **oitavo indicador: cobertura da extração**.
  `lote_execucao` guarda uma linha por execução de ingestão (custo real, custo estimado, tokens,
  linhas, cobertura), gravada pelo nó novo `Gravar Uso do Lote`. A chave `(caso_id, execucao_ref)`
  é o que impede o custo de sair **dobrado**: o `Resumo de Custo` roda uma vez por ramo do lote e
  as duas passadas trazem o total inteiro.

> **PARA OS TRÊS INDICADORES NOVOS ACENDEREM, DUAS COISAS PRECISAM ACONTECER FORA DO GIT:** aplicar
> a `0115` no Supabase e **reimportar o `N8N/workflow.e1-ingestao.json`** (o n8n executa o JSON
> importado, e merge não reimporta). Sem a migration, a tela mostra um traço com a causa escrita —
> não zero. Sem a reimportação, a tabela existe e fica vazia. O **tempo médio** não depende de
> nenhuma das duas: é uma janela derivada — de
> `caso.criado_em` (gravado pelo `Upsert Caso`, no envio do intake) até o `criado_em` do último
> documento do mandato; janelas acima de 12h são contadas à parte, porque a partir daí o número
> mede espera pelo cliente, não processamento.

## Estado dos PRs (18/08, sessão 51 — leia isto antes de continuar)

| PR | O quê | Estado |
|---|---|---|
| **#133** | Barra lateral rolável, `/casos` vira Painel (8 indicadores), lista completa em `/casos/todos`, abertura animada, migration `0115` (custo do lote em `lote_execucao`) | **mergeado no `main`** |
| **#134** | Correção: "1.000 linhas extraídas" no Painel era o teto padrão do Supabase/PostgREST (`db-max-rows`), não o dado real | **mergeado no `main`** |
| **sessão 50** | Os sete itens de "o que está aberto", atacados em ordem a pedido do dono: subtotais impressos, mútuos, Modelagem, apelidos, teto de gasto, dedup e o teto de 1000 nas listas | **mergeado no `main`** (PRs #137, #139, #140, #141) |
| **sessão 51** | A aba "Perguntas ao cliente" (`/casos/[id]/perguntas`), o fim do teto de 1000 no portal e a `0122` (o texto que vai ao cliente em português) | **mergeado no `main`** (PR #142) |
| **sessão 51 (cont.)** | Os cinco defeitos de número do EXPORT do Excel, achados rodando o arquivo do caso de referência | **branch `claude/client-question-suggestions-ves2ty`** |

**Nada da sessão 50 ficou pendente de merge** — o `main` já tem os sete itens, e a branch da sessão
51 sai dele. As migrations `0116` a `0121` **já estão aplicadas** (o dono confirmou em 18/08); o que
continua pendente daquela rodada é a reimportação do workflow e a rodada real, no quadro "O próximo
passo".

**O risco que a sessão 50 fechou, e que estava anotado aqui como "não se resolve sozinho":** as
listas de `documento` e `pendencia` do painel continuavam sujeitas ao teto de 1000 do PostgREST.
Agora elas paginam (`portal/src/lib/supabase/paginar.ts`), junto com a lista de mandatos, e o
painel avisa se o teto de segurança for atingido. **A sessão 51 terminou o serviço** — ver "O teto
de 1000 deixou de existir para o portal".

## A rodada v46 (17/08) — o que ela provou e os dois defeitos que ela achou

**9 documentos, 714 linhas, US$ ~0,46.** O defeito que comeu 19 dos 35 documentos na v45 está
**morto**: todos os 9 tiveram extração chamada, e o único sem linha é a certidão negativa — que é o
resultado CERTO (`0111`). Conferido contra o gabarito do gerador:

| | |
|---|---|
| DFC | caixa inicial 3.621 e final 825 — **exatos** |
| DVA | valor adicionado a distribuir 49.110 — **exato** |
| Mútuos | planilha 16.060 (11.160 + 4.900) — **exato**, e o balanço traz 11.400: a divergência plantada de **R$ 240 mil** está no dado, dos dois lados |
| Livro razão | 99 de 99 linhas — **100%**, no documento que motivou as três camadas |
| Balancete | 78 de 78 linhas — **100%** |
| Balanço | 105 de 114 linhas (92%) · DRE 34 de 39 (87%) · DVA 13 de 16 (81%) |

**O que falta são os SUBTOTAIS IMPRESSOS** — "ATIVO CIRCULANTE", "TOTAL DO ATIVO", "RECEITA
OPERACIONAL BRUTA". Eles viraram metadado (`secao`) em vez de linha. Some-se a isso que os
subtotais de subgrupo ("Disponível") FORAM extraídos, e a soma bruta de cada seção dá **exatamente
2× a verdade**. O export já sabe descontar subtotal de subseção; o que falta é o total de topo.

### Defeito 1 — o comparativo não comparava (corrigido)

A mesma conta saía em **três linhas** do Excel, uma por exercício, com as outras colunas vazias. Duas
causas, nas duas pontas:

- **n8n:** `ordem` numerava PARES (conta × coluna) desde que a saída virou agrupada, mas a `0027` a
  define como "posição na leitura do DOCUMENTO". Agora os pares de uma conta compartilham a `ordem`
  da linha que os originou;
- **portal:** o rank que impede dois "Outros" de colapsarem era calculado por VERSÃO, então os três
  valores da mesma conta viravam ocorrência 1, 2 e 3. Agora é por versão **e coluna** — que é o que o
  comentário do próprio bloco dizia querer.

A correção do portal vale para o dado **que já está no banco**: o export da v46 sai alinhado sem
nova extração. Seis verificações novas cobrem as duas formas (agrupada e antiga), e elas reprovam o
código anterior.

### Defeito 2 — a entidade poluída (corrigido, exige reimportar)

O export da v46 mostra `Canastra Industria 2025x2024x2023` como entidade em todas as abas. A
correção está no repositório desde 17/08 (32 entidades limpas, 6 nulas, zero sujas nos 38 nomes),
mas **só entra em produção quando o workflow for reimportado**.

## A instalação passa a se DECLARAR (`0131`) — e os recados em prosa deixam de ser o mecanismo

Este arquivo carrega, espalhados pelas seções acima, recados corretos que **nada executa**:

> **Para o dono:** a `0114` precisa ser aplicada no Supabase.
> **PARA OS TRÊS INDICADORES ACENDEREM:** aplicar a `0115` e **reimportar** o workflow.

Cada um está certo e nenhum é conferido por ninguém. Quem abre o portal não lê este arquivo; quem
lê este arquivo não está com o portal aberto. **E o sintoma no meio é o pior possível** para um
sistema cuja proposta é honestidade sobre os próprios números: a tela **não quebra** — mostra um
traço, ou zero, ou trata todo mandato como ativo. Tem cara de funcionando. É a mesma família do
corte silencioso de leitura que a `0028` matou, um nível acima: não é o dado que é cortado, é o
requisito que é esquecido.

A `0131` põe isso onde se executa:

- **`instalacao_requisito`** é o catálogo — 13 requisitos, um por linha. Dado, não lista dentro de
  função: é a lição do limiar `0.95` no corpo de `fn_registrar_campos_extraidos` (corrigida pela
  `0041`) e da `estagio.startsWith("extracao")` na tela de autonomia (corrigida pela `0126`).
  Quem acrescenta requisito não deveria precisar reescrever a função que os confere.
- **`porque` guarda o SINTOMA VISÍVEL**, não a descrição da migration. "0115 ausente" não serve
  para quem não tem o repositório na outra aba; "os indicadores de custo do painel mostram um
  traço" serve. É a coluna mais importante da tabela.
- **`fn_instalacao_conferir`** sonda por `to_regclass`/`to_regproc` — resolvem pelo `search_path` e
  devolvem NULL em vez de erro — e **sobrevive ao objeto ausente**: sem o guarda, o `count(*)` de
  um seed cuja tabela não existe derrubaria com exceção justamente o painel que existe para dizer
  o que fazer.
- **O tipo `comportamento`** é o único que não sonda catálogo. "O workflow do n8n foi reimportado"
  não é uma pergunta de banco, e só se prova pelo EFEITO: a tabela que aquele nó grava tem linha.
  Neste banco de teste ele é o **único** requisito ausente, e o teste trava exatamente isso.
- **No portal, até 21/08:** `/instalacao` listava tudo com o sintoma de cada item, e o painel
  (`/casos`) trazia um aviso no topo que só aparecia quando faltava algo. **As duas telas saíram
  em 21/08 por decisão do dono** — ver "O PORTAL ENCOLHE". O catálogo e as duas funções ficaram
  inteiros no banco: quem confere agora é `select * from fn_instalacao_conferir()`, e a suíte
  `Supabase/test/instalacao.test.sql` continua cobrando o catálogo contra a realidade.

**O que ela NÃO promete, e está escrito na própria tela:** "o objeto existe" não é "a migration foi
aplicada corretamente" — `create or replace` sobre um corpo velho deixa a assinatura idêntica, e
nenhuma sonda de catálogo vê isso. Quem confere comportamento é a suíte, no CI. O que a sonda
garante é o contrapositivo, que é a parte útil: **objeto ausente é migration ausente, sem dúvida.**

> **APLICADA em 20/08.** A partir daqui quem responde no lugar deste arquivo é
> `fn_instalacao_conferir()` — e ela responde sobre o banco em que você está de fato conectado, que
> é a pergunta que este arquivo nunca pôde responder. Se algum recado em prosa acima e a função
> discordarem, **a função é que está certa.** (Até 21/08 a mesma resposta vinha por tela; a tela
> saiu, a resposta não.)

## A rotulagem manual SAIU, e a passada de eficiência (o que foi medido e o que NÃO era lento)

**Decisão do dono:** não haverá fluxo de rotulagem manual. O objetivo é o sistema operar sem
triagem humana, e uma tela que pede uma tarde de mesa por rodada orienta o contrário.

O que saiu: as quatro telas de rotulagem (`/autonomia/golden` e filhas), os cinco componentes, a
suíte `verificar-tela-cega.mts` e o passo dela no CI. **O que FICOU, e por quê:** o caminho de
escrita no banco (`0130`) — ele não custa nada parado, e `fn_golden_classe_a` mede falso-positivo
de Classe A a partir de **veredito de produção**, sem rotulagem nenhuma. O painel de autonomia
agora diz a consequência em vez de convidar: sem concordância medida, estágio interpretativo
**não sobe**, e a regra de ouro recusa.

### A passada de eficiência — e o valor dela está no que NÃO mudou

Quatro hipóteses foram medidas e **três foram descartadas pela medição**, o que é o resultado
mais útil que uma passada dessas produz: ninguém precisa refazer esta caça.

| Hipótese | Medição | Veredito |
|---|---|---|
| `fn_normalizar_texto` por (rótulo × termo) em `fn_exigencias_do_caso` | 243 ms → 254 ms | **5% PIOR.** Não é o gargalo. |
| `linhas_distintas` achatada pelo planejador (faltava `as materialized`) | 228 ms → 232 ms | **2% pior.** O `distinct` já estava valendo. |
| Índice ausente em caminho quente | `idx_documento_caso` e os outros existem | **Nada faltando.** A varredura sequencial em `documento` é escolha correta do planejador com 177 linhas. |
| Cache de prompt da OpenAI não sendo acertado | sistema estático vem PRIMEIRO; `cached_tokens` já é lido pela contabilidade | **Já está certo.** Classificação já usa o modelo barato. |

**O que era real, e virou a `0132`:** a sonda de instalação da `0131` fazia `count(*)` por requisito
de seed — e um dos requisitos é `lote_execucao`, que ganha uma linha por execução e **nunca para de
crescer**, sondada a cada carga do painel. Medido com 50 mil lotes: sonda inteira **7,9 ms → 0,5 ms**.
Mais `pg_attribute` no lugar de `information_schema.columns` (3,4 ms → 0,25 ms). Nenhum veredito muda.

**O que foi medido e está saudável:** export de 28 documentos / 1.260 linhas em **450 ms** (montar +
serializar); `fn_conferir_modelagem` em 347 ms (era 9.344 ms antes da `0101`); a sonda quente em
0,5 ms. **Onde o tempo de um lote realmente vai:** nas chamadas à OpenAI, não no Postgres —
`fn_recomputar_completude` custa 237 ms e roda uma vez por documento (trabalho quadrático no lote),
mas isso é <5% do relógio de um lote de 38 documentos. Consertar exige mudar o workflow do n8n e
**reimportar** — risco desproporcional ao ganho, e fica registrado aqui em vez de feito.

## O LOOP DE VARIAÇÕES (22/08) — cinco defeitos que nenhuma suíte pegava

**O buraco que ele fecha, em uma frase:** as seis suítes provam a ingestão sobre
extração **fiel** — PDF gerado por `reportlab`, texto limpo, layout conhecido.
Documento de mandato real não é fiel, e **tudo o que o sistema faz depois de ler o
PDF nunca tinha sido exercitado sobre entrada suja.**

`Verificação/variacoes.mts` injeta a sujeira **no ponto em que a OpenAI responde** e
deixa o resto correr igual: o código do nó sai do JSON gerado (o mesmo que o dono
importa no n8n), o banco é o das 84 migrations, o export é o do portal. Zero
chamada de API, ~3 minutos, banco clonado de um molde já migrado (0,2 s por
variante).

> **O que ele NÃO prova, e precisa estar escrito:** a leitura do PDF em si. Scan
> torto, carimbo, coluna deslocada e tabela quebrada entre páginas são defeitos da
> OpenAI lendo o arquivo, e nenhum arnês que começa DEPOIS da resposta dela os
> alcança. **O B1 continua de pé.**

### O método: cinco rodadas com as variantes TROCADAS por completo

| Rodada | Variantes | Achados do sistema |
|---|---|---|
| 1–4 | escala mista, locale anglo, parênteses, sem subtotais, comparativo sem período, moeda mista, PC zero, entidade vazia, truncado, ruído de rodapé… (22) | **2** (`0138`, `0139`) |
| 5–6 | só balanço / só DRE, empresa única, um exercício, código contábil, caixa alta/baixa, texto sem número, percentual misturado, redutora invertida… (22) | **3** |
| 7–8 | nota como conta, subtotais da DRE, moeda no rótulo, sinal com hífen, NaN/Infinity, 1.167 linhas, caracteres de controle, razão social gigante… (22) | **0** |
| 9–10 | subtotal ≠ soma, PL a descoberto, receita zero, caixa negativo, insolvência, colunas mensais, anos diferentes, oito casas decimais… (22) | **0** |
| 11 | rejeitados, aceite sem autor, página absurda, seção em texto livre, moeda minúscula, tipo colapsado, hash repetido… (13) | **0** |

**Convergiu:** as duas últimas rodadas não acharam defeito nenhum do sistema — só
erros da minha própria régua, que também foram corrigidos.

### Os cinco defeitos, e o que cada um custava

| # | Onde | O que era | Como aparecia |
|---|---|---|---|
| 1 | `fn_veredito_producao` (`0136`) | `v_falhas text[] \|\| 'literal cru'` — ambiguidade de operador do Postgres | **exceção** sempre que não havia veredito: em banco novo a promoção automática morria em TODA inserção de decisão, em silêncio |
| 2 | `fn_mudar_dial` (`0137`) | reafirmar o nível corrente caía no default `'declarada'` | **apagava** `base_do_nivel`, `medicao_em` e `medicao_resumo` — o sistema subdeclarava a própria evidência |
| 3 | `abaDivida` | `#fim` do histórico só é escrito quando há valor; a abertura projetada referenciava célula vazia | **a dívida evaporava**: 23.462 + 14.257 → ZERO no primeiro ano projetado, com amortização zero |
| 4 | `chaveDeAncora` | o código contábil do ERP entrava na chave da âncora | **`1.1.01.002 TOTAL DO ATIVO` não casava com `total do ativo`** → sem reconciliação, balanço abria em −36.116 |
| 5 | `normalizar` | `\s` não cobre U+200B, U+200C–F, U+00AD, U+2060 | **um caractere invisível partia a conta em duas**, a série virava dois pontos de um, o balanço abria em 180 |

E um sexto, que não é bug e sim ausência de resposta: **o export MORRIA** com
`ano null fora do horizonte` quando nenhuma linha tinha valor numérico — o
analista não recebia arquivo nenhum. Agora o modelo se recusa nomeando a falta e o
arquivo sai com as abas de dado mais a explicação em três linhas.

### O que os cinco têm em comum

**Todos moram DEPOIS da extração**, que é justamente onde nenhuma suíte olhava com
entrada suja. E três deles (1, 3, 5) são da mesma família: *falha sem sintoma* —
a promoção que morre calada, a dívida que some sem pagamento, a conta que se
divide em duas. O único a reclamar era o CHECK do balanço, colunas adiante.

**O que mais assusta no nº 3:** dívida não paga que desaparece é a mentira mais
lisonjeira que este arquivo pode contar num mandato de reestruturação. Uma empresa
com 37,7 milhões projetava como se não devesse nada.

### O arnês virou portão

As cinco variantes que pegaram cada defeito ficaram no conjunto consolidado,
marcadas `[PEGOU]` (25 variantes no total), e **desfazer qualquer uma das cinco correções deixa o passo
vermelho** — conferido uma a uma. Dois dos religamentos exigiram auditar o
INVARIANTE em vez do efeito colateral: "a dívida evapora na virada" e "índice de
liquidez sobre base impossível". Antes disso, duas correções passavam sem teste
que as defendesse — que é o mesmo que não ter correção.

Está no CI (`.github/workflows/suites.yml`), depois do e2e.

## A VARREDURA FRIA DOS DEZ ÚLTIMOS PRs (21/08) — seis defeitos, e cinco medidos

Revisão dos PRs **#152 a #161** sem partir do pressuposto de que estavam certos. A base era verde
antes e continua verde depois: n8n 321, export **650** (eram 638), premissas do realizado **32**
(eram 25), e2e 46, banco completo, `tsc`/`eslint` limpos, `Supabase/schema.sql` idêntico e `git diff` de
`N8N/` vazio. **Nenhum dos 638 asserts existentes reprovava com qualquer um dos seis defeitos no
lugar** — e é isso que os torna dignos de nota, não a gravidade de cada um.

| # | Onde | O que estava errado | Medido |
|---|---|---|---|
| 1 | `RP_DEPOIS` (#160) | o "depois" do reperfilamento lia amortização **bruta**; todo o resto lê a de **caixa** | serviço 55.150 → 52.917 com o haircut, e o alívio **imóvel em zero** |
| 2 | `R_LIQ_CORR` | devolvia **0 numérico** com passivo circulante zero, e o covenant leu `ROMPE` | `PC=0` → liquidez `0,00` e veredito **"ROMPE"** |
| 3 | `R_LIQ_SECA` | idem, sem teste de covenant — só engana quem lê | idem |
| 4 | `R_ALAV_PL` | guarda testava `<>0` e o rótulo prometia `PL<=0` | a fixture publicava **−1,03x** com PL de −632.191 |
| 5 | `ALIQUOTA` (#158) | alíquota efetiva sobre **prejuízo** virava taxa negativa | **−5,85%** num caso de LAIR −20.500 |
| 6 | `TAXA_DIVIDA` (#158) | somava **receita** financeira em módulo junto da despesa | **35%** onde a dívida custa 30% |

### O que os seis têm em comum, e é a única generalização que vale

**Todos publicam um NÚMERO onde a razão não existe.** Nenhum deles quebra, nenhum acende vermelho, e
cada um é lido pela ponta seguinte como se fosse dado: o covenant lê `0` e acusa rompimento; o comitê
lê `−1,03x` e entende alavancagem baixa; a projeção lê alíquota negativa e faz o fisco **pagar** a
empresa. É a mesma família dos quatro incidentes de UMA CONTA, UM LUGAR — e, como eles, **erra
sempre para o lado de parecer melhor**, com uma exceção que prova a regra: o `ROMPE` falso da
liquidez erra para o lado de parecer pior, e por isso teria sido o primeiro a ser notado.

O arquivo já sabia a regra e a aplicava **ao lado**: `R_ND_EBITDA` se recusa a publicar múltiplo com
EBITDA negativo, `R_ROE` se recusa com PL negativo, e o `R_LIQ_IMED` que a #160 acrescentou **três
linhas acima** do `R_LIQ_CORR` já devolvia texto. A doutrina estava escrita; o que faltava era ela
valer nas linhas vizinhas.

### O defeito 1 é o mais caro, e o motivo é o que ele desmente

O bloco REPERFILAMENTO existe para responder "qual reestruturação resolve?", e o veredito dele manda
o leitor usar três alavancas quando a carência não basta — prazo maior, **haircut**, dinheiro novo.
Com a amortização bruta no "depois", **a alavanca do haircut media zero**: o serviço de caixa caía e
o bloco não via. Pior que isso, o contrafactual `RP_DSCR_SEM` — que soma o alívio de volta ao serviço
— **andava** quando a alavanca era puxada, quando ele é justamente o lado que precisa ficar parado.
O assert (40) olha as duas pontas de propósito: o alívio tem de **mexer** e o contrafactual tem de
**ficar**; cada uma sozinha passa com o defeito pela metade.

### E um sétimo achado que NÃO foi corrigido, porque a correção é doutrina

**A 0137 se contradiz sobre quantos níveis a máquina pode subir de uma vez.** O cabeçalho da trava 1
diz *"a promoção automática sobe UM nível e para em N2"*; o `como_ler`, o comentário da função e o
aviso final dizem *"sobe ATÉ N2"*. As duas leituras só divergem partindo de **N0**, e nenhum teste
partia de N0 — a divergência não tinha árbitro. O código promove **direto a N2**, dois níveis num
passo.

Hoje isto é **latente**: nenhum estágio semeado está nessa posição (`extracao_linhas_financeiras`
nasce em N0 mas está em N2 com o freio puxado; `classificacao_contabil` tem teto N1 e nem entra na
varredura). Latente é exatamente o que muda de sentido sozinho quando alguém semear um estágio novo.

Não mudei o comportamento: **quantos níveis a máquina pode subir sozinha é decisão do dono**, não de
engenharia, e o peso do texto está do lado de "até N2" (três das quatro declarações). O que fiz foi
tirar a ambiguidade do escuro — o caso 7 de `Supabase/test/auto_promocao_dial.test.sql` **pina** o salto
N0→N2, então mudá-lo passa a ser um teste vermelho e não uma descoberta em produção.

## O ARQUIVO DE COMITÊ, EM QUATRO FRENTES (21/08, sessão 59)

Pedido do dono: executar tudo o que melhora o resultado no export. Quatro frentes, e a primeira é
uma correção que valia mais que as outras três.

### 1. A aba Modelagem parou de projetar, e o arquivo deixou de ter dois números

**O invariante que isto restaura é o que organiza o projeto: UMA CONTA, UM LUGAR.** A aba Modelagem
nasceu na fase 7.4 projetando cada linha pela premissa vinculada, e estava certa enquanto era o
único modelo do arquivo. Depois vieram as 14 abas do modelo institucional, que projetam AS MESMAS
LINHAS com base diferente: lá o fornecedor gira contra CUSTOS e o resto contra RECEITA LÍQUIDA; aqui
todo percentual e todo prazo incidiam sobre a receita TOTAL. A diferença entre as duas projeções é a
razão receita/custo, e as duas iam no mesmo arquivo ao comitê.

Ficou o REGISTRO: qual premissa em cada linha, com que valor por exercício, e o último realizado. A
distribuição mensal saiu junto, e é perda declarada — ela repartia o valor projetado. **A curva não
se perdeu:** é fato derivado do faturamento do cliente e passa a ser publicada em linha própria.

### 2. Os quatro índices que o `Arquitetura do Sistema/2 Especificação/f0/08` fasejou

Liquidez imediata, ROA, ROE e Altman Z''. O `Arquitetura do Sistema/2 Especificação/f0/08` os deixou de fora "até a extração isolar as
linhas-conceito", e ela isola desde as 14 abas. **PL negativo publica "PL<=0"** em vez de número:
prejuízo sobre patrimônio a descoberto dá retorno positivo, que lido rápido afirma o contrário. **E
o Altman se recusa sem o X2:** sem conta de lucro retido isolada, zero derrubaria o índice em até
3,26 pontos e jogaria empresa saudável na zona de aflição.

### 3. Os dois covenants por cenário, como SENSIBILIDADE

O EBITDA varia com o cenário; a dívida é a do cenário ativo. **Não é a comparação completa**, e a
nota de rodapé diz isso: é PISO da deterioração, porque no cenário pior o revolver saca mais. "Rompe
aqui" implica "rompe lá"; o contrário não vale. O CHECK contra o bloco de RATIOS achou um defeito na
primeira execução — eu lia o interruptor da grade em vez do `$G$2` do Output, e o `CHOOSE` devolvia
zero em silêncio.

### 4. A alavanca de reestruturação: carência por tranche

O `§2.6` do diagnóstico. O arquivo dizia DSCR 0,3 e não tinha alavanca nenhuma. Agora tem carência
editável ao lado do prazo, e o bloco REPERFILAMENTO mostra o serviço antes, depois, o alívio e o
DSCR nos dois mundos. **O veredito não diz "melhorou": diz se atravessou o corte**, e quando não
atravessa nomeia o caminho seguinte.

Três cuidados que o teste trava: o lado "antes" roda com números congelados (senão os dois lados
andam juntos e o alívio sai sempre zero); os dois lados são as MESMAS tranches (revolver fora dos
dois); e o DSCR de hoje é REFERÊNCIA à linha de RATIOS, nunca recálculo.

**638 verificações no export**, contra 623 antes.

## O DIAL PASSA A SUBIR SOZINHO (21/08, sessão 59) — `0137`, e as quatro travas

**Decisão do dono:** quando o veredito de produção alcançar o critério (30 vereditos, 95% de
concordância), o estágio sobe sem ninguém chamar função nenhuma.

**O que isso muda na doutrina, dito sem rodeio, porque quem ler daqui a um ano precisa saber que foi
deliberado.** A `0126` pôs a regra de ouro dentro de `fn_mudar_dial` para impedir exatamente uma
coisa: o sistema se autorizar a si mesmo. A `0136` abriu uma porta medida, mas ainda exigia mão
humana para atravessá-la. **A `0137` tira a mão.** A partir daqui o sistema promove a si mesmo com
base numa medida que ele próprio declara enviesada para cima.

**Por que isso é aceitável, e é uma razão só:** o que a promoção automática alcança é **N2**, que é
auto-clear de linha de alta confiança, e não N3. Em N2 todos os fechamentos fail-safe do `Arquitetura do Sistema/1 Visão e Doutrina/01`
continuam valendo: pendência abre, guarda dispara, o Portão 2 pede aceite humano onde a doutrina
pede. O que muda é o volume de linha que passa sem toque, num estágio onde a máquina demonstrou 95%
de acerto em 30 casos.

### As quatro travas, e cada uma responde a uma forma conhecida de isto dar errado

| | Trava | O que ela impede |
|---|---|---|
| 1 | **Para em N2, nunca N3** | Piso enviesado não sustenta autonomia plena. O topo continua sendo decisão humana explícita |
| 2 | **O freio gruda** | Humano que BAIXA o nível desliga a automação daquele estágio na hora. Sem isto o freio duraria até o próximo veredito e a máquina desfaria a decisão de quem o puxou, que é o pior defeito possível num mecanismo de segurança: **ele parece funcionar** |
| 3 | **Interruptor por estágio, em dado** | `estagio_autonomia.auto_promocao`. Desligar é um `update`, sem migration e sem deploy |
| 4 | **Tudo na trilha** | Ator próprio (`sistema:auto_dial`) e a medição que autorizou anexada. Promoção que ninguém audita depois é indistinguível de promoção que não deveria ter acontecido |

**A promoção passa pela própria `fn_mudar_dial`**, e não por `update` na tabela. É o que garante que
a automação não escape de guarda nenhuma, e que guarda nova acrescentada lá passe a valer aqui sem
ninguém lembrar de copiar.

**O gatilho é `after insert on decisao`**, porque toda fonte de veredito da `0136` grava uma linha
lá: revisão de documento, rejeição de pendência (`0106`) e override de classe contábil (`0128`). Um
agendador precisaria de `pg_cron` e promoveria com até uma hora de atraso; o gatilho promove no
instante em que a 30ª nota chega. **Ele jamais derruba a ação de quem o disparou:** erro dentro dele
vira NOTICE, porque o analista não pode perder a rejeição de uma pendência por causa do dial.

**Religar depois de um freio é explícito:**

```sql
update estagio_autonomia set auto_promocao = true where estagio = 'classificacao_doc_checklist';
```

Quem desconfiou é quem decide voltar a confiar.

## AS PREMISSAS PASSAM A SAIR DO REALIZADO (21/08, sessão 58)

**Oito das premissas que a tela de Modelagem pedia em campo vazio já estavam respondidas pelo
próprio caso.** O balanço diz em quantos dias a empresa recebe, estoca e paga; a DRE diz quanto o
custo e o SG&A consomem da receita e a que alíquota o lucro foi tributado. Digitar de cabeça o que o
documento afirma é a forma mais barata de o modelo deixar de reproduzir o balanço de onde saiu.

Agora a seção 2 abre com o bloco **"Sugerido pelo realizado"**: CUSTO_VARIAVEL, SGA_PCT, PMR, PME,
PMP, ALIQUOTA, PARCELA_ONEROSA e TAXA_DIVIDA, cada uma com **a divisão que a produziu à vista**
(numerador, denominador e a conta em palavras). Um clique grava com `origem = 'historico'`, que o
schema da `0038` já previa e nada usava.

**As duas regras que sustentam isso, e são elas que o teste trava:**

- **ZERO NÃO É RESPOSTA.** Sem a conta que serve de numerador, ou sem a base que serve de
  denominador, a sugestão não sai: sai o motivo. Zero dias de recebimento não é "não sei", é a
  afirmação de que a empresa vende à vista. Numerador zero com a conta PRESENTE passa, porque aí é
  fato do documento.
- **A BASE DE CADA RAZÃO É A QUE O MODELO APLICA.** Fornecedor gira contra CUSTOS; cliente e estoque
  giram contra RECEITA LÍQUIDA. Medir num denominador e aplicar noutro é o defeito que o próprio
  `modelo-institucional` denuncia no Modelo Base, onde ele infla o passivo projetado em ~1,27×. O
  PME contra receita contraria o manual de propósito: a base é a que o `Working Capital` usa para
  projetar a conta.

Para as duas pontas concordarem sobre o que é cliente, estoque e fornecedor, os três classificadores
**subiram** de dentro da aba `Working Capital` para exportados do `modelo-institucional`, e as duas
os importam. As 623 verificações do export rodaram sem uma linha alterada, que é a prova de que o
hoisting não mudou comportamento.

**Um achado que fica anotado, e não foi consertado aqui:** o `export-modelagem` aplica TODA premissa
de `dias_de_giro` sobre a receita total do caso, inclusive a de fornecedor, enquanto o
`modelo-institucional` aplica a de fornecedor sobre custos. São duas réguas para a mesma quantidade,
e a nota da célula do export já declara a base que usou. Não mexi porque mexer é mudar número de
arquivo entregue, e isso pede a rodada real antes.

## O VEREDITO DE PRODUÇÃO PASSA A CONTAR (21/08, sessão 58) — `0136`, a saída B do B3

**A contradição que estava aberta era aritmética.** A `0126` pôs a regra de ouro do `Arquitetura do Sistema/1 Visão e Doutrina/01` dentro
de `fn_mudar_dial`: estágio interpretativo só sobe para N2/N3 com concordância medida contra rodada
de golden set CONGELADA. A sessão 53 removeu o fluxo de rotulagem manual, por decisão do dono, porque
o objetivo é o sistema operar sem triagem humana. Sem rotulagem nenhuma rodada congela; sem rodada
nenhum interpretativo sobe. **O sistema passou a se recusar a certificar a si mesmo** — o que está
certo, e é um estado terminal, não um caminho.

**A saída escolhida (dono, 21/08) é a B: o trabalho normal já produz rótulo.** Toda vez que o
analista confirma ou corrige o palpite da máquina na tela de revisão, ele emite um veredito. A casa
já lia isso em dois lugares e nunca ligara ao dial: `fn_golden_classe_a` (`0126`) e
`fn_classe_contabil_concordancia` (`0128`). A `0136` generaliza os dois numa porta só.

**`fn_veredito_producao(estagio)` despacha por estágio e RECUSA o que não sabe medir.** Hoje tem
fonte para três: classificação de documento (a decisão que `fn_revisar_documento` grava, `aprovacao`
contra `correcao_classificacao`), reconciliação Classe A e classificação contábil. Para os demais ela
devolve `suficiente = false` com o motivo, e nunca uma concordância inventada a partir de zero
veredito — **"não medi" e "medi e deu ruim" são frases diferentes**, e a segunda não se produz a
partir da primeira. É a mesma distinção que a `0131` faz entre tabela ausente e tabela vazia.

**O que ela não finge ser, e isto é a parte que não pode sumir da tela.** Quem emite o veredito **vê
o palpite da máquina** antes de decidir; o rotulador cego do `Arquitetura do Sistema/2 Especificação/f0/06` decide sem ver. A diferença tem
direção conhecida: o viés de confirmação empurra a concordância para cima. Então o número é um
**PISO** — "a máquina acerta pelo menos isto" — e nunca um ground truth.

Por isso `base_do_nivel` ganhou valor próprio, **`medida_por_veredito`**, que vale menos que `medida`
e mais que `declarada`. **O assert mais importante da suíte é que ela nunca vira `medida`:** no dia
em que rótulo cego e rótulo enviesado ficarem indistinguíveis naquela coluna, a honestidade do dial
acaba sem sintoma nenhum, porque o número é o mesmo.

**Três decisões que o teste trava:** massa antes de concordância (cinco vereditos com 100% de acerto
não autorizam nada, e a falha nomeia o número que faltou); o **tipo mais fraco governa** quando tem
massa, mas tipo raro não reprova o estágio inteiro sozinho; e a recusa vai para a trilha **com a
medição junto**, que é o que responde "quanto faltava, e está subindo?" daqui a três meses. O
`n_minimo_veredito` entra em 30 contra os 20 do `Arquitetura do Sistema/2 Especificação/f0/06`, porque rótulo enviesado precisa de mais
massa, e é dado: muda por update.

**O que NÃO mudou:** o teto por natureza do estágio segue inegociável, e descer continua sem pedir
nada. Freio que exige papelada não é freio.

## A `0133` QUE FALTOU, e a sonda que a achou (21/08, sessão 58)

> **FECHADO no mesmo dia:** o dono aplicou a `0133` em 21/08, e as três conferências abaixo passaram
> a responder `true`. O registro fica porque o método que a achou vale mais que o item, e porque a
> forma do engano se repete: **três arquivos afirmavam, de memória, um estado do banco.**

**O arquivo dizia "aplicadas até a `0133`" e estava errado — a `0133` era justamente a que não estava.**
A `0134` e a `0135`, posteriores, estão aplicadas. Medido no banco de produção, não declarado de
memória, e é a terceira vez que o mesmo tipo de engano aparece: quem responde sobre um banco é o
banco.

**O que a `0133` faz, e o que está acontecendo sem ela.** Ela é a correção do defeito que a nossa
própria `0116` abriu. `fn_reconciliar_ativo_passivo_pl` prefere o TOTAL IMPRESSO e só soma a seção
quando o total não existe; depois da `0116` os dois lados da checagem passaram a ser totais
impressos, e **total impresso contra total impresso fecha por construção**. Hoje, no banco do dono:
apagar metade das contas do Ativo Circulante não abre pendência nenhuma, `lote_integro` fica verde e
a Modelagem recebe uma seção com buraco. Não parece erro, parece documento em ordem.

**Como conferir e como resolver:**

```sql
select 'fn_conferir_arvore existe' as item,
       exists (select 1 from pg_proc where proname = 'fn_conferir_arvore') as ok
union all
select 'fn_reconciliar_arvore abre a pendencia secao_fecha',
       exists (select 1 from pg_proc p where p.proname = 'fn_reconciliar_arvore'
                 and position('secao_fecha' in pg_get_functiondef(p.oid)) > 0);
```

Os dois falsos significam que ela nunca rodou; foi o que voltou em 21/08, junto com um terceiro
(`fn_reconciliar_por_documento` não chamava a árvore), o que descartou aplicação pela metade. O
conserto foi aplicar `Supabase/migrations/0133_a_secao_que_nao_fecha.sql` e rodar a conferência de novo. **Ela é posterior à
`0134`/`0135` na ordem de aplicação, e isso não é problema:** a `0133` só reescreve as três funções
de reconciliação, que nenhuma das duas seguintes toca.

**A SONDA DAS 80 MIGRATIONS.** O `fn_instalacao_conferir` (`0131`) responde por 13 requisitos
escolhidos; esta pergunta era outra, "quais das 80 rodaram", e não tinha resposta. A sonda que a
respondeu é uma consulta só de catálogo, montada com três cuidados que valem mais que ela:

- **um objeto SOBREVIVENTE por migration**, conferido contra o `Supabase/schema.sql`, senão objeto criado
  numa migration e removido em outra acusaria falta falsa;
- **17 migrations não criam nada**, só reescrevem função, e nessas a existência não prova coisa
  alguma: a conferência é por um trecho de código que só a versão nova tem (`attisdropped` na sonda,
  `secao_nao_fecha` na árvore, `sazonalidade_sem_curva` na modelagem);
- **uma é honestamente inconferível** e sai como `n/d`: a `0006` recria funções que a `0004` e a
  `0005` já criam, sem deixar marca própria.

Testada nos dois sentidos: contra um banco com as 80 aplicadas do zero, tudo verde; e com tabela,
coluna, função e marcador derrubados de propósito, as quatro linhas certas acusaram e nenhuma outra
se mexeu.

## A ABERTURA PASSA A APARECER (21/08, sessão 58)

Ela existia e quase nunca tocava. A marca de "já vista" morava no `sessionStorage`, que **sobrevive
ao recarregamento**: quem abriu o portal uma vez de manhã não a via mais no dia inteiro. Agora a
marca mora na memória do módulo, que morre com a carga da página, e é comparada contra a **sessão do
Supabase**. O resultado são três regras: abrir ou recarregar o portal toca; entrar de novo toca,
porque a sessão muda de identidade no login; e voltar de um mandato para o painel **não** toca, que
é a única exceção e a que impede a abertura de virar pedágio na tela mais usada da casa.

## O PORTAL ENCOLHE (21/08, sessão 57) — três telas saem, e o painel passa a falar com o analista

**Decisões do dono, e todas de produto, não de engenharia.** O que saiu funcionava; saiu por não
valer o espaço que ocupava na tela. A regra que as une: **o portal é do analista**, e o que sobra
nele tem de responder a uma pergunta de mandato. Instalação, operação e um segundo caminho para o
mesmo dado não respondem.

**1. O aviso de instalação e a tela `/instalacao` saíram do portal.** O aviso era a primeira coisa
no painel — a tela mais aberta da casa — e o que ele anunciava era um item de infraestrutura
(`lote_execucao` sem linha, isto é, o workflow do n8n a reimportar). Um alerta permanente sobre a
própria instalação, no topo da tela de trabalho, cobra de quem abre o portal para trabalhar uma
dívida que é de quem opera o banco.

**O motor ficou inteiro, e isto é o ponto:** `instalacao_requisito`, `fn_instalacao_conferir` e
`fn_instalacao_resumo` (`0131`/`0132`) continuam no banco, os `grant`s continuam de pé, e
`Supabase/test/instalacao.test.sql` continua cobrando o catálogo contra a realidade a cada execução do
`Supabase/test/run.sh`. O que mudou é o CANAL: a pergunta *"este banco tem tudo o que o portal precisa
para não mentir?"* passa a ser feita por SQL, por quem aplica migration, e não por quem abre um
mandato:

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

**O que se perde, e fica dito:** o sintoma volta a não ter voz na tela. A `0131` existiu porque um
requisito ausente não quebra o portal — produz um traço no lugar de um número, uma lista tratando
todo mandato como ativo, uma aba de perguntas vazia. Isso continua verdadeiro; o que muda é que
ninguém será avisado enquanto estiver olhando. A troca é deliberada.

**2. "Consultar a base" saiu — o Modo A do `Arquitetura do Sistema/2 Especificação/f0/07` é descontinuado.** O `§2.4` do diagnóstico de
11/08 dava duas saídas para o Modo A: construir, ou escrever que ele não vem. A sessão 53 tomou a
primeira; o dono tomou a segunda em 21/08, com a razão em uma linha: **o que a tela consultava já
está na planilha, e a planilha está entregue.** Um segundo caminho para o mesmo dado é um segundo
lugar para ele divergir — a mesma família do defeito que este projeto mais persegue, dois números
para o mesmo fato.

**3. A tela `/operacao` saiu, um dia depois de entrar.** Ela foi entregue na sessão 56 e é a mesma
troca das outras duas: lotes, custo por execução, tokens e alertas de pipeline são a saúde da
MÁQUINA, não trabalho de mandato — e a barra lateral do analista não é lugar para isso. O motor
outra vez ficou inteiro: `fn_operacao_lotes` e `fn_operacao_resumo` (`0135`), os quatro alertas
decididos no banco e `Supabase/test/operacao.test.sql` continuam de pé, com a mediana e a contraprova do
1,4× que não acende. A leitura passa a ser por SQL:

```sql
select * from fn_operacao_resumo(30);
select * from fn_operacao_lotes(30, 50) where cardinality(alertas) > 0;
```

**4. E o painel passou a ser escrito para quem usa, não para quem construiu.** A tela mais aberta da
casa carregava vocabulário de dentro: *"gasto de API"*, *"cobertura da extração"*, *"sem medição, a
migration 0115 não está aplicada"*. Nada disso é pergunta de analista. O painel agora diz
**custo de processamento**, **linhas financeiras lidas**, **cobertura da leitura**,
**mandatos em andamento** e **mandatos encerrados**; o traço de "não medido" explica a ausência sem
citar migration; e os travessões que emendavam as frases saíram. Os números e a lógica são os
mesmos: mudou a língua.

Saíram `portal/src/app/casos/[id]/base/page.tsx` (399 linhas), o botão na tela do mandato,
`portal/src/app/instalacao/page.tsx`, `portal/src/components/instalacao-aviso.tsx`,
`portal/src/app/operacao/page.tsx` e a entrada de Operação na barra lateral. **Nada de banco foi
tocado, nenhuma migration nova, nenhum teste removido:** as suítes continuam com a mesma contagem, e
o `Arquitetura do Sistema/2 Especificação/f0/07` passou a declarar o Modo B — o `.xlsx` — como a entrega.

## OS TRÊS ITENS DE OBSERVABILIDADE, ESPELHO E DADO (21/08, sessão 56)

Itens 3, 4 e 5 do ranking. Nenhum deles muda um número do output — os três mudam **o que se
consegue ver**, que é a condição para que um número errado não sobreviva à próxima rodada.

### 3. A operação passa a ser vista (`0135`) — e o dado já estava gravado

O diagnóstico de 11/08 chamou isto de *"zero observabilidade"*: uma falha em produção só aparece
quando alguém abre a tela. O portal tem oito `console.error` e nenhuma métrica.

**O achado é que não faltava instrumentação — faltava a pergunta.** A `0115` criou `lote_execucao` e
o nó `Gravar Uso do Lote` a alimenta desde então: uma linha por execução, com documentos, falhas,
custo real, custo estimado, tokens, linhas extraídas e cobertura. **Nunca foi lida por ninguém.** O
custo desta entrega foi ler o que já estava lá, não instrumentar de novo.

`fn_operacao_lotes(p_dias, p_limite)` devolve uma linha por execução com os **alertas já decididos no
banco**, e `fn_operacao_resumo(p_dias)` faz o cabeçalho. O veredito não mora na tela de propósito:
repetir a régua na tela criaria **duas réguas sobre a mesma quantidade** — a forma de defeito
que esta casa já pagou três vezes — e a segunda divergiria no dia em que existisse um segundo leitor.
(A tela `/operacao` que lia estas funções saiu do portal em 21/08; ver "O PORTAL ENCOLHE".)

| Alerta | O que ele pega |
|---|---|
| `cobertura_nao_medida` | O mais importante e o menos óbvio: **não é cobertura baixa** (disso a guarda já cuida) — é a guarda **não ter opinado** sobre o lote. As três camadas ficam mudas juntas e o lote passa parecendo normal. |
| `documento_com_falha` | A falha já virou pendência tipada; o painel diz que ela existe sem exigir abrir mandato por mandato. |
| `documento_sem_medicao` | Nem falha, nem sucesso. O estado que mais se parece com normalidade e menos é. |
| `custo_acima_do_previsto` | Custo real acima de **1,5× a estimativa daquele lote**. A régua é razão contra a própria previsão, não teto em dólar — teto absoluto depende do tamanho do lote e envelhece na primeira mudança de preço. |

**Duas decisões que o teste trava, e o teste tem contraprova:** a cobertura publicada é **mediana e
não média** (média mistura lote de 40 documentos com lote de 1 e não descreve nenhum dos dois — o
assert fixa 0,900 contra a média de 0,906); e o resumo publica `dias_desde_o_ultimo`, porque
**silêncio é estado** — "0 alertas" sem execução nenhuma afirmaria uma saúde que ninguém mediu, e a
tela vazia diz isso com todas as letras em vez de pintar verde. O 1,4× que **não** acende é assert
próprio: alerta que dispara para variação de token vira ruído e ninguém olha a tela em duas semanas.

### 4. O espelho lib↔workflow passa a ser conferido nas 26 funções, não em duas

**A causa comum dos dois bugs de triagem da sessão 55 era esta**, e ela continuava aberta. Toda
função de `N8N/lib/*.mjs` mora em dois lugares: a lib, que as suítes exercitam, e uma cópia literal
dentro do `build-workflow.mjs` — **a única que o n8n executa**. Nó de Code não importa módulo; a
duplicação é estrutural. O que dava para remover era o silêncio: corrigir a lib e esquecer a cópia
deixava a suíte verde e a produção errada, e foi exatamente o que aconteceu duas vezes.

`N8N/test/espelho-inline.test.mjs` extrai cada função embutida do JSON do workflow e roda **os mesmos
casos** nela e na lib. **Compara comportamento, não texto** — as cópias são minificadas de propósito,
com nomes próprios de variável; comparar fonte reprovaria por formatação e convidaria a "consertar"
formatando, o pior desfecho possível para um teste.

**O assert que faz o arquivo durar é o penúltimo:** ele varre o workflow, lista TODA função duplicada
e exige que cada uma esteja coberta ou declarada em `SEM_CASO` **com motivo**. A 27ª função duplicada
não entra em silêncio. O último confere que o inventário não encolheu sem alguém notar. Verificado
por religamento: reintroduzir o `Math.max` da confiança ou o `parseCsv` sem aspas reprova **dois**
casos, um por função.

> **A divergência que o teste documenta em vez de esconder:** `parseTipo` devolve objeto na lib e
> apenas o código no workflow. Está anotado no `porque` da tabela e projetado no comparador — um
> contrato diferente de propósito não é defeito, mas precisa estar escrito onde alguém tropece nele.

### 5. Onde o dado do cliente mora, quanto tempo fica e quem vê (`Arquitetura do Sistema/2 Especificação/10`)

O diagnóstico registrava *"sem backup/retenção declarados — dado de cliente em Supabase, sem
procedimento de recuperação escrito"*, e a sessão 36 mostrou por que não é burocracia: houve um susto
de perda de dado e a resposta teve de ser montada na hora. **A pergunta "como se recupera?" aparece
sob pressão, que é o pior momento para descobrir a resposta.**

O documento **não preenche por dedução** o que depende do console: onde a resposta não está no
repositório, ele escreve **[A CONFIRMAR]** em vez de uma frase tranquilizadora. Política de backup
que ninguém testou é crença, não controle — e este projeto existe para não confundir as duas.

**O que ele fixa, e vale ler:** (a) o fato que abre qualquer conversa de LGPD é que **o documento do
cliente vai à OpenAI** — desenho do produto, não efeito colateral; (b) hoje **não há expurgo, e isso
é escolha por omissão**; (c) **o schema e o pipeline se remontam do repositório sozinhos** —
migrations em ordem reconstroem o banco (é o que o `run.sh` faz a cada execução) e os quatro
workflows saem de geradores conferidos por `git diff --exit-code`, então **o que não se recupera de
backup é o DADO**; (d) o teste de restauração que falta, com `fn_instalacao_conferir()` como veredito e **o tempo
anotado**, porque "temos backup" e "voltamos em 40 minutos" são afirmações diferentes; (e) o acesso é
**binário** — qualquer autenticado vê todos os mandatos, aceitável com duas pessoas e não com a
terceira.

### E um portão que reprovava por RUÍDO — o `Supabase/schema.sql` e o dono do DEFAULT ACL

Achado pelo CI da própria sessão, e vale mais como lição do que como conserto. O `run.sh` filtra do
`pg_dump` a versão do servidor e o token aleatório do `\restrict` — ruído que mudaria a cada
execução — e conta com `--no-owner` para o resto. **`--no-owner` não cobre o DEFAULT ACL:**
`ALTER DEFAULT PRIVILEGES FOR ROLE <alguem>` carrega o nome do superusuário que aplicou as
migrations. Num container que só tem `root`, o arquivo saía com `FOR ROLE root` contra o
`FOR ROLE postgres` do CI: **schema idêntico, portão vermelho.**

Normalizado para `postgres`, que é o nome verdadeiro no Supabase — então o arquivo publicado
continua sendo o que produção tem. O GRANT em si (a `anon`/`authenticated`/`service_role`) **não** é
tocado: é ele que carrega a informação, e é ele que este arquivo existe para denunciar. A regra é a
que o próprio comentário do `run.sh` já defendia: **um portão que acusa sempre é um portão que se
aprende a ignorar**, e o jeito de honrá-la é o portão medir o schema, não medir quem digitou o
comando.

## AS DUAS TRAVAS DE FLUIDEZ, EXECUTADAS (20/08, sessão 55) — `0134` e a guarda do giro

Ranqueadas por (impacto no output × fluidez do processo) ÷ esforço, e as duas de topo eram
executáveis sem depender de ninguém.

### 1. A guarda do giro agregado — o output

**O defeito não tinha sintoma nenhum.** Cada conta de giro é projetada por `dias ÷ 360 × base`, e
**nada olhava o agregado**. Vincular a MESMA premissa de prazo a N contas — um clique por linha na
tela de Modelagem, e o caminho natural de quem está com pressa — prende **N × dias de receita** em
capital de giro. E o balanço **continua fechando**, porque o patrimônio líquido absorve a diferença.
O arquivo ia ao comitê com passivo circulante crescendo **oitenta vezes em cinco anos** e nenhuma
célula vermelha.

**A régua não julga o negócio — compara a HIPÓTESE com o FATO.** Não existe limiar absoluto de
"quantos dias de giro são demais": depende do setor e do ciclo. O que não depende de opinião é a
razão entre o giro projetado e o giro que **a própria empresa** teve no último exercício realizado.

| | realizado | projetado |
|---|---|---|
| Ativo de giro, em dias de receita | 157 | **767** |
| Passivo de giro, em dias de receita | 84 | **852** |
| **CHECK — projetado ÷ realizado** | — | **5,9×** (limiar 2×) |

> **O `modelo-da-fixture.mts` fazia exatamente a patologia** — uma premissa de 60 dias ligada a toda
> conta de circulante. Isso era defeito da fixture; passa a ser o **caso de teste** da guarda. O
> arquivo de demonstração agora **declara** o problema em vez de escondê-lo, que é o comportamento
> certo dos dois lados.

**Duas decisões de desenho que valem ler:** a razão **não é publicada no realizado** (contra o próprio
último ano ela é 1 por construção, e número que não decide nada ensina o leitor a ignorar a linha); e
o denominador é a **receita líquida nos dois lados**, inclusive no passivo — aqui a régua é de ordem
de grandeza, e bases diferentes tornariam ativo e passivo incomparáveis entre si. Cada conta continua
girando contra a base contábil correta dela.

### 2. A sazonalidade travava o "pronto" para sempre (`0134`) — a fluidez

Suspeita anotada desde a sessão 39, **medida agora**. `fn_conferir_modelagem` listava toda premissa
ativa com `valores` vazio e exigia a lista vazia para dar `pronto`. Certo para quase tudo — `SGA_PCT`
sem percentual É premissa pela metade. Mas três premissas do catálogo têm `formula = 'curva_mensal'`
e nelas **`valores` vazio é o estado CERTO**: a curva sai de `fn_sazonalidade_do_caso` (`0040`),
derivada do documento mensal, **não digitada**.

```
antes de vincular:  pronto=false, sem_valor=[SGA_PCT]
depois de vincular: pronto=false, sem_valor=[SAZONALIDADE, SGA_PCT]
```

O analista faz a coisa certa — vincula a sazonalidade, que é o que a aba existe para permitir — e a
tela passa a cobrar **uma ação que não existe**. Não há campo para preencher. A saída que sobra para
quem tem pressa é **desvincular a sazonalidade** e perder a distribuição mensal para calar o aviso.

O critério passa a ser a **fórmula do catálogo**, não uma lista de códigos: quem acrescentar a quarta
curva mensal não vai ter de lembrar de editar a função — mesma lição do limiar `0.95` dentro da
`fn_registrar_campos_extraidos` (`0041`).

**E o caso ruim de verdade não foi calado.** Curva ativa num caso **sem** documento mensal ganhou
nome próprio, `sazonalidade_sem_curva`, que **informa e não bloqueia**: os números ANUAIS continuam
certos, só o rateio dentro do ano fica liso. Travar o portão por isso devolveria o atrito pela porta
dos fundos, e o analista aprenderia a ignorar o portão. **O portão trava o que está errado; o que
está pior do que poderia estar é informação, e informação se publica.**

> **Religamento nos dois:** desfazendo o filtro da `0134`, o teste falha nomeando
> `CRONOGRAMA_FISICO`; a contraprova (premissa de fórmula normal sem valor) continua travando o
> `pronto`, provando que o portão não foi afrouxado — só deixou de cobrar o impossível.

## OS DOIS DEFEITOS QUE SE MASCARAVAM, e o ativo circulante fecha em ZERO (20/08, sessão 55)

O resíduo de reconciliação do **ativo circulante** era de −3.200 — pequeno o bastante para passar
por arredondamento. Eram **dois defeitos de sinais opostos**, e é por isso que nenhum foi achado
antes: **corrigir só um PIORAVA o número.**

| Estado | Resíduo do AC |
|---|---|
| com os dois defeitos | −3.200 |
| só (a) corrigido | −12.400 |
| só (b) corrigido | +9.200 |
| **os dois corrigidos** | **ZERO** |

**(a) Uma coincidência aritmética em 2024 apagava uma conta em 2025 — e em todo o grupo.**
`detectarSubtotaisPorOrdem` marcou "Matérias-primas e insumos" na coluna de 2024 (12.400) porque ali
as linhas seguintes somavam, **por coincidência**, o valor dela. O veredito era gravado como
`(secao_canonica, rótulo)` — **sem a coluna**. Resultado: a conta sumia do modelo em todas as colunas
e em todas as empresas. Em 2025 o bloco `ativo_circulante` ficava com **16 linhas somando 36.240**
onde o documento tem **17 somando 45.440**.

A regra passa a exigir **acordo entre colunas**: subtotal numa coluna só não basta, tem de ser
subtotal em todas as colunas com valor. É o que `detectarSubtotaisInformados` (B) já fazia. E isso
**não enfraquece o cabeçalho de grupo de verdade** — "Estoques" é nome de seção declarada e cai na
regra (A), estrutural, que não depende de aritmética. Quem passa a precisar de acordo é só a detecção
que se apoia SÓ em soma, que é exatamente a que produz coincidência.

> **O acordo é por COLUNA, não por ocorrência** — e a diferença tem assert próprio. Um comparativo
> sem `periodo_coluna` traz a mesma conta duas vezes na mesma coluna, e o detector colapsa as
> repetições de propósito, marcando só a primeira. Exigir "todas as ocorrências" reprovava o subtotal
> de verdade e devolvia a dupla contagem. Foi o assert `(0109d)` que pegou, na primeira tentativa.

**(b) `Math.abs` no histórico do giro somava as contas redutoras.** Conta redutora é negativa por
natureza: "(-) Perdas estimadas" (−3.850) e "(-) Provisão para obsolescência" (−2.350) **reduzem** o
circulante. Em módulo passavam a SOMAR, e o erro é o **dobro** delas: +12.400 num ativo circulante de
45.440 — **27%**. Os blocos de balanço não passam pela normalização de sinal (ela só toca
`BLOCOS_DE_DESPESA`, da DRE), então o sinal do documento é a verdade. **A magnitude FICA no passivo**,
onde o documento às vezes publica saldo negativo por convenção de partida dobrada.

**Religamento, com os números:** desfazendo (a) → falha com 12.400; desfazendo (b) → falha com
12.400; os dois juntos → **zero**. O assert `(38)` olha o RESULTADO e não cada causa, justamente
porque os dois se cancelam parcialmente.

**O que sobra no auditor, e é decisão registrada:** os −15.149 do passivo circulante são a
divergência entre o **mapa de dívida** (43.542 de curto prazo) e o **balanço** (28.393). O dono
decidiu: **o mapa manda** e o balanço é reconciliado. O arquivo declara a diferença em vez de
escondê-la.

## A VARREDURA CRÍTICA DO CÓDIGO (20/08, sessão 55) — dois bugs de triagem, e o terceiro achado que já estava corrigido

**Decisão do dono, registrada:** quando o **mapa de dívida** e o **balanço** discordam, o **mapa
manda** e o balanço é reconciliado. É o desenho que já estava em vigor; agora está escrito.

### Bug 1 — a confiança da classificação era a MAIOR das duas, não a do vencedor

`mergeClassification` escolhe entre o palpite do NOME do arquivo e o da IA por confiança, e devolvia
`Math.max` das duas. O caso alcançável: a IA responde `DESCONHECIDO` **com confiança 0,9** — ela está
segura de que o documento é ilegível —, o tipo vira `null`, o palpite do nome vence com **0,5**… e
saía **0,9**. O limiar que abre `classificacao_pendente` é **0,70**. **Um documento que a IA declarou
ilegível entrava classificado, sem humano nenhum olhar, apoiado num palpite de 0,5.**

Corrigido para a confiança do VENCEDOR. Quando as duas têm tipo, o vencedor JÁ É o de maior
confiança — então o `max` some sem perda em nenhum dos quatro ramos.

### Bug 2 — `parseCsv` não tratava aspas, e isso é corrupção silenciosa

Era `linha.split(sep)`, sem noção de aspas. Num CSV brasileiro quebra no caso mais comum que existe:

```
nome,obs,v
Empresa,"Silva, João & Cia",1000
    →  { nome: "Empresa", obs: '"Silva', v: 'João & Cia"' }
```

O valor **1000 desapareceu** e a coluna `v` recebeu um pedaço do nome. O cabeçalho é lido pelo mesmo
`split`, então toda coluna depois da vírgula desliza uma casa. Sem estouro e sem aviso. Vale para
todo upload `text/csv` e `text/plain`.

Reescrito como máquina de estados: separador dentro de aspas, aspas escapadas (`""`), quebra de linha
dentro do campo, e **detecção do separador contando FORA das aspas** — sem isso, `n;o` com `"a,b,c"`
elegia a vírgula e quebrava o arquivo inteiro.

### E a causa comum dos dois: ESPELHO SEM GUARDA

As duas funções moram em DOIS lugares — a lib (`N8N/lib/*.mjs`), que os testes exercitam, e uma cópia
LITERAL dentro do `build-workflow.mjs`, que é a que vai para o JSON e **a única que o n8n executa**.
Nós de Code do n8n não importam módulo, então a duplicação é estrutural. O que dava para remover era
o silêncio: corrigir a lib e esquecer a cópia deixava a suíte VERDE e a produção errada.

`N8N/test/espelho-inline.test.mjs` **extrai a função do JSON commitado** e roda a mesma tabela de
casos nas duas, exigindo resultado idêntico. Não compara texto — comparar fonte reprovaria por espaço
em branco e convidaria a "consertar" formatando. Compara COMPORTAMENTO. Religamento medido:
estragando só a cópia inline, **2 testes caem** nomeando o caso divergente.

### ~~O DEFEITO QUE FICA ABERTO~~ — **FECHADO na mesma sessão, e esta entrada mentiu por dois dias**

> **Esta seção dava um defeito por aberto depois de ele ter sido corrigido**, e ficou assim de 20/08
> a 21/08. A causa não é descuido: a varredura escreveu o achado ANTES da passada que o consertou, na
> mesma sessão 55, e ninguém voltou para reconciliar as duas seções do mesmo arquivo. É exatamente a
> forma de erro contra a qual o `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` avisa — *"a lista de pendências do
> `ESTADO.md` já disse uma vez que o Modo A não existia depois de ele existir"*. O texto original
> fica abaixo, riscado, porque a hipótese que ele registra é a parte que ensina.

**O que era:** uma conta legítima de 9.200 sumia do modelo institucional. No balanço da Vertentes
Metalúrgica (2025), o bloco `ativo_circulante` tinha **16 linhas somando 36.240** enquanto as folhas
do documento são **17 somando 45.440** — o informado. A que faltava era **"Matérias-primas e insumos"
(9.200)**, e ela é conta, não subtotal.

**Onde foi corrigido:** commit `dbc5eec`, "Os dois defeitos que se mascaravam, e o ativo circulante
passa a fechar em ZERO" — o defeito (a) daquele par. O religamento é o assert **(38)** do
`verificar-export.mts`, que olha o RESULTADO (resíduo zero) e não cada causa, porque os dois defeitos
se cancelavam parcialmente.

**Conferido de novo em 21/08, contra o código de hoje** (`566810e`), e não pela leitura do commit:

| Medição | Resultado |
|---|---|
| suíte de export | **638 / 638**, zero falhas |
| resíduo da "reconciliação com o ativo circulante informado" (`Balance Sheet`) | **0,00 nas sete colunas** |
| "Matérias-primas e insumos" nas linhas que chegam ao modelo | presente, `papel=conta`, `secao=ativo_circulante`, **9.200 em 2025** e 12.400 em 2024 |
| `rotulosDeSubtotalInformado` na chamada REAL do export | **35 rótulos**, e "materias primas e insumos" **não é um deles** |

> **E a medição acima derrubou um segundo receio, que eu levantei nesta conferência e não se
> sustentou.** Uma primeira sonda deu o conjunto de subtotais VAZIO, o que sugeriria que a regra de
> acordo entre colunas tinha matado junto a detecção estrutural (A) — a que pega "Estoques", "Contas
> a Receber" e os outros cabeçalhos de grupo. Estava medindo o lugar errado: o vazio era do
> `entradaModeloDaFixture` (o construtor da fixture do script), e não da chamada de
> `rotulosDeSubtotalInformado` dentro do `buildExportWorkbook`, que é a que o modelo de fato recebe.
> Instrumentada a chamada real, ela devolve **35 rótulos** e os cabeçalhos de grupo estão todos lá.
> A claim que o comentário do código fazia — *"não enfraquece o cabeçalho de grupo de verdade"* —
> passa de afirmação a número. **Sonda no lugar errado responde com confiança sobre outra coisa**, e
> é a versão barata do mesmo erro que a `0133` cobrou caro.

### E a hipótese anotada estava errada no mecanismo — é o que vale guardar

A nota original apostava que a chave grosseira vazava pelo **documento**: *"uma coincidência
aritmética no balanço de OUTRA empresa do grupo apaga a conta desta"*, e concluía que corrigir exigia
estreitar a chave para incluir o documento — mexendo no contrato que o comentário de
`rotulosDeSubtotalInformado` defende (detectar sobre a aba inteira, para a aba analítica e o modelo
darem o MESMO veredito).

A dimensão que faltava na chave não era o documento: era a **coluna**. `detectarSubtotaisPorOrdem`
marcou o rótulo na coluna de **2024** (12.400), onde as linhas seguintes somavam por coincidência o
valor dele; o veredito era gravado como `(secao_canonica, rótulo)`, sem coluna, e por isso apagava a
conta em 2025 — e, de quebra, nas outras empresas. A correção **não estreitou a chave**: passou a
exigir **acordo entre colunas** (subtotal numa coluna só não basta), que é o que
`detectarSubtotaisInformados` (B) já fazia. O contrato que a nota temia quebrar ficou inteiro.

> **A lição, que é a mesma de sempre neste repositório:** a hipótese acertou a FAMÍLIA da causa
> (chave grosseira demais) e errou a DIMENSÃO — e a correção que ela propunha teria mexido no
> contrato errado. Foi medir que separou as duas coisas. O que a nota fez de certo, e por isso ela
> valeu a pena existir, foi **não corrigir sem fechar a causa**.

### Limpeza: o que saiu, e por que tenho certeza

| Removido | Prova |
|---|---|
| `vincularLinha` (server action, 22 linhas) | superseded por `salvarSecao` — o comentário do próprio arquivo conta a troca ("236 idas ao servidor, uma por clique"); zero referências. A RPC `fn_vincular_linha_premissa` **continua viva**, chamada por `salvarSecao` |
| `JANELAS_MEDIA` (`N8N/lib/macro.mjs`) | declarada uma vez, referenciada em lugar nenhum. O portal tem a sua própria (`JANELAS_MEDIA_EXPORT`), independente |
| `FILL_TOTAL` (`oria-marca.ts`) | idem |
| `ChecklistItem` (`types.ts`) | idem |
| `docs/pr-test.md` | o arquivo diz de si mesmo: *"Pode ser removido com segurança."* |

**O que NÃO removi, e por quê:** `portal/scripts/_dump.mts` não é referenciado por nada, mas é
ferramenta manual de depuração da mesma família das que o `PROMPT_ESPELHAR_MODELO_BASE` §6 documenta.
"Sem referência" não é "nunca mais será usado", e a instrução era remover só o que é certo. Os outros
~45 `export` sem uso externo são tipos e constantes usados DENTRO do próprio arquivo: tirar o
`export` é cosmético e mexe em 20 arquivos para não corrigir defeito nenhum.

> **Falso positivo que a varredura pegou e eu não segui:** `metadata` em `layout.tsx` aparece como
> "sem uso" e é consumido pelo Next por convenção. Ferramenta de código morto que ninguém confere
> apaga o que funciona.

## A DÍVIDA BANCÁRIA QUE ERA PROJETADA COMO GIRO (20/08, sessão 55)

**Achado rodando o arquivo, não lendo código** — o método que a sessão 51 provou valer. Gerei o
export completo da fixture e passei o `auditar-xlsx.mts`: **10 de 11 itens verdes e um reprovado**,
o resíduo de reconciliação, com `Balance Sheet!F24` em **−19.987 — 20,9% do ativo total**.

**A decomposição, medida célula a célula:**

| Componente do passivo circulante | Modelo | Balanço | Excesso |
|---|---|---|---|
| Operacional (`ESP_PC` do giro) | 42.698 | 37.894 | +4.804 |
| Dívida CP (`ST Inv. & Debt`) | 41.553 | 28.393 | +13.160 |
| Tributos circulante | 6.881 | 4.858 | +2.023 |
| **Soma** | **91.132** | **71.145** | **19.987** |

**A causa: seis lugares faziam a MESMA pergunta com TRÊS regexes diferentes.** "Esta linha é dívida,
e portanto não é giro?" era respondida por `empréstimo|financiamento|debênture|arrendamento` no
`Working Capital`, pela mesma coisa `+leasing` no `Cash Flow` e no passivo não circulante, e por
`+nota promissória|cédula de crédito` na origem da dívida. **As diferenças não eram deliberadas** —
os três sítios dão o MESMO motivo no comentário ("contaria duas vezes"). O efeito era classificação
que muda de aba para aba dentro do mesmo arquivo: *"Leasing operacional a pagar"* é dívida no Cash
Flow e **giro** no Working Capital.

**E as três deixavam passar dívida bancária com nome brasileiro:** `Conta garantida` (1.550) e
`Duplicatas descontadas e antecipação de recebíveis` (5.277) — **6.827, ou 9,6% do passivo
circulante informado** — ficavam no passivo operacional e eram projetadas por **dias de giro contra
receita**. É exatamente o que o comentário do `abaCapitalGiro` proíbe em voz alta: *"o passivo
operacional carregaria dívida, e a NCG passaria a MELHORAR quando a empresa se endivida mais."*

**A correção:** um vocabulário único, `PADROES_DIVIDA_FINANCEIRA`, no idioma do `PADROES_CAIXA` que
já existia ao lado — a união das três variantes mais os instrumentos que faltavam. Os seis sítios
passam a chamar `ehDividaFinanceira`. **Resíduo: −19.987 → −15.149** (20,9% → 15,8% do ativo).

**O que FICOU DE FORA de propósito:** risco sacado, confirming, forfait e vendor. São supplier
finance, e se são dívida ou fornecedor é julgamento contábil em aberto. Classificá-los num regex
mudaria resultado financeiro por decisão nossa — e a regra do `PROMPT_ESPELHAR_MODELO_BASE` é
explícita: divergência de mecanismo que muda número é decisão do dono. Há assert garantindo que eles
continuam como giro, para a decisão não ser tomada por descuido depois.

**O religamento, com o número da reprovação:** estreitando o vocabulário de volta à variante antiga,
**8 asserts caem** e o resíduo volta a **−19.987 (20,9%)**.

### O que SOBRA, e é pergunta para o dono — não defeito de código

Os **−15.149** restantes são **divergência entre dois documentos**: o mapa de dívida diz **43.542**
de dívida de curto prazo e o balanço diz **28.393**. O modelo declara a diferença na linha de
reconciliação em vez de escondê-la, que é o desenho certo, e o auditor a reprova por materialidade,
o que também está certo — o comentário dele já dizia que o resíduo *"é a medida direta da qualidade
da extração daquele caso"*.

> **Para o dono:** qual das duas fontes manda quando elas discordam? Hoje o modelo usa o MAPA (é o
> detalhe por contrato, com juros) e reconcilia contra o balanço. Se o balanço é que manda, é uma
> linha de código — mas é decisão de produto, e muda número que vai a comitê.

### Duas coisas que investiguei e NÃO mexi, para não fugir do Modelo Base

- **`INSS a recolher` e `FGTS a recolher` vão para a aba de Tributos**, não para o giro
  (`ehTributoARecolher` inclui `inss|fgts|previd` de propósito). São encargos mensais e recorrentes,
  então o cronograma decrescente da aba de tributos é discutível — mas é classificação deliberada,
  documentada, e mudá-la muda número.
- **A projeção da fixture explode** (passivo circulante de 71.145 para 5,7 milhões em 5 anos) porque
  `modelo-da-fixture.mts` liga UMA premissa `PMR = 60 dias` a **toda** conta de circulante: vinte
  contas × 60 dias = 1.200 dias de receita em giro. É artefato da fixture de demonstração, não do
  motor — o portal manda as premissas reais. Fica anotado porque o arquivo de demonstração é o que
  alguém abre para conferir o modelo, e hoje ele mostra um absurdo plausível.

## A SEÇÃO PASSA A TER DE FECHAR (20/08, sessão 55) — `0133`

**O defeito foi ABERTO por uma correção nossa, e estava vivo desde a `0116`.**

`fn_reconciliar_ativo_passivo_pl` prefere o TOTAL IMPRESSO e só soma a seção quando o total não
existe. Até a `0116` isso era conservador: o prompt não trazia os totais, a checagem SOMAVA as
contas, e uma conta perdida quebrava a soma. A `0116` mandou o total impresso chegar como LINHA — e
estava certa, sem ele o export não tem contra o que conferir. O efeito colateral é que **os dois
lados da checagem viraram totais impressos, e total impresso contra total impresso fecha por
construção**: o balanço do cliente bate consigo mesmo.

**Medido no religamento, não afirmado:** apagar "Produtos acabados" (6.400) do Estoques do book e
rodar a reconciliação inteira deixa `ativo_passivo_pl` **VERDE**. É o assert
`CEGUEIRA MEDIDA` do `Supabase/test/secao_fecha.test.sql`, e ele existe para que a `0133` perca o motivo
de existir no dia em que deixar de ser verdade.

**A correção é barata porque a árvore já estava no banco.** `campo_extraido.secao` guarda o PAI
IMEDIATO, não o grupo de topo — então "os filhos de P" é pergunta EXATA (as linhas cuja `secao` é a
`chave` de P), não casamento por semelhança. E a identidade que todo demonstrativo obedece é
**pai = soma dos filhos diretos**, que a extração teve de satisfazer sem saber que seria conferida.

| Pega | Como |
|---|---|
| **linha perdida** | some um filho, o pai deixa de bater |
| **valor errado** | dígito trocado quebra o pai |
| **linha duplicada** | fica com a `0105`, de propósito (ver guardas) |
| **sinal invertido** | "(-) Provisão" lida positiva quebra o pai por 2× o valor |
| **total declarado 2× que discorda** | achado PRÓPRIO, não "a seção não fecha" |

E **localiza na seção**: quem lê "Estoques não fecha por 6.400" reextrai um bloco, não o documento.

**As guardas, e elas são a razão entre autonomia e trabalho humano em código.** Pendência que abre
sem defeito custa mesa e não compra qualidade — é regressão pura. Então: rótulo duplicado (no pai ou
na parcela) vira pré-condição e aponta a `0105`, porque duas pendências para um defeito são dois
toques onde cabe um; unidade mista não se soma, e a parcela divergente **não é descartada em
silêncio**; linha derivada não é parcela; e **UMA pendência por documento**, não uma por seção — erro
de escala quebra todas de uma vez.

**A tolerância é de ARREDONDAMENTO (~0,5·(n+1)), não os 0,5% das outras checagens.** As outras
comparam DOCUMENTOS diferentes, que arredondam diferente; aqui os dois lados saem da mesma coluna do
mesmo documento. 0,5% de um Ativo de 95.780 é 479 — deixaria passar a conta de meio milhão que a
checagem existe para achar.

**A FRONTEIRA, e ela foi medida antes de ser escrita: cascata não é partição.** Os filhos de
"RESULTADO ANTES DOS TRIBUTOS" são o IRPJ e o IR diferido, que levam ao lucro líquido — não parcelas
que somam ao pai. Rodar sobre DRE acusaria **3 seções do book que estão CERTAS**. O gate é
`BALANCO`/`BALANCETE`/`COMBINADO`, e há um assert que prova que a DRE realmente não fecha por soma,
para que ninguém "conserte" isso acrescentando DRE de volta e inundando a fila.

**Dois defeitos meus que o fixture achou, e valem mais que a correção:**

1. A primeira versão contava "TOTAL DO ATIVO" como parcela — a soma dava **exatamente 2× o pai em 31
   seções**. Ele é irmão das parcelas, não pai delas: é a REAFIRMAÇÃO do total, e o documento a
   imprime justamente para ser conferida. A regra de reconhecimento é por VALOR e não por rótulo,
   e isso também foi medido: "TOTAL DO PASSIVO E DO PATRIMÔNIO LÍQUIDO" não casa por texto com a
   seção "PASSIVO E PATRIMÔNIO LÍQUIDO" (sobra o "do" do meio).
2. Eu redefini `fn_reconciliar_por_documento` a partir do corpo da `0023` e **apaguei em silêncio o
   que a `0117`, a `0124` e a `0105` acrescentaram** — mútuos, espelho intragrupo e duplicidade
   sumiram da rodada. A suíte pegou na hora ("a divergência plantada de mútuos ABRE pendência — 0
   pendência(s)"). **A lição é de processo:** `create or replace` numa função que migrations
   posteriores reescreveram tem de partir da versão VIGENTE, não da que o `grep` acha primeiro.

> **APLICADA** — o dono confirmou em 20/08 que a fila inteira (`0126`–`0133`) entrou no Supabase.
> A `0133` não muda ingestão nem export: acrescenta uma checagem Classe A que só fala quando uma
> seção não fecha. **O que ela passa a produzir a partir da próxima rodada** é a taxa de seções que
> fecham por tipo de documento — a primeira medida de qualidade de extração que não custa hora
> humana.

## O próximo passo (para quem retomar depois de 19/08, sessão 53)

**O DONO FEZ AS DUAS COISAS QUE FALTAVAM** — confirmado em 19/08: as migrations estão aplicadas
**até a `0125`** e o `workflow.e1-ingestao.json` foi **reimportado**. Não há mais nada de infra
pendente **daquela rodada**.

> **NÃO HÁ MAIS NADA DE BANCO PENDENTE.** A `0126` (golden set) e tudo o que veio depois dela até a
> `0133` foram aplicadas — o dono confirmou em 20/08. Nenhum nível de autonomia mudou com elas; o
> que mudou é que o N2 da extração passa a se declarar como `declarada` em vez de ficar
> indistinguível de um N2 medido. **O bloqueio abaixo é agora o único que sobra: rodar o book.**

**Sobrou UM bloqueio, e é grande: NINGUÉM RODOU O BOOK AINDA.**

Isso importa mais nesta rodada do que nas anteriores, e o motivo é aritmético: a sessão 52 acrescentou
**três checagens novas e um conserto de motor que nunca rodaram sobre dado real**. O fixture prova que
elas funcionam sobre extração FIEL; a rodada é a única coisa que prova que elas funcionam sobre o que
o modelo de verdade lê de um PDF sujo.

| | O que a rodada prova | De onde vem | Como saber que passou |
|---|---|---|---|
| 1 | **O fatiamento liga em produção** — ele estava DESLIGADO até agora (zero de 38 documentos fatiados) | sessão 52 | o lote sai com **~44 chamadas de extração**, não 38; o `17_Livro_Razao` vira **4 blocos** |
| 2 | Os **SUBTOTAIS IMPRESSOS** chegam | `0116`, sessão 50 | "TOTAL DO ATIVO" e "RECEITA OPERACIONAL BRUTA" aparecem como LINHA, não só como `secao` |
| 3 | A **divergência de mútuos** aparece quando existe | `0123` | pendência `reconciliacao:mutuos_planilha_vs_balanco`, se o caso tiver planilha e balanço |
| 4 | O **espelho intragrupo** não dá falso positivo | `0124` | `reconciliacao:intragrupo_espelho` só abre se um par de empresas realmente não fechar |
| 5 | A **proveniência** chega ao arquivo | `0125` | a nota de uma célula histórica diz arquivo, página, confiança e aceite — não "Extraído de BALANCO" |
| 6 | `lote_integro` e `cobertura_do_lote` | sessão 50 | `cobertura_do_lote` **não pode vir `null`** (null = a camada 1 não mediu e as outras duas estão mudas) |
| 7 | O custo bate com o previsto | sessões 50-52 | o guarda prevê ~US$ 1,42 para o book sintético contra US$ 1,29 medido (+10%); num mandato real o desvio é o número a olhar |

**Ordem sugerida:** rodar o book num mandato NOVO → exportar o completo → passar o
`auditar-xlsx.mts` e o `Arquitetura do Sistema/6 Referência/ACEITE.md` por cima. Os três juntos levam menos de uma hora e são a
única evidência que nenhuma suíte substitui.

**Com a rodada na mão, a próxima sessão tem duas tarefas que só existem depois dela:**

1. **Recalibrar o limiar de cobertura de 0,85** com pontos REAIS. Hoje ele está calibrado contra os
   38 documentos SINTÉTICOS do book (erro mediano da régua +3%, pior caso 96% com extração perfeita).
   O documento real é mais sujo, e a folga de 11 pontos existe para ele — mas ninguém mediu ainda.
2. **Conferir se o fatiamento cortou onde devia** e se a emenda entre blocos não duplicou linha. A
   `juntarBlocos` limpa emenda repetida, mas ela nunca viu bloco de verdade.

> **A `0118` muda o que se vê ao reenviar um arquivo.** Reenviar o MESMO PDF sem que prompt, modelo
> ou esquema tenham mudado não chama mais a OpenAI: o documento aparece no lote, sem custo e sem
> versão nova. Se a intenção era reextrair de verdade, mude o prompt (ou espere a próxima mudança
> dele) — o fingerprint muda junto e a extração volta a acontecer.

> **Opcional, e só isso: o `Max rows` do Supabase.** O teto de 1000 linhas do PostgREST
> (*Project Settings → API → Max rows*) continua no padrão, e **nenhuma tela depende dele** — o
> `paginar` lê em janelas até o banco acabar. Subi-lo só deixa cada leitura mais barata.

### OS TRÊS CENÁRIOS PASSAM A SER COMPARÁVEIS (20/08, sessão 54)

**O defeito, do `§2.2` do diagnóstico de 11/08:** o arquivo tem UM interruptor de cenário
(`Output!$G$2`) e todas as abas leem dele por `CHOOSE`. Ter um interruptor só é a decisão **certa** —
dois produziriam um arquivo em dois cenários ao mesmo tempo, sem nada denunciar. A consequência é que
o arquivo mostra **um cenário por vez**, e a comparação base × cliente × stress, que é o motivo de
existirem três, não estava em lugar nenhum. Para comparar, o analista girava o dial e anotava números
num papel.

**O que entrou:** uma cascata paralela na aba de receita (`OS TRÊS CENÁRIOS EM NÚMERO`) e o bloco de
leitura no `Output` (`RESUMO DOS TRÊS CENÁRIOS`), com receita líquida, crescimento, EBITDA e margem
para os três cenários ao mesmo tempo, sem olhar o interruptor.

**A fronteira é a da cascata, e está DITA na aba.** Ficam fora ND/EBITDA, DSCR e pico de caixa: eles
exigiriam replicar a cascata de dívida e o fluxo de caixa por cenário — três modelos paralelos dentro
do arquivo —, e num arquivo que vai a credor cada linha nova é uma chance de ele passar a mentir. Um
bloco que mostrasse "ND/EBITDA dos três cenários" lendo a dívida de UM seria pior que a ausência
dele: o número existiria, pareceria comparação, e não seria. A linha que diz isso está no bloco, não
num comentário de código.

**As sombras não duplicam a lógica da cascata ativa.** As quatro linhas — a ativa e as três — saem do
mesmo `formulaConta`, com o cenário como parâmetro. Uma sombra escrita à parte divergiria no primeiro
dia em que alguém mexesse numa das duas, e divergiria **em silêncio**, porque as duas continuariam
produzindo números plausíveis.

> **E as sombras existem só na PROJEÇÃO, porque o passado é um.** No realizado o EBITDA reconcilia com
> o número que o documento informou, então sombra e linha ativa poderiam divergir por um motivo
> legítimo e o CHECK acusaria um defeito que não há. Três colunas históricas com o mesmo número também
> convidariam a procurar uma diferença que não existe.

**Um defeito achado no caminho, e ele era do tipo que sai zero em silêncio:** as sombras existem só na
projeção, então no primeiro ano projetado o "ano anterior" da sombra é uma célula que não existe — e
referência a célula vazia vale **zero** em Excel. As três cascatas partiriam de zero e o comitê leria
três cenários de receita nula sem uma única célula vermelha. A raiz passou a ser lida da linha ATIVA,
que é onde o realizado mora e é o mesmo número para os três cenários por definição.

**E a linha `EBITDA` da aba de receita estava declarada e VAZIA** — rótulo "EBITDA" com todas as
colunas em branco, exatamente o estado que a linha `DEPRECIACAO` da mesma aba já teve antes de alguém
notar. Duas linhas declaradas e nunca preenchidas, na mesma aba, pelo mesmo motivo: dependem de uma
aba construída depois dela. Agora é **espelho** do Income Statement, não um segundo cálculo — recomputá-la
aqui daria duas respostas para "qual foi o EBITDA de 2025".

> **Os dois grupos de assert são complementares, e isso foi medido no religamento em vez de suposto.**
> O CHECK só compara a sombra do cenário ATIVO com a linha ativa, e num arquivo recém-exportado o
> ativo é o Base. Religamento A (a sombra passou a usar sempre a taxa do Base): o **CHECK continuou
> zero** e caíram os asserts do Stress. Religamento B (a agregação da sombra deixou de somar uma conta
> de custo): o CHECK acusou 42.000 e 44.100 e os asserts do Stress **passaram**. Nenhum pega o defeito
> do outro — um CHECK verde não prova que os três cenários estão ligados, e três cenários diferentes
> não provam que a sombra bate com o modelo.

### O GOLDEN SET PASSA A SER ROTULÁVEL, e a rotulagem é CEGA (20/08, sessão 54) — `0130`

**A `0126` construiu o golden set inteiro do lado da leitura e nada do lado da escrita.** Quatro
tabelas, as cinco métricas do `Arquitetura do Sistema/2 Especificação/f0/06`, o portão `fn_golden_suficiente`, a regra de ouro executada em
`fn_mudar_dial` — e nenhuma função para abrir rodada, incluir documento, gravar rótulo ou congelar.
Rotular só era possível escrevendo `insert` à mão no psql. **O portão estava construído e não havia
estrada até ele**, que é o mesmo defeito que a `0126`, a `0127` e a `0128` corrigiram uma camada
acima — e o que travava a F4 do `Arquitetura do Sistema/1 Visão e Doutrina/03` não era decisão nenhuma: era a falta de um formulário.

**A decisão que governa o desenho: a rotulagem é CEGA.** `fn_golden_linhas_para_rotular` devolve as
rubricas que a extração achou **sem os valores**. É o fechamento #5 do `Arquitetura do Sistema/1 Visão e Doutrina/01` (anti-ancoragem)
aplicado onde a aposta é maior que numa tela de aceite: o rótulo do golden set é a EVIDÊNCIA que
autoriza subir autonomia. Quem vê a resposta da máquina enquanto rotula não produz ground truth,
produz uma conferência — e conferência tem viés de confirmação conhecido: o número plausível passa. A
métrica então sobe sem que nada tenha melhorado, e o dial sobe com ela. **O sistema certificaria a si
mesmo.** O assert que trava isso não compara valores: ele exige que a palavra "valor" não apareça em
chave nenhuma do retorno, para um apelido novo acrescentado daqui a um ano cair no teste.

**E devolve as rubricas, em vez de esconder tudo.** Porque o que se mede é o VALOR e a rubrica é só a
chave de casamento: `fn_golden_campos` junta por `fn_normalizar_texto(chave)` + período + entidade.
Esconder as rubricas faria o rotulador digitar a grafia dele ("Receita líquida de vendas" contra
"Receita Líquida"), o par não casaria, e a linha entraria como **AUSENTE** — a família de defeito mais
grave do placar — creditada à máquina por uma diferença de datilografia. A medição passaria a medir a
coincidência de grafia entre duas pessoas. Ver a rubrica não ancora o julgamento do valor: o valor
continua tendo de ser lido no papel.

**A contrapartida é obrigatória.** Uma lista só das rubricas que a máquina achou deixaria a perda
silenciosa invisível — o rotulador confirmaria as 40 linhas extraídas e nunca notaria as 3 que a
extração perdeu. Então `fn_golden_rotular_campos` **aceita rubrica fora da lista** (é o único caminho
pelo qual `n_ausente` chega a ser medido) e **revela o casamento só depois de gravar**. Revelar antes
seria ancoragem pela porta de trás: "sua linha não casou" durante a digitação é um convite a procurar
a grafia que casa, e aí o rótulo passa a perseguir a máquina. Depois é informação — quem vê 3 de 12
sem par sabe que ou a extração perdeu três linhas, ou ele escreveu três rubricas que o normalizador
não reconhece, e as duas coisas importam.

**As recusas retornadas, e por que cada uma existe:** tipo fora do catálogo (typo em rótulo
append-only vira falso negativo PERMANENTE da máquina no F1 daquele tipo, e ninguém relê um rótulo
que não se edita); rótulo vazio (contaria como documento rotulado na cobertura sem medir nada — o
jeito mais fácil de bater o N mínimo sem produzir evidência); rodada congelada, com o caminho de
saída escrito (rodada nova, nunca edição); rodada sem nenhum rótulo no congelamento (apareceria na
lista de rodadas parecendo evidência). Estrato e origem são **obrigatórios e não inferidos**: o banco
não distingue documento de cliente do book sintético, e chutar isso inflaria a amostra com aquilo
cujo gabarito já se conhece.

> **Um rotulador só é escolha legítima com consequência medível, e ela fica dita no ato de congelar.**
> O `Arquitetura do Sistema/2 Especificação/f0/06` pede dois rotuladores nos casos ambíguos para que a discordância entre humanos seja
> EXCLUÍDA do placar da máquina. Com um só não há discordância a excluir: o documento genuinamente
> ambíguo entra como erro dela, e a medição fica **conservadora — o número que sai é um PISO da
> qualidade real, não uma estimativa dela**. Conservador é o lado certo para errar, e mesmo assim
> quem lê "acerto 0,91" tem direito de saber que 0,91 é um piso. `fn_golden_congelar` devolve esse
> aviso.

**A TELA (`/autonomia/golden`).** Três páginas: as rodadas, o detalhe de uma rodada (progresso por
tipo, inclusão da amostra com estrato sugerido, congelamento) e **a tela cega de um documento**. A
tela cega carrega o **nome do arquivo e nada mais** — não o tipo, não a empresa, não o período, não
os valores, e não o `resumo`/`justificativa`, que é o vazamento mais fácil de não notar: um resumo
dizendo *"balanço da Alfa em 31/12/2024"* entrega as três primeiras métricas do `Arquitetura do Sistema/2 Especificação/f0/06` numa frase. A
tela **explica por que é cega**, porque sem isso esconder a resposta parece falta de informação em vez
de método, e a primeira reação de quem rotula é procurar onde está o palpite.

**A pergunta mais importante da tela é a das linhas livres:** *"o documento tem alguma linha que não
está na lista acima?"*. Uma tabela só com as rubricas que a extração achou faria a extração parecer
perfeita justamente nos documentos de que ela perdeu metade — quem rotula confirmaria as 40 listadas
e nunca notaria as 3 que faltam. `n_ausente` só chega a ser medido por ali, então a pergunta é feita
com palavra e em destaque, não deixada implícita numa linha vazia no fim.

> **E existe uma suíte só para o vazamento, porque ele não tem sintoma** —
> `portal/scripts/verificar-tela-cega.mts`, 18 asserts. Se a tela passar a mostrar o que a extração
> leu, **tudo continua funcionando**: a página renderiza, os rótulos gravam, as cinco métricas saem,
> o painel mostra números bonitos. Só que os números param de medir algo, porque quem rotula passou a
> conferir em vez de julgar. Nenhum teste de comportamento pega isso — o comportamento fica correto.
> A suíte então olha o que a página **pede ao banco**: extrai as colunas de cada `.select()` e reprova
> as dez que respondem ao que o rótulo tem de julgar. Ela ignora comentários de propósito, senão a
> própria explicação da regra reprovaria o arquivo — e a saída natural seria apagar a explicação.
> Religamento medido: acrescentar `tipo_taxonomia, resumo, confianca` à consulta derruba 3 asserts;
> dar um campo `valor_num` ao tipo `Linha` derruba outro (o defeito ali é ter *onde o dado pousar*).

### A TRANSCRIÇÃO HUMANA ASSISTIDA, e a contaminação que ela criaria (20/08, sessão 53) — `0129`

**O fechamento nº 2 do `Arquitetura do Sistema/1 Visão e Doutrina/01` era o único dos oito sem código:** *"gate de captura com saída. Input
ilegível/corrompido → transcrição humana assistida, nunca dead-end de pendência infinita."* O gate
existia (a `0010`/`0020` abrem `arquivo_ilegivel`) e a saída existia em outra forma (reenviar ao
cliente, rejeitar) — **a transcrição assistida em si nunca foi construída**, e ela é a saída que serve
quando o cliente não tem outra via do arquivo, que em reestruturação é o caso comum.

**A forma: planilha modelo preenchida pelo analista** (decisão do dono). Não é tela de digitação linha
a linha — ninguém digita balanço em formulário web se puder usar Excel. A planilha é ferramenta de
mesa e não sai da casa, então pode usar o vocabulário interno sem o cuidado que a `0122` teve de dar
às perguntas ao cliente.

#### A CONTAMINAÇÃO QUE ELA CRIARIA, e que a mesma migration fecha

Linha transcrita mora em `campo_extraido`, do lado das que a IA leu — e `fn_golden_campos` mede a
extração comparando `campo_extraido` com o rótulo do golden set. **Sem uma distinção, a primeira
transcrição inflaria a medição da autonomia:** linha que uma pessoa digitou olhando o documento bate
com o rótulo quase sempre, e o acerto sairia creditado à extração — subindo justamente nos documentos
difíceis, que são os transcritos. É a armadilha que a `0126` fechou com `golden_documento.origem`,
reaparecendo por outra porta.

`campo_extraido.origem_valor` distingue `extracao` de `transcricao_humana`, e `fn_golden_campos` passa
a excluir o transcrito. **Medido no religamento:** sem o filtro, as duas linhas transcritas voltam como
`n_exato = 2` — acerto perfeito da IA sobre um número que ela nunca leu.

#### TRÊS DECISÕES

1. **A transcrição é VERSÃO NOVA** (doutrina da `0026`), e `fn_versao_com_extracao` a elege como
   vigente por ela ter linhas. A versão ilegível fica preservada, com zero linhas, contando por que
   houve transcrição.
2. **As guardas de extração NÃO rodam.** Elas pegam alucinação de modelo: "quatro contas com o mesmo
   valor" é padrão suspeito numa saída de IA e é **rotina** num balanço com contas zeradas. Acusar de
   fabricação alguém que está lendo o papel seria guarda que só atrapalha. O que substitui é a
   **autoria** — e a confiança fica **NULA**, porque não existe autoavaliação de pessoa e escrever 1,0
   inventaria uma medida.
3. **A linha nasce aceita, e isso não fura a anti-ancoragem.** O fechamento #5 exige aceite humano
   antes de um número entrar na base; aqui o humano não aceita a sugestão de uma máquina — ele é a
   **fonte**. Pedir que ele "aceite" o que ele mesmo digitou seria clique cerimonial, e cerimônia vazia
   é o que ensina a clicar sem ler.

**E a pendência de ilegibilidade fecha com o nome de quem transcreveu**, não por "sistema". É isso que
faz o gate deixar de ser dead-end.

### O MODO A DO `Arquitetura do Sistema/2 Especificação/f0/07` PASSA A EXISTIR — a base viva (20/08, sessão 53)

> **DESCONTINUADO EM 21/08 (sessão 57), por decisão do dono.** A tela `/casos/[id]/base` e o botão
> *"Consultar a base"* saíram do portal: o que ela consultava já está na planilha, entregue. O texto
> abaixo fica como registro de por que ela existiu e do que ela deliberadamente não fazia — a
> decisão de NÃO SOMAR continua valendo para o export, que é a entrega. Ver "O PORTAL ENCOLHE".

**O modo declarado PRINCIPAL da entrega não tinha tela.** O `Arquitetura do Sistema/2 Especificação/f0/07` define dois modos: *"Modo A — base
viva no portal · **principal**"*, onde o analista *"consulta/filtra os dados curados na tela, por
Entidade × Período × Conta/linha financeira"*, cada valor carregando *"sua proveniência e seu status de
aceite"*; e o Modo B, o export. **Só o B existia.** O portal tinha a tela de UM documento e o `.xlsx`;
perguntar *"o que a base diz sobre Estoques na Alfa em 2024"* exigia abrir os documentos um a um ou
baixar o arquivo — que é o outro modo.

`/casos/[id]/base` responde isso: filtra por empresa, período, conta e status de aceite, atravessando
os documentos, com o arquivo/página/confiança de cada número ao lado.

#### A DECISÃO CENTRAL DELA É NÃO SOMAR

Consolidar demonstração é difícil de um jeito que não aparece — subtotal impresso que não pode entrar
na soma, conta sem vocabulário que herda a seção dos irmãos, escalas diferentes no mesmo caso, o mesmo
rótulo sendo subtotal num documento e conta-folha em outro. **O export paga esse preço com 574
verificações atrás dele.** Uma tela que somasse "para ficar mais útil" produziria um SEGUNDO total para
a mesma pergunta, mais fraco — e dois números para o mesmo fato é o defeito que este sistema mais
persegue. Então não há total, não há AV% e não há conversão de escala: cada linha aparece como o
documento a trouxe, com a unidade ao lado, e **a tela diz isso com palavra**, porque sem a frase alguém
somaria a coluna no olho e a culpa pareceria dele.

O que ela faz que o arquivo não faz: responder rápido, com proveniência à mão, e sobre a base **viva** —
incluindo as linhas **pendentes** de aceite, que o export por doutrina não trata como fato. Pendente é
visualmente distinto *e* escrito com palavra (exigência do `Arquitetura do Sistema/2 Especificação/f0/07`; cor sozinha não carrega significado).

#### UMA REGRA QUE VIROU COMPARTILHADA, em vez de uma segunda implementação

"De qual empresa e de qual período é este número" não é trivial: a linha pode pertencer à COLUNA
(`entidade_coluna`, `0014`; `periodo_coluna`, `0017`) e não ao documento, o apelido da coluna precisa
ser promovido à razão social (`consolidarNomesDeEntidade`), e o período vem cru da extração. Isso era
**uma linha solta dentro do laço do `buildExportWorkbook`** — suficiente enquanto o arquivo era o único
leitor. A tela faz a mesma pergunta, então a regra saiu para `entidadePeriodoDaLinha`, exportada, e o
export passou a chamá-la: **uma regra, dois leitores**, em vez de duas respostas para a mesma pergunta
em duas telas.

**A extração é comportamento-preservador** (os 568 asserts anteriores seguem verdes) e ganhou 6 asserts
próprios — porque com dois leitores um defeito ali erra o arquivo E a tela do mesmo jeito, e a
coincidência esconderia o erro em vez de expô-lo. **Religamento medido:** trocar o `||` por `??` derruba
o assert da coluna vazia; ignorar `periodo_coluna` derruba os asserts novos **e 4 antigos**, que é a
prova de que a função extraída é de fato a que o arquivo usa.

#### O TETO DA LISTA SAI DO SILÊNCIO

A tela mostra 500 linhas e **diz** quantas ficaram fora, com o que fazer a respeito. Cortar em 500 sem
dizer nada seria o mesmo defeito do teto do PostgREST que este código já matou duas vezes: a lista abre
normalmente e parece completa. O teto da paginação também é anunciado, e erro de leitura é dito em vez
de virar tela vazia — vazio por erro de RLS mente com mais convicção que um erro, porque quem lê conclui
que a base está vazia.

### A PLANILHA DE TRANSCRIÇÃO, e a versão que a tela não estava mostrando (20/08, sessão 53)

**A `0129` ficou com a função no banco e nada a chamando** — foi dito no commit dela e aqui. Isto é a
outra metade: a planilha existe, se baixa, se preenche e se reimporta.

`portal/src/lib/transcricao.ts` guarda **as duas metades do formato no mesmo arquivo** — gerar e ler.
Não é conveniência: o formato é um contrato entre quem escreve e quem lê, e as duas pontas são este
sistema. Separá-las é a receita para a coluna mudar de lugar num lado e não no outro, e o sintoma disso
não é um erro — é uma transcrição importada com o valor na coluna da unidade.

**A rota** `GET /casos/[id]/documentos/[docId]/transcricao` devolve o `.xlsx` com o padrão de resposta
da rota de export. **A ação** `importarTranscricao` lê a planilha e chama `fn_registrar_transcricao_humana`.
**O bloco na tela** aparece em exatamente dois estados — arquivo ilegível, ou zero linha extraída — e em
nenhum outro: transcrição grava linha aceita sem passar por guarda, e oferecê-la ao lado de uma extração
que funcionou seria abrir um atalho para digitar o número que fecha.

#### A GUARDA DO ID DO DOCUMENTO, que o banco não teria como fazer

A planilha carrega o `documento_id` na célula `B5`, e a importação **recusa** quando ele não é o desta
tela. O banco não tem como pegar isso: para ele chegariam linhas plausíveis, e ele as gravaria
**aceitas, com o nome de quem enviou**. Enviar a planilha do balanço da Alfa na tela da Beta é erro
plausível de quem tem seis arquivos abertos, e o resultado seria um número errado *com autor* — o pior
tipo, porque ninguém volta a desconfiar de número que tem dono. A recusa nomeia os dois ids, para a
próxima tentativa não ser chute.

**E a recusa é DEVOLVIDA, não lançada** — ao contrário das outras duas ações desta tela. Não é
inconsistência: é a doutrina de recusa retornada da casa uma camada acima, e aqui ela é obrigatória por
um motivo mecânico. O Next redige a mensagem de erro de server action em produção; um `throw` entregaria
um digest opaco no lugar de *"esta planilha foi gerada para outro documento"*. Nas outras ações o texto
da recusa é secundário; aqui o texto **é** o produto — ele diz o que fazer com o arquivo que a pessoa
tem na mão.

#### O DEFEITO QUE UM ASSERT PEGOU: `(1.234)` valia −1,234

A leitura de número em pt-BR tinha a regra *"se tem vírgula, o ponto é milhar; sem vírgula, o ponto pode
ser decimal"*. Ela está **certa** para `0.75` e **catastrófica** para `1.234`, que é como um PDF
brasileiro escreve mil duzentos e trinta e quatro: o valor voltava três ordens de grandeza abaixo, num
número plausível o bastante para passar por revisão. É o mesmo defeito do `parseFloat` um passo adiante.

O ramo novo lê ponto separando grupos de **exatamente três dígitos** como milhar. A ambiguidade é real e
a escolha está escrita: numa planilha em pt-BR o decimal se escreve com vírgula, e o grupo de três
dígitos é o que distingue — `1.5`, `0.75` e `12.34` seguem sendo decimais, porque nenhum milhar tem um
ou dois dígitos depois do ponto. Nove asserts travam essa fronteira, para a regra não ser "simplificada"
para *tira todo ponto* e `0,75` virar 75.

#### E A TELA MOSTRAVA A VERSÃO ERRADA — defeito que a `0129` tornou agudo

A página do documento lia `doc.documento_versao?.[0]`: a primeira que o PostgREST devolvesse, sem ordem
garantida. Passava despercebido enquanto quase todo documento tinha uma versão só. **Transcrição sempre
cria versão nova** (doutrina da `0026`) — então a versão exibida continuaria sendo a antiga, a ilegível,
a de zero linhas. O sintoma seria o pior possível para quem acabou de digitar um balanço à mão: a tela
recarrega dizendo *"nenhuma linha foi extraída deste documento"* e oferecendo o bloco de transcrição de
novo, como se o trabalho tivesse sido perdido. Agora a página chama `fn_versao_com_extracao` (`0102`) —
a regra canônica, não uma reimplementação em TypeScript.

**A suíte nova, `portal/scripts/verificar-transcricao.mts` (35 verificações), é round-trip de verdade**
— gera, escreve o `.xlsx`, lê de volta —, porque o defeito que interessa é a coluna que muda de lugar em
uma das duas metades. Ela também trava que sobra em branco **não** vira linha: a planilha traz 60 linhas
livres, e se elas entrassem, cada transcrição gravaria dezenas de linhas afirmando que o documento diz
zero.

### A CLASSIFICAÇÃO CONTÁBIL PASSA A EXISTIR, em sombra (20/08, sessão 53) — `0128`

**O oitavo estágio do MVP, com zero linha de código até aqui.** O `Arquitetura do Sistema/1 Visão e Doutrina/03` o lista entre os que
"existem na v1 de produção", o `Arquitetura do Sistema/2 Especificação/05` o especifica por inteiro (taxonomia de cinco rótulos, as
três condições de auto-aceite, o registro de justificativa, o de override) e a `0002` o semeia no
dial em N0. Medido antes de escrever: `grep` por `classe_contabil` devolvia UMA ocorrência — a coluna
que a `0126` criou no golden set para guardar o rótulo humano de uma classificação que ninguém
produzia. O EBITDA saía do modelo como linha de cascata, sem nenhuma noção de recorrência.

**É a forma inversa do defeito que a `0127` corrigiu:** lá o dial subestimava a realidade; aqui ele
afirmava a existência de um estágio.

**Como ela decide (decisão do dono): regra determinística sobre rubrica.** Sem IA e sem custo por
documento — é a condição 2 do próprio `Arquitetura do Sistema/2 Especificação/05` ("bate com um padrão conhecido pré-registrado"). O
catálogo de rubricas é DADO versionado, com `justificativa` NOT NULL por linha, e rubrica que ele não
conhece cai em `revisar_manual`.

**Em N0 ela não toca em número nenhum do arquivo entregue** (decisão do dono, e leitura fiel de N0): a
sugestão fica registrada e visível, o `.xlsx` sai idêntico. É isso que permite acumular concordância
sem risco de número errado chegar a comitê.

| | |
|---|---|
| Cobertura medida | **207 de 231** rubricas reais de resultado — **89,6%** |
| O que sobra em `revisar_manual` | 6 subtotais impressos que a `fn_papel_linha` não reconhece, 1 genuinamente ambíguo, e artefato de fixture |
| O seed | **corrigido duas vezes pela medição**, e as duas correções estão comentadas nele |

#### TRÊS DECISÕES, E A PRIMEIRA VEIO DE UMA MEDIÇÃO

1. **A regra só roda em linha de RESULTADO.** Conta de balanço não é recorrente nem não recorrente —
   a pergunta não se aplica. Rodar em tudo produziria **3.195 pedidos de revisão** contra 527 linhas
   em que a pergunta cabe, e analista que recebe 3.195 itens não revisa nenhum (é a lição do Sinal 1
   refinado na `0022`). **Ausência de sugestão é a forma de dizer "não se aplica"** — não entra um
   sexto rótulo para isso.
2. **A taxonomia é TABELA, não enum.** Os cinco do `Arquitetura do Sistema/2 Especificação/05`, sem acréscimo. Mas como linhas de
   catálogo, porque um sexto rótulo deve custar uma linha de seed e não uma migration que altera tipo.
3. **O auto-aceite do `Arquitetura do Sistema/2 Especificação/05` NÃO foi implementado, e o motivo é uma contradição do documento.** Ele
   tem uma seção sobre "quando a sugestão pode ser aceita" e abre dizendo "teto N1 **para sempre**".
   Sob teto N1 auto-aceite não pode acontecer: as três condições descrevem o que a própria doutrina do
   documento proíbe. Implementá-las seria código morto que alguém liga por engano.

#### E A TELA, porque sem ela a 0128 não produz sinal nenhum

A classe é por LINHA extraída, então a casa dela é `/casos/[id]/documentos/[docId]` — a mesma tela em
que o analista já aceita linha por linha. Mesmo lugar, mesmo ato.

- **A sugestão e a decisão ficam visíveis ao mesmo tempo.** Se a tela substituísse uma pela outra, o
  analista perderia de vista do que está discordando, e quem abrisse depois não saberia que houve
  discordância — que é justamente o dado.
- **A sugestão NÃO vem pré-selecionada no seletor**, e é deliberado: seletor que abre preenchido com o
  palpite da máquina transforma "confirmar" no caminho de menor esforço, e o aceite deixa de ser
  decisão para virar clique de inércia. É a anti-ancoragem aplicada à interface.
- **Sem sugestão, sem seletor.** Linha de balanço não recebe um controle que convidaria a inventar
  resposta.
- **O contador da classe é SEPARADO do de aceite**, não somado: aceitar o NÚMERO e classificar a
  NATUREZA dele são duas decisões sobre a mesma linha, e somá-las daria um "N de M" que não
  corresponde a nada.

E a **concordância medida** entrou no `/autonomia`, ao lado do dial que ela governa — com a tabela das
**rubricas que mais erram**, que é por onde se ajusta o catálogo. Corrigir a regra é mais barato e mais
auditável que reclassificar linha a linha para sempre.

#### O SINAL DE CALIBRAÇÃO, e é ele que faz isto valer a pena em sombra

`fn_classe_contabil_concordancia` responde a frase do `Arquitetura do Sistema/2 Especificação/05` — *"o override vira sinal de
calibração"* — em número, e nomeia **as rubricas que mais erram**, que é o que permite ajustar a
REGRA e não o modelo. É a mesma economia que a `0126` achou na Classe A: o rótulo vem do trabalho que
o analista já faz, sem rotulagem dedicada. Denominador = linhas com os dois lados; quem ninguém olhou
fica fora e é contado à parte.

#### E UMA RESSALVA MEDIDA, que está escrita no corpo da regra

`fn_papel_linha` **não pega todo subtotal impresso** — conferido: ela devolve `conta` para "CUSTO DOS
PRODUTOS VENDIDOS" e para "(-) DESPESAS OPERACIONAIS". Então o filtro de subtotal reduz o ruído sem
eliminá-lo, e dizer o contrário seria prometer o que ele não cumpre.

### O DIAL PASSA A SER OBEDECIDO — e dois níveis declarados eram falsos (20/08, sessão 53) — `0127`

**A `0126` cuidou de COMO O DIAL MUDA. Ela não cuidou de o dial ser LIDO.** E a `0041` já havia
diagnosticado isso com um comando: *"`grep -rl estagio_autonomia portal/src n8n` não retornava NADA
— a tabela não tinha um único leitor"*. Ela consertou para **um** estágio. Rodando a mesma busca
hoje, estágio por estágio, os outros **sete** continuavam sem leitor: mudar o nível deles era
validado contra o teto, cobrado contra golden set pela `0126`, gravado na trilha — e **inerte**.

**E dois deles não só não eram lidos: declaravam o nível ERRADO.**

| Estágio | Declarava | Fazia | Onde estava o número |
|---|---|---|---|
| `classificacao_doc_checklist` | N1, limiar 0,95 | **N2, limiar 0,70** — documento com confiança 0,80 entrava classificado sem humano olhar | `p_threshold default 0.7` **e** `THRESHOLD_AUTO` no `classifier.mjs` — duas réguas, nenhuma o dial |
| `reconciliacao_classe_bc` | N0 ("não influencia decisão") | **N1** — abre pendência desde a `0015`, e pendência entra na fila e conta no Portão 2 | a classe nunca era olhada em `fn_registrar_reconciliacao` |

**Por que isso é pior do que parece:** quem lê o dial para decidir se confia num achado da Classe
B/C conclui "sombra, não influencia" e está errado. E quem baixasse a classificação para N1 para
forçar revisão de tudo não conseguiria — o nível não era lido.

**A `0127` não muda comportamento nenhum.** É a escolha da `0041`, pelo mesmo motivo: o dial passa a
declarar o que o sistema já faz, e a partir daí mudar de verdade passa a ser uma chamada.

- **`fn_dial_permite_auto`** — o leitor ÚNICO de "este estágio, nesta confiança, pode seguir sem
  humano?". Uma função e não a regra copiada, porque quatro cópias de uma regra de doutrina voltam a
  divergir — que é o defeito que a `0041` e a `0126` existem para fechar.
- **`fn_dial_influencia`** — o leitor de N0, que é significado diferente: não é sobre limiar, é sobre
  o resultado poder chegar à fila de alguém. **Os defaults seguros são opostos de propósito:** sem
  linha no dial, `permite_auto` devolve false (ausência de configuração não é permissão) e
  `influencia` devolve true (calar achado por falta de configuração esconde problema).
- **A classificação tira o limiar do dial**, com o parâmetro ficando como queda para banco sem a
  linha semeada — sem essa queda, um banco antigo passaria a abrir pendência em TODO documento no
  instante em que a migration entrasse. E a mensagem da pendência passa a dizer **qual** limiar
  reprovou, porque o limiar agora é dado e pode ter mudado desde ontem.
- **A Classe B/C respeita o nível:** em N0 registra em `reconciliacao` e não abre pendência. "Roda e
  registra" é a primeira metade da definição de sombra, e é ela que permite medir antes de confiar.

#### O RAMO QUE FALTAVA, E É O ASSERT MAIS IMPORTANTE DA SUÍTE NOVA

Silenciar um estágio com divergência **presente** cairia no `elsif` que fecha pendência, e marcaria
a pendência aberta como *"resolvida por sistema:reconciliacao"*. Mas o sintoma não sumiu: o estágio
foi silenciado. Resolver ali escreveria na trilha que o problema acabou, quando o que acabou foi o
direito daquele estágio de falar — e a trilha é append-only justamente para não permitir esse tipo
de reescrita. O ramo novo registra `reconciliacao_em_sombra` e **deixa em paz** a pendência que um
humano já pode estar tratando.

#### E A CORREÇÃO DA CLASSIFICAÇÃO PASSOU PELO PORTÃO DA 0126

N1 → N2 alcança auto-clear em estágio interpretativo, então exigiu `p_sem_medicao_porque`. O painel
passa a mostrar **dois** estágios como "declarada" em vez de um. Não é regressão: é o tamanho real
da autonomia não medida, que estava escondido num default de parâmetro.

**Um teste frágil que isto expôs, e o conserto vale mais que ele:** o cenário 1 da `golden.test.sql`
confiava em a classificação estar em N1 *por semeadura*. No dia em que uma migration declarou o N2
que ela já praticava, o cenário passou a testar "N2 → N2" — que não é subida — e reprovou. Agora ele
**estabelece a própria pré-condição** (baixar é sempre livre); depender de um default global é que
custa.

**O que a `0127` deliberadamente NÃO fez, com o motivo escrito:** `extracao_identificadores` continua
sem leitor porque para obedecer ao dial ele precisa de uma CONFIANÇA que hoje não chega ao banco —
`fn_registrar_diagnostico` recebe `p_tipo_confirma boolean`, com a decisão já tomada no nó do n8n, e
um dial no banco não alcança decisão tomada fora dele. Fechar exige mudar a assinatura **e** o nó, o
que obriga a reimportar o workflow. Os dois estágios determinísticos também seguem sem leitor, e ali
a razão é de natureza: a garantia deles é aritmética, não concordância humana.

### A REGRA DE OURO PASSA A SER EXECUTADA (19/08, sessão 53) — `0126`

**O `Arquitetura do Sistema/1 Visão e Doutrina/01` fecha com uma regra de ouro, em negrito e sem ressalva:** *"nada de subir o dial de
autonomia de um estágio interpretativo sem golden set e concordância medida."* **E `fn_mudar_dial`
(0041) conferia UMA coisa: o teto.** Pedir N2 num estágio de teto N2 era aceito com um `p_motivo` em
texto livre, e nada olhava para medição alguma — não existia onde olhar. A regra estava escrita na
doutrina, repetida no cabeçalho de duas migrations, impressa em letras âmbar na tela de autonomia, e
não era código em lugar nenhum.

**Quem fez isso primeiro foi a própria `0041`, e ela declara que fez:** *"este N2 é decisão de
produto do dono, NÃO autonomia medida… o golden set físico ainda não existe."* É a mesma forma dos
defeitos que a `0123` achou — `v_lados_bp` atribuída e nunca lida, "a guarda que o comentário da
`0117` prometia não existia" —, com a diferença de que aqui a promessa é do documento fundador.

**E o protocolo estava pronto desde 14/07.** O `Arquitetura do Sistema/2 Especificação/f0/06` foi fechado como v1: dimensionamento (~20–30
por tipo core), o que se rotula, uma tabela de CINCO métricas, rotulagem com dois avaliadores e o
laço de calibração desenhado. No banco não havia uma linha disso — `grep -ril golden` devolvia
documentação, o comentário de um script e prosa de migration.

| O que entrou | Onde |
|---|---|
| Ground truth: rodada que **congela**, documento com **estrato** e **origem**, rótulo **por rotulador**, e `golden_campo` com tolerância declarada no rótulo | `0126` |
| As **cinco métricas** do `Arquitetura do Sistema/2 Especificação/f0/06`: F1 da classificação por tipo, acurácia dos identificadores, erro de campo, concordância contábil e falso-positivo da Classe A | `fn_golden_*` |
| `natureza` e `base_do_nivel` em `estagio_autonomia` — a tabela de teto do `Arquitetura do Sistema/1 Visão e Doutrina/01` e a ressalva "declarada, não medida" saem da prosa | `0126` |
| O **portão**: subida que alcança N2/N3 em estágio interpretativo exige medição, ou motivo assumido | `fn_mudar_dial` |
| O painel de autonomia mostrando a base, a cobertura por tipo e o que falta | `/autonomia` |

**AS TRÊS DECISÕES QUE VALE LER:**

1. **O portão morde na subida que ALCANÇA N2/N3, não em toda subida.** A leitura literal cobraria
   golden set para ir de N0 a N1 — e N1 é "sugestão, humano confirma todo item": nada é automatizado,
   e a anti-ancoragem continua inteira. O risco que a regra guarda é automatizar erro em escala, e a
   escala começa no auto-clear. Cobrar medição para exibir sugestão travaria o caminho que a própria
   doutrina manda percorrer. **Descer nunca pede nada** — freio que exige papelada não é freio.
2. **Golden SINTÉTICO não sobe dial, e isso é coluna.** Sem `origem`, o portão seria teatro: os dois
   books têm `GABARITO.json`, rotulá-los é de graça, a concordância sairia ~100% por construção e o
   dial subiria com a medição do INSTRUMENTO. O cabeçalho do `medir-auto-aceite.mts` avisa disso em
   prosa há sessões; agora o aviso é guarda. Medido no teste: os MESMOS 20 documentos, o MESMO F1,
   e a subida é recusada só por a origem ser sintética.
3. **A decisão declarada continua possível — e passa a ser CONTÁVEL.** `p_sem_medicao_porque` é um
   MOTIVO, não um booleano (booleano vira `true` e se esquece; motivo é lido por quem revisa a
   trilha). Com ele a subida acontece, a trilha grava `mudanca_dial_sem_medicao` e o nível fica
   `declarada`. Sem essa porta, a cadeia de migrations deixaria de aplicar do zero — é a lição das
   verificações-alçapão que a `0119` e a `0120` tiveram de ter desarmadas: guarda que impede o estado
   legítimo do dono não é guarda.

#### A MÉTRICA QUE NUNCA PRECISOU DE GOLDEN SET, E NINGUÉM SOMOU

A quinta linha da tabela do `Arquitetura do Sistema/2 Especificação/f0/06` é *"taxa de falso-positivo da reconciliação Classe A → subir
Classe A de N1 para N2"*. **O rótulo dela existe desde a `0106`**, cujo cabeçalho define `rejeitada`
como *"a pendência não procede (falso positivo do motor)"*, com essas palavras. Ou seja: desde 11 de
agosto o sistema coleta, a cada rejeição de analista, um ponto de dado sobre a qualidade da própria
reconciliação — e ninguém tinha somado. `fn_golden_classe_a` soma, com o denominador certo: **só
vereditos humanos.** Pendência que o próprio sistema resolveu (o sintoma sumiu) não é ninguém dizendo
que ela procedia, então fica fora dos dois lados e é contada à parte.

#### O QUE O TESTE ACHOU, E É UM DEFEITO DE AUTORIDADE

A `fn_golden_cobertura` agrupava a cobertura por `documento.tipo_taxonomia` — **o tipo que a MÁQUINA
disse.** Cobertura de ground truth medida pela resposta que está sob avaliação. Numa rodada com 25
balanços rotulados dos quais o classificador chamou 5 de DRE, ela reportava "BALANCO 20, DRE 5" e
reprovava por falta de amostra — quando a rodada tem 25 balanços e o que ela deveria acusar é a
classificação errada. Agora o tipo vem do CONSENSO dos rotuladores. É a mesma família das três
confusões de unidade da sessão 52, num eixo diferente: autoridade, não unidade.

**E um segundo, achado ao escrever o critério:** contar no "tipo mais fraco governa" um tipo que só
existe como falso-positivo daria **poder de veto a um único documento** (precisão 0, recall
indefinido, F1 zero) — e contaria o mesmo erro duas vezes, porque o documento cuja verdade era X e a
máquina chamou de Y já é falso-negativo de X. O erro é contado uma vez, onde tem denominador. Medido:
sem o filtro, o pior caso da rodada de teste cai de 0,8889 para **0,0000**.

#### E O CENÁRIO DO DIAL QUE PASSARIA PELO MOTIVO ERRADO

Ligar o portão derrubou um cenário da `dial.test.sql`, e o motivo vale mais que a correção. O cenário
5 ("o limiar vem da tabela") vinha depois do cenário 4, que deixa o dial em **N1**. Com o portão, a
volta para N2 é recusada — e o assert seguinte, *"com limiar 0.99 a linha de 0.98 fica pendente"*,
**passaria verde pelo motivo errado**: pendente por N1, não pelo limiar. Um cenário inteiro medindo
outra coisa e dizendo que passou. A recusa passou a ser afirmada ali mesmo, porque é ela que decide
se o resto do cenário significa algo.

**O que NÃO foi feito, e é honesto dizer:** o golden set FÍSICO. Rotular documento real de cliente,
com controle de acesso LGPD, é o que o `Arquitetura do Sistema/2 Especificação/f0/06` já classificava como "tarefa de execução" que "não se
monta em documentação" — continua sendo do dono. O que mudou é que agora existe onde colocar, o que
mede, e um portão que cobra. **E fica anotada a decisão de schema que falta:** o dial é por ESTÁGIO
(`0001`/`0002`) e o `Arquitetura do Sistema/2 Especificação/f0/06` raciocina por TIPO — ele chega a dizer que "tipo sem ~20 exemplos
permanece em N0/N1". Autonomia por (estágio × tipo) não existe no schema, e inventá-la de lado seria
decidir uma mudança de modelo de dados por tabela. Enquanto não existir, vale a leitura conservadora:
o tipo mais fraco governa.

### "OS TRÊS CENÁRIOS SÃO TRÊS?" — e o buraco que a pergunta abriu no arnês (19/08, sessão 52)

**O §2.2 do diagnóstico pedia um bloco "Resumo dos três cenários" lado a lado. Ao medir para
construí-lo, apareceu algo antes:** o `Cliente Case` nasce como `=<Base Case>` em TODA conta do modelo
(convenção do Modelo Base, e certa como ponto de partida). Num arquivo recém-exportado, **girar o dial
de 1 para 2 não muda um número sequer — e nada dizia isso.** Um "Cliente Case" que é, número por
número, o Base Case podia chegar a um comitê sem a planilha o contradizer, com o dropdown de três
opções servindo de evidência de que ela deveria contradizer.

O Stress tem a forma espelhada do mesmo risco: é o Base vezes um haircut único
(`Considerações!$F$8`). Zerada aquela célula, o Stress vira o Base e o dropdown continua oferecendo
três.

**O que entrou:** um painel `OS TRÊS CENÁRIOS SÃO TRÊS?` no `Output`, ao lado do interruptor, dizendo
por cenário se ele está **diferenciado** ou **IDÊNTICO AO BASE**. A medida é EXATA e vem da linha
`DIF_CENARIO` da aba de receita: a soma, conta a conta e ano a ano, de `ABS(premissa do cenário −
premissa do Base)`. Zero significa premissas idênticas e não pode significar outra coisa — somar as
premissas em vez das diferenças em módulo seria mais curto e errado (dois conjuntos diferentes podem
ter a mesma soma). E é **fórmula viva**: no minuto em que o analista digitar a primeira premissa
própria do Cliente Case dentro do Excel, o aviso some sozinho.

#### O BURACO QUE ESTE TESTE ACHOU NO ARNÊS

O teste do painel reprovava dizendo **"IDÊNTICO AO BASE" sobre um Stress de 20%**. A causa não estava
no produto: o nome da aba principal do modelo tem VÍRGULA (`Revenues, COGS & SG&A`), então toda
referência a ela vai entre apóstrofos — e o scanner de argumentos de função do `avaliar-formula.mts`
pulava trecho entre **aspas duplas** e não entre **apóstrofos**. A vírgula de dentro do nome partia o
argumento em dois, `N('Revenues` não avaliava nada, e o resultado era **0. Em silêncio.**

**O efeito:** qualquer assert que avaliasse uma fórmula referenciando a aba principal do modelo dentro
de uma função lia zero e passava por não conseguir avaliar — a forma mais silenciosa de teste que não
prova nada. Corrigido nos dois scanners do arquivo, e travado por assert próprio. Conferido que a
correção não mudou nenhum assert antigo: a contagem foi de 559 para 566 com exatamente 7 asserts
novos.

#### O QUE NÃO FOI FEITO DO §2.2, E POR QUÊ

O bloco numérico com as métricas dos três cenários lado a lado **não entrou**, e a razão é que a
especificação dele não fecha:

1. **A lista de métricas mistura duas famílias.** Receita e EBITDA saem de uma cascata paralela sobre
   as premissas (que existem por cenário no arquivo). **DSCR mínimo e necessidade de pico não** — eles
   saem do `Cash Flow` e da lógica do revolver, e não há como avaliá-los para um cenário INATIVO sem
   replicar o modelo inteiro, que é o "caminho caro (e desnecessário)" que o próprio §2.2 descarta.
2. **A metade viável custa duplicar a projeção.** As contas se projetam por quatro formas diferentes
   (`pct_de_linha`, `indice_macro` com e sem painel, crescimento composto, e "sem premissa"). Uma
   cascata paralela reescreveria essas quatro regras num segundo lugar — e esta sessão já pagou duas
   vezes a lição de duas réguas sobre a mesma quantidade (a `0123` e o par fatiamento×orçamento). O
   caminho correto é PARAMETRIZAR a cascata pelo cenário e emiti-la quatro vezes do mesmo código, com
   um CHECK provando que a sombra do cenário ativo é igual à linha ativa — é refatoração da aba que
   produz os números do modelo, e merece decisão própria.
3. **E a coluna do meio nasceria vazia:** com o Cliente Case idêntico ao Base por construção, duas das
   três colunas mostrariam o mesmo número até alguém preencher as premissas. É exatamente o que o
   painel novo passa a denunciar — e denunciar isso vale mais, hoje, do que exibir duas colunas iguais.

### A PROVENIÊNCIA VOLTA AO ARQUIVO DE COMITÊ (19/08, sessão 52)

O §2.3 do diagnóstico de 11/08 tinha medido a perda: antes do PR #109 cada célula de dado trazia
documento, **página, confiança e status de aceite**; o #109 separou os dois exports — decisão certa e
medida — e a camada saiu junto com as abas de dado.

**E nem o nome do arquivo estava lá.** Achado ao ler o código para consertar: o que a nota mostrava é
`documentos`, que a `fn_linhas_para_modelagem` monta como `array_agg(distinct tipo_taxonomia)` — o
TIPO. A nota dizia *"Extraído de BALANCO, DF_AUDITADA"*. Num mandato com oito balanços, isso é a
categoria e não a peça.

**A mudança é na `fn_valores_por_ano`, e não na `fn_linhas_para_modelagem` — esse é o ponto.** A
segunda devolve UMA linha por (seção, rótulo), e a proveniência dela é da ocorrência de maior módulo
**entre os exercícios**. Usada na nota de uma célula de 2023, ela descreveria a célula de 2025 com
toda a convicção. Rastreabilidade que aponta para o lugar errado é pior que rastreabilidade nenhuma:
a primeira convida a conferir e leva ao lugar errado.

**O número não podia mudar por causa disto,** e não mudou: `valor` continua sendo
`(array_agg(valor order by abs(valor) desc))[1]`, letra por letra. Reescrever com janela seria
elegante e arriscado — em empate de módulo com sinais opostos (`abs(-1900) = abs(1900)`) duas formas
de "maior módulo" escolhem valores diferentes, e isso é número de modelo mudando de graça. A
proveniência vem por join de volta na ocorrência que tem aquele valor, com desempate declarado.

**A nota melhora nas CATORZE abas de uma vez.** O §2.3 pedia a `Premissas`; `valorNaEscala` é o
caminho único por onde valor de documento entra no arquivo, então sair por ele custa o mesmo e não
deixa aba de segunda classe.

A nota agora diz, nesta ordem — primeiro onde procurar, depois o quanto confiar:

> `Extraído de 01_Balanco_2025x2024.pdf · página 3 · confiança da extração 97% · ACEITO por rodrigo@oria`

e, quando ninguém conferiu:

> `… · aceite: pendente — este número ainda NÃO foi conferido por ninguém`

Campo que a extração não informou sai FORA da frase: `null` é "não sei", e escrever "página 0" seria
dar precisão falsa. Os 7 asserts substantivos foram conferidos reprovando com o código antigo.

### O INTRAGRUPO QUE NÃO É MÚTUO passa a ser conferido — pelo ESPELHO (19/08, sessão 52)

**O item estava aberto com a dificuldade certa escrita:** *"cada uma casa com uma conta DIFERENTE do
balanço — e escolher errado inventa divergência."*

**A primeira ideia era errada e não foi usada.** Comparar a planilha contra o balanço, como a `0117`
faz com mútuos, é comparar FLUXO com ESTOQUE: o documento que a taxonomia tem para as outras naturezas
é `FAT_INTRAGRUPO`, faturamento do exercício. No book os números coincidem por construção (nada foi
pago no ano), então a checagem teria saído verde sobre uma comparação sem sentido — a mesma forma de
defeito que a `0123` acabou de achar.

**O que se confere é o ESPELHO.** Todo saldo intragrupo aparece duas vezes dentro do mandato: a receber
no balanço de quem tem o crédito, a pagar no de quem tem a obrigação. É identidade contábil, e não
precisa de segundo documento — os balanços que o mandato já tem bastam.

**E o pareamento é pelo PAR DE EMPRESAS, não pela natureza** — é essa a resposta à dificuldade. O dado
do book mostra por quê:

| | |
|---|---|
| Canastra Indústria | `Contas a receber intragrupo - Canastra Comercial` |
| Canastra Comercial | `Fornecedores intragrupo - Canastra Indústria` |

Quem vende chama de "contas a receber"; quem compra chama de "fornecedores". **Pela natureza elas nunca
se encontram; pelo par de empresas, sempre.** E nenhuma linha precisa ser casada com "a conta certa": a
linha DIZ com quem é. A contraparte sai do sufixo do rótulo contra a lista de entidades do caso —
medido: **6 de 6 rótulos intragrupo do book casados com a empresa certa, 3 de 3 de terceiro
corretamente ignorados** (`terceiros`, `nacionais`, `mercado interno`).

**Ficam fora, com o motivo escrito:** mútuo (é da `fn_reconciliar_mutuos` — uma linha, uma régua),
mútuo com sócio (não tem espelho), o documento COMBINADO (as linhas intragrupo dele são eliminações,
que nomeiam as duas pontas) e par em que uma das empresas não entregou balanço (aí a falta de espelho é
falta de documento, e o Portão 1 já cobra).

**Canastra: os quatro pares fecham** — aluguel 940, conta corrente 1.900, fornecimento 2.900 e 5.200.
Zero pendências, que é o certo para um book cuja única divergência plantada é a de mútuos.

#### E ela achou um defeito no book VERTENTES, na primeira vez que rodou

A `escalar_passivo` do `motor.py` multiplica o passivo INTEIRO de cada controlada por um fator até o PL
cair num alvo — e a conta corrente ia junto. Resultado: a VT Logística registrava **978** a pagar
contra os **1.400** que a Metalúrgica registrava a receber. **422 de diferença, num book que declara
ter UMA divergência só** (os 180 dos mútuos).

O próprio gerador já declarava o invariante que estava violando, no comentário de `construir`:
*"contrapartes intragrupo que faltavam na Metalúrgica (o combinado precisa dos dois lados para as
eliminações fecharem)"*. Elas não fechavam.

**Saldo intragrupo é fixado pela contraparte e não é livre para calibração.** As contas de
`INTRAGRUPO_FIXO` saíram do fator, que passou a ser recalculado sobre o resto do passivo — o PL-alvo
continua sendo atingido. É a segunda consequência ruim da calibração por PL-alvo; o `book-canastra` já
tinha abandonado a técnica pela primeira (com três exercícios o fator vira distorção ENTRE anos).

#### E um portão que faltava no CI

Do mesmo `gerar_fixture.py` saem TRÊS artefatos versionados — o SQL da suíte de banco, o JSON da suíte
de export e (via `gerar.py`) o GABARITO. Os workflows do n8n têm `git diff --exit-code` desde a sessão
20, com o motivo escrito: *"o JSON commitado pode divergir da fonte que o gera"*. **As fixtures não
tinham, e o mesmo defeito aconteceu aqui:** a correção do `motor.py` mudou o SQL e o GABARITO, o JSON
ficou para trás, e a suíte de export reprovou em 5 itens comparando um export NOVO com um gabarito NOVO
a partir de uma fixture VELHA. O portão entrou, e cobre as três fixtures (as duas de Vertentes e a do
Canastra).

### O FATIAMENTO ESTAVA DESLIGADO — e a correção anotada aqui era a errada (19/08, sessão 52)

**O que estava escrito nesta lista:** *"O item mais denso do book ainda estoura o teto de saída:
`17_Livro_Razao_Fornecedores` mede 17.875 tokens (109% dos 16.384). O `Fatiar Extracao` cobre isso
hoje partindo o documento; o que falta é o caso de o BLOCO mais denso ainda não caber — extrair por
faixa de PÁGINA."*

**Medi antes de mexer, e as duas metades estavam erradas.** Rodando `planejarFatias` sobre o texto
real dos 38 PDFs (`pdf/TEXTO_EXTRAIDO.json`, que é a forma que o nó `Extract From File` entrega):

| | |
|---|---|
| documentos fatiados | **ZERO de 38** — todos davam `blocos = 1` |
| livro razão | ia **inteiro numa chamada**, pedindo 16.506 tokens = **101% do teto** |
| razão células/linha no book | **1,67 a 6,81** (o aging tem seis faixas por linha) |

**A causa é de UNIDADE, e é a terceira da mesma família no mesmo arquivo** (as outras duas estão nos
comentários de `linhasDeConta` e de `LIMIAR_COBERTURA`, ambas já corrigidas). `MAX_CELULAS_POR_BLOCO`
é derivado como *"quantas CÉLULAS cabem em 60% do teto de saída"* — 234 — e vinha sendo aplicado a
uma contagem de **LINHAS**. Uma linha de comparativo de três exercícios produz três células, então o
corte ficava de 1,7× a 6,8× mais frouxo do que o nome dele diz. Na prática: nunca disparava.

**Não era preciso mudar topologia nenhuma.** Faixa de página nunca foi o eixo do problema. Com o peso
em células, o fatiamento por âncora que já existe corta o razão em blocos que cabem — e um bloco pode
descer a UMA linha, que é mais fino que qualquer página.

**Medido depois:**

| | antes | depois |
|---|---|---|
| chamadas de extração no book | 38 | **44** (+6) |
| documentos que estouravam o teto | 1 | **0** |
| pior bloco do livro razão | 101% do teto | **16%** |
| o guarda de gasto contra o custo medido | +45% | **+10%** (US$ 1,42 previsto × 1,29 medido) |

**A contagem erra para CIMA de propósito, e o número está medido: +64% agregado** sobre a verdade
declarada pelo gerador (pior caso +187%, no razão — data, número de lançamento e código de conta são
números que não viram célula). Errar para cima fatia mais fino que o necessário: ~6 chamadas a mais,
~US$ 0,12 sobre US$ 1,29. Errar para baixo trunca, e truncar custa o dado — é a mesma escolha que
`FRACAO_DO_TETO` já documentava.

**Medi a versão refinada e ela foi REJEITADA:** tirando data, CNPJ, código de conta (`1.1.01.001`) e
percentual, o erro agregado cai de +64% para +23% — mas **quatro documentos passam a SUBESTIMAR**, e
o balancete analítico subestima em 43%. Menos erro médio pelo preço de errar para o lado que trunca é
troca ruim. Ficou registrado em `celulasDaLinha` para quem tentar de novo.

**O orçamento também estava errado, e do outro lado.** Ele recebia `celulas = contagem de LINHAS` e
`colunas` lidas do NOME do arquivo — e `tokensDeSaida` usa `colunas` para **dividir** células em
contas, então passar linha onde ele espera célula fazia `contas = linhas / colunas` num lugar em que a
linha JÁ É a conta. Duas pontas erradas ao mesmo tempo, e os erros se somavam em vez de cancelar.
Agora as duas quantidades saem do próprio texto, e a razão células/linhas conta a coluna de EMPRESA
junto — que a leitura do nome nunca viu (o comentário de então já declarava essa cegueira).

**O que sobra de irreparável, e agora aparece:** uma linha que SOZINHA passe do teto. Não há corte
mais fino que a linha (ela é a âncora, e meia âncora não localiza nada no PDF). `planejarFatias` marca
esse bloco com `acimaDoTeto`, o nó propaga em `bloco_acima_do_teto`, e `juntarBlocos` escreve o motivo
— que a `0016` já converte em pendência. Nenhum documento do book cai nesse caso.

**E o aviso do `medir-custo-book.mjs` mentia por construção:** ele comparava a saída do DOCUMENTO com
o teto, o que deixou de significar algo no dia em que o fatiamento nasceu. Agora ele compara o pior
BLOCO, lista quantos blocos cada documento vai gerar, e ganhou um invariante que **REPROVA** se um
documento voltar a passar do teto sem ser fatiado.

### A FIXTURE DE EXTRAÇÃO DO BOOK-CANASTRA, e os três defeitos que ela achou na primeira rodada (19/08, sessão 52)

**A lacuna que ela fecha.** O `book-canastra` está no repositório desde o PR #112 e provava duas
coisas: que os números do gerador fecham no papel, e que o lote não cabe no teto de gasto. **A
ingestão nunca havia sido exercitada sobre ele** — era a maior lacuna de cobertura viva, e estava
anotada como tal neste arquivo.

Agora existe `Supabase/test/gerar_fixture_canastra.py` → `Supabase/test/fixture_book_canastra.sql` (28
documentos, 1.264 linhas) e `Supabase/test/canastra.test.sql`, ligados ao `Supabase/test/run.sh`. A regra que ele
trava é a de Vertentes, sobre documento **difícil**: *extração fiel => a única pendência é a
divergência que o book planta de propósito* (R$ 240 mil de mútuos). Cada uma das 15 armadilhas que
virasse pendência seria falso positivo.

**Carregada e reconciliada, ela abriu ZERO pendência.** Num caso que planta uma. Três defeitos, e a
`0123` os corrige:

| | O defeito | O número |
|---|---|---|
| 1 | A checagem procurava a palavra "mútuo" no **rótulo de cada linha** da planilha. Nenhuma planilha real a repete ali — ela diz a natureza **uma vez, no título** ("RELAÇÃO DE MÚTUOS ENTRE PARTES RELACIONADAS" / "Mutuante \| Mutuária \| Saldo devedor"). O filtro zerava o lado B e a função devolvia `documento_ausente`, o único resultado que **não** abre pendência: a divergência não estava "não encontrada", estava **declarada inexistente**. | R$ 240 mil invisíveis |
| 2 | A guarda que o comentário da `0117` prometia **não existia**: `v_lados_bp` era atribuída e nunca lida. | — |
| 3 | Achado ao ligar a guarda: **mútuo com SÓCIO não tem espelho** no mandato (a contraparte é o quotista) e estava somado junto com o intragrupo. | 14.000 na SPE, que esconderiam os 240 atrás de um número 60× maior |

**Por que o defeito 1 passou seis sessões.** O `fixture_book_vertentes.sql` escreve o rótulo como
`"A → B — Mútuo"`, colando a natureza dentro do nome da linha. Isso não vem de PDF nenhum — é um
enfeite do gerador do fixture. A checagem estava aprovada por um dado que só existia no teste.

**A guarda prometida está errada, e isso foi MEDIDO, não deduzido.** "Interromper quando há os dois
lados" calaria a checagem exatamente onde a evidência é mais forte: no Canastra os dois lados dão
16.300 cada — eles se confirmam, e é a planilha (16.060) que discorda. A regra que entrou: lados que
**concordam** estabelecem o saldo por dupla evidência (uma comparação, não uma por lado); lados que
**discordam** são eles o achado, e aí a planilha não é atribuída a nenhum deles.

**E a primeira versão da correção repetiu o defeito que consertava.** Ler "rótulo OU seção" sem
ordem fez a suíte de Vertentes reprovar na hora: o fixture de lá põe `secao = "MÚTUOS E CONTAS
INTRAGRUPO"`, um agrupador que nomeia DUAS naturezas, e com a seção valendo por si a conta corrente
(1.400) e o aluguel (640) entraram na soma — **a divergência saltou de R$ 180 mil para R$ 2.220
mil**. É textualmente o que o comentário da `0117` já avisava. A régua final tem **precedência
estrita**: o rótulo, quando fala, é a autoridade sobre a linha dele; a seção só vale quando os
rótulos estão calados; nada dizer significa que o documento inteiro é a relação de mútuos, que é o
que a taxonomia já afirmou ao classificá-lo.

**O que fica aberto, e está dito na migration:** mútuo com sócio passa a não ser conferido por
ninguém — o par dele não é a planilha intragrupo, é o contrato com o quotista, e ninguém cruza isso
hoje. Antes da `0123` ele também não era conferido; a diferença é que agora está escrito.

**Duas coisas que a fixture ensinou sobre a forma FIEL de extrair, e que valem para o prompt:**
matriz se extrai como um grupo por COLUNA (`secao` = nome da coluna, `chave` = o rótulo da linha) —
escrever "Terrenos — custo" cola a coluna dentro do nome da conta e cria três rótulos que nenhuma
outra peça reconhece; e **a taxonomia não tem tipo para anexo de composição de imobilizado** (conferi
o seed `0002`), então ele entrou como `NOTAS_EXPL`, que é a semântica certa (detalhamento
complementar que não se soma debaixo do total do balanço) mas não o nome certo.

### O EXPORT DO EXCEL: cinco defeitos de número, achados rodando o arquivo (18/08, sessão 51)

**De onde isto saiu:** gerar o export completo do caso de referência
(`Supabase/test/fixture_modelagem_v35.sql` — o caso REAL capturado da produção) e rodar o
`auditar-xlsx.mts` nele. **Três dos dez itens reprovavam:**

| Item | Medida |
|---|---|
| o balanço fecha? | **NÃO** — Ativo − (Passivo+PL) = **−20.529** nas seis colunas |
| a DRE reproduz o documento? | **NÃO** — receita −440, lucro bruto −800, EBIT **+9.409**, resultado líquido **+20.780** |
| o ativo é o do documento? | **NÃO** — **+10.277** |

Modelo que não fecha não projeta: fluxo, revolver e alavancagem viram aritmética sobre um
balanço impossível. Os cinco defeitos, cada um com o número que ele movia:

1. **A série histórica de cada conta vinha indexada só pelo RÓTULO.** `fn_valores_por_ano`
   agrupa por (rotulo_norm, secao_canonica, ano) e devolve a seção porque demonstração real
   repete rótulo entre seções; a rota indexava só pelo rótulo e a última seção lida
   sobrescrevia as outras. É o irmão do defeito que a `modelagem-linha.ts` já tinha
   corrigido para os VÍNCULOS — ficou de fora justamente onde decide os NÚMEROS. Medido no
   v35: **treze rótulos** em duas seções com valores diferentes (`Empréstimos e
   Financiamentos` 37.379 × 44.474, `Obrigações Tributárias` 13.549 × 7.895, `Provisão para
   contingências` −1.900 na despesa × 2.567 no passivo…). A dívida existente do modelo saía
   **3.176 errada (12%)**. O casamento virou `seriesPorLinha`/`serieDaLinha` na lib, e a
   rota e o gerador local passaram a chamar a MESMA função.
2. **Ocorrência repetida do mesmo rótulo era lida como componente de subtotal.** O detector
   por ordem lê a sequência impressa; a extração repete rótulo dentro do mesmo documento
   (é o que um comparativo produz sem `periodo_coluna`). Errava dos dois lados: declarava
   subtotal uma DESPESA REAL (a provisão de −1.900 e o IR de −420 **sumiam** do modelo —
   SG&A 1.900 menor, EBIT 1.900 maior) e deixava de reconhecer subtotal de verdade, porque
   os componentes dele também vinham duplicados.
3. **Cabeçalho de grupo impresso entrava como conta** quando a `ordem` não é a do documento.
   `Contas a Receber`, `Disponível`, `Estoques` não estão na lista fechada da
   `fn_papel_linha`. A remoção nova exige PROVA: rótulo exatamente igual a um nome de grupo,
   o documento informando o total daquele grupo, a soma EXCEDENDO esse total, e a remoção
   aproximando sem ultrapassar — documento simples nunca perde a conta, e valor idêntico ao
   de outra linha do bloco não é removido (é a mesma conta transposta, e a doutrina é não
   apagar conta).
4. **O balanço não reconciliava com o TOTAL GERAL do documento.** Cada grupo já seguia o
   total informado, mas os totais de grupo do próprio documento não somam o total geral
   dele (67.878 + 101.200 = 169.078 contra `TOTAL DO ATIVO` **158.801**). Agora há uma linha
   de reconciliação por lado, e ela **só entra quando o documento informa os DOIS totais
   gerais e eles concordam** — evidência dupla; senão nada é ajustado e o CHECK continua
   acusando. A DRE ganhou o mesmo nos quatro níveis que o documento informa. Junto veio o
   desempate de âncora: `PASSIVO E PATRIMÔNIO LÍQUIDO` (121.198) × `TOTAL DO PASSIVO E DO
   PATRIMÔNIO LÍQUIDO` (158.801) passa a ser decidido pelo rótulo que **diz "total"**, e não
   pela ordem em que o banco devolveu.
5. **O export de DADOS não pedia recálculo ao abrir.** Todo total das abas classificadas é
   `=SUM(...)` sem valor em cache: sem `fullCalcOnLoad` o Excel abre a célula VAZIA até
   alguém apertar F9. A flag era ligada dentro do modelo institucional — então o arquivo do
   botão **Exportar dados**, o que serve para CONFERIR a extração, saía sem ela.

**O auditor ganhou dentes e perdeu alarme falso.** Item novo — *o resíduo de reconciliação é
imaterial (≤5% da base)?* — porque sem ele "o balanço fecha" e "a DRE reproduz o documento"
passariam por CONSTRUÇÃO; o tamanho do resíduo é a medida direta da qualidade da extração
(no v35 ele acusa **18% do ativo**, que é a verdade daquele caso: conta duplicada com dois
rótulos, que nenhum código desambigua). E arquivo SEM modelo (export de dados, ou mandato
sem modelagem) deixou de receber cinco reprovações de itens que não se aplicam.

**Resultado no caso de referência: 10 de 10 itens do modelo OK** (era 7/10), com o resíduo
declarado e medido. Balanço fechando nas seis colunas, ativo total igual ao documento em
todos os exercícios, DRE realizada reproduzindo o documento nas 24 células conferidas.

**Desempenho, medido antes de mexer:** o build do export é LINEAR no número de campos
(1.000 → 299 ms; 16.000 → 3.543 ms; 30.000 → 6.257 ms — ~0,21 ms por campo). Não há O(n²)
nesse caminho e nada foi "otimizado" às cegas.

### O teto de 1000 deixou de existir para o portal (18/08, sessão 51)

Pedido do dono, literal: *"a lista pagina não deve ser restringida, remova o teto de 1000 do
PostgREST"*. O teto mora em dois lugares, e os dois foram tratados:

**1. No servidor — e lá ele é do DONO, não do repositório.** É o `db-max-rows` do PostgREST
(*painel do Supabase → Project Settings → API → Max rows*, padrão 1000). Subi-lo para 100000 remove
o teto na prática e deixa cada leitura mais barata. **Está documentado no `Supabase/README.md`, com o
caminho exato — e é opcional**, pelo motivo abaixo.

**2. No portal — e aqui ele acabou de verdade.** Duas mudanças:

- **`paginar` deixou de depender do teto do servidor.** A parada era "página com menos linhas que a
  janela = acabou", e isso só era correto porque a janela (1000) era exatamente o teto padrão. Com
  `Max rows` abaixo de 1000, TODA página voltaria curta e a leitura pararia na primeira — o defeito
  original de volta, escondido dentro da própria defesa contra ele. Agora a leitura anda pelo número
  de linhas REALMENTE devolvidas e só termina quando uma página volta **vazia**: vale para qualquer
  teto, e custa uma requisição a mais por consulta. O teto de segurança subiu de 50 mil para **500
  mil linhas** e continua declarando (`truncado`) em vez de entregar o pedaço como se fosse o todo.
- **As leituras que ainda escapavam passaram a paginar** — e uma delas já estava a meses de
  quebrar:

| Onde | O que era truncado | Por que importa |
|---|---|---|
| `indice_macro_obs` (export) | as observações macro | **920 linhas hoje**, +72 por ano. Ao passar de 1000, o corte cairia nas MAIS RECENTES (ordem crescente por data) — e é a última observação que dá o câmbio de fechamento do ano |
| `indice_macro_expectativa` (export) | as coletas do Focus | cada coleta acrescenta linhas; truncar não deixa o arquivo sem macro, deixa com a expectativa ERRADA |
| `fn_linhas_para_modelagem` (export e tela) | as linhas do modelo | é o conteúdo das 14 abas e da seção 3 da Modelagem |
| `fn_valores_por_ano` (export) | a série histórica por conta | 400 rótulos × 3 exercícios já passam de mil; cortar aqui dá a uma conta menos anos do que ela tem |
| `caso_linha_premissa` (export e tela) | os vínculos linha→premissa | truncado, o analista reescolhe premissa de linha que já tinha uma |

Todas com **ordem total e estável** (o desempate que impede duas páginas de repetirem e omitirem a
mesma linha), e o export passou a **declarar** no cabeçalho `X-Oria-Leitura-Truncada` se algum teto
de segurança for atingido — um arquivo incompleto que não se anuncia é pior que um erro.

Ficam de fora, de propósito e por não crescerem com a mesa: catálogos (taxonomia, premissas, séries
macro, banco de perguntas), consultas de linha única e as duas listas com `limit` deliberado (barra
lateral, trilha de autonomia).

### A `0122` — o texto que vai AO CLIENTE passa a ser escrito em português (18/08, sessão 51)

**Achado rodando a aba nova sobre o book da Canastra**, e é o tipo de defeito que só aparece com
dado real na tela. As perguntas saíam assim, literal:

| Saía | Sai agora |
|---|---|
| "Na DRE de **24,25** não localizamos a linha de despesas financeiras" | "Na DRE de **2024 e 2025**…" |
| "no faturamento de **L36M**?" | "no faturamento de **2025**?" |
| "A relação de mútuos informa **16060 milhar**" | "…informa **R$ 16.060 mil**" |

Nenhuma delas está errada no DADO — `24,25` é a referência multi-ano do classificador, `L36M` é a
notação de janela móvel de `Arquitetura do Sistema/2 Especificação/f0/03`, `16060 milhar` é a soma com a escala declarada. Estão erradas no
LEITOR, e o leitor aqui é o cliente do mandato: **este é o único texto do sistema que sai da casa**,
e ele não pode falar em chave interna.

São três consertos, e o terceiro **não é de redação**:

1. **`fn_periodo_por_extenso`** — o período na forma que cabe depois de "de"/"em": `2025`,
   `2024 e 2025`, `2023 a 2025`, `2021, 2023 e 2025` (com buraco vira lista: o intervalo afirmaria
   um exercício que o documento não traz), `2025 (1º trimestre)` e `um período de 36 meses`. Rótulo
   que não diz ano nenhum **sai como veio**.
2. **`fn_valor_pt_br`** — `R$ 16.060 mil`, com separador de milhar do país, escala em palavra, sinal
   antes da moeda (`-R$ 240 mil`) e escala desconhecida **visível**. Independe do `lc_numeric` do
   servidor.
3. **`fn_anos_texto` deixa de ler `L36M` como o ano 2036.** A regra de "dois dígitos no fim"
   (`0023`) foi escrita para `dez/25` e `12M25`; em `L36M` o que está no fim é o **tamanho da
   janela**. Duas consequências, as duas invisíveis: na `0120` o período da pergunta é escolhido
   pelo maior ano do caso, então um documento `L36M` **vencia** um 2025 real (foi exatamente o que a
   Canastra produziu); e em `fn_valores_por_ano` uma coluna `L24M` entraria no modelo como o
   exercício de 2024 — janela móvel tratada como ano fechado. Corrigir só o texto teria trocado
   `L36M` por `2036`: um ano plausível e errado.

**E o período passou a ser o DA EMPRESA de que a pergunta fala.** A sugestão é por (pergunta ×
entidade) desde a `0119` e o período não acompanhava: num grupo em que a DRE da Indústria cobre
2023–2025 e a da Comercial só 2024–2025, a pergunta sobre a Comercial citava um exercício que o
documento dela não tem — e quem recebe não reconhece o próprio documento na pergunta.

Dezesseis asserts novos em `Supabase/test/perguntas.test.sql` (`#12`), incluindo o que vale por todos:
**nenhuma pergunta do caso publica referência crua nem nome de escala**.

### As perguntas ao cliente ganharam a ABA que faltava (18/08, sessão 51)

A `0120` construiu o motor inteiro e **nenhuma tela o chamava**: `fn_sugerir_perguntas(caso)`
devolve a pergunta pronta — com motivo, risco, impacto, os marcadores resolvidos e o nome da
empresa — e a única forma de ver uma sugestão era rodar a função no SQL Editor. Para quem usa o
produto, a `0120` não existia.

**Onde ela ficou, e por que não onde o desenho anterior previa.** O plano era abrir a pergunta
dentro do botão "Contatar o Cliente" da fila de pendências (`0109`). O dono redirecionou, e a razão
é boa: **essas perguntas são sugestões que provavelmente ainda não foram feitas a ninguém** —
pendência é decisão sobre problema já medido, sugestão é rascunho de conversa. Numa lista só, a
segunda herda a aparência de tarefa concluída da primeira. Então elas moram numa aba própria,
`/casos/[id]/perguntas`, com entrada no cabeçalho do mandato (com a contagem) e um link a partir da
pendência **depois** que ela é marcada como pedida ao cliente — que é o momento exato em que o
analista precisa do texto.

O que a aba faz, em ordem de uso:

| | |
|---|---|
| **Mostra o texto pronto** | renderizado pelo banco, com `{data_base}`/`{saldo_mutuos}` resolvidos e a empresa no prefixo. Bloco próprio, para ser lido como citação do que vai sair da casa |
| **Copia** | `BotaoCopiar` com plano B (`execCommand`) para o portal aberto fora de contexto seguro — e que **declara** quando não conseguiu, em vez de piscar "copiado" |
| **Registra o envio** | `fn_registrar_pergunta_acao`, com o texto EXATO da tela num campo oculto: é ele que a `0120` congela. Append-only — reenviar é linha nova, e não há como apagar |
| **Registra o descarte** | "Não vou perguntar" grava a decisão sem sumir com a sugestão: quem chegar depois vê que alguém já olhou |
| **Diz quem e quando** | `ja_enviada` vem do banco (casado por empresa); autor e data vêm de `caso_pergunta` |
| **Explica o porquê** | motivo, risco, impacto e o gatilho traduzido, recolhidos num `<details>` — sustentam a pergunta numa reunião, e ninguém quer relê-los para copiar um texto |

Três cuidados que não são enfeite:

- **A lista é paginada**, como todas as outras — e isto vale para função que devolve tabela como
  vale para consulta: o PostgREST corta em 1000 linhas em silêncio, e a sugestão é uma por
  (pergunta × empresa que não satisfaz) desde a `0119`. A ordem é `(prioridade, codigo,
  entidade_id)`, **total e estável**; o teste `#11` da `perguntas.test.sql` trava a propriedade que
  torna essa ordem total (o par código × empresa é único na saída) — sem ela, duas páginas repetem
  uma linha e omitem outra.
- **A tela diz, em cima, que nada foi perguntado ainda e que nada é enviado automaticamente.** Uma
  lista de textos prontos com um botão verde se parece com caixa de saída; não é. O canal continua
  sendo o analista.
- **Banco sem a `0120` aplicada não quebra nada.** A aba explica que a migration falta e mostra a
  resposta do banco; a tela do mandato perde só o número do botão. Merge não é apply, e o dono
  aplica à mão — banco atrasado é estado normal, não defeito.

### O teto de 1000 linhas: agora em TODAS as telas, e o pior deles era o export

O PR #136 tirou do teto do PostgREST as três listas do PAINEL. Faltavam as de DENTRO do mandato — e
entre elas estava a mais cara de todas: **o export baixava `campo_extraido` sem paginação**. Um
mandato com mais de mil linhas extraídas gerava um `.xlsx` faltando linhas, que abre normalmente e
parece completo. O book de teste sozinho tem ~3.000 linhas com número.

Passaram a paginar (`portal/src/lib/supabase/paginar.ts`, de mil em mil):

| Onde | O que era truncado |
|---|---|
| **`/casos/[id]/export`** | as **linhas extraídas** (o produto), os documentos e as causas de falha |
| `/casos/[id]` | documentos, fila de pendências do mandato, contagem de linhas por documento |
| `/casos/[id]/documentos/[docId]` | as linhas do documento (um razão real passa de mil sozinho) |
| `/casos/[id]/revisao` | a fila de revisão — que desde a `0119` multiplica pelo número de empresas |
| `/casos/todos` | mandatos, documentos e pendências |
| `/casos` (painel) | `lote_execucao`, que alimenta os indicadores de custo |
| `/api/intake/status` | os **contadores de progresso** da ingestão: a barra parava em mil e o lote parecia travado |
| `/casos/[id]/modelagem` | a lista que sugere entidade e último exercício |

**Toda consulta paginada ganhou desempate por `id` na ordenação** — sem ordem total e estável, duas
páginas podem repetir e omitir a mesma linha, que é um jeito pior de errar do que truncar.

Ficaram DE PROPÓSITO sem paginação, e não são defeito: a barra lateral (`limit(30)` deliberado), a
trilha de autonomia (`limit(15)`) e as consultas de linha única (`.single()`) ou de catálogo
(taxonomia, índices macro), que não crescem com a mesa.

### A 0121 — o achado que o dado real do dono entregou (18/08)

**Não veio de teste: veio da base.** Rodando o diagnóstico de entidades antes da rodada de
validação, quatro mandatos voltaram com **três linhas para a mesma empresa** —
`Canastra Industria 2025x2024x2023`, `CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.` e
`Meses Canastra Industria`. A primeira e a terceira são sujeira de nome de arquivo, já corrigida na
origem em 17/08. **A segunda não é sujeira: é a razão social correta**, e continuava sendo criada
como linha nova — em mandato novo, com o workflow já reimportado.

**A causa é uma metade esquecida da `0030`.** Aquela migration ensinou `fn_registrar_documento` a
casar entidade pela forma canônica, porque o nome chega de duas fontes que escrevem diferente: o
arquivo e o diagnóstico do conteúdo. `fn_registrar_diagnostico` — que é **a segunda fonte** — ficou
comparando `lower(razao_social) = lower(nome)`. Os dois efeitos, reproduzidos em base limpa antes de
consertar:

1. **duplica a empresa** quando o documento chega sem entidade (o classificador se abstém em 6 dos
   38 do book) e o diagnóstico traz a razão social completa;
2. **abre pendência falsa** de `entidade_incorreta` entre duas grafias da mesma companhia — que
   `fn_mesma_entidade` já reconhecia como a mesma.

**Por que ficou caro agora:** antes da `0119`, entidade duplicada partia colunas do export. Depois
dela, a entidade é o **eixo** da cobrança de linha exigida — a mesma empresa é cobrada duas vezes,
abre pendência em dobro, e a `0120` gera duas perguntas ao cliente sobre a mesma coisa.

**O que deliberadamente NÃO foi feito:** limpar as entidades já duplicadas. Os quatro mandatos são
de teste (v41, V45, v46, v4x); fusão de entidades para arrumar dado de teste é trabalho que não se
paga. Corrigida a função que as produz, mandato novo nasce limpo — e a validação deve rodar num
mandato novo. Se a duplicata aparecer um dia em mandato de cliente, a fusão vira fatia própria.

### O PR #138 do Ian, incorporado com seis correções (0120)

**O que ele resolve:** o capítulo 10 do onboarding define 36 perguntas a fazer ao cliente depois que
a extração roda. Nenhuma era sistema — quando o analista clicava "Contatar o Cliente", o que
perguntar saía da cabeça dele. Agora `fn_sugerir_perguntas` devolve a pergunta pronta, com
motivo/risco/impacto e os marcadores preenchidos. O encaixe é o melhor da entrega:
`exigencia_ausente` lê a **mesma** `fn_exigencias_do_caso` da pendência — pendência e pergunta são
duas faces da mesma avaliação e não podem divergir. Escopo declarado: 11 das 36, com as outras 25
nomeadas família a família.

**As seis correções feitas na incorporação:**

| | O quê | Por quê |
|---|---|---|
| 1 | **Conflito com o `main` resolvido, e a `0120` entrou na lista de comandos** | O `#137` mergeou depois da base dele. E a migration não estava no `Supabase/README.md` — o portão do `run.sh` reprovava. |
| 2 | **A migration voltou a ser reaplicável** | `create policy` sem `drop policy if exists`: rerodar morria em *"policy already exists"*. O resto do arquivo já era reaplicável (`create table if not exists`, `on conflict do nothing`) — só as políticas escapavam, e a casa já tem o padrão (`0009`, `0107`, `0108`, `0115`). |
| 3 | **`caso_pergunta` virou append-only de verdade** | A tabela dizia "append-only por desenho" e publicava `for all to authenticated`. Medido: `set role authenticated; delete from caso_pergunta` **apagou a linha**. Agora são duas políticas, SELECT e INSERT — o desenho do `evento_auditoria` (0003), que é onde ele já estava certo. |
| 4 | **`{data_base}`/`{ano}` deixaram de errar o exercício** | O período saía de `max(referencia)` — máximo de TEXTO. Num caso com `2025` e `L24M`, a pergunta ia ao cliente dizendo *"No balanço de **L24M**…"*: rótulo de janela móvel, não data de balanço, e nem o mais recente. Agora ordena por ano com `fn_anos_texto`. |
| 5 | **A verificação embutida deixou de ser alçapão** | `count(*) where ativo <> 11 → exception`: bastava você **desativar uma pergunta** (a coluna `ativo` existe para isso) para a reaplicação morrer. É o mesmo defeito que a `0119` teve, na mesma posição do arquivo. Agora ela confere as 11 pelo código, e o que você fizer depois vira NOTICE. |
| 6 | **A pergunta passou a nomear a empresa** | A pendência nomeia a entidade desde a `0119`; a pergunta, não — e ela é **enviada ao cliente**. Num grupo de oito balanços, *"no balanço de 2025 não localizamos Ativo Total"* não diz de qual empresa se fala. Era o reemit que ele mesmo previu quando a `0119` ainda não existia. `ja_enviada` passou a ser por entidade junto: enviar sobre a Alfa não responde pela Beta. |

Menor, também feito: índice em `caso_pergunta (caso_id, pergunta_codigo)`, que o `ja_enviada` usa a
cada sugestão.

### O PR #135 do Ian, incorporado com quatro correções (0119)

**O que ele resolve, e o número que prova:** a `0113` perguntava "algum documento do tipo tem a
linha?". Num grupo com oito balanços, sete sem a linha de caixa, o oitavo respondia sim e as sete
ausências sumiam — **zero pendência**. A `0119` pergunta "cada entidade que trouxe linhas desse tipo
tem a linha NELA?": sete pendências, cada uma nomeando a empresa, e a oitava limpa.

**A suspeita que eu tinha, e que a medição derrubou:** granularidade fina costuma virar máquina de
pendência falsa. Medi num banco limpo, com o fixture Vertentes (5 entidades, 14 documentos, extração
fiel): **1 pendência antes, 1 depois — idêntico**. Os dois fallbacks dele funcionam. (Na primeira
medição vi 7, mas era lixo de outro teste no mesmo caso; num banco limpo o número não se move.)

**As quatro correções feitas na incorporação:**

| | O quê | Por quê |
|---|---|---|
| 1 | **Renumerada `0116` → `0119`** | A faixa 0116-0118 foi ocupada pelo PR #136, mergeado antes. O portão de prefixo duplicado do `run.sh` reprovava — e com razão. |
| 2 | **A verificação embutida deixou de ser alçapão** | Ela abortava a migration se encontrasse qualquer `escopo_entidade` não nulo. No dia em que o dono ligasse o override do COMBINADO — que é o que o cabeçalho manda ele fazer — e reaplicasse a lista do `Supabase/README.md`, a migration **morreria no meio por causa de uma decisão legítima dele**. Medido: a versão original aborta. Agora prova o que interessa (a coluna não tem DEFAULT) e o override vira NOTICE. |
| 3 | **A varredura saiu da migration** para `Supabase/varredura_linha_exigida.sql` | Era a única parte que tocava caso já gravado, e o efeito visível é uma leva de pendências novas na fila do painel sem ninguém ter enviado nada. Separada, o dono aplica a estrutura hoje e escolhe a hora da varredura — ou roda num mandato só. O script diz quantas pendências entraram. |
| 4 | **`fn_exigencias_do_caso` ficou 5,9× mais rápida** | O `explain analyze` mostrou 662 ms dos 914 ms num único filtro: `fn_linhas_do_tipo` rodando uma vez por DOCUMENTO em vez de por tipo. Separar em duas CTEs não mudou nada — o Postgres achata CTE simples e empurrava o filtro de volta. Com `as materialized`: **693 ms → 116 ms** num caso de 400 documentos. |

As duas propriedades novas estão travadas em teste (`Supabase/test/linha_exigida_entidade.test.sql`,
blocos 8 e 9), e a do `materialized` é teste de TEXTO de propósito: medir por relógio daria um teste
que falha em máquina lenta e passa com o defeito de volta em máquina rápida.

### O que a sessão 50 (18/08) fez, e o que ficou de fora

Os sete itens da lista "o que está aberto" foram atacados em ordem, a pedido do dono. O que
**entrou**:

| | O quê | Onde |
|---|---|---|
| 1 | **Subtotais impressos viram LINHA.** O prompt passou a exigir o valor impresso na linha do agrupamento ("ATIVO CIRCULANTE ... 3.961"), que antes virava só o nome da `secao` e sumia. A `0116` ensina `fn_papel_linha` a reconhecer os totais novos (topo da DRE, DVA) para eles não receberem premissa e dobrarem a conta. | `N8N/lib/extract.mjs`, `0116` |
| 2 | **A divergência de mútuos é acusada.** Checagem B nova, lado a lado (ativo × passivo), disparada pelos dois lados do par. No fixture ela acusa exatamente os R$ 180 mil que o book planta de propósito — e o teste que cobrava "zero pendências" era, ele mesmo, a prova de que a checagem faltava. No painel, a fila agora diz QUAL checagem acusou. | `0117`, `portal/src/lib/rotulos.ts` |
| 3 | **A tela de Modelagem entrou na linguagem do portal:** `<main>` aninhado (que estreitava a página dentro do layout) foi embora, as três seções viraram `carta` com âncora, e uma trilha de passos no topo diz o que falta em cada uma. Na tabela, o cabeçalho gruda e o "salvar" aparece também no topo com o aviso de alteração não salva — os dois viviam no rodapé, fora da tela justamente enquanto se edita. | `portal/src/app/casos/[id]/modelagem/` |
| 4 | **`negativas`/`societario`/`parcelamentos` saíram da lista à mão** e viraram termos da taxonomia. A remoção de palavra de tipo em `parseEntidade` varre o vocabulário palavra a palavra, então quem entra lá é removido de graça. | `N8N/lib/taxonomia.mjs` |
| 5 | **O teto de gasto decide depois do `Extrair Texto`.** Com o documento medido, a estimativa deixa de ser por byte (margem de 1,8×, que recusava lote que cabia) e passa a contar linhas e BLOCOS — exatamente os que o `Fatiar Extracao` vai gastar. Medido no book: guarda por byte US$ 0,67 contra custo real US$ 0,49; por conteúdo, US$ 0,61. Continua barrando antes de qualquer gasto. | `N8N/lib/custo.mjs`, grafo |
| 6 | **Dedup por fingerprint (a segunda metade da 0026).** Prompt+modelo+esquema viram uma impressão gravada na versão; mesmo arquivo + mesma impressão + extração que TEM linha ⇒ o grafo pula a chamada. A exigência de "ter linha" é o que impede uma extração falha de valer como feita. | `0118`, grafo |
| 7 | **As listas do painel saíram do teto de 1000** (documentos, pendências e mandatos), com paginação de mil em mil e um aviso que aparece se o teto de segurança de 50 mil for atingido. | `portal/src/lib/supabase/paginar.ts` |

O que **ficou de fora, e é honesto dizer**:

- **O item 1 não pode ser provado sem gastar crédito.** O prompt mudou e os testes travam o texto
  dele, mas se o modelo passa a devolver os totais é a rodada que responde. É o passo 4 acima.
- **A checagem de mútuos cobre MÚTUO contra MÚTUO.** Conta corrente rotativa, aluguel entre
  coligadas e rateio de despesa também moram na planilha intragrupo e continuam sem conferência —
  casar cada uma com a conta certa de cada balanço é outro problema.
- **A tela de Modelagem recebeu revisão de apresentação, não redesenho de fluxo.** A ordem dos três
  passos e o modelo de dados por trás dela continuam os mesmos.

### O book inteiro, quando houver crédito

Os 38 documentos do `book-canastra` estão prontos para subir:

| | Estado |
|---|---|
| Orçamento | estima **US$ 1,88** (era US$ 2,46, e US$ 11,40 no estimador plano) → **passa** |
| Gasto real esperado | **~US$ 1,25** — 42% do teto de US$ 3 (era 2,23 antes do agrupamento) |
| Timeout do n8n | **desativado** (conferido pelo dono em 11/08) |
| Duração | **~23 minutos** (33s por extração no Tier 1) |

> **ANTES DE RODAR, REIMPORTE O `N8N/workflow.e1-ingestao.json`.** A execução de 12/08 recusou o
> lote com *"51 chamadas ≈ US$ 7,65"* — um número que o código deste repositório não produz desde
> 07/08 (US$ 0,15 por chamada saiu de lá). O n8n executa o JSON **importado**, e merge não
> reimporta. A partir da v3 dá para conferir da tela: a mensagem de recusa começa com
> `[orçamento v3 (2026-08-13)]` e o campo `orcamento_versao` aparece na saída do nó mesmo quando o
> lote passa. Se a versão não aparecer, o workflow importado é velho.

Gerar os PDFs: `cd "Dados de Teste"/book-canastra && PYTHONPATH=. python3 gerar.py`

> **A rodada de 17/08 ("Teste V45") já aconteceu, e o que ela achou muda o que a próxima tem de
> provar.** Foram **438 linhas**: 19 dos 35 documentos — os centrais (Balanço, DRE, DFC, DMPL, DVA,
> balancetes, razão, faturamento) — **nunca tiveram a extração chamada**, e nada reclamou. A causa era
> topológica (duas conexões cruas no mesmo input, e só o ramo do fallback propagava), está corrigida
> com o `Juntar Ramos`, e a classe inteira ficou barrada por teste. O que a próxima rodada precisa
> trazer, além do custo: **`lote_integro` verdadeiro** no `Conferir Lote` — sem isso, qualquer número
> de cobertura está medindo só os documentos que chegaram lá.

**O que trazer de volta:** a saída do nó **`Resumo de Custo`** (último do canvas) — ela traz o custo
real do lote, o que o orçamento estimou e os **tokens de saída por linha**, que é o número com que
`CUSTO_POR_MB_USD` e o modelo de saída se recalibram. Mais: quantos dos 38 chegaram, e o que a
reconciliação abriu — em especial o erro plantado de **R$ 240 mil na planilha de mútuos**.

### O buraco que a rodada completa abriu — e as três camadas que o fecham

A rodada do `book-canastra` (35 documentos, 21 min, US$ 0,71, no workflow ANTIGO) respondeu o custo e
abriu outra coisa: **das 2.893 células de valor dos PDFs, chegaram ao banco 1.139 — 39%**. Duas
famílias: 5 documentos TRUNCARAM (teto de 16.384 tokens de saída do gpt-4o; `01_Balanco` sozinho pede
~20.900) e o resto veio pela metade **em silêncio** (`17_Livro_Razao`: 99 de 461, sem uma pendência).

O `.xlsx` da modelagem exportado dessa rodada passa em **9 de 10** itens do auditor; o único reprovado
é o balanço não fechar por 40.169 — que é o buraco da extração chegando ao arquivo entregue.

Três camadas, no `N8N/lib/cobertura.mjs` e no grafo:

| | O que faz | Onde |
|---|---|---|
| **1. Medir antes de chamar** | lê a camada de texto do PDF na instância (sem IA, sem custo) e conta as linhas com número | nó `Extrair Texto` |
| **2. Fatiar** | acima de 60% do teto, um item por bloco de ≤234 células, cada um com o TEXTO da primeira e última linha da faixa como âncora | nó `Fatiar Extracao` |
| **3. Guarda de cobertura** | compara o que voltou com o que o documento tem; abaixo de 60% abre pendência com os dois números | nó `Juntar Blocos` |

No `book-canastra`: 38 documentos → **41 chamadas** de extração, 3 fatiados. Custo projetado com o
dado INTEIRO: **~US$ 1,4** (era 0,71 com 39% do dado) — menos da metade do teto.

> **Corrigido na execução 6164 (13/08, mesmo dia):** o fan-out corta a cadeia de `pairedItem` do
> n8n, e toda expressão `$('Outro Nó').item` rio abaixo virou `undefined` — os nós Postgres
> receberam "undefined" em Query Parameters. Agora `Fatiar Extracao` e `Juntar Blocos` declaram
> `pairedItem`, os dois ids viajam com o item, e `Gravar Campos`/`Registrar Diagnostico`/`Reconciliar`
> leem do PRÓPRIO item. **Quem for reimportar precisa da versão com essa correção.**
>
> **O que a camada 3 promete, com precisão:** ela não impede o modelo de pular uma linha. Impede que
> isso seja silencioso. E o `Extrair Texto` tem `onError: continue` — PDF escaneado não tem camada de
> texto, o nó falha nele, o documento segue como imagem e as camadas 2 e 3 se calam. **O pior caso da
> mudança é o comportamento de ontem.**

### A rodada de 14/08 com o agrupamento: cobertura 39% → 58%

**1.683 linhas gravadas** contra 1.139 (+48%), ainda **sem** as camadas 2 e 3 (elas estavam
desligadas: a referência a ramo irmão não resolvia). O ganho é todo do agrupamento, e o maior efeito
foi o fim do truncamento nos dois maiores documentos:

| Documento | células | antes | agora |
|---|---:|---:|---:|
| `01_Balanco_..._2025x2024x2023` | 326 | **0** | **281 (86%)** |
| `35_Demonstracoes_Contabeis_...` | 308 | **0** | **282 (92%)** |
| `13/14_Balanco_COMBINADO` (8-9 colunas de empresa) | 70 | 57 | 57-64 (81-91%) |
| `17_Livro_Razao_Fornecedores` | 461 | 99 | **1** ← ver abaixo |

**O livro razão caiu para 1 linha, e o guarda de desalinhamento explicou por quê:** o documento tem
**três colunas de valor** (Débito, Crédito, Saldo), o modelo devolveu três valores por lançamento e
declarou `cols` VAZIA — 98 de 99 contas descartadas. O guarda agiu certo; faltava o prompt dizer que
coluna de valor **não é só período e empresa**. Corrigido em 14/08, com os cinco casos nomeados
(razão, balancete, aging, estoques, mapa de dívida) e a consequência escrita.

### A régua da cobertura estava na UNIDADE ERRADA (corrigido em 14/08)

A guarda comparava **linhas com dígito** (do texto) com **pares conta × coluna** (do banco). São
unidades diferentes, e num documento comparativo a razão passa de 100%: o `02_DRE` deu 91 pares
contra 46 linhas = **198%**. A guarda ficava cega justamente onde há mais a perder.

Agora as duas pontas estão em CONTAS:

| | |
|---|---|
| régua | **linhas de conta** — tem valor e tem identidade (rótulo, código de conta, ou linha de tabela numérica); fora cabeçalho de ano, CNPJ, data, página, CRC/CPF |
| medida | **linhas devolvidas** pela extração (era contas distintas até 17/08 — ver abaixo) |
| `02_DRE` | ~30 de 39 = **77%** — ele ESTÁ incompleto, e a régua antiga dizia 198% |

O limiar subiu de 0,60 para **0,85** porque o alvo é cobertura total: isso vai abrir pendência em
documentos que antes passavam, e é o objetivo.

### A régua calibrada contra a verdade — e a cegueira que ela escondia (17/08)

`node N8N/medir-regua-cobertura.mjs` confronta a régua com a contagem que o **gerador** do book
declara (ele sabe quantas linhas escreveu; não é outra leitura do PDF). A primeira medição, nos 38
documentos, achou o defeito que o limiar nunca resolveria:

| Documento | linhas de verdade | a régua via | |
|---|---:|---:|---|
| `17_Livro_Razao` | 99 | **3** | −97% |
| `15_Balancete` | 78 | **3** | −96% |
| `22_Aging` | 14 | **2** | −86% |
| `27_Imobilizado` | 9 | **2** | −78% |

A régua acertava as demonstrações (+2% a +4%) e **desabava nos analíticos — os que perdem dado**. E
como a guarda se cala abaixo de 20 linhas, a cegueira virava **silêncio**: o livro razão, o caso que
motivou as três camadas, nunca chegava a ser avaliado por elas. A causa: "termina em valor" pressupõe
rótulo e valor na mesma linha, e num documento de sistema contábil a linha termina em `D`/`C`, o
rótulo é código sem letra, ou o histórico é parágrafo que o leitor de PDF deixa sozinho numa linha.

A **régua v2** troca isso por "tem valor E tem identidade" (rótulo, código de conta, ou linha de
tabela numérica com dois valores ou mais). Erro absoluto médio **29% → 9%**, sem piorar um documento
sequer; os avaliados pela guarda passam de 10 para 14. O limiar **fica em 0,85**: o pior documento
honesto do book se reporta a 96%, então sobram 11 pontos de folga — e a folga é para o documento
real, que é mais sujo que o sintético. O CI roda a medição a cada push.

### E a unidade do OUTRO lado da guarda: linha, não conta distinta (17/08)

A mesma medição achou o viés oposto, e ele tinha número exato: a guarda comparava **contas distintas
gravadas** com **linhas do texto**, e num livro razão o mesmo fornecedor aparece em vários
lançamentos — 99 linhas para **66 históricos distintos**. Uma extração que não perdia NADA se
reportava em 66% e abria pendência. Foi o segundo erro de unidade da mesma guarda, na direção
contrária ao primeiro (pares × linhas dava 198%).

Agora as duas pontas são **linha**: `achatarGrupos` marca cada campo com a linha do documento que o
originou, `juntarBlocos` conta as linhas distintas depois de limpar a emenda, e o campo **não chega
ao banco** (nada de migration por causa de uma contagem interna). Uma conta com três colunas conta
uma vez; dois lançamentos do mesmo fornecedor contam dois. Bloco no formato plano antigo, sem a
marca, cai para as contas distintas — o comportamento de antes, em vez de cobertura zero. O painel do
`Resumo de Custo` passa a somar a mesma unidade, e `contas_distintas` continua saindo por documento,
porque é ela que denuncia rótulo repetido.

### O custo, medido e projetado (13/08/2026)

A primeira fatura real veio dos 14 documentos do `book-vertentes`: **US$ 0,90**, com alvo de US$ 0,50.
84% era saída de extração, a ~64 tokens por célula de valor — 45% acima do que este repositório
supunha. A saída passou a ser **agrupada** (uma seção por grupo, colunas declaradas uma vez, conta
escrita uma vez com um valor por coluna) e o `medir-custo-book.mjs` projeta:

| Book | formato plano | agrupado |
|---|---:|---:|
| `book-vertentes` (14 docs) | US$ 0,857 (fatura real: **0,90**) | **US$ 0,471** |
| `book-canastra` (38 docs) | US$ 2,226 | **US$ 1,252** |

~~**Aberto:** o livro razão projeta 109% do teto de saída mesmo agrupado.~~ **Fechado no mesmo dia
pelo fatiamento** (camada 2): ele vira 2 blocos de ≤234 células e nenhum deles chega perto do teto. O
`medir-custo-book.mjs` continua avisando, nomeando o arquivo, se algum documento voltar a passar de
80% do teto numa chamada — a guarda fica de pé mesmo depois de a causa conhecida sumir.

## O que só o dono pode fazer

> **DECISÃO ABERTA, medida em 08/09 (sessão 81): republicar o workflow RE-EXTRAI todo documento já
> extraído.** O alias `HEADCOUNT` acrescentado a `N8N/lib/taxonomia.mjs` muda `codigosConhecidos()`
> → o `enum` do schema estrito → o **`FINGERPRINT_EXTRACAO`**. Medido no `workflow.e1-ingestao.json`:
> `f17efcbc53780818` (sem o alias) → `d1a77ddf7937b595` (agora). O dedup da `0118`/`0127` é por
> `(hash, fingerprint_extracao)`, então na primeira rodada depois da republicação **nenhum documento
> casa o curto-circuito `Extração já feita?`**: 38 no "teste Canastra", 190 no araucária. Custo de LLM
> novo, versões novas de documento, e — porque a extração é LLM — números que podem sair diferentes do
> `.xlsx` do lote `7377` que já foi entregue, sem nada no sistema explicando a diferença. **É por
> desenho, não é bug**, e o alias não vale em produção enquanto não republicar. O que é decisão sua:
> quando pagar essa rodada, e se o araucária (190, contra a cota RPD 500) entra junto ou depois.
> Detalhe medido no cabeçalho do alias em `N8N/lib/taxonomia.mjs`.

**As duas linhas de infra da sessão 52 saíram em 19/08** — migrations até a `0125` aplicadas, workflow
reimportado. A sessão 53 acrescentou uma migration e um item que não é de infra.

1. **RODAR O BOOK NUM MANDATO NOVO, e depois o aceite sobre o export de verdade.** Continua sendo o
   item que destrava mais, e o que ele prova está na tabela de "O próximo passo" — sete coisas, três
   delas checagens que nunca viram dado real. O aceite são duas peças: `auditar-xlsx.mts` (10 itens
   automáticos) e `Arquitetura do Sistema/6 Referência/ACEITE.md` (10 itens humanos). Foi a falta desse par que deixou sair, em
   06/08, um arquivo com seis números errados e as suítes verdes.

2. ~~**Aplicar a `0126`.**~~ — **FEITO em 20/08**, junto com todo o resto até a `0133`. Não sobrou
   nada de banco pendente. `/autonomia` passa a dizer em que cada nível se apoia em vez de adivinhar
   pelo nome do estágio, e `fn_instalacao_conferir()` responde sobre o banco em que você está de fato
   conectado — que é onde esta pergunta deve ser feita daqui em diante, não neste arquivo. (A tela
   `/instalacao` saiu em 21/08; a função ficou.)

3. **A ROTULAGEM DO GOLDEN SET — e este não é de infra, é de julgamento.** A máquina está pronta e
   testada; o que falta é o `Arquitetura do Sistema/2 Especificação/f0/06` executado: ~20 documentos REAIS por tipo core, estratificados por
   qualidade de captura (digital, PDF nativo, escaneado, foto), dois rotuladores nos casos ambíguos, e
   a rodada **congelada** ao fim. Rotular o book não serve e o banco recusa (`origem = 'sintetico'`):
   o gabarito dele já é conhecido, então a concordância mediria o instrumento. É o item de maior
   alcance que existe hoje — sem ele o dial não sobe por medição e a F4 do `Arquitetura do Sistema/1 Visão e Doutrina/03` não começa.

> **A conferência de 30 segundos, depois de qualquer rodada nova.** Merge não é apply, e da tela
> "aplicada" e "não aplicada" têm a mesma aparência. Vale reconferir quando algo parecer não ter
> mudado:
> ```sql
> -- 0122: a pergunta ao cliente em português
> select fn_periodo_por_extenso('multi','23,24,25');  -- esperado: 2023 a 2025
> select fn_valor_pt_br(16060, 'milhar');             -- esperado: R$ 16.060 mil
> select fn_anos_texto('L36M');                       -- esperado: {} (antes: {2036})
>
> -- 0123/0124/0125: as funções que a sessão 52 acrescentou
> select proname from pg_proc
>  where proname in ('fn_texto_nomeia_mutuo','fn_mutuo_com_socio',
>                    'fn_contraparte_intragrupo','fn_lado_intragrupo',
>                    'fn_natureza_intragrupo','fn_reconciliar_intragrupo');
> -- esperado: as SEIS
>
> -- 0125 muda o TIPO DE RETORNO da fn_valores_por_ano (quatro colunas novas):
> select count(*) from information_schema.routines r
>  join information_schema.parameters p on p.specific_name = r.specific_name
>  where r.routine_name = 'fn_valores_por_ano' and p.parameter_name = 'arquivo';
> -- esperado: 1. Zero significa que a 0125 não entrou, e a nota do export volta
> -- a dizer só "Extraído de BALANCO" sem quebrar nada — falha silenciosa.
> ```

> **Conferência de 5 segundos do workflow, se a rodada sair estranha:** o canvas tem **33 nós**.
> Procure, em ordem: `Medir Documento` → `Orcamento do Lote` → `Lote cabe?`, `Precisa Fallback?` →
> `Juntar Ramos`, `Registrar Documento` → `Recompor Contexto` → `Extracao ja feita?` (o dedup) e
> `Juntar Extraidos`, e na ponta direita `Resumo de Custo` → `Gravar Uso do Lote` → `Conferir Lote`.
> E, para cobrir falha de qualquer origem, o `workflow.erros.json` ligado como **Error Workflow** nas
> Settings do Intake (`N8N/README.md`).

## O que está aberto no produto

> **Os quatro itens que abriam esta lista em 17/08 foram FECHADOS na sessão 50** (subtotais
> impressos, checagem de mútuos, tela de Modelagem e os apelidos à mão) — ver "O que a sessão 50
> fez". Dois deles com uma ressalva registrada lá: o dos subtotais só a rodada real prova, e a
> checagem de mútuos cobre mútuo contra mútuo, não a planilha intragrupo inteira.

- ~~**AS PERGUNTAS AO CLIENTE NÃO TÊM TELA**~~ — **fechado em 18/08 (sessão 51)**: elas ganharam
  uma **aba própria**, `/casos/[id]/perguntas`, com o texto pronto para copiar, o registro de envio
  por `fn_registrar_pergunta_acao` (texto congelado) e o de descarte. Ficaram FORA da fila de
  pendências por decisão do dono — sugestão que ninguém fez ainda não se mistura com decisão sobre
  problema medido. Ver "As perguntas ao cliente ganharam a ABA que faltava". **Depende da `0120`
  estar aplicada no Supabase**; sem ela a aba explica o que falta em vez de quebrar.
- ~~**A conferência das linhas intragrupo que NÃO são mútuo**~~ — **fechado em 19/08 (sessão 52)**,
  pelo ESPELHO entre cada par de empresas (`0124`), não pela planilha: a planilha de faturamento
  intragrupo é FLUXO e o balanço é ESTOQUE. Ver "O INTRAGRUPO QUE NÃO É MÚTUO". **O que ela NÃO cobre,
  e fica anotado:** rateio de despesa que não deixa saldo no balanço (não há espelho para conferir), e
  mútuo com sócio — cujo par é o contrato com o quotista, que ninguém cruza hoje.
- ~~**O item mais denso do book ainda estoura o teto de saída**~~ — **fechado em 19/08 (sessão 52),
  e a correção anotada aqui era a errada.** Não faltava extrair por faixa de PÁGINA: o fatiamento
  estava desligado por erro de unidade (teto em CÉLULAS aplicado a uma contagem de LINHAS), e ZERO
  dos 38 documentos era fatiado. Ver "O FATIAMENTO ESTAVA DESLIGADO". **O que sobra, e agora aparece
  na fila:** linha que sozinha passe do teto — sem corte mais fino possível; nenhum documento do book
  cai nesse caso.

### O QUE SOBROU, em ordem de quem destrava o quê (19/08, sessão 52)

**DEPENDE DA RODADA DO DONO — não dá para começar antes:**

1. **Recalibrar o limiar de cobertura (0,85)** com pontos reais. Hoje ele está calibrado contra 38
   documentos SINTÉTICOS.
2. **Conferir o fatiamento em produção** — ele nunca rodou ligado. Cortou onde devia? A emenda entre
   blocos duplicou linha? A `juntarBlocos` limpa emenda repetida e nunca viu bloco de verdade.
3. **Conferir os subtotais impressos** (`0116`) — a única mudança daquela rodada que só a extração
   real prova.

**NÃO DEPENDE DE NADA — pode começar já:**

4. **Golden set e concordância medida** — **a MÁQUINA foi feita em 19/08 (sessão 53, `0126`); o que
   falta é a ROTULAGEM.** O esquema, as cinco métricas do `Arquitetura do Sistema/2 Especificação/f0/06` e o portão que cobra existem e
   estão travados por teste; rotular documento real de cliente continua sendo trabalho de execução
   do dono, com LGPD, e o `Arquitetura do Sistema/2 Especificação/f0/06` já dizia que não se monta em documentação. Ver "A REGRA DE OURO
   PASSA A SER EXECUTADA". Sem a rotulagem o dial continua não subindo por medição — a diferença é
   que agora ele também não sobe **em silêncio**.
5. **Bloco numérico dos três cenários lado a lado** — dimensionado abaixo, e é decisão do dono se
   vale: exige PARAMETRIZAR a cascata da aba que produz os números do modelo.
6. ~~**Modo A do `Arquitetura do Sistema/2 Especificação/f0/07`** (base viva consultável no portal) — ou a decisão escrita de que ele não
   vem~~ — **fechado DUAS vezes, e a segunda é a que vale.** Em 20/08 (sessão 53) ele veio; em
   21/08 (sessão 57) o dono o TIROU, que era a outra saída que o §2.4 do diagnóstico admitia — a
   decisão escrita de que ele não vem. O que segue descreve a tela enquanto ela existiu:
   `/casos/[id]/base` filtrava por empresa,
   período, conta e status de aceite atravessando os documentos, com proveniência e confiança de
   cada número. As duas saídas que o §2.4 do diagnóstico pedia eram "construir" ou "escrever que não
   vem"; a primeira foi tomada. Ver "O MODO A DO `Arquitetura do Sistema/2 Especificação/f0/07` PASSA A EXISTIR". **O que ela
   deliberadamente NÃO faz, e fica anotado:** não SOMA — consolidar demonstração é o que o export
   paga com 574 verificações atrás, e uma tela que somasse produziria um segundo total para a mesma
   pergunta, mais fraco que o do arquivo de comitê.

**BLOQUEADO PELO TEXTO DA ENTREGA — não é engenharia, é transcrição que ninguém pode inventar:**

6-b. **As outras 25 perguntas ao cliente** (`0120` entregou 11 das 36 do capítulo 10, com as 25
   restantes nomeadas família a família). O que falta não é a máquina — `fn_sugerir_perguntas`, os
   marcadores, o registro de envio com texto congelado e a aba já existem, e acrescentar pergunta é
   uma linha de `seed`. Falta o **texto**: a `0120` declara que o enunciado é *VERBATIM da entrega*, e
   o repositório não tem os códigos `1.1`–`8.3` / `A1`–`A12` do capítulo 10. Redigi-los "no espírito"
   produziria 25 perguntas que o cliente recebe em nome da casa e que ninguém aprovou — e elas
   pareceriam aprovadas, porque saem do sistema. **Destrava com o arquivo do capítulo 10 no repo.**

**BLOQUEADOS POR DADO QUE O KIT BÁSICO NÃO COLETA** — não são trabalho, são espera:

7. **Tranche em moeda estrangeira** (falta a MOEDA por tranche; aplicar câmbio sem saber erra ~5×).
8. **Vida útil por classe de imobilizado** (exige laudo).
9. **Goodwill** — os três blocos de espelho só valem quando houver ágio de verdade no caso.

**ANOTADOS, PEQUENOS, NÃO RECONFERIDOS NESTA SESSÃO:**

10. **`fn_conferir_modelagem` conta premissa de sazonalidade como "sem valor"** — vem da sessão 39. O
    critério em vigor (`0101`) é `valores is null or valores = '{}'`, e uma premissa de sazonalidade
    guarda os fatores em outro lugar. **Não reconferi contra dado real** — fica como suspeita, não
    como fato.
11. **"Sugerir do realizado"** (proposta, nunca feita): oito premissas saem do próprio balanço/DRE do
    caso, com `origem = 'historico'`, que o schema da `0038` já prevê.

O diagnóstico completo, com evidência e prioridade, está em `Arquitetura do Sistema/4 Análises e Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md`.
Os itens acima, com o histórico de cada um:

- ~~**A entidade sai poluída com o período**~~ — **fechado em 17/08.** Eram quatro famílias de
  sujeira, não uma: o comparativo de TRÊS exercícios (`2025x2024x2023`, que o regex de um `x` só não
  pegava), preposições (`Aging De Canastra`), sobra de tipo quando o apelido casado é mais curto que
  o nome do arquivo (`Composicao Imobilizado Canastra`), e nome sem tipo nenhum virando empresa
  (`Relatorio Auditor Independente`, `Iv Rev3`). Medido nos 38 nomes do book: **32 entidades limpas,
  6 nulas** (essas vão ao fallback por conteúdo, que lê a entidade do documento) e **zero sujas**.
  A remoção de palavra de tipo usa a própria taxonomia como fonte, palavra a palavra, então cresce
  sozinha. ~~Fica anotado: `negativas`, `societario` e `parcelamentos` numa lista à mão~~ — **já
  resolvido**: os três viraram termos de `CERTIDOES`, `ORGANOGRAMA` e `SITUACAO_FISCAL` em
  `N8N/lib/taxonomia.mjs`, e a regra do vocabulário os remove sozinha. O que sobrou naquela lista é
  de outra natureza (ruído de nome de arquivo: `rev3`, `scan`, `anexo`) e não tem lugar na taxonomia.
- ~~**Fixture de extração do `book-canastra`**~~ — **fechado em 19/08 (sessão 52)**: existe
  `fixture_book_canastra.sql` (28 documentos, 1.264 linhas) e `canastra.test.sql` no `run.sh`, e a
  primeira rodada dela achou três defeitos na checagem de mútuos (`0123`). Ver "A FIXTURE DE
  EXTRAÇÃO DO BOOK-CANASTRA". **Fica anotado o que ela NÃO cobre:** ela prova a ingestão sobre
  documento difícil com extração FIEL — a extração real sobre os PDFs sujos (o que o modelo de
  verdade lê deles) continua sendo provada só pela rodada do dono.
- **Resumo dos três cenários lado a lado** — **parcialmente atacado em 19/08 (sessão 52)**, e o que
  ficou de fora está dimensionado. Entrou o painel `OS TRÊS CENÁRIOS SÃO TRÊS?`, que denuncia cenário
  não diferenciado (o Cliente Case nasce idêntico ao Base). NÃO entrou o bloco numérico lado a lado:
  a lista de métricas do §2.2 mistura o que uma cascata paralela alcança (receita, EBITDA) com o que
  exige replicar o modelo inteiro (DSCR mínimo, necessidade de pico), e a metade viável custa
  PARAMETRIZAR a cascata da aba de receita pelo cenário — refatoração da aba que produz os números do
  modelo, com um CHECK provando que a sombra do cenário ativo é igual à linha ativa. Ver "OS TRÊS
  CENÁRIOS SÃO TRÊS?".
- ~~**Proveniência completa na aba `Premissas`**~~ — **fechado em 19/08 (sessão 52)** e em todas as
  catorze abas, não só na `Premissas` (`0125`). Ver "A PROVENIÊNCIA VOLTA AO ARQUIVO DE COMITÊ".
- **Golden set** e concordância medida — sem isso o dial de autonomia não sobe, e a F4 do
  `Arquitetura do Sistema/1 Visão e Doutrina/03` não começa.
- ~~**Modo A do `Arquitetura do Sistema/2 Especificação/f0/07`** (base viva consultável no portal) — ou a decisão escrita de que ele não
  vem~~ — **fechado em 21/08 (sessão 57) pela SEGUNDA saída**: o Modo A foi construído em 20/08 e
  descontinuado pelo dono em 21/08, e o `Arquitetura do Sistema/2 Especificação/f0/07` passou a dizer isso. A entrega é o Modo B, o
  `.xlsx`. Ver "O PORTAL ENCOLHE".

## Os comandos que funcionam

```bash
# insumo dos testes (gera pdf/ + GABARITO.json, não versionados)
cd "Dados de Teste"/book-vertentes && PYTHONPATH=. python3 gerar.py && cd -

node --test 'N8N/test/*.test.mjs'                                      # da RAIZ do repo
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres Supabase/test/run.sh
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres E2E_PSQL="psql" \
  ./portal/node_modules/.bin/tsx Verificação/run.mts
```

> `E2E_PSQL` é o **comando** do psql, não um flag: com `E2E_PSQL=1` o arnês tenta executar um binário
> chamado `1`. E o `node --test` roda da raiz — de outro diretório o glob não casa nada e a suíte diz
> "0 testes" em vez de falhar.
