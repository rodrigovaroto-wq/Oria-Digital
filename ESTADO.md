# Estado do projeto — leia isto antes do `HANDOFF.md`


## SESSÃO 138 (24–25/11/2026) — Fase A: A1 (cópia de segurança) e A2 (base das fontes externas) FEITAS e em produção

> **Migration mais nova: `0304_a_fonte_que_dizia_mensal_e_rodava_todo_dia.sql` (Fase A, A3: o catálogo `fonte_externa` acompanha o macro diário; juros por modalidade conectada via SGS, mensal, 30 dias) — ESCRITA, NÃO APLICADA em produção; a sonda (`fn_instalacao_conferir() where migration = '0304'`) é quem responde.**
> **Migration anterior: `0303_a_fonte_que_caia_e_parecia_nao_ter_nada.sql`, APLICADA EM PRODUÇÃO em 24/11/2026** (pela API de gerenciamento, 1,6 s, arquivo do commit `a4e813f`, md5 `a874a608…`). Antes: Postgres 17.6, cobertura 0302, 475 itens na sonda e 0 ausentes, `fonte_externa` inexistente, 81 casos / 2.999 pendências / 7.599 reconciliações. Depois: cobertura 0303, 511 itens e 0 ausentes, os 36 da 0303 presentes, 22 fontes (1 não oficial), 81 / 2.999 / 7.599 (nada tocado). PRs: #310 (A1+A2), #311 (cópia para repositório privado, senha com `@`), #312 (novas tentativas no Storage).

### ▶ PRÓXIMA SESSÃO — COMECE AQUI: Fase A, fatia A3 (dados de mercado, n8n)

- **Pedido pronto para colar:** `/autopilot Fase A, fatia A3 (dados de mercado). Leia ESTADO.md sessão 138 e Business Plan/06_execucao/FASE_A_FONTES_PUBLICAS.md §5 A3. Primeiro passo: conferir se o macro diário roda em produção (último dado gravado de cada série). Depois uma fonte por commit, na ordem da tabela da A3; antes da CVM, medir o tamanho do banco (plano gratuito, 500 MB). Toda fonte registra pela fn_registrar_consulta_externa (0303) e "falhou" nunca vira "nada encontrado".`
- **Não depende do dono.** A A4 (dados da empresa, portal) depende de uma decisão antes de começar: quem registra as consultas — o analista pelo portal (hoje: `authenticated` tem EXECUTE e o registro grava `registrado_por`) ou só o servidor (exige a chave de serviço na Vercel).
- **Ponto de entrada no código:** `fonte_externa` (catálogo, 22 fontes, todas com prazo mínimo de 1 dia até a fatia medir a cadência real) e `fn_registrar_consulta_externa(fonte, caso, cnpj, http_status, erro, corpo, itens, registros_lidos, custo, nao_consultado)`; o macro existente está em `N8N/lib/macro.mjs` e `N8N/build-workflow-macro.mjs` (agenda mensal, dia 12 — o plano dizia diário).

### O que esta sessão fez

- **A2 FEITA e em produção** (0303): `fonte_externa`, `consulta_externa` (imutável; quatro estados; hash do corpo obrigatório em `encontrado` e `nada_encontrado`, nunca o da string vazia; data e validade pelo banco; só CNPJ), `fato_externo`; ponto único `fn_registrar_consulta_externa`; sonda com 36 requisitos (1420–1455). Teste `EXECUCOES=196 FALHAS=0`; não-vazio medido (regra central 54 asserts). Três ciclos de revisão; o 3º sem CRÍTICO/ALTO.
- **A1 FEITA, critério medido em 25/11/2026** (run 45683483492 no repositório PRIVADO `rodrigovaroto-wq/OriaDigital-backup`, que chama o workflow reutilizável `.github/workflows/copia-de-seguranca.yml` daqui): contagens no snapshot de produção = cópia restaurada do zero em Postgres 18 (caso 81, documento 2.165, entidade 408, pendência 2.999, reconciliação 7.599); Storage 186/186 objetos (78,3 MB); sonda na cópia sem perda (só `envio_segredo_no_vault`: o Vault fica fora de propósito). Artefatos cifrados (AES-256): banco 11,5 MB por 7 dias, documentos 42,4 MB por 3 dias ≈ 207 MB dos 500 MB. Roda todo dia às 06:40 UTC.
- **Por que no repositório privado:** o Oria-Digital é PÚBLICO e artefato de Actions de repositório público pode ser baixado por qualquer pessoa logada (decisão do dono, 25/11).
- **Defeitos achados pela execução real e corrigidos:** senha com `@` quebrava a URL e o erro imprimiu o fim da senha no log (log apagado; `codificar-url.py`); a chave `sb_secret_…` dava HTTP 400 em todo download (a Storage responde 400 para "não encontrado"; a certa é a `service_role` legada); 4 de 186 downloads com HTTP 522 passageiro reprovavam a cópia (até 3 tentativas, `6b84155`).
- **Segredos (25/11):** senha do banco trocada pelo dono (sem `@`); atualizados `BACKUP_DB_URL`, `BACKUP_PASSPHRASE`, `SUPABASE_SERVICE_ROLE_KEY` no repositório privado, `SONDA_DB_URL` no Oria-Digital (sonda verde depois, run 45678622441) e a credencial "Postgres (Trat. Dados)" do n8n. O `BACKUP_DB_URL` antigo do Oria-Digital não é mais usado.
- **Decisões do dono (24/11), no `FASE_A_FONTES_PUBLICAS.md` §2:** 6) ANBIMA, CCEE e FipeZAP oficiais; 7) o 404 "não existe" tratado na A4, fonte por fonte; 8) toda fonte com prazo, cadência desconhecida = 1 dia.

### NÃO CONFERIDO / riscos abertos

- **O n8n conecta com a senha nova do banco?** A próxima execução da ingestão ou do macro responde. A A3 começa por aí.
- **7 cópias diárias seguidas** (critério do item 0.2) completam em 2/12 se nada falhar. **Nada avisa se o agendamento parar** (risco nomeado; candidato: a `sonda-producao.yml` conferir a idade do último artefato).
- **Achados deixados da A2** (MÉDIO/BAIXO): marcador da sonda 1453 nos dois ramos; corpo só com BOM/NBSP não conta como vazio; 200 + corpo vazio + itens nulo dá 22023 em vez de gravar `falhou`; `p_erro` só com `\n`; falta assert do 4xx com corpo de espaço.

### O dono faz à mão

1. Registrar as decisões 6–8 na v0.1.7 do registro (ou pedir ao Claude numa rodada pequena).
2. Antes da A4: decidir quem registra as consultas (ver acima).
3. Responder se o MVP fica sem agentes; e o conflito de pessoa física (decisão 4 × N-C7b/R5) antes de qualquer consulta por CPF.

## SESSÃO 137 (24/11/2026) — parceiros externos e a prioridade nova: Fase A (fontes públicas grátis)

> **Só documentação e planilhas. Nenhuma migration, nenhum código do produto, nada aplicado em produção.** A migration mais nova continua a `0302`.

- **Duas planilhas** em `Business Plan/06_execucao/parceiros_externos/`, ambas geradas por script (não editar à mão):
  - **Planilha 1:** 103 funcionalidades, 35 integrações e a etapa/agente/origem dos 179 dados da captação, que apontam para o `Plano_de_Captacao_v3.xlsx` em vez de copiá-lo.
  - **Planilha 2 (v2, linguagem simples):** 44 plataformas-ponte com compatibilidade e utilidade, a combinação proposta e o que falta construir, as perguntas para as demos e 102 fornecedores por API.
- **Prioridade nova do dono:** Fase A (fontes públicas grátis) → B (book confiável) → C (conferência e análises), antes das plataformas pagas e dos agentes. Detalhe em [`Business Plan/06_execucao/FASE_A_FONTES_PUBLICAS.md`](Business%20Plan/06_execucao/FASE_A_FONTES_PUBLICAS.md); §0 nova no plano único.
- **Decisões do dono, a registrar na v0.1.7:**
  - CNPJ pelo espelho BrasilAPI, marcado "não oficial"; a base oficial da Receita fica pendente.
  - Listas pequenas baixadas inteiras; PGFN e PEP por consulta.
  - Sócios pessoa física sem autorização registrada, **mas a Fase A consulta só empresas**. Isso contradiz a N-C7b e a R5: está nas pendências.
  - Cópia de segurança mínima já na A1.
- **Medido em 24/11:** 17 APIs públicas respondem deste ambiente; CGU e DataJud pedem chave; CAGED (FTP) e ANEEL não responderam daqui (conferir em produção).
- **NÃO CONFERIDO:** o banco de produção (a sonda não foi rodada) e se o macro diário roda em produção (primeiro passo da A3).
- **O dono faz à mão:**
  - registrar as decisões na v0.1.7;
  - cadastrar os dois segredos da cópia de segurança (A1). **Corrigido na sessão 138: são três** (BACKUP_DB_URL, BACKUP_PASSPHRASE e SUPABASE_SERVICE_ROLE_KEY), e o dono confirmou que estão cadastrados;
  - responder se o MVP fica sem agentes.


## SESSÃO 136 (24/11/2026) — registro de decisões v0.1.6: o score do dado externo decidido

> **Só documentação. Nenhuma migration, nenhum código do produto, nada aplicado em produção.** A migration mais nova continua a `0302`.

- **Item 0.13 FEITO.** [Registro v0.1.6](Business%20Plan/07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.6.html), seção 22: **D15** (o score), **D15.1–D15.8** (respostas do dono às perguntas da Espec. 15), **D15.9–D15.15** (as 7 regras), **D4-1** (o dono monta o gabarito do piloto) e **J7** (o slide 5 mantém "mais de 30 fontes" como meta). A v0.1.5 e o gerador dela foram para `99_historico/registro_de_decisoes/` com `git mv`.
- **Duas respostas do dono divergem da recomendação, e mudaram o plano:** **D15.4**, pisos já bloqueiam no piloto (o 1.K3 virou P1; só o score ponderado fica em sombra até o 3.8); **D15.3**, qualquer analista libera o dado em REVISÃO, em qualquer gravidade (a E3 e a E3-1 continuam para o diagnóstico).
- **Continuam abertas, por escolha do dono:** R1 (quem é o segundo revisor; "indico depois"), N-C5a e A6.
- **Medido:** da v0.1.5 para a v0.1.6 mudaram só 3 caracteres (versão e data); 90 → 108 decisões com âncora; os geradores regeram a v0.1.5 e a v0.1.6 idênticas byte a byte; 18 de 18 códigos novos citados em documento oficial (verificador provado não-cego: sem J7 ou sem D4-1 no texto, acusa a falta); 0 links relativos quebrados em 238 arquivos `.md` e `.html`.


## SESSÃO 135 (24/11/2026) — o score do dado externo entra no plano, distribuído pelas fases

> **Só documentação. Nenhuma migration, nenhum código do produto, nada aplicado em produção.** A migration mais nova continua a `0302`.

- **O dono aprovou a v2 do §5A da Espec. 15** (pesos na mediana de três avaliações independentes e as 7 regras) e pediu para integrar ao plano, por fase, pensando na construção de cada agente.
- **Fase 0:** 0.13, registrar D15.1–D15.8 e as 7 regras no registro v0.1.6.
- **Fase 1, Trilha K nova:** 1.K1 catálogo das fontes; **1.K2 vetos no banco (P1)**; 1.K3 score em modo sombra e o portão de cada agente do piloto (Captador, Conferidor, Mercado, Caixa, Dívida, book), com `casos_do_score.py` como oráculo do teste; 1.K4 propagação pelo menor score e frescor pela data do uso; 1.K5 painel. A tabela "Em que fase nasce o portão de cada agente" está na trilha. Nenhum item de agente passou a depender da Trilha K: em sombra, o portão não bloqueia.
- **Fase 2:** 2.18 refeito (portões de Risco, Estrategista, Entregas, Captador formal e monitoramento); 2.19 refeito (furos de portão e alerta de carimbo). **Fase 3:** 3.8 calibração; 3.9 bloqueio em degraus com rebaixamento automático.
- **Contrato dos agentes** (`AGENTES.md`, item 8): todo dado externo chega ao agente pelo portão dele; os números ficam só na Espec. 15.
- **A proposta em página** foi para `Arquitetura do Sistema/2 Especificação/15_anexos/Portoes_de_Confiabilidade_Oria_v2.html` (retrato derivado do §5A, com impressão em PDF).
- **Medido:** as ondas de paralelismo continuam válidas (73 itens das Fases 0 e 1, cada um numa onda só, nenhuma dependência na mesma onda ou depois).
- **O dono faz à mão:** confirmar a v0.1.6 quando o 0.13 for feito.


## SESSÃO 134 (23/11/2026) — pendência nova: score de confiabilidade do dado externo (Espec. 15)

> **Só documentação. Nenhuma migration, nenhum código, nada aplicado em produção.** A migration mais nova continua a `0302`.

- **Pedido do dono:** score para os dados captados **fora** (não os documentos do cliente), por várias dimensões, com um portão em cada etapa do processo. **Não se constrói agora.**
- **Desenho e pesquisa:** [`Arquitetura do Sistema/2 Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md`](Arquitetura%20do%20Sistema/2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md): 13 dimensões em três níveis (fonte, dado, execução), vetos + piso por dimensão + classe (o score ponderado só é lido depois dos vetos e pisos), pesos % e score mínimo por agente com 12 casos conferidos (§5A, proposta inicial), portões nas 7 etapas, matriz por tipo de dado, 14 limitações, D15.1–D15.8 abertas, fontes no §13.
- **§5A v2 (pedido do dono, mesmo dia):** a proposta de pesos foi comparada às cegas com três avaliações independentes (a v1 concordou com a maioria em 53 de 64 julgamentos; em 6 das 11 divergências deixava passar o que a maioria segurava). A v2 usa a estrutura dos três, os pesos na mediana e 7 regras aprovadas pelo dono. Os 13 casos saem de `Arquitetura do Sistema/2 Especificação/15_anexos/casos_do_score.py`.
- **No plano:** itens novos **2.18** (catálogo, vetos, modo sombra) e **2.19** (calibração e portões), P2. Pendências: decisões D15.x e a prova "a classe prevê o erro".
- **Portões rodados:** `conhecimento/conferir.mjs` OK (287/0); links relativos dos arquivos tocados: 0 quebrados.
- **NÃO CONFERIDO:** o banco de produção (a sonda não foi rodada).
- **O dono faz à mão:** decidir D15.1–D15.8 (recomendações no §11 da Espec. 15).


## SESSÃO 133 (19–23/11/2026) — Fase 4: pasta `Business Plan/` organizada e plano de execução único

> **Só documentação. Nenhuma migration, nenhum código, nada aplicado em produção.** A migration mais nova continua a `0302`.

- **O plano em vigor agora é um só:** [`Business Plan/06_execucao/PLANO_DE_EXECUCAO.md`](Business%20Plan/06_execucao/PLANO_DE_EXECUCAO.md) (decisão K1), sem datas (K2). Fases 0 (fundação) → 1 (piloto com a Partners, K6) → 2 (restante da v1) → 3 (evolução operacional) → 4 (futuro), portões G0–G3. **O item 0.1, o estudo de infraestrutura com ≥ 5 opções por item, é a primeira entrega (R2).**
- **Planos antigos superados**, com nota no topo e sem apagar: MAPA_DE_EXECUCAO, PLANO_MVP_2026-11, PLANO_DE_EXECUCAO_2026-11, PRONTIDAO_POR_ESTAGIO, PLANO_LINHA_A_LINHA, `03_MVP_E_ROADMAP`; o roadmap do ARQUITETURA_ALVO e a ordem do DESENHO_QUATRO_FUNCOES. O `estado-e-handoff`, o `/fechar` e o `CLAUDE.md` passam a apontar para o plano único.
- **Pasta `Business Plan/`:** índice com uma fonte por assunto; registro de decisões em `07_decisoes/` (hoje a v0.1.5); workflow v0.3.0 em `02_…`; histórico em `99_historico/` (40 de 40 arquivos movidos com `git mv`, 0 linha alterada). As seções de negócio da `DOCUMENTACAO.md` do deck viraram links para lá (K5).
- **Medido:** 88 de 88 códigos de decisão citados nos documentos oficiais; 0 links relativos quebrados no repositório; os dois geradores regeram a v0.1.3 e o workflow idênticos byte a byte. Os dois verificadores foram provados não-cegos.
- **Achados no código que viraram itens P1 da Fase 0 (riscos K4):** extração em N2 sem medição (`0041_dial_manda.sql:419`, item 0.5); n8n com `service_role` (0.4); nenhum backup fora do Supabase (0.2, 0.3); proteção do `main` não conferida (0.6); sem contrato de dados com o provedor de IA (0.7). E: **0 das 138.931 linhas de `campo_extraido` têm `ln`** (item 1.A5).
- **Decisão nova do dono (23/11): D6-1, registro v0.1.4.** A classificação de documentos (`classificacao_doc_checklist`, em N2 "declarada, não medida" desde a `0127`) volta a N1 junto com a extração, no item 0.5. A v0.1.4 foi registrada e depois superada pela v0.1.5 (G5-1, abaixo); a v0.1.3 e a v0.1.4 estão no histórico.
- **Segunda revisão independente (23/11):** 3 ALTOS corrigidos. (1) O banco já promove o dial sozinho (`trg_auto_promover_dial`, `0137`) com 30 vereditos: rebaixar a N1 por migration `sistema:` não basta, o item 0.5 agora desliga `auto_promocao`. (2) Três "não existe" desmentidos pelo código: link para a página no portal (`original-do-documento.ts`), `covenant_rompido` e `litigio_relevante` como fatos do texto (`0148`). (3) Itens marcados FEITO sem a medida do critério: hoje nenhum item do plano está FEITO; a regra "FEITO exige a medida" entrou no plano e no `estado-e-handoff`. As ondas viraram as camadas de dependência (todo item das Fases 0 e 1 numa onda só).
- **Decisão nova do dono (23/11): G5-1, registro v0.1.5.** Gravidade "alto" = > 1% do EBITDA ou da dívida (a G5 dizia só "> 1%"). Régua usada no item 1.D6.
- **NÃO CONFERIDO:** o banco de produção (a sonda não foi rodada nesta sessão).
- **O dono faz à mão:** revisar e mergear o PR; ligar a proteção do `main` (0.6); decidir o início do estudo de infraestrutura (0.1).


## SESSÃO 132 (19/11/2026) — README corrigido sobre a IA e o Postgres

> **Só documentação. Nenhuma migration, nenhum código, nada aplicado em produção.** A migration mais nova continua a `0302`, aplicada em 18/11.

- **README estava errado sobre a IA.** Dizia `gpt-4o-mini` na classificação e `gpt-4o` na extração. O modelo ativo é o `gpt-5.6-luna` nas duas, desde 11/09/2026 (`N8N/lib/custo.mjs`, `MODELOS_POR_PROVEDOR`; o `workflow.e1-ingestao.json` gerado cita o Luna 29 vezes). Corrigido, com o Gemini 3.5 Flash-Lite como alternativa por `IA_PROVEDOR`.
- **README dizia Postgres 16.** Produção é 17.6 (medido na MB0, 11/11); local e CI seguem em 16. Corrigido. Contagens de migrations e testes atualizadas (189 → 190; 124 → 126).
- **Inventário completo do que está construído:** feito como página HTML fora do repositório (a pedido do dono, não fica versionado). Contagens do `main` em 19/11: 190 migrations, 55 tabelas, 37 views, 310 funções no `schema.sql`, 140 policies, 38 gatilhos, 126 suítes SQL, 203 arquivos TS no portal.
- **NÃO CONFERIDO:** onde a instância do n8n está hospedada, a região do Supabase e a proteção do `main`.
- Portões rodados: `conhecimento/conferir.mjs` OK, `verificar-espelho-claude-md.mjs` OK, `verificar-comandos.mjs` OK.

## SESSÃO 131 (18/11/2026) — 0302 (`fato_financeiro`, P27) APLICADA EM PRODUÇÃO; repositório organizado (#302)

> **Na época, a migration mais recente no repositório era `0303_a_fonte_que_caia_e_parecia_nao_ter_nada.sql` (Fase A, A2: a base comum das fontes externas), então escrita e ainda não aplicada — APLICADA EM PRODUÇÃO em 24/11/2026 (ver sessão 138).** A anterior, `0302_a_linha_que_nao_tinha_identidade.sql`, foi APLICADA EM PRODUÇÃO em 18/11/2026. É a antiga 0243 do #296 (P27, `fato_financeiro`), com o mesmo corpo. Onde as seções abaixo dizem "0243", leia "0302".

- **0302 APLICADA EM PRODUÇÃO em 18/11/2026** (pedido do dono). Pelo MCP do Supabase, em dois notebooks: "0302 — aplicar" (célula 1: o `alter type ... add value`, sozinho; célula 2: o resto do arquivo do commit `1e68bcb` sem `begin`/`commit` e sem os comentários de nível de topo) e "0302 — conferir depois". A cópia de transporte foi conferida antes no banco de teste: reaplicada, a assinatura md5 dos objetos não muda (`09fc3a17…`) e a sonda dá 20 de 20.
  - Antes: Postgres 17; cobertura 0301; 455 itens na sonda, 1 ausente (`envio_segredo_no_vault`, o de sempre); 81 mandatos; 2.999 pendências; 138.931 linhas em `campo_extraido`, 0 com `ln`; `fato_financeiro` inexistente; rótulo `conta_canonica_incerta` inexistente.
  - Depois: cobertura 0302; 475 itens, o mesmo 1 ausente; os 20 requisitos da 0302 presentes; `fato_financeiro` é VIEW `{security_invoker=true}`; `fn_fato_sonda_recentes()` = 0 (as 3 versões mais novas medidas, nenhuma divergência); 81 / 2.999 / 138.931 / `ln` 0 (nada tocado); 0 pendências `conta_canonica_incerta` (só a extração nova abre).
  - Definição dos objetos idêntica à do banco de teste: md5 sem ACL `b22379cd…` nos dois. Com ACL difere só pelo privilégio `m` (MAINTAIN) que o Postgres 17 dá ao dono; nenhum objeto da 0302 dá acesso ao `anon`.
- **Por que renumerar:** aplicada depois da 0301, a 0243 gravaria `instalacao_cobertura.ate_migration = '0243'` e rebaixaria o marcador de 0301 para 0243. Agora usa `greatest(ate_migration, '0302')`, e a ordem da sonda foi de 1105–1124 para 1400–1419.
- **Por que o CI do #296 estava vermelho:** o job `banco` reprovou só pelo `schema.sql` (496 linhas `SET (pg_attver=N)`; o filtro já estava no `main`, fae35f5). O Sonar reprovou pelos rascunhos de `patches/s129-…` e `patches/s130-…` (48 problemas, 87% de duplicação), que saíram do PR.
- **6ª revisão independente: 0 ALTO.** Os 2 MÉDIOS foram corrigidos e medidos (as views da sonda legíveis pelo `anon` sob o default de privilégio: 1 assert reprova sem a correção; corridas sem dblink pareciam verdes: agora reprovam). BAIXO não corrigido: o marcador literal do `search_path` em `fato_guarda_de_escrita_search_path`.
- **Organização do repositório (#302, mergeado):** README na raiz, índice da documentação, READMEs por camada, 12 arquivos superados removidos, sessões até a 117 movidas para `Arquitetura do Sistema/3 Estado e Execução/ESTADO_ATE_2026-11-04.md`.
- **NÃO MEDIDO:** uma extração nova em produção passando pelo gatilho (`fato_pendencia_avaliada` deve aparecer em `evento_auditoria`). Conferir na próxima rodada do n8n.

## SESSÃO 130 (13/11/2026) — REVISÃO DO REDESENHO, KIT PELO BANCO (0301) E REDESENHO "JANELA DE VIDRO"

> **Migration aplicada mais nova (S130, APLICADA EM PRODUÇÃO em 13/11): `0301_o_kit_que_levava_quatro_segundos_para_abrir.sql`.** PR rodrigovaroto-wq/Oria-Digital#300, branch `claude/vibrant-euler-rlto0l`.

- O #298 foi mergeado ANTES da revisão independente do `3c9ad4f`. Ela foi refeita, logada, e achou 4 ALTOS (A1 Kit "lido" sem linha em 13 de 81 mandatos; A2 chip "pendências" = bloqueantes; A3 fila cortada a 390 px; A4 texto no mármore abaixo de AA) e 3 médios.
- `40ab600`: o portal lê `fn_kit_do_caso` (0300) nos três chamadores, por `lib/kit-do-caso.ts`. Custo medido: a visão geral foi de ~2 s para ~7 s, porque a função levava 3–9 s.
- `de9cbc6`: A2, A3, A4 e M1–M3. Com a correção desligada, 36 asserts reprovam.
- **0301 APLICADA EM PRODUÇÃO em 13/11/2026** (a pedido do dono, pela API, 1,7 s, arquivo do commit `125b420`). Antes: 454 itens, 0 ausentes, cobertura 0300, 81 mandatos. Depois: 455 itens, 0 ausentes, cobertura 0301, 81 mandatos. `fn_kit_do_caso` como sócio: 3,1 s → 0,04 s (ee6251e6) e 4,0 s → 0,39 s (5469db1d), já aquecido; a resposta é a mesma (md5 das 8 linhas igual antes e depois).
- `30ac932`: redesenho etapa 1 (janela de vidro, trilho de ícones, Início em 2×2). Textos abaixo de AA: 4 → 0. **FCP +10 a 40 ms em todas as telas, causa não isolada: o dono aceitou por enquanto e pediu para reduzir depois.**
- **Pendente:** os 8 avisos de estilo do Sonar do #300; o mandato e as abas no visual novo (etapa 2).
- Histórico da 0301, antes de aplicada: sob a RLS, os `exists` do CTE `lido` viravam um Seq Scan em `documento_versao` inteira, chamando `fn_versao_extracao_concluida` 1.679 vezes. Medido em produção com rollback, como sócio: 3,09 s → 0,03 s (9 documentos) e 4,5 s → 0,4 s (115 documentos), com as 8 linhas iguais. **Não mergear o #300 sem a 0301 aplicada.**
- **Dono, 13/11: novo redesenho "janela de vidro"**, a partir de 4 templates do Drive (octadesk descartado): Cobalto, fundo próprio (sem as imagens dos templates), trilho de ícones que expande. Primeiro a moldura e o Início.

## SESSÃO 129b (12–13/11/2026, conta Claude Oria, branch `claude/tender-albattani-vx6m60`) — 0277: a conciliação do aging corrigida (3 ALTOS da 0274), APLICADA em 13/11

> **Migration desta seção: `0277_o_aging_que_apagava_a_divergencia_de_um_ano_e_somava_o_pai_com_as_filhas.sql`** (a mais nova do repositório é a `0300_o_item_do_kit_que_ficava_recebido_sem_ninguem_ter_lido.sql`, da S129/S130 abaixo, já aplicada). Em 13/11, depois do merge do `main` (#298: 0276 e 0300), o dono pediu: aplicar a 0277, abrir o PR e ligar a conciliação do aging na rodada (nota da aplicação abaixo, quando houver). O dono pediu 0277; a 0275 ficou livre. Branch `claude/tender-albattani-vx6m60`, tudo enviado (commits 69926e1, 25cf23c, f765403, 35b9795). Sem PR.

- **0277 APLICADA EM PRODUÇÃO em 13/11/2026** (a pedido do dono, pela API de gerenciamento, 1,9 s, arquivo do commit `1927f31`, que já traz a cobertura com `greatest` e a sonda renumerada para 1373–1386). Antes: 435 itens na sonda, 1 ausente (`envio_segredo_no_vault`, o de sempre), cobertura 0300, 81 mandatos, `aging_importado` 0, 0 pendências do aging, 2.999 pendências (2.146 abertas), 7.599 reconciliações. Depois: 449 itens (os 14 da 0277, 0 ausentes deles), o mesmo ausente do Vault, cobertura 0300 (não rebaixou), 81 mandatos, 2.999 / 2.146 / 7.599 (nada tocado), FK `aging_importado.entidade_id` NO ACTION. `fn_registrar_reconciliacao` e `fn_fundir_entidade` trocadas (md5 do corpo mudou).
- **0278 APLICADA EM PRODUÇÃO em 13/11/2026** (decisão do dono: ligar a conciliação do aging na rodada; 1,4 s; arquivo do commit `8a47e45`). `fn_reconciliar_caso` reemitida do corpo da 0192 (+26 linhas, 0 modificadas): concilia as carteiras vigentes UMA vez no fim da rodada; o aging roda em subtransação (um erro dele não derruba as checagens clássicas do lote) e o "não conciliou" (erro ou falta de permissão) grava `evento_auditoria` 'aging_nao_conciliado_na_rodada' por `fn_rastro_aging_nao_conciliado`. A via `fn_reconciliar_por_documento(doc,'tudo')` NÃO liga: o único chamador dela em produção é `fn_reconferir_caso` (0240), sem chamador hoje; se o "Mandato reconferido" for ligado, ligar o aging nela. Revisão independente: 0 ALTO; os 2 MÉDIOS e o BAIXO corrigidos antes de aplicar. 32 asserts. Antes: 449 itens na sonda, só o ausente do Vault, cobertura 0300, 81 mandatos, 2.999 pendências, 7.599 reconciliações, 15.923 eventos, md5 do corpo = o da 0192. Depois: 454 itens (5 da 0278, 0 ausentes), o mesmo ausente do Vault, cobertura 0300, 81 / 2.999 / 7.599 / 15.923 (nada tocado), ACL de `fn_reconciliar_caso` igual. **NÃO MEDIDO:** uma rodada real do n8n com carteira (não existe carteira em produção); conferir na primeira importação.
- **O que a 0277 corrige** (a 0274 está em produção com a tabela `aging_importado` vazia: nada foi conciliado errado):
  1. **O ok de um ano resolvia a divergência de outro.** A pendência do aging passa a ser achada pela data-base da carteira na função central `fn_registrar_reconciliacao`, reemitida do corpo da 0241 com 33 linhas novas e 6 modificadas. Os outros tipos ficam idênticos (corpo de produção conferido byte a byte com o da 0241).
  2. **Pai + filhas de Fornecedores somavam em dobro.** Em produção, grupos com pai e filhas somando em dobro: 282 → 7 (quase todos sem escala, que viram `unidade_divergente`).
  3. **Balanço só existente como coluna de combinado virava `documento_ausente`.** 12 entidades em 3 mandatos existem só como coluna de combinado; agora conciliam por ele.
  - Aging × balanço em módulo. A convenção de passivo negativo aparece só em 3 de 917 versões de produção, então o módulo só vale para conta de passivo com a convenção provada no documento.
  - Fusão de entidades: a carteira só é levada pela fusão (`fn_aging_levar_na_fusao`, guarda `oria.fusao_de`). `fn_fundir_entidade` reemitida do corpo da 0213.
- **Revisões independentes (`revisor-defeito-silencioso`):** a 1ª achou 3 ALTOS na 1ª versão (um período `data-base` fabricado contaminava as checagens clássicas; pendência NULL casava qualquer ano; sinal). O dono decidiu reemitir a função central. A 2ª achou 1 ALTO herdado (fusão apagava a carteira), 1 MÉDIO e 2 BAIXOS, corrigidos em f765403. A 3ª achou 0 ALTO, 1 MÉDIO e 2 BAIXOS, corrigidos em 35b9795. **A 35b9795 não teve revisão própria**, só o autor e as suítes.
- **Suítes (banco `tdf_test`, sessão principal):** `run.sh` inteiro, TODOS OS TESTES PASSARAM. 0277: 91 asserts. 0274: 153 ok. `node --test 'Supabase/test/*.test.mjs'`: 48 pass, 0 fail, 4 skipped. `conferir-chamadas` OK. Sonda `--so-buraco` sem buraco. Conhecimento `conferir` OK. **CI do GitHub: NÃO CONFERIDO** (não houve PR).
- **Medido e NÃO corrigido:** o BALANCETE nunca fecha numa data (192 de 192).
- **Tetos declarados no cabeçalho da 0277:** o passo 0 (raise se houver pendência do aging não resolvida de antes) foi medido só à mão. `fn_corrigir_descricao_contaminada` não conhece `data_base`. Não existe aging real (DM7): as carteiras dos testes são montadas. A conciliação não é refeita na fusão.
- **Ficha nova:** `.claude/conhecimento/fichas/periodo-fabricado-vaza-para-checagens-classicas.md` (armadilha). Não houve ficha para a fixture pai/filho: ela já é coberta por `.claude/memory/fixture-nasce-vazia.md`.
- **Fora desta rodada:** ACL dos default privileges (55 tabelas); a tela ME2; ligar `fn_reconciliar_aging_do_caso` em `fn_reconciliar_caso` (decisão do dono); P27/0243 (parada); P28 (o dono ainda não quer).

### ▶ PRÓXIMOS PASSOS (em ordem)

1. **Dono decide aplicar a 0277 em produção.** Ela reemite as funções QUENTES `fn_registrar_reconciliacao` e `fn_fundir_entidade`. Aplicar depois da 0274 (já aplicada). Arquivo: o da branch no commit `35b9795`. Depois, conferir pela sonda: `select chave, migration, tipo, objeto, presente, detalhe, porque from fn_instalacao_conferir() where migration='0277' and not presente;` deve dar 0 linhas (são 14 requisitos, ordem 1373–1386).
2. Abrir o PR quando o dono pedir.
3. A ME2 (a tela) só depois da 0277 aplicada.
4. ~~Decisão do dono sobre ligar a conciliação na rodada~~ FEITO: 0278 aplicada em 13/11.

## SESSÃO 129 (12/11/2026) — VISÃO GERAL DO MANDATO: 13,4 s → leituras em lote (0276); redesenho do portal em andamento

> **S129 concluída** pela S130 (#298–#301). O plano de continuação dela (`PLANO_DE_CONTINUACAO_S129.md`) saiu do repositório em 18/11/2026 e está no histórico do git.
> - Primeiro passo: refazer a revisão independente do redesenho (`3c9ad4f`), que foi interrompida.
> - Depois: corrigir os achados e os 7 avisos do Sonar, ter o CI verde e fazer o merge do #298, já autorizado pelo dono.

> **Migration aplicada mais nova (S130, APLICADA EM PRODUÇÃO em 13/11): `0301_o_kit_que_levava_quatro_segundos_para_abrir.sql`** (acelera `fn_kit_do_caso` sob a RLS; ver S130 no topo). **Antes dela: `0300_o_item_do_kit_que_ficava_recebido_sem_ninguem_ter_lido.sql` (Função 1, APLICADA EM PRODUÇÃO em 13/11).** (Anterior: ver o resto desta linha.) **migration mais nova no repositório: `0276_a_visao_geral_que_buscava_dez_mil_linhas_e_230_chamadas_para_contar.sql` (ESCRITA, NÃO APLICADA).** `fn_linhas_por_versao(uuid[])` e `fn_algum_documento_serve_como(uuid[], text)`, ambas `security invoker`. A 0275 ficou de fora DE PROPÓSITO: está reservada para a correção do aging (S127b, abaixo).

- **Defeito medido:** a visão geral do mandato (`portal/src/app/casos/[id]/page.tsx`) levava 13,4 s num mandato de 115 documentos e 10.231 linhas. Duas causas somavam 10,2 s: a contagem de linhas paginava `campo_extraido` em 12 idas sequenciais (5,8 s), e o Kit Básico fazia 230 RPCs de `fn_documento_serve_como` (4,4 s).
- **0276 APLICADA EM PRODUÇÃO em 12/11/2026** (a pedido do dono, pela API de gerenciamento, 1,2 s). Antes: 422 itens na sonda, 0 ausentes, cobertura 0274, 81 mandatos, nenhuma das duas funções. Depois: 426 itens (os 4 da 0276), 0 ausentes, cobertura 0276, 81 mandatos. Medido com a sessão do dono no mandato de 115 documentos: contagem 5,2 s (12 idas) → 0,2 s (1 ida), 115 de 115 versões devolvidas, soma 10.231 igual à paginada; Kit 4,7 s (230 RPCs) → 0,45 s (2 RPCs), mesma resposta.
- **Falta:** trocar `lib/supabase/linhas-por-versao.ts` e `lib/kit-basico.ts` para chamar as funções em lote, mantendo o caminho atual quando a função não existir. **São TRÊS chamadores do Kit, não dois:** `casos/[id]/page.tsx`, `documentos/(lista)/page.tsx` e `casos/[id]/export/route.ts:603-607`.
- **ALTO pré-existente (revisão independente da 0276, não introduzido por ela):** o export monta o próprio serviço do Kit com `return !r.error && r.data === true;`, então QUALQUER erro (um timeout numa das RPCs) vira "item não atendido" e o item sai como faltante no book entregue ao cliente (regra 1). Os outros dois chamadores lançam quando há erro. Ao trocar para o lote, o export tem de ir junto, sem herdar o `!r.error &&`.
- **Redesenho do portal: o dono escolheu a direção A (Cobalto noturno)** e a frase de login "O detalhe que muda a tese aparece primeiro." Maquetes, pranchas e a comparação com 8 concorrentes estão em `Arquitetura do Sistema/7 Marca/redesenho-2026-11/`.
- **Feito e comitado nesta sessão (PR #298):**
  - a 0276, aplicada em produção;
  - o portal usando as leituras em lote: visão geral 13,4 s → 1,1 s;
  - o ALTO do export, em que erro virava "Kit faltante";
  - o ALTO do checklist no export, a partir da revisão;
  - o login na direção A, com acessibilidade revisada.
- **▶ ONDE PAROU (o dono pediu para parar em 12/11, por limite de uso):**
  1. **Item 2, "a tela aparece na hora": FEITO em 13/11 (retomada às 21:02 BRT).**
     - O patch foi aplicado e terminado. Os blocos chegam por Suspense com esqueleto (`components/revelar.tsx`, `casos/painel-*.ts(x)`, `casos/[id]/visao-*.ts(x)`).
     - Título do Início: 3,2–3,8 s → 0,28 s. DCL do Início: 3,3 → 2,4 s. Visão geral: DCL 1,0–2,1 → 0,65–0,97 s.
     - CLS 0 nas 12 cargas.
     - Patch removido.
  1b. **Telas internas na direção A: FEITAS em 13/11.**
      - Visual: fundo único de mármore (escuro e claro), cartões foscos flutuantes, barra lateral flutuante, botão Sol/Lua entre a discrição e o perfil, e Geist no portal todo.
      - "Precisa de você" agrupado por mandato e "Seus mandatos" em tabela com régua de etapas e paginação.
      - Selo de origem do número, Kit Básico com % só do que tem conteúdo, e o bloco "Andamento da leitura".
      - "Conferido" segue como "ainda não medido", porque depende da 0300 aplicada e da decisão do dono (botão "conferi" por documento, recomendado, sem resposta ainda).
      - FALTA: a revisão independente do commit das telas.
  1c. **0300 APLICADA EM PRODUÇÃO em 13/11/2026** (a pedido do dono, pela API de gerenciamento, 2,5 s, sem erro).
      - Antes: 426 itens na sonda, 0 ausentes, cobertura 0276, 81 mandatos, 235 `item_faltante` abertas.
      - Depois: 435 itens (os 9 da 0300), 0 ausentes, cobertura 0300, 81 mandatos.
      - Backfill: 233 chaves adotadas (evento `{"adotadas":233}`); as 2 de contrato social da 0208 ficaram sem chave, como previsto.
      - `fn_kit_do_caso` no mandato 5469db1d: BALANCO, COMBINADO, FAT_INTRAGRUPO e FATURAMENTO_24M `extraido`; DRE `recebido_sem_linha`; FLUXO_CAIXA e MUTUOS `faltante`; CONTRATO_SOCIAL `aguardando_extracao`.
      - O portal AINDA NÃO LÊ `fn_kit_do_caso` (fatia 1.2). Ver o relatório no commit e4a3a9e: estados novos `lido_sem_dado_por_natureza` e `aguardando_desde`; contadores de empresa nulos fora das granularidades `entidade` e `entidade_periodo`.
      - **"Conferido": decisão em aberto, com possibilidade RECOMENDADA registrada.** Hoje é quase inalcançável: 1.443 de 1.648 versões têm todas as linhas auto-aceitas, e `fn_aceitar_extracao` não converte auto-aceite em aceite de pessoa.
        - Recomendação: um botão "conferi" por documento, que grava quem conferiu e quando (padrão DataSnipper). `fn_kit_do_caso` passaria a tratar como `conferido` o item cujo documento vigente tenha esse registro.
        - O dono pediu para NÃO implementar ainda (13/11).
  2. **Fila aprovada pelo dono, nesta ordem:**
     - telas internas na direção A, incorporando do benchmark a cor por origem do número, o Kit com % de prontidão (recebido ≠ conferido) e o progresso por documento;
     - transições de página e abas deslizantes (transitions.dev);
     - régua do mandato animada;
     - modo apresentação ("ver como o cliente vê");
     - sextante em traço, número com troca suave e confirmações vivas;
     - gráficos sóbrios;
     - destaque do trecho no PDF (investigar se o banco guarda a posição);
     - a conta do número calculado;
     - a grade documento × fato.
  3. **Aprovados pelo dono, mas que exigem banco (desenho antes do código; o desenho foi interrompido antes de ser escrito):**
     - (a) o envio fecha sozinho o item do Kit e a pendência, sem fechar o que não foi conferido;
     - (b) link para o cliente enviar documentos (Área do cliente, arquivada no REDESENHO; pré-requisito 0216 feito);
     - (c) número novo × reapresentado por período entre versões;
     - (d) pendência vira achado, com dono, efeito e mitigação, e relatório de riscos.
     - **Desenho pronto:** `Arquitetura do Sistema/3 Estado e Execução/DESENHO_QUATRO_FUNCOES_2026-11.md`.
     - **Decidido pelo dono em 13/11:**
       - aceitas todas as 23 recomendações;
       - ordem 1 → 4 → 3 → 2;
       - a Área do cliente (2) só depois de 18/12;
       - migrations desta frente a partir da **0300** (não 0277); a 0275 segue reservada para o aging. Reconferir na hora.
  - Ferramentas auditadas: transitions.dev aprovado (CSS puro, licença sem redistribuir a biblioteca); React Bits, um componente por vez; Taste Skill NÃO instalar (gatilho Stop de 10 min e manda inventar dado), só a biblioteca de paletas.

## SESSÃO 127b (11–12/11/2026, conta Claude Oria) — PLANO DO MVP: MB0, MB1, MB2; 0272 (mapeamento de colunas)

> **Migration aplicada mais nova (S130, APLICADA EM PRODUÇÃO em 13/11): `0301_o_kit_que_levava_quatro_segundos_para_abrir.sql`** (acelera `fn_kit_do_caso` sob a RLS; ver S130 no topo). **Antes dela: `0300_o_item_do_kit_que_ficava_recebido_sem_ninguem_ter_lido.sql` (Função 1, APLICADA EM PRODUÇÃO em 13/11).** (Anterior: ver o resto desta linha.) **migration mais nova no repositório: `0276_a_visao_geral_que_buscava_dez_mil_linhas_e_230_chamadas_para_contar.sql` (S129, APLICADA EM PRODUÇÃO em 12/11). Na S127b era a `0274_o_aging_que_so_existia_no_navegador_e_nunca_conferia_com_o_balanco.sql`** (APLICADA EM PRODUÇÃO em 12/11/2026, ver abaixo; nota de quando foi escrita: a sessão principal comita e aplica; `aging_importado`, o resumo do aging por mandato e entidade, e a conciliação com Clientes/Fornecedores e Adiantamentos do balanço; MB3b). A anterior, `0273_a_contraparte_com_nome_de_total_que_so_o_analista_distingue.sql`, está APLICADA (abaixo), e a `0272_o_mapeamento_de_colunas_que_cada_arquivo_redescobria.sql` também. A 0272 nasceu 0242 nesta branch e foi renumerada em 12/11: a 0242 de produção é a da conta canônica (`0242_a_secao_que_so_existia_em_codigo.sql`, branch `claude/peaceful-archimedes-hisyd0`, já aplicada), e a maior do repositório era a 0271. Produção em 12/11, antes desta rodada: 0242 (conta canônica), 0270 e 0271 aplicadas; `instalacao_cobertura` em 0271. Branch `claude/hopeful-ramanujan-c425e4`.

- **Plano novo:** `Arquitetura do Sistema/3 Estado e Execução/PLANO_MVP_2026-11.md`, aprovado pelo dono (DM0) em 11/11. O plano anterior fica como está. O andamento por fatia está no §7 dele.
- **MB0:** `Dados de Teste/volume/` (AR, AP e OFX sintéticos de até 1M de linhas que fecham com o BP do book-distress).
- **MB1:** `Leitor/lib/tabela.mjs` (leitor tabular em fluxo, CSV e XLSX, no navegador).
- **MB2:** `Leitor/lib/mapeamento.mjs` (mapeamento de colunas e formato, título × subtotal × rejeitada) + a 0272.
- **0272 APLICADA EM PRODUÇÃO em 12/11/2026** (a pedido do dono, pela API de gerenciamento, 1,6 s). Antes: 386 itens na sonda, 0 ausentes, 81 mandatos, cobertura 0271. Depois: 396 itens (os 10 da 0272), 0 ausentes, 81 mandatos, `mapeamento_de_colunas` vazia, cobertura 0272. O vetor da biblioteca JS dá a mesma impressão do cabeçalho no Postgres de produção. `run.sh` local: TODOS OS TESTES PASSARAM.
- **0273 APLICADA EM PRODUÇÃO em 12/11/2026** (a pedido do dono, 1,5 s): `contraparte_confirmada` (o analista confirma, POR MANDATO, que um "TOTAL DISTRIBUIDORA LTDA" é cliente de verdade). Antes: 396 itens, 0 ausentes, 81 mandatos, cobertura 0272. Depois: 408 (os 12 da 0273), 0 ausentes, 81 mandatos, tabela vazia, cobertura 0273. Os três vetores de `fn_texto_normalizado` conferem em produção. NADA chama `fn_contrapartes_confirmadas` ainda: a tela é a ME2.
- **0274 APLICADA EM PRODUÇÃO em 12/11/2026** (a pedido do dono, 1,9 s): `aging_importado` + a conciliação do aging com o balanço (positivos × Clientes/Fornecedores, negativos × Adiantamentos). A consulta de "antes" falhou (coluna errada) e não foi refeita a tempo: o último estado medido antes é o de depois da 0273 (408 itens, 0 ausentes, 81 mandatos). Depois: 422 itens (os 14 da 0274), 0 ausentes, 81 mandatos, `aging_importado` vazia, cobertura 0274; 7.599 reconciliações, a mais nova de 11/11 19:14 (a 0274 não criou nenhuma), 0 do tipo `aging_*`, 2.999 pendências. **A conciliação NÃO está ligada na rodada** (`fn_reconciliar_caso`): roda na importação e por `fn_reconciliar_aging_do_caso`; decisão do dono pendente.
- **(FEITO na S129b como 0277, ver acima)** **▶ PRIMEIRA TAREFA DA PRÓXIMA SESSÃO — 0275 (o número CONTINUA reservado para isto: a S129 usou a 0276 de propósito para não tomá-lo; ao escrevê-la, a 0275 fica abaixo da mais nova e a `instalacao_cobertura` NÃO pode ser rebaixada de 0276 para 0275), ANTES de qualquer tela ou n8n chamar `fn_aging_importar`.** A revisão independente da 0274 (12/11, depois de aplicada) achou 3 ALTOS na conciliação, todos reproduzidos e NENHUM ativo em produção (as tabelas `aging_importado`, `contraparte_confirmada` e `mapeamento_de_colunas` estão vazias e nada chama a importação):
  1. **O ok de um ano resolve a divergência de outro ano.** A pendência é chaveada pelo `periodo_id` do documento do balanço, não pela data-base; num comparativo (2024 e 2025 no mesmo documento) a carteira que confere apaga a pendência da outra; `fn_reconciliar_aging_do_caso` visita por data-base crescente e o ano mais novo sempre apaga o mais velho. Caso normal: 169 balanços comparativos de 31/12 por ano em produção.
  2. **Pai e filhos de Fornecedores somam em dobro** (`0274:439-448`): a regra "o pai vale sozinho" depende de `secao` dos filhos = nome do pai; a fixture monta assim, a extração de produção grava os filhos com `secao = 'Passivo Circulante'`. Medido em produção (leitura): o dobro em 245 grupos documento×ano de Fornecedores, em 28 de 53 mandatos (Clientes: 4). Carteira correta → pendência falsa de 100%. O assert do teste prova arranjo que produção não produz (regra 4).
  3. **Balanço que só existe como coluna de um combinado vira `documento_ausente`**, sem pendência (a busca filtra `d.entidade_id`): 16 entidades em 7 mandatos.
  Médios da mesma revisão: contas de estoque com "cliente"/"fornecedor" no rótulo casam como Clientes/Fornecedores; nada amarra o resumo ao arquivo (exigir `resumo.titulos = aplicador.titulo`); o mapeamento global (0272) pode ser trocado por qualquer Sócio/Analista de outro mandato (a tela tem de reconfirmar); balancete anual de produção nunca "fecha" (`fecha_em` NULL); em produção o `authenticated` tem INSERT/UPDATE/DELETE nas tabelas novas pelos default privileges (a RLS sem policy de escrita segura; vale para 55 tabelas). Sem defeito: segurança por mandato, `search_path` das 7 definer, anon, efeito nulo sobre as reconciliações existentes, biblioteca JS × banco.
- **Sobreposição a decidir:** a Claude Oria 2 guardou no `main` (PR #295) o `DESENHO_LEITOR_TRANSACIONAL.md` (leitor no servidor com DuckDB; GUARDADO, não aprovado), que resolve o mesmo problema da MB1/MB2 por outro caminho e reserva "0272 em diante". A 0272 desta branch ocupa esse número; quem reabrir o desenho usa a próxima livre.

## SESSÃO 130 (13/11/2026, conta Claude Oria) — P27 reescrita como VIEW; aguarda a 6ª revisão

> **A 0243 do #296 agora é VIEW** (`fato_financeiro` com `security_invoker = true` sobre `fn_fato_resolver`, invoker; um gatilho só, em `evento_auditoria`/`extracao_sombra`, que abre e baixa a pendência `conta_canonica_incerta` sem gravar fato). NÃO APLICADA. Os 2 ALTOS da 5ª revisão (corrida; transcrição humana sem fato) deixam de existir por construção; falta a 6ª revisão independente provar isso. O detalhe (desenho, matriz de teste, sabotagens, desempenho, não medido) está no cabeçalho da 0243 e em `patches/s130-p27-view` (fora do repositório desde 18/11; recuperáveis com `git show 8a416628:"Arquitetura do Sistema/3 Estado e Execução/patches/s130-p27-view"`)-progresso.md`.
> - Medido local (PG16): fato_financeiro 187 asserts e corridas com dblink 14 asserts, 0 reprovados; run.sh inteiro verde; N8N 814/814; portal verde. Aplicação 0,065 s. Extração de 4.000 linhas 1,5–1,7 s. Ler um mandato de 40 mil fatos: 5,2–5,7 s (a P28 deve materializar por mandato).
> - NÃO medido: produção (versão do Postgres: ≥ 15 inferido da 0207; maior mandato real).
> - Para retomar: 6ª revisão (`revisor-defeito-silencioso`) → sem ALTO, confirmar com o dono e aplicar → medir a sonda da 0243 e o `ln` → merge com merge commit.

## SESSÃO 129 (12/11/2026, conta Claude Oria) — P27 no PR #296: 5 revisões, decisão de trocar a tabela por VIEW; PARADA pelo dono (limite)

> **Na época, a migration mais nova do repositório continuava `0271_o_quadro_de_imobilizado_que_a_ia_gravava_como_balanco.sql`.** A `0243` está SÓ no PR #296 (branch `claude/eager-franklin-n4oxjd`, HEAD `7d5f503`), **NÃO APLICADA** e **NÃO PODE ser aplicada como está** (2 ALTOS abertos da 5ª revisão, abaixo). CI verde no `7d5f503` (os testes não pegam os ALTOS).

### Onde parou (12/11, ~20:00 UTC)
- O dono mandou parar por limite de uso. O especialista foi parado ANTES de escrever a versão VIEW: nada de código novo se perdeu; a árvore estava limpa.
- **Decisão do dono (12/11): (a) `fato_financeiro` vira VIEW sobre `fn_fato_resolver`**, e "teste tudo antes de qualquer aplicação prática; essa parte tem de ser extremamente bem produzida e testada".
- Os scripts das revisões 3–5 (reproduções com duas sessões, sabotagens, custo) estão em `patches/s129-p27-scripts-de-revisao/` (fora do repositório desde 18/11; recuperáveis com `git show 8a416628:"Arquitetura do Sistema/3 Estado e Execução/patches/s129-p27-scripts-de-revisao/"`) (eram do scratchpad e de /tmp; os caminhos dentro deles apontam para lá e para bancos locais `tdf_*` que não existem mais).

### A trajetória no #296 (cada commit tem defeito, causa e não-vazio na mensagem)
1. `006bbab` — 0243 recuperada do `1e195b2` + patch da 3ª tentativa; **bloqueio da 0270 resolvido**: a 0243 NÃO reemite mais `fn_registrar_campos_extraidos` (o `ln` da 0270 fica). Critério novo: entidade só por `fn_coluna_entidade`, período só pela ÚNICA coluna de saldo ou ÚNICA do ano em doc não parcial; senão nulo com motivo. 159 asserts.
2. 3ª revisão: 3 ALTOS (duas colunas casando a mesma entidade por ordem física; DRE→BALANCETE sem re-resolver; sonda verde com a extração sem gerar fato) + 3 médios + 1 baixo → `b1e67d2` (175 asserts).
3. 4ª revisão: 1 ALTO (janela da aplicação: o que o n8n comitava entre backfill e create trigger ficava sem fato, para sempre) + 2 médios (identidade dependia da ordem dos eventos; reparo não reparava conta) → dono escolheu "recalcular sempre" → `7d5f503` (escritor único `fn_fato_recalcular`, 205 asserts, janela fechada medida com duas sessões).
4. **5ª revisão do `7d5f503`: 2 ALTOS, mesma família ("o fato não converge para o estado atual")**:
   - Corrida: gatilho de cadastro recalcula em snapshot velho enquanto um update de documento não comitado segura lock → documento com entidade, fatos `documento_sem_entidade`; extração COMBINADO concorrente com cadastro de entidade → motivo falso ou valor atribuído onde o do-zero dá `coluna_casa_varias_entidades`.
   - `fn_registrar_transcricao_humana` (portal) cria a versão vigente e ela nunca vira fato (v2 0 fatos, v1 46).
   - Médios: cadastro de período ~36 s num mandato 10×4.000 (70% dos fatos têm período nulo); sonda `recentes` não olha entidade/período/valor; update de `campo_extraido.valor_num` deixa fato velho. Baixo: sonda `um_escritor` afirma mecanismo (falso verde e falso vermelho).
   - Diagnóstico: a causa é a arquitetura (cópia mantida por gatilhos); cada rodada abria caminho novo. Daí a VIEW.

### Para retomar, em ordem
1. Branch `claude/eager-franklin-n4oxjd`, a partir do `7d5f503`. Despachar `migrations-postgres` com o desenho e o plano abaixo (o brief inteiro foi escrito na S129; o essencial está aqui).
2. **Desenho:** `fato_financeiro` = VIEW (`security_invoker = true`; resolver NÃO security definer) sobre `fn_fato_resolver(versão)`, mesmas colunas e semântica da tabela; identidade = `campo_extraido_id`; decidir e justificar todas as versões × só a vigente. SAEM tabela, gatilhos de materialização, `fn_fato_recalcular`, backfill, recálculo final, sondas `um_escritor`/convergência, o repontar da fusão (`fn_fundir_entidade` volta à da migration anterior se a 0243 não precisar mais tocá-la). FICA um gatilho só no evento `extracao_sombra` que abre/fecha a pendência `conta_canonica_incerta` (só extração nova; backfill não abre; versão superada baixa), sem gravar fato; decidir se transcrição humana abre pendência. Grep de chamadores antes de remover.
3. **Plano de teste (o centro):** A) todos os cenários das 5 revisões com o fato esperado ESCRITO À MÃO (não "igual ao resolver", que é tautológico numa view): 1.310, 500, 435, 342, ALFA/Beta/Eliminações/Consolidado, Alfa Comércio Atacado × Alfa Comércio nas duas ordens, Saldo Final+Saldo Atual, 2025+31/12/2025, balancete parcial, DRE→BALANCETE, fusão Atacado→ALFA (Vertentes Imóveis sem dono com motivo), duas chamadas, seção e valor alterados, transcrição humana, entidade renomeada/cadastrada depois, período cadastrado depois. B) corridas R1/R2/R3 e janela com duas sessões reais (dblink no CI se houver). C) pendência. D) segurança sob default ACL de tabela E de função simulado: authenticated só o próprio mandato, anon nada, read_only_user lê a sonda, ninguém escreve. E) desempenho: versão 4.000, maior mandato das fixtures, mandato 10×4.000, view inteira ~85 mil, extração com/sem o gatilho, aplicação; se ler mandato passar de alguns segundos, propor (sem implementar) view materializada para a P28. F) ordem produção × zero = mesmo schema; `ln` da 0270 gravado; reaplicação idempotente. G) não-vazio em cada parte (inclusive security_invoker off, resolver definer, gatilho da pendência removido). H) todas as suítes + n8n/portal que tocam campo_extraido. I) leitura de produção só se houver acesso de leitura: maior mandato e versão do Postgres (confirmar PG15+).
4. Comitar, push, 6ª revisão independente (`revisor-defeito-silencioso`), CI. Só sem ALTO: confirmar com o dono e aplicar; medir sonda da 0243, `ln` não nulo em `campo_extraido` não caiu, leitor só-leitura lê a sonda.
5. Merge do #296 com merge commit, nunca squash.

## SESSÃO 128 (11–12/11/2026, conta Claude Oria) — P26 NO AR (0242 aplicada); P27 (0243) SEPARADA para PR próprio

> **Migration aplicada mais nova (S130, APLICADA EM PRODUÇÃO em 13/11): `0301_o_kit_que_levava_quatro_segundos_para_abrir.sql`** (acelera `fn_kit_do_caso` sob a RLS; ver S130 no topo). **Antes dela: `0300_o_item_do_kit_que_ficava_recebido_sem_ninguem_ter_lido.sql` (Função 1, APLICADA EM PRODUÇÃO em 13/11).** (Anterior: ver o resto desta linha.) **migration mais nova do repositório (hoje: `0276_a_visao_geral_que_buscava_dez_mil_linhas_e_230_chamadas_para_contar.sql`, ver S129; antes dela `0274_o_aging_que_so_existia_no_navegador_e_nunca_conferia_com_o_balanco.sql`, ver S127b; na S128 era a `0271_o_quadro_de_imobilizado_que_a_ia_gravava_como_balanco.sql`) (Claude Oria 2, P11, junto da `0270_a_linha_que_nao_sabia_de_que_linha_veio.sql`) — as duas APLICADAS EM PRODUÇÃO segundo a sonda de 12/11 (0270: 4/4; 0271: 1/1), ao contrário do que a seção da P11 diz abaixo.** A da Claude Oria: `0242_a_secao_que_so_existia_em_codigo.sql` — APLICADA EM PRODUÇÃO (11/11, com o bloco de grant do `3e5d012` aplicado logo depois). Em 12/11 o dono decidiu SEPARAR: o PR #294 leva só a P26 (0242 + o teste do leitor só-leitura) e a P27 (0243) sai daqui para um PR novo. A 0243 NÃO está aplicada e NÃO está nesta branch: o código está nos commits `8f0f66d` e `1e195b2` (histórico desta branch) e a 3ª tentativa no patch abaixo. Onde esta seção e a S127 falarem de migration, vale esta.

> **BLOQUEIO NOVO DA P27 (medido em 12/11):** a `0270` da Claude Oria 2 (P11, coluna `ln`) está APLICADA em produção e reemitiu `fn_registrar_campos_extraidos`. A 0243 reemite essa função a partir do corpo da 0231: aplicada, APAGARIA em silêncio a gravação do `ln` da P11; e num banco do zero a 0270 (depois da 0243 na ordem) apagaria a materialização. Decisão para o PR da P27: tirar a materialização de dentro de `fn_registrar_campos_extraidos` (gatilho próprio), para não depender do corpo de uma função que a Claude Oria 2 reemite a cada fatia.

### Onde parou (11/11, ~21:30 UTC) — leia antes de qualquer coisa
- **O dono mandou parar** no meio da 3ª tentativa de correção da 0243. O trabalho interrompido NÃO foi testado e NÃO está na branch: está salvo em `Arquitetura do Sistema/3 Estado e Execução/patches/s128-0243-terceira-tentativa-NAO-TESTADA.patch` (968 linhas, sobre o `1e195b2`; `git apply --check` limpo). Ele toca só `Supabase/migrations/0243_…sql` e `Supabase/test/fato_financeiro.test.sql`; o `schema.sql` NÃO vai no patch (é derivado: regere com o `run.sh`).
- **O último estado TESTADO da P27 é o commit `1e195b2`** (no histórico desta branch; a 0243 foi retirada da branch em 12/11): run.sh inteiro verde local (fato_financeiro 127 asserts), CI verde (workflow_dispatch, run 43101449284, 6 jobs). Mas esse estado tem **2 ALTOS abertos** da 2ª revisão (abaixo): NÃO aplicar nem mergear a 0243 como está.
- **Autorização do dono (11/11):** aplicar as migrations no momento certo e mergear o #294 quando estiver sem erro e pronto para operação. **A P28 NÃO** — o dono disse que ainda não a quer.

### Para retomar, em ordem
1. Numa branch nova a partir do `main` (depois do merge do #294): recuperar a 0243 e o teste dela com `git show 1e195b2:<caminho> > <caminho>` (os dois arquivos: `Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql` e `Supabase/test/fato_financeiro.test.sql`), repor no `run.sh` o bloco "== 0243" e no `Supabase/README.md` o bloco da 0243 (ambos no `1e195b2`), e o teste do leitor (`sonda_para_o_leitor_somente_leitura.test.sql`) volta a listar `fn_tipo_gera_fato`, `fn_linha_vira_fato` e `fn_papel_linha`. Depois aplicar o patch `Arquitetura do Sistema/3 Estado e Execução/patches/s128-0243-terceira-tentativa-NAO-TESTADA.patch` com `git apply`. **Antes de tudo, resolver o bloqueio da 0270 (acima).** e ler o cabeçalho da 0243 (item 5, "O CRITÉRIO NOVO") e o diff do teste. Conferir o que está pronto contra a lista do passo 2; o especialista foi parado no meio, então partes podem faltar.
2. Terminar a 3ª tentativa (regra das três correções: é a ÚLTIMA nesta família; se falhar, parar e rever a arquitetura com o dono). O critério, decidido por mim e registrado no cabeçalho: **a 0243 não interpreta nome de coluna**; só atribui entidade/período quando uma função que o banco já usa decide sem ambiguidade; senão nulo com motivo.
   - Entidade: só por `fn_coluna_entidade(versão, entidade)` (0030, `fn_mesma_entidade`). Já no patch.
   - Período: a ÚNICA coluna de saldo (`fn_coluna_e_saldo`) ou a ÚNICA coluna de ano do documento em documento não parcial; o resto nulo. `fn_coluna_periodo_do_ano` (0234) foi descartada por desempatar por contagem/ordem alfabética (escolheria "AV% 2025"). Já no patch.
   - **Invariante da família** (no teste): em nenhum documento duas colunas diferentes caem na mesma (conta, entidade, período) não nulos. Conferir que está no teste e medir não-vazio.
   - Os cenários da 2ª revisão (`scratchpad/s1.sql`..`s6.sql`, perdidos com o container; refazer pelo texto abaixo) entram no teste: balancete 06/2025 com Mai/2025=100, Jun/2025=150, 31/05/2025=120, 30/06/2025=130 (somava 500); DRE 06/2025 com Jun/2025, Acumulado 2025, 1T2025, 2T2025 (435); Saldo Atual 150 / Orçado 2025 / AV% 2025 / Var. 2025 x 2024 (342); COMBINADO com entidade "ALFA COMERCIO DE ALIMENTOS LTDA" e colunas "Alfa Comércio"=10, "Beta Indústria"=7, "Eliminações"=-2, "Consolidado"=15 (ALFA ficava com 15).
   - Médios da 2ª revisão, a conferir no patch: `fn_fato_repontar_entidade` só reponta entidade que já não existe e grava evento (no patch); nulo que fica falso — gatilhos em `periodo`/`entidade` e `fn_materializar_fatos()` re-resolvendo os existentes (no cabeçalho do patch; conferir o código); sonda da guarda `fn_fato_pode_escrever` e `sem_privilegio` de escrita do authenticated em `fato_financeiro` (32 requisitos no patch, ordem 1105–1138); evento `fatos_materializacao_negada` e ator real (`fn_fato_ator`, no patch); `set local lock_timeout = '5s'` antes dos `create trigger` (no cabeçalho; conferir o código).
3. Rodar tudo: `sudo -u postgres env TEST_DB=<x> PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh` (o `TEST_DB` vai DEPOIS do `env`: o sudo limpa o ambiente), `node --test 'Supabase/test/*.test.mjs'`, conferir-chamadas, sonda `--so-buraco`, `indexar`+`conferir`; protocolo não-vazio em cada parte nova.
4. Comitar e abrir o PR da P27 (o #294 já foi mergeado só com a P26). Disparar o CI à mão se o GitHub não criar a execução do `pull_request` (no #294 ele não criou depois do primeiro push: usar `workflow_dispatch` de `suites.yml` na branch) e pedir a 3ª revisão independente (`revisor-defeito-silencioso`) com os cenários acima.
5. Sem nada alto: aplicar a 0243 em produção pela API (arquivo do commit, não da árvore; tem `alter type … add value` antes do `begin;` — conferido pelas duas revisões que o rótulo novo não é usado na mesma transação; o `create trigger` em `documento` segura lock e roda o backfill na mesma transação: se der timeout/deadlock, reaplicar). Medir depois: sonda `where migration='0243' and not presente` = 0 linhas, evento `fato_financeiro_backfill`, a consulta de bijeção do `Supabase/README.md`, e `select count(*) from fn_instalacao_conferir()` pela API (o leitor só-leitura tem de ler).
6. Fechar o estado (este arquivo, `MAPA_DE_EXECUCAO.md`, `STATUS_POR_ETAPA_2026-11-11.md`: 3.2) e só então mergear o PR da P27. **Merge com merge commit, nunca squash:** os commits `8f0f66d` e `1e195b2` só ficam alcançáveis pelo segundo pai do merge do #294.

### O que a sessão fez
1. **P26 — catálogo `conta_canonica` (0242).** 27 nós: 5 raízes (`demo_*`), grupos ATIVO e PASSIVO+PL, 15 seções (= `SECAO_CANONICA_ENUM` do extrator), o ANC como grupo com 4 subgrupos + `outros_ativos_nao_circulantes` (igual ao `BALANCO_OUTLINE` do portal). Natureza = saldo normal do grupo (`receita_bruta` credora; `mista` só onde o grupo tem componentes próprios dos dois lados; conta redutora é da folha, nunca herdada). Guardas no banco (raiz declarada, FK composta da demonstração, gatilho de instrução que exige que todo nó desça da raiz). Portão node `Supabase/test/conta_canonica_regua.test.mjs` (enum × seed × portal). Uma revisão independente achou 4 médios, todos corrigidos antes de aplicar (`11a179e`).
   - **Aplicada em produção** em 11/11 (1,9 s) a partir do `11a179e`, depois de CI verde (workflow_dispatch). Medido depois: 27 nós, 5 raízes, 9 constraints, 1 gatilho, 81 mandatos.
   - **Defeito que a aplicação revelou:** a sonda inteira ficou ilegível para o leitor da API (`supabase_read_only_user`): "permission denied for function fn_conta_canonica_orfas" (view da sonda chama função com o privilégio de quem LÊ). Corrigido no `3e5d012` (grant condicional, como 0233/0234) e **aplicado em produção** com a autorização do dono. Medido depois: sonda com 386 requisitos, 9/9 da 0242 presentes, só `envio_segredo_no_vault` ausente (o de sempre).
   - **O portão que faltava** (no `8f0f66d`): o `run.sh` cria `supabase_read_only_user` como em produção (nologin, bypassrls, `pg_read_all_data`, `pg_monitor`) ANTES das migrations, e `Supabase/test/sonda_para_o_leitor_somente_leitura.test.sql` roda a sonda como ele. Sem o grant da 0242, da 0243 ou da transitiva `fn_papel_linha`: 4 de 6 reprovam.
2. **P27 — `fato_financeiro` (0243), NÃO aplicada.** Decisões do dono (11/11): conta = nó de SEÇÃO; só documentos de demonstração (BALANCO, BALANCETE, COMBINADO, DRE, FLUXO_CAIXA, DVA, DMPL, DF_AUDITADA) e papel `conta`; UMA pendência `conta_canonica_incerta` por documento-versão, só para extração nova (o backfill não abre: 563 documentos-versão ficariam). Ponto único: `fn_registrar_campos_extraidos` reemitida do corpo da 0231 (mesma assinatura: o n8n NÃO precisa republicar).
   - `8f0f66d` (1ª versão) → 1ª revisão: 2 altos (coluna que não é saldo herdava o período do documento: soma 1.310 em vez de 150; balancete parcial ia para o ano) + 7 médios. → `1e195b2` corrigiu todos (127 asserts). → 2ª revisão: **2 altos novos, mesma família**: em documento parcial toda coluna com o ano ia para o período do documento (500, 435, 342); e o casamento de entidade por igualdade não casava "Alfa Comércio" com a razão social (ALFA ficava com o Consolidado). E 3 médios: `fn_fato_repontar_entidade` executável pelo authenticated sem fusão nem evento; nulo com motivo que fica falso quando o período/entidade é cadastrado depois (4.479 fatos); sonda cega à guarda de escrita.
   - Estimativa em produção (só leitura, do patch interrompido): 85.531 fatos; com o critério novo, 59.734 sem período (70%) e 1.685 sem entidade — nulo explicado em vez de período fabricado. A P28 decide se vale criar a leitura de saldo do BALANCETE e do mês por extenso.

### NÃO medido / riscos conhecidos
- **ACL de produção ≠ ACL local (revisão final do #294, BAIXO, anterior a este PR):** em produção o `pg_default_acl` do dono `postgres` dá ALL a `authenticated` e `service_role` em toda tabela nova de `public` (46 de 52 tabelas já estão assim; `conta_canonica` e as 3 views da sonda da 0242 também: `arwdDxtm`). INSERT/UPDATE/DELETE são barrados pela RLS sem policy de escrita; TRUNCATE passa por cima da RLS, mas o PostgREST não o expõe. O assert local "com papel lê e não escreve" mede um ACL que produção não tem. Sem fatia ainda: decidir se as migrations passam a revogar o que o default privilege concede.
- O patch da 3ª tentativa: nenhuma suíte rodou sobre ele.
- Custo do gatilho em `documento` (2ª revisão, doc de 4.000 linhas): UPDATE de `entidade_id` 2,06 s (sem a materialização: 10 ms); `fn_registrar_campos_extraidos` 5,95 s (antes 4,46 s). UPDATE de `status` 0,5 ms (não dispara). Teto registrado, não otimizado.
- Por que o GitHub não cria a execução de `pull_request` nos pushes do #294: não investigado.

## SESSÃO 127 (11/11/2026, conta Claude Oria) — CI sem apt; 0240 e 0241 APLICADAS EM PRODUÇÃO

> **Migration aplicada mais nova (S130, APLICADA EM PRODUÇÃO em 13/11): `0301_o_kit_que_levava_quatro_segundos_para_abrir.sql`** (acelera `fn_kit_do_caso` sob a RLS; ver S130 no topo). **Antes dela: `0300_o_item_do_kit_que_ficava_recebido_sem_ninguem_ter_lido.sql` (Função 1, APLICADA EM PRODUÇÃO em 13/11).** (Anterior: ver o resto desta linha.) **(Superado pela S128, acima: a 0242 foi APLICADA em produção em 11/11; e a sonda de 12/11 diz que a 0270 e a 0271 TAMBÉM estão aplicadas.)** **migration mais nova (hoje: `0276_a_visao_geral_que_buscava_dez_mil_linhas_e_230_chamadas_para_contar.sql`, ver S129; antes dela `0274_o_aging_que_so_existia_no_navegador_e_nunca_conferia_com_o_balanco.sql`, ver S127b; na S127 era a `0271_o_quadro_de_imobilizado_que_a_ia_gravava_como_balanco.sql` (e a `0270_a_linha_que_nao_sabia_de_que_linha_veio.sql`) — ESCRITAS NA P11 (etapa 2.2), NÃO APLICADAS EM PRODUÇÃO. A anterior, `0241_a_descricao_que_o_periodo_irmao_reescrevia.sql`, está APLICADA EM PRODUÇÃO em 11/11/2026, depois da `0240` (nessa ordem, pela API de gerenciamento, a pedido do dono, antes do merge do #291).** Branch `claude/loving-tesla-7eutsq`, PR #291. Onde esta seção e a S126 falarem de migration, vale esta.

### Aplicação em produção (11/11, a pedido do dono)
- **Antes:** 80 mandatos; sonda com 365 itens e 1 ausente (`envio_segredo_no_vault`, que a API não lê); 479 pendências de reconciliação abertas.
- **0240 (1,4 s):** 4 de 4 requisitos presentes.
- **0241 (1,8 s):** 3 de 3 requisitos presentes. Backfill: `corrigidas = 0`, como esperado.
  - O resumo diz `contaminadas = 415, sem_registro_proprio = 415`. Não é dano. Medido: são pendências abertas criadas ANTES de 30/09/2026, quando `reconciliacao.descricao` ainda não existia. O backfill não sabe de onde veio o texto delas, conta e não toca. O rótulo "contaminadas" exagera: o certo seria "sem origem gravada". Nenhuma descrição mudou (0 eventos `descricao_da_pendencia_corrigida`).
- **Depois:** 80 mandatos; sonda só com o mesmo ausente do Vault; 479 pendências de reconciliação abertas.
- Nada de n8n nem de portal a republicar por causa destas duas.


### O que a rodada fez
1. **CI sem apt (`f93d254`).** O DNS do runner não resolvia `*.ubuntu.com` e travava todo PR (#289 e #290 vermelhos antes de qualquer teste). O psql vem da imagem (PostgreSQL 18.6). O pdftotext usa apt com prazo de 120 s e, se falhar, reserva `debian:trixie-slim` via Docker. Provado no CI do próprio PR: o passo levou 2 min 20 s (o apt esgotou e a reserva funcionou) e a suíte n8n deu 786/786.
2. **0240 (pendência 10 da S126).** `fn_versao_atual` segue a versão vigente da 0233; `fn_versao_mais_nova` guarda o corpo antigo. `fn_reconferir_caso` avalia as guardas na versão mais nova: com a vigente, a falha do reenvio sumiria da fila (achado do especialista). `fn_pares_duplicados_do_caso` também passou à vigente (8 de 8 reconciliações).
   - FORA desta fatia: `versoesVigentes` em `portal/src/lib/export.ts`. Pertence à Claude Oria pela divisão do #290 e não foi feito.
3. **0241 (pendência 8 da S126).** A descrição de uma pendência de reconciliação só é reescrita pela rodada do próprio período, da própria chave (regra 3), ou por documento (`secao_fecha`). Backfill `fn_corrigir_descricao_contaminada`, que grava o resumo `sistema:0241` sempre, mesmo com tudo zero.
   - Número de produção: pelo critério antigo (só `periodo_id`) eram 7; pelo critério corrigido são **0**. As 7 mostravam texto legítimo da própria chave (0192/4). O backfill não muda nada em produção hoje.
4. **Pendência 9 da S126 (2 "sem período par" do Canastra).** Não era período: o `27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf` foi classificado como BALANCO, e a própria justificativa da IA diz "não é um balanço completo". A taxonomia não tem tipo para quadro de imobilizado. Diagnóstico sem código; ficha `.claude/conhecimento/fichas/quadro-de-imobilizado-classificado-como-balanco.md`. Criar o tipo muda o `FINGERPRINT_EXTRACAO` e re-extrai todos os documentos: decisão do dono.
5. **Fase 0, sem código ao alcance.** 0.19 espera a D12.3 (cotação do Integra, dono). 0.2 espera o portão da extração (24/11, Claude Oria 2).

### Decisões do dono registradas nesta sessão
- A Claude Oria usa a faixa de migrations **0240 a 0269**. A próxima livre é a **0244** (a 0243 é a P27, ESCRITA E NÃO APLICADA).
- A Fase 3 (conta canônica) pode correr em paralelo à Fase 2 da Claude Oria 2.

### Medido nesta rodada (11/11, banco local `tdf_test`, Postgres 16.15; NÃO é produção)
- `Supabase/test/run.sh`: TODOS OS TESTES PASSARAM. **0240: 16 asserts ok. 0241: 29 asserts ok.**
- `N8N/test/*.test.mjs`: **786 de 786.** Para rodar local foi preciso gerar os 4 books (`Dados de Teste/book-*`) e `npm ci --ignore-scripts` no portal; é o mesmo preparo do CI. Sem ele, 5 testes reprovam por falta de arquivo (medido antes do preparo).
- Portal: os 13 verificadores `tsx` do espelho saem com 0. O portal não foi tocado nesta rodada.
- `Leitor/test`: 65 de 65. `.claude/conhecimento/test` e `.claude/hooks/test`: 14 de 14. `Supabase/test/*.test.mjs`: 40 passam, 0 falham, 4 saltam.
- `conferir-chamadas.mjs`: CHAMADAS OK. `sonda-producao.mjs --so-buraco` no banco local: sem buraco (85 migrations).
- Geradores do n8n regerados: sem diferença em relação ao commitado.
- Taxonomia: 36 tipos e nenhum "composição do imobilizado", conferido no banco local (montado pelas migrations).

### NÃO medido nesta rodada
- **Produção, ANTES da aplicação.** A leitura e a escrita de produção vieram depois do fechamento (ver "Aplicação em produção"). Antes dela, o "0 pendências contaminadas" (`19325ba`, medido em 11/11 antes desta rodada) e as 307 linhas do balanço e a leitura de produção da ficha do imobilizado (feita por quem a escreveu, em 11/11) NÃO foram remedidas aqui.
- **Mutações** ("cada parte desligada reprova"). Os números (0240: 3, 5 e 2; 0241: 2 e 1 no commit `c4f14be`; 29 asserts) vêm das mensagens de commit. Não foram remedidos aqui.
- **Desempenho** da `fn_pares_duplicados_do_caso`: não remedido aqui (está no commit `faa3338`).
- **Achados da P10 da S126 já FECHADOS pelo PR #288 (mergeado, `17176af`), não pela S127:**
  - Canastra `26_Contingencias` (38 → 16) e `29_Extrato_Bancario` (27 → 6) eram a régua, não o dado: os valores são idênticos (12 valores, 78.608; 6 valores, 1.650). A `linha-de-base-extracao.sql` passou a separar `valores_gravados`.
  - A guarda de desalinhamento do Distress `08_Mapa_de_Divida` (92 → 35) passou a aceitar o número provado: medido 53 pares, 0 descartados.
  - O que sobra disso ("Não lido"/"Não conferido" no deck e no export) está no PR #289, ainda aberto.

### O que o dono faz à mão, em ordem
1. ~~Mergear o #291~~ (feito a pedido do dono) e ~~aplicar 0240 e 0241~~ (feito, ver acima).
2. ~~Mergear o #289 e o #290~~ (feitos em 11/11; ingestão republicada depois do #289, FINGERPRINT inalterado). Texto original: Eles NÃO estão no #291. Antes, atualizar cada um com o `main` (o CI deles caiu pelo DNS, que o #291 resolve). O #289 conflita no topo do `ESTADO.md` com esta seção: resolver mantendo as duas. Depois do #289, a Claude Oria 2 republica a ingestão.
3. **Tipo "composição do imobilizado" na taxonomia — autorizado pelo dono "se gerar valor".** Decisão: NÃO criar isolado agora. Criar o tipo muda o prompt de classificação, logo o `FINGERPRINT_EXTRACAO`, e o próximo envio de cada mandato re-extrai e paga TODOS os documentos. A P11 (Claude Oria 2, Fase 2) também vai mudar o prompt. Feito em separado, seriam duas re-extrações pagas; junto, uma. **Entregar à Claude Oria 2 para entrar na mesma mudança de prompt da P11:** seed do tipo na `taxonomia_tipo_documento` (migration da faixa dela) + o tipo no `SYSTEM_PROMPT`. Ver a ficha `quadro-de-imobilizado-classificado-como-balanco`.
4. Já constavam: reenviar os originais reais (P10); trocar a senha colada no chat em 11/11; clicar "Reprocessar" no navegador.

### Próxima sessão da Claude Oria
Fase 3, etapa 3.1 (**P26**, catálogo `conta_canonica` com hierarquia, natureza e seção, semeado da taxonomia atual), com a primeira migration da faixa livre: **0242**. Conforme `Arquitetura do Sistema/3 Estado e Execução/PLANO_DE_EXECUCAO_2026-11.md` §3, semana 6. O status por etapa (`STATUS_POR_ETAPA_2026-11-11.md`) vem com o #290 e não está nesta branch.

## SESSÃO 126 (10–11/11/2026) — P7b, P8 e P9 NO AR (PR #287 mergeado, 0232–0234 aplicadas, n8n republicado, portal publicado); P10 rodada nos sintéticos

### ▶ PRÓXIMOS PASSOS — lista única e ordenada (atualizada em 11/11, fim da sessão 126)

**A fechar primeiro (já em andamento):**
1. ~~FEITO em 11/11 (S127, a pedido do dono): #289 mergeado (`3727c42`) e ingestão REPUBLICADA do `main` (`768c112`) com `N8N/republicar.sh`: ensaio, publicação, 63/63 nós conferidos, ativo; `Juntar Blocos` com `versao_medicao 'p4-3'` e `textos_perdidos`; FINGERPRINT inalterado (`70de46f4c67573af`), nada re-extrai.~~ **PR [#289](https://github.com/rodrigovaroto-wq/Oria-Digital/pull/289)** (o deck e o export deixam de afirmar "o mapa não imprime vencimento" quando o texto não foi lido): conferir o CI verde no head e mergear. Depois, republicar a ingestão com `N8N/republicar.sh`, primeiro `--dry-run` e depois a publicação, a partir do `main`. Conferir que o `Juntar Blocos` publicado grava `versao_medicao: 'p4-3'` e `textos_perdidos`. No commit `73d9b4f`, `banco`, `e2e` e `variacoes` caíram por DNS do runner do GitHub ("Temporary failure resolving archive.ubuntu.com"), antes de qualquer teste. Não era falha do PR.

**Dependem do dono:**
2. **Corpus real da P10** (Valtra, Krauspenhar, AMO): os originais não estão no bucket (AMO 0 de 118, Valtra 2 de 15, Krauspenhar 1 de 7). Reenviar os arquivos e rodar a P10 de novo, medindo com `Supabase/test/linha-de-base-extracao.sql` (ler `valores_gravados`, não `linhas_gravadas`).
3. **Trocar a senha** que o dono colou no chat em 11/11. Ela não foi usada pela sessão.
4. **Testar no navegador o botão "Reprocessar"** (aba Documentos → "Fila de reprocesso") com usuário logado. A rota está no ar, mas nunca foi clicada por uma pessoa.

**Sem fatia ainda (achados registrados):**
5. **Ramo novo do Mapa de Dívida (texto desalinhado com número provado):** provado só offline, na resposta real da execução 9637. Ao vivo, na 9641, o modelo devolveu os textos alinhados e o ramo não disparou. Provar quando um documento real o acionar.
6. **Piraquara 08 (Distress sintético) já gravado:** com o #289 no ar, os 6 contratos aparecem como "Não conferido". Para corrigir, re-extrair: o reenvio do mesmo arquivo é reaproveitado, então precisa mudar o arquivo ou o fingerprint.
7. **Contratos com texto perdido ficam sem credor, vencimento e taxa:** agora isso é dito, mas o dado não volta. A recuperação exigiria a IA devolver o credor como coluna e não só no rótulo (ajuste de prompt muda o FINGERPRINT e re-extrai tudo: decisão do dono).
8. ~~RESOLVIDO na S127 (0241, aplicada)~~ **`fn_registrar_reconciliacao` reescreve a descrição de uma pendência aberta com a de outro período** que tenha interseção de anos (achado na 0234). No Valtra, a pendência do período "data-base 01/01/2026 - 30/06/2026" mostra "2024: …", vinda do Faturamento "24,26".
9. ~~DIAGNOSTICADO na S127~~ **2 "sem período par" do Canastra sintético:** quadro de imobilizado classificado como BALANCO; o tipo vai junto da P11 (ver S127).
10. ~~RESOLVIDO na S127 (0240, aplicada)~~ **`fn_versao_atual`** (usada pelas reconciliações) não segue a regra de versão vigente da 0233, ao contrário da Modelagem e do export. Inofensivo até o n8n gravar `falha_transitoria_esgotada = true`.
11. **Do plano:** P11 a P15 (semana 3, "nenhuma linha faltando, nenhuma inventada"), em `PLANO_DE_EXECUCAO_2026-11.md`.


> **(Superado pela S127, acima: a 0240 e a 0241 foram APLICADAS em produção em 11/11/2026.)** Na S126, a última aplicada era a `0234_o_periodo_que_o_documento_tinha_e_a_checagem_nao_lia.sql` — APLICADA EM PRODUÇÃO em 11/11/2026, junto com a 0232 e a 0233 (nessa ordem, pela API de gerenciamento, antes do merge).
> - Branch `claude/confident-bardeen-15mjip`. Nada mergeado no `main`, nada republicado no n8n, nada publicado no portal, P10 não rodou.
> - Acesso a produção conferido nesta sessão: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_URL`, `N8N_BASE_URL`, `N8N_API_KEY`, `VERCEL_TOKEN` estão no ambiente (só os nomes foram lidos). Leitura de produção feita pela API de gerenciamento (`POST https://api.supabase.com/v1/projects/<ref>/database/query`, `read_only:true`; o ref sai de `SUPABASE_URL`). O MCP do Supabase (notebooks) recusa permissão.

### Publicação (11/11, depois da retomada) — o estado vigente

- **Migrations aplicadas em produção, na ordem 0232 → 0233 → 0234**, antes do merge (a fila tem de existir antes do portal):
  - Sonda antes: 349 itens, 1 ausente. O ausente é o conhecido `envio_segredo_no_vault`: a API não lê o Vault, o segredo não está faltando. 80 mandatos.
  - Depois: os 4 + 4 + 8 requisitos das três migrations presentes, 1 ausente (o mesmo), 80 mandatos.
- **0234 em produção (45 s):**
  - Backfill `sistema:0234` resolveu **38** pendências (esperado 38).
  - `periodo_incorreto` abertas: **57 → 19**.
  - "sem período par" abertas: **8 → 3**. Ficam as 2 do Canastra sintético, de outra causa, e a do S105.
  - Nenhuma pendência nova aberta.
  - Fw Valtra: `ativo_passivo_pl` anual 2023, 2024 e 2025 passaram de "sem período par" para **ok**. O balanço fecha, medido.
- **PR #287 mergeado** (`42e03c6`), CI todo verde no head (`89e20b9`), Sonar verde. Desassinado.
- **Ingestão republicada** do `main` com `N8N/republicar.sh`: ensaio e depois publicação; 63 de 63 nós batem; ativo; sem estágio de reserva. FINGERPRINT inalterado (`70de46f4c67573af`), então nada já lido re-extrai por causa disto.
- **Portal publicado** (Vercel produção READY no `42e03c6`). A rota nova responde 401 sem sessão.
- NÃO conferido no navegador: o bloco "Fila de reprocesso" e o botão com sessão de usuário, porque não há login de teste nesta sessão.

### Correções dos achados da P10 (11/11) — PR #288 mergeado (`17176af`), ingestão republicada (63/63, fingerprint inalterado)

- **"Perda silenciosa" do Canastra era da régua, não do dado.** Contingências 38→16 e Extrato 27→6 eram só pares de texto puro: o modelo juntou Natureza/Prognóstico e Agência/Conta ao rótulo. Os valores são idênticos (12 valores, 78.608; 6 valores, 1.650). `linha-de-base-extracao.sql` passa a separar `valores_gravados` de `textos_gravados`; regressão de dado se lê em `valores_gravados`.
- **Mapa de Dívida (Distress): o número provado não é mais descartado por texto desalinhado.**
  - `achatarGrupos` aceita a conta só com prova dupla: os valores numéricos de `vt` e de `vn` batem em ordem, e o padrão de tipos de `vt` é subsequência do de `vn`.
  - O texto que não dá para reatribuir vira pendência ("números mantidos, TEXTOS sem coluna"), nunca silêncio. O deck lê credor, vencimento e taxa do texto.
  - Medido na resposta REAL da execução 9637, rodada offline com o código novo: 53 pares (eram 35), 0 descartados, 6 com pendência de texto.
- **Livro Razão (Canastra):** a coluna "Saldo" só se cala quando a soma não fecha E o total é igual ao último valor da série. "Saldo" aditivo continua conferido.
- Três rodadas de revisão independente; a última sem ALTO.
- **NÃO provado ao vivo:** reprocessar os dois documentos nos mandatos originais seria reaproveitado (o fingerprint não mudou e eles têm linha). A prova exige um mandato de teste novo. A criação dele em produção foi BLOQUEADA pelo controle de segurança da sessão ("Modify Shared Resources"), e a sessão não contornou. Caminhos: o dono libera a criação de um mandato de teste (apagado depois) ou cria um mandato e reenvia os dois PDFs (`Dados de Teste/book-distress` 08 e `book-canastra` 17).
- **Em aberto:** os 6 contratos do Piraquara, quando relidos, ficam com `valor_texto` nulo e pendência declarada; o export mostra a célula em branco (MÉDIO 2 da revisão, sem fatia).

### P10 — RODADA nos sintéticos (11/11, decisão do dono: reais depois)

- **Como foi rodada.** Leitura da chave de serviço e do segredo do envio liberada pelo dono. Os 66 originais dos 3 mandatos "P4 linha de base" foram baixados do bucket e reenviados ao Form do n8n em 3 lotes, um por mandato, com token assinado por `assinarEnvio` (o mesmo código do portal) em nome do Sócio de teste. Os segredos ficaram só em arquivos temporários, apagados no fim. O fingerprint mudou desde 09/11, então cada documento virou versão nova do MESMO documento.
- **Custo total: US$ 0,28** (Vertentes 0,0595; Canastra 0,1707; Distress 0,0515), muito abaixo do teto D6.

| Mandato (execução) | Docs com falha antes → depois | Linhas extraídas antes → depois | Cobertura antes → depois |
|---|---|---|---|
| Vertentes (9496 → 9634) | 1 → **0** | 914 → **1.109** | 92,7% → **99,8%** |
| Canastra (9505 → 9635) | 1 → 3 | 800 → **2.865** (o lote anterior tinha 18 docs, este 38) | 92,3% → 97,9% |
| Distress (9506 → 9637) | 2 → 2 | 935 → 849 | 100,7% → 97,1% |

Por documento (`Supabase/test/linha-de-base-extracao.sql`, padrão `P4 %`; a foto "antes" e a "depois" estão no scratchpad da sessão, `p10-antes.json` e `p10-depois.json`):

- **Ganhos:**
  - Vertentes `06_BP_COMBINADO`: de **0 para 185** pares; a falha aberta fechou.
  - Canastra `17_Livro_Razao`: 409 → 604.
  - Distress `04_BP_Montagens`: 126 → 94. Provável melhora: a leitura antiga tinha 11 subtotais repetidos, e 32 linhas × 3 colunas dá 96.
- **Regressão COM pendência:** Distress `08_Mapa_de_Divida`, 92 → 35 pares, 6 contas descartadas por desalinhamento.
  - Causa: cada contrato veio com 10 colunas declaradas, 10 números e 9 textos. `achatarGrupos` (`N8N/lib/extract.mjs` ~l.500) descarta a conta inteira quando `vt.length` ≠ colunas, mesmo com os 10 números alinhados.
  - A guarda é antiga. Na leitura de 09/11 o modelo devolveu alinhado.
  - Fatia proposta: com `vn` alinhado e só `vt` desalinhado, aceitar os números e descartar só os textos, declarando o descarte. É decisão de desenho da guarda: rever com o dono.
- **REGRESSÃO SILENCIOSA, sem pendência (regra 7, a pior):**
  - Canastra `26_Contingencias_e_Processos_Judiciais`: 38 → **16** pares.
  - Canastra `29_Extrato_Bancario_Consolidado`: 27 → **6** pares.
  - Nenhuma falha e nenhuma pendência nas duas. A régua de cobertura não reclamou. **Investigar primeiro na próxima sessão**: ler as duas respostas da IA nas execuções 9505 e 9635 e a régua desses documentos.
- **Falhas novas do Canastra:** 2 contas descartadas por desalinhamento (`01_Balanco`, `22_Aging`) e a série do `17_Livro_Razao`. Esta última soma a coluna "Saldo", que num razão é saldo acumulado, então é provável alarme falso da guarda de série.
- Nenhum documento terminou com `falha_transitoria_esgotada = true` nesta rodada. A P8 foi exercitada sem disparo.
- NÃO rodado: o corpus real (Valtra, Krauspenhar, AMO), que precisa dos arquivos originais reenviados pelo dono; e o Espelho, cujo mandato não existe mais.

### Atualização de 11/11 (retomada) — vale por cima do que está abaixo

- **Decisão do dono (11/11): NÃO há modelo de reserva.** Só o `gpt-5.6-luna`. O fallback para `gpt-4o` de `d4b38b5` foi desfeito em `5243b15`. Fica o registro por tentativa e `falha_transitoria_esgotada` (as 4 tentativas do modelo único esgotadas), que a 0233 lê. O risco do TPM do `gpt-4o` deixou de existir. A republicação tem de produzir um `Juntar Tentativas` com 4 entradas, sem "Esperar Retry 4" nem "tentativa 5".
- **Revisão independente da 0233 e 0234 FEITA**: 2 ALTO, 2 MÉDIO e 1 BAIXO, corrigidos em `373995e`.
  - 0233: a versão vigente prefere a de maior número sem a flag; se todas têm a flag, a de mais linhas.
  - 0234: a contenção não vale com lado parcial; documento parcial volta ao sentinela; a abertura ano−1 só vale em BALANCO/BALANCETE ou em documento sem Débito/Crédito.
  - Números novos: a 0234 alcança 4 das 8 "sem período par" (as anuais do Valtra), e o backfill fecha **32 + 6 = 38** `periodo_incorreto` (era 35 a 41).
- **Em andamento ao escrever:** o export do portal (`versoesVigentes` em `export.ts`) seguir a mesma regra de versão vigente da 0233. Sem isso, o Excel mostraria a v2 parcial enquanto a Modelagem mostra a v1. Ainda declarado, sem correção: `fn_versao_atual`, usada pelas reconciliações, não segue a regra.
- **PR [#287](https://github.com/rodrigovaroto-wq/Oria-Digital/pull/287) aberto em RASCUNHO e assinado.** CI do `d34cae7` verde depois de corrigir o import `@/` que o `tsx` da raiz não resolvia. Sonar passou.
- **P10, preparação medida (11/11, só leitura):**
  - Foto "antes" do corpus tirada com `Supabase/test/linha-de-base-extracao.sql` (padrões Fw Valtra, KRAUSPENHAR, AMO teste 00, P4). Resumo: AMO 118 docs (14 falhas abertas, 6 incompletos), Valtra 15 (6 falhas, 2 incompletos, pior cobertura 55%), Krauspenhar 7 (5 falhas, 5 incompletos, 39 descartadas, pior 45%). Rodar de novo a mesma consulta depois da P10 para a tabela antes × depois.
  - **Bloqueio da P10 com dado real:** quase nenhum original do corpus real está no bucket. AMO tem 0 de 118, Valtra 2 de 15, Krauspenhar 1 de 7. Os sintéticos da P4 têm todos (Canastra 38, Distress 14, Vertentes 14), e o book do Espelho está no repositório (o mandato não existe mais em produção). Para a P10 cobrir o corpus real, o dono precisa reenviar os arquivos reais. Sem isso, ela roda só sobre os sintéticos mais os 3 reais com original.

### Ordem para retomar (nesta ordem)

1. **Revisão independente da 0233 e da 0234 — INTERROMPIDA no meio** (o revisor foi parado sem relatório). Rodar de novo o `revisor-defeito-silencioso` sobre o commit "0233 + 0234" (ver abaixo), com estes riscos já listados para ele olhar: (a) 0233: reenvio em laço / versão nova que falha de novo; coerência com `fn_registrar_documento` (procura QUALQUER versão com mesmo hash+fingerprint concluída) e com a fila da 0232; o corpo partiu da 0231 — conferir que nada da 0231 se perdeu. (b) 0234: TODOS os chamadores de `fn_coluna_periodo_do_ano` e de `fn_periodos_equivalentes` (a regra nova de equivalência vale em todo lugar que usa a função, não só no diagnóstico: reaproveitamento de pendência de reconciliação por período, desempate, fusão); a regra "mesmo ano mais recente + contenção + união contígua" esconder divergência verdadeira; DRE "Saldo anterior" (resultado do ano anterior) tratado como abertura de balanço; backfill reaberto pelo diagnóstico seguinte; backfill tocar decisão humana.
2. Corrigir o que a revisão achar; `run.sh` oficial verde; comitar a correção.
3. **Abrir o PR** da branch para o `main` (ainda NÃO aberto). Assinar, esperar CI e Sonar verdes, desassinar (CLAUDE.md, "Acompanhar PR"). **O merge é do dono.**
4. Depois do merge, **aplicar em produção, nesta ordem: 0232, 0233, 0234** (como `postgres`; a 0234 reconcilia 3 mandatos e pode estourar o tempo do SQL Editor: usar a API de gerenciamento ou psql). Antes de cada uma: sonda e contagem de mandatos; depois: `select chave, presente, detalhe from fn_instalacao_conferir() where not presente;` vazio. Conferir na 0234: `count(*) from pendencia where resolvida_por = 'sistema:0234'` (esperado 35 a 41) e as "sem período par" abertas (8 antes; esperado cair para 2 — as do Canastra sintético têm outra causa).
5. **A 0232 tem de estar no banco ANTES do deploy do portal**: sem ela a aba Documentos mostra "Não foi possível ler a fila" em TODO mandato.
6. **Republicar a ingestão** a partir do `main` atualizado (`N8N/republicar.sh`, que usa `preparar-republicacao.mjs` e `conferir-publicado.mjs`; nunca `PUT` direto). No editor, conferir: `Juntar Tentativas` com 5 entradas; `IA Extrair (tentativa 5)` com `onError: continueRegularOutput`, `retryOnFail`, a credencial OpenAI e `neverError`/batching iguais aos outros estágios.
7. **Risco não provado da P8, conferir antes da P10:** o limite de TPM do `gpt-4o` na conta OpenAI. Os 500 mil TPM declarados são do `gpt-5.6-luna`; se o 4o estiver no Tier 1 (30 mil TPM), a chamada de reserva (~20 mil de entrada + 16 mil de saída reservados) toma 429 sempre. Também não provado: que o `gpt-4o` aceita o `extractionSchema` em modo strict.
8. Deploy do portal (depois da 0232) e prova no navegador: aba Documentos de um mandato com falha aberta → "Fila de reprocesso" → Reprocessar → acompanhamento até "lido". Em produção só 11 documentos têm o original no bucket.
9. **P10** (autorizada, D6: teto US$ 5 por book; o código usa `TETO_EXECUCAO_USD` = US$ 3 por execução): rodada de regressão paga sobre o corpus da P4 (Valtra, Krauspenhar, AMO + sintéticos Canastra, Distress, Espelho, Vertentes), comparar com a tabela da P4 (`Supabase/test/linha-de-base-extracao.sql`) documento a documento. Medir também quantas segundas passadas foram pagas (pendência da S125) e quantos documentos usaram a reserva (`resumo` em `lote_execucao`: `documentos_com_reserva`).

### O que foi feito (comitado e enviado na branch)

**P7b — fila de reprocesso com botão (`ff603ba`, `43aa2cf`).**
- Medido em produção antes (10/11, só leitura): 517 documentos com `extracao_falhou` aberta; os 517 têm `arquivo_ref`, mas só **11** têm o objeto no bucket `documentos` (defeito jul–out/2026); 70 têm linha gravada.
- `0232_a_fila_de_reprocesso_que_o_portal_nao_tinha.sql`: `fn_fila_de_reprocesso(caso)` (SECURITY INVOKER; motivo `sem_original` ou `reaproveitaria`, no MESMO predicado de `fn_registrar_documento`: qualquer versão do caso com mesmo hash, fingerprint vigente e concluída). Teste `fila_de_reprocesso.test.sql`, 43 asserts; voltar para "só a versão mais nova" reprova 5.
- Portal: bloco "Fila de reprocesso" na aba Documentos (`components/fila-de-reprocesso.tsx`); `POST /api/casos/[id]/reprocessar` (papel → token → baixa o original com o cliente do usuário → Form do n8n; corta pelo orçamento do lote de `N8N/lib/custo.mjs`; recusa "já está em leitura" por 32,5 min); `GET /api/casos/[id]/reprocessar/status` acompanha POR DOCUMENTO (só "lido" com versão nova E evento `extracao_sombra`; recusa do n8n mostra a mensagem dele e "Nada foi lido"). Suíte `portal/scripts/verificar-fila-de-reprocesso.mts`, 34 asserts (no CI e em `.claude/COMANDOS-CANONICOS.md`).
- Revisão independente: 2 ALTO (a fila olhava só a versão mais nova; o status contava `documento.criado_em` e nunca via o reprocesso) e 3 MÉDIO, corrigidos antes do commit.
- Limites declarados: falha de OUTRO envio no mesmo mandato depois de `desde` pode aparecer como recusa se nada deste pedido foi lido; `rejeitada` conta como aberta (mesmo predicado de `fn_versao_extracao_concluida`).

**P8 no n8n — reserva `gpt-4o` e registro por tentativa (`d4b38b5`).**
- Decisão do dono (10/11): o alternativo é OUTRO MODELO DA OPENAI (não Gemini). Escolha da sessão: `gpt-4o` (~12,5× o Luna por token).
- 4 tentativas no principal (30/60/60 s) + 1 na reserva após 60 s; permanente não cai na reserva, exceto 404 do modelo. Em reserva não há segunda passada por cobertura.
- Defeito silencioso achado e corrigido: o Parse cobrava SEMPRE pelo preço do principal.
- Medição `p4-2`: `modelos_usados`, `usou_reserva`, `reserva_por_modelo_indisponivel`, `falha_transitoria_esgotada` (contrato lido pela 0233), `registro_tentativas`. Resumo de Custo conta reserva e 404 do principal.
- FINGERPRINT inalterado (`70de46f4c67573af`). N8N 800/800 no commit. Revisão independente: 2 ALTO, 2 MÉDIO, 1 BAIXO, corrigidos.
- Teto declarado: o orçamento do lote não conhece a reserva (pior caso ~12,5× a estimativa).

**P9 no n8n — "Método Indireto/Direto" (`0874934`).** O DFC do Valtra registrava a entidade "Metodo Indireto Moto Agricola" (2 `entidade_incorreta` abertas). Corrigido em `parseEntidade`. Sobre 597 nomes de arquivo, mudam só os 3 de DFC com método. N8N 802/802. Vale para envios novos; a Moto Agricola já registrada continua com as 2 pendências.

### Comitado SEM revisão independente (a revisão foi interrompida)

**0233 (P8, banco) — `0233_a_falha_transitoria_com_linha_que_o_reenvio_nao_relia.sql`.** `fn_versao_extracao_concluida` vira false, mesmo com linha, quando o último `extracao_sombra` traz `medicao.falha_transitoria_esgotada = true` (booleano), há `extracao_falhou` aberta e nenhuma linha teve aceite humano (`aceito_por` não `sistema:%`). Reemitida a partir do corpo da 0231. Produção (10/11): 2.064 eventos, nenhum com o campo, alcance hoje 0; 535 falhas abertas, 77 com linha, 4 delas com aceite humano. Teste `reextracao_transitoria.test.sql`, 23 asserts; sem a condição do campo reprovam 7. **Armadilha:** `o_balanco_sem_dado_financeiro.test.sql` reaplica a 0231 no meio da suíte; o teste da 0233 começa com `\i` da 0233 para restaurar.

**0234 (P9, banco) — `0234_o_periodo_que_o_documento_tinha_e_a_checagem_nao_lia.sql`.**
- Medido em produção (10/11), pendências abertas: `entidade_incorreta` 80, `periodo_incorreto` 57, `precondicao_nao_satisfeita` 347 (8 com "sem período par").
- (A) "sem período par": o balanço/DRE anual do Valtra tem colunas "Saldo Final/Inicial" e "Saldo atual/anterior", sem ano; `fn_coluna_periodo_do_ano` (0023) só casava ano no texto. Agora cai para fechamento = ano da referência e abertura = ano − 1 (não parcial), com as funções da 0201. Alcance simulado: 6 das 8 (Valtra 5, S105 1); as 2 do Canastra sintético têm outra causa, não diagnosticada.
- (B) `periodo_incorreto` falso: `fn_periodos_equivalentes` ganhou "mesmo ano mais recente + contenção + união contígua". Simulado sobre as 57 abertas: 35 caem, mais 6 que já eram equivalentes e estavam abertas; 16 verdadeiras continuam. Limite: "multi 32M26" × "multi 24,26" segue aberta.
- Backfill `fn_resolver_periodo_incorreto_falso` (só `aberta` + `origem_estagio='diagnostico'`, `resolvida_por='sistema:0234'`) e reconciliação dos mandatos com "sem período par".
- Teste `o_periodo_que_a_checagem_nao_lia.test.sql`, 40 asserts (funções antigas de volta reprovam 19). `canonico.test.sql`: o fixture "multi 22,23,24" × "anual 2024" virou equivalente pela regra nova e foi trocado por "anual 2025" × 2024.
- Defeito ACHADO e NÃO corrigido: `fn_registrar_reconciliacao` reaproveita a pendência aberta por interseção de anos e reescreve a descrição com a da última checagem (Valtra: a pendência do período "data-base 01/01/2026 - 30/06/2026" mostra "2024: …", vinda do Faturamento "24,26").
- Fora de escopo, declarado: `entidade_incorreta` por leitura errada da IA ("ARAUGÁRIA" × "ARAUCÁRIA", "OMNIBEAUTY ... DE CONSOLIDADO") é da P13; a pendência de entidade da Moto Agricola já registrada.
- Suítes no fim: `run.sh` rc=0 (3.376 ok), `Supabase/test/*.test.mjs` 40 pass / 0 fail, `conferir-chamadas` OK, sonda `--so-buraco` sem buraco.

### Medido em produção nesta sessão e ainda sem fatia
- Das 517 falhas abertas: 72 trazem "ESGOTADO" (transitória esgotada) e nenhuma tem linha; 15 são transitórias sem a marca (14 do Vertentes antigo, "Resposta da OpenAI sem conteudo"; 1 com linha: "DRE MOTO AGRICOLA 2023.pdf", bloco 4, 798 pares, de fingerprint antigo, então qualquer reenvio já re-extrai).
- `entidade_incorreta` "Comparativo Araucaria …", "Relatorio …", "Liquido …" e o "01_" do prefixo são de rodadas antigas: o classificador atual já acerta. Ficam abertas até o diagnóstico rodar de novo nesses mandatos de teste.

## SESSÃO 125 (10/11/2026) — P6b provada ao vivo; PR #282 no ar; balancete com "colunas trocadas" falsa corrigido (`d14ef83`, ainda não republicado)

> **Última migration DAQUELA sessão: continua `0231_o_balanco_sem_dado_financeiro_que_ninguem_via.sql`.** Nenhuma migration nova nesta sessão. A fatia `d14ef83` mexe só em `N8N/lib/aritmetica.mjs`, nos seus testes e no JSON gerado da ingestão.
> - Sonda `fn_instalacao_conferir` depois do teste: 0 ausentes; 80 mandatos antes e depois.
> - NÃO conferido nesta rodada: CI da branch `claude/practical-ptolemy-fqvf9e`.

**O que está em produção (conferido em 10/11):**
- **PR #282 mergeado** em `b729715`.
- **Ingestão republicada em 10/11, 12:02 UTC**, a partir de `b729715`, com `N8N/republicar.sh`: `conferir-publicado` 63 de 63 nós batem.
- Antes da republicação divergiam 5 nós: Orçamento do Lote, Recompor Conteúdo Extraído, Medir Documento, Fatiar Extração e Juntar Blocos. A P6b não estava no ar.

**P6b provada AO VIVO (10/11, 17:12–17:15 UTC):**
- Mandato de teste "S125 — P6b números colados (teste, apagar)", caso `cc498e8d-7b28-4b81-af7b-659367046105`, execução n8n 9601.
- Rota `ocr`, motivo `numeros-colados`.
- Descartadas por desalinhamento: 303 → 0.
- Pares gravados: 1.516 → 2.008.
- Custo: US$ 0,191 → US$ 0,2534.
- Mandato apagado em seguida como Sócio de teste: 1 original removido do Storage, evento `caso_excluido`, `fn_excluir_caso` (1 documento, 16 pendências, 2.008 campos).
- 80 mandatos antes e depois. Sonda `fn_instalacao_conferir`: 0 ausentes.
- A senha do Sócio de teste foi redefinida, com autorização do dono, e está só no scratchpad da sessão.

**Defeito achado, SEM fatia (decisão do dono pendente):**
- `FINGERPRINT_EXTRACAO` (`N8N/build-workflow.mjs`, ~linha 182) cobre só prompt, modelo e esquema. A P6b muda a rota (texto → imagem) e não muda o fingerprint, que continua `ff16b69dc9f1ad42`.
- Efeito: reenviar o balancete ao KRAUSPENHAR (`33b58a89-0d77-417a-8859-e193c61e8db8`) seria pulado por `fn_versao_extracao_concluida`, porque a versão `9e13f05e` já tem linhas. Correção de rota nunca chega a documento já lido.
- O Krauspenhar real segue com 1.516 pares e 303 descartadas.
- Corrigir o fingerprint faz o próximo envio de TODO mandato re-extrair e pagar de novo.

**Fatia feita (`d14ef83`, NÃO republicada):**
- A conferência aritmética do balancete (`classificarContasDeBalancete`, `N8N/lib/aritmetica.mjs`) abria "colunas trocadas" falsa.
- Causa: o PDF imprime o crédito negativo. Coluna devedora: SAt = SA + D + C (157 de 157 do ativo). Coluna credora: SAt = SA − D − C (284 de 289 do resto).
- Nos 2.008 pares reais: 207 / 194 / 74 contas com 1 pendência → 475 / 0 / 0 sem pendência (contagem por grupo, como medida).
- Regra 2: 2 testes novos reprovam sem o ramo; 1 reprova com o gate sempre aberto.
- Suíte n8n 766/0, com os 4 books gerados. FINGERPRINT inalterado.
- Revisão independente: 0 ALTO, 3 MÉDIO. Dois eram de comentário e foram corrigidos no mesmo commit. O terceiro exige republicar.
- Enquanto não republicar, a pendência falsa segue nascendo em produção.

**Medido, sem fatia: a régua de cobertura do balancete colado está errada**
- "82% (502 de 610)" e os 7 de 11 blocos "<85%" do mesmo documento são FALSOS.
- As 610 linhas da régua: 108 de cabeçalho e rodapé de página (9 por página × 12), 42 nomes de conta soltos (o texto colado põe o nome e os números em linhas separadas) e 460 linhas reais.
- A leitura devolveu 502, mais que as 460 reais. Efeito: 7 segundas passadas pagas à toa e uma pendência de cobertura falsa.
- Das 502, 50 linhas são idênticas a outra (mesma chave, página e valores). Parte é legítima (sintética com uma analítica só, ex.: ADIANTAMENTO A FORNECEDORES). Parte é provável duplicata da IA. Separar exige o código da conta e a coordenada da linha (P11/P12).
- A "régua exata 20/20" da S124 foi medida na rota de texto. Neste layout colado ela não vale.

**MAPA_DE_EXECUCAO.md:** não lista P6b como pendente. Não foi alterado.

**2ª parte (10/11): PR #283 mergeado (`034ff52`); o dono decidiu os passos 2 e 3, feitos na branch:**
- **Fingerprint com a rota** (`66e7fa1`): `N8N/lib/rota-pdf.mjs` é a lista única da rota, embutida no nó e 4ª parte do hash. `ff16b69dc9f1ad42` → `70de46f4c67573af`. A régua fica fora de propósito. Custo aceito pelo dono: o próximo envio de cada mandato re-extrai e paga todo documento.
- **Régua** (`72b95a4`, `200c002`, `ab048c2`, `ffcf42d`): no texto real da 9601, 610 → 475 (460 contas + 12 "Filial 0" + 2 contratos + 1 CPF; erra para cima). A 1ª versão contava para BAIXO em livro em milhares (DRE 10→3, aging 6→0); três passadas de revisão independente, a última sem ALTO. Régua de produção 20/20 e 87 textos de books e capturas sem mudança. N8N 778/0. Não fechado, declarado: "Receita 450 mil" depois de linha só de números conta 1 em vez de 2.
- **NÃO republicado:** a correção do alarme "colunas trocadas" (d14ef83), o fingerprint e a régua só entram no ar com a republicação, que pede autorização do dono. Depois dela, reenviar o balancete ao KRAUSPENHAR real e medir: régua ≈ 475, 0 descartadas, ~2.008 pares, sem "colunas trocadas".

**3ª parte (10/11, 18:33 UTC): #284 mergeado (`d6c176b`), ingestão republicada (63/63, fingerprint `70de46f4c67573af` no ar), balancete reenviado ao KRAUSPENHAR real (execução 9605):**

| Medida | Versão 2 (rota velha) | Versão 3 (hoje) |
|---|---|---|
| Rota | texto | imagem, `numeros-colados` |
| Descartadas por desalinhamento | 303 | 0 no resultado final (1 numa tentativa de bloco, "LUCROS DIST. JOAO HATMANN") |
| Pares gravados | 1.516 | 1.880 (470 linhas) |
| Régua / lidas | 610 / 379 | 475 / 470 — cobertura 98,95% |
| Falha do documento | `extracao_falhou` | nenhuma (`falha_motivo` nulo, 0 documentos com falha) |
| Conferência do balancete | — | rotulada 444, trocada 0, nenhuma 1: sem pendência "colunas trocadas" |
| Custo | US$ 0,187 | US$ 0,2165 |

- O reenvio foi re-extraído porque o fingerprint mudou: a prova de que correção de rota agora chega a documento já lido.
- Linhas idênticas: 21 (eram 50 no teste da 9601). Separar repetição legítima de duplicata segue na P11/P12.
- NÃO conferido: quantas segundas passadas foram pagas (o nó da tentativa 2 recebeu 6 itens).
- Pendências antigas que seguem abertas, sem relação com esta rodada: `divergencia_reconciliacao` (secao_fecha e conflito_entre_documentos) e `tipo_incorreto`.

**Próxima sessão:** seguir o plano: P7b, P8, P9, P10. P11/P12 continuam no plano.

## SESSÃO 124 (09–10/11/2026) — 0231 aplicada; régua e abas do .xlsx no ar e provadas ao vivo; P6 provada no Valtra real; P6b (Krauspenhar) no PR #282

> **Última migration DAQUELA sessão: `0231_o_balanco_sem_dado_financeiro_que_ninguem_via.sql` — APLICADA EM PRODUÇÃO em 10/11/2026.**
> - Ensaio em transação revertida antes: sonda 349, 0 ausentes, backfill 42, 82 mandatos.
> - Depois de aplicar: sonda 349 itens, 0 ausentes, os 7 requisitos da 0231 presentes; 42 pendências abertas pelo backfill; 82 mandatos antes e depois. O portal (`912ae59`) foi publicado ANTES.
> - NÃO conferido: md5 do corpo das funções de produção contra o banco montado do repositório (o Postgres local caiu no meio).
> - Corrige: zero linha + `tem_dado_financeiro = false` em tipo NÃO societário fechava sem linha e sem pendência. Passa a abrir `extracao_falhou`.
> - Alcance medido em produção (09/11): 42 documentos (os 41 do ALTO da S123 + 1 do lote S124). Em mandatos reais: AMOBELEZA 10, Krauspenhar 1, AMO teste 00 2.
> - Backfill não reabre decisão humana (medido: 0 dos 42).

**O que está em produção (conferido em 09/11):**
- **#278 mergeado** em `264605e` (CI 8/8 verde antes). **#276 fechado sem merge**: o #278 o continha (o HEAD do #276 era ancestral).
- **Ingestão republicada em 09/11, 21:39 UTC**, do `main` de `264605e`. `preparar-republicacao` + `conferir-publicado`: 60 nós batem (antes divergiam 2: Juntar Blocos e Gravar Campos (Sombra), a metade n8n da 0229). `multipleFiles` ligado; path do form e errorWorkflow preservados.
- **Medição por documento voltou:** 11 de 11 eventos `extracao_sombra` novos levam `medicao` (em 09/11 antes da republicação: 0 de 5).
- **Sonda de produção:** 342 itens, 0 ausentes. Migration aplicada mais nova: 0230.
- **Mandato de teste criado em produção:** "S124 — Espelho (sintético, medição)" (caso `10d371c2-7266-4d6a-ac11-cd001452a59d`), 11 documentos, 2 lotes: US$ 0,4596 (3 docs; DRE e balancete de 16 blocos custaram US$ 0,217 e 0,208) + US$ 0,1217 (8 docs). A senha do Sócio de teste foi redefinida e está só no scratchpad da sessão.

**No ar desde 10/11 (PR #279 mergeado em `912ae59`, CI 8/8 e Sonar verdes):** o portal, a 0231 e a ingestão republicada (`conferir-publicado`: 63 nós batem; `multipleFiles`, path do form e errorWorkflow preservados).

**Provado AO VIVO em 10/11** (mandato "S124 — Planilhas de várias abas (sintético)", caso `2a0a2116-45cc-43be-89d4-7e29dd6497bd`, execução 9570, 5 arquivos, US$ 0,043, 0 falhas):
- O nó Compression real entrega `workbook.xml`; `Expandir Abas` emitiu 8 itens (2 abas × 4 planilhas, nomes certos); `Agrupar Linhas XLSX` devolveu 4 documentos, com `pairedItem`.
- Nenhuma pendência "leu SO a primeira" (no lote de 09/11 as 4 tinham). Mapa de Dívida: 14 → 26 linhas lidas (95 → 119 pares); Extrato: 136 → 140. Contingências (61) e Estoque (67) ficaram iguais: NÃO conferido se a 2ª aba delas tem linha de valor.
- A 0231 ao vivo: a procuração chegou SEM tipo, zero linha e `false`, e abriu a pendência nova com o motivo certo.
- Observado, sem fatia: no Mapa de Dívida a régua contou 16 e a leitura devolveu 26 (cobertura acima de 1 em planilha de várias abas); a procuração não foi classificada neste lote.

**Defeitos fechados na branch:**
1. **"Arquivo com acento some entre o portal e o n8n" (ALTO da P4) não era do portal nem do n8n** (`a3ceaa6`, `c8fcabd`). O Chromium do Playwright em locale POSIX descarta calado caminho não-ASCII no `setInputFiles`: 3 de 11 no input; com `LC_ALL=C.UTF-8`, 11 de 11. O encaminhamento do portal, reproduzido à parte: 11 de 11. Provado ao vivo: o reenvio dos 8 com acento deu 8 de 8 documentos. `ENVIO_CASO_ID` no `enviar-book.mts` reenvia a um mandato existente. Não provado: navegador real de cliente em Windows/macOS.
2. **Comentário do IF "Extracao ja feita?"** (lacuna do #278) corrigido (`b424df1`); workflow regerado idêntico.
3. **Régua** (`9cdf90e`): contava título numerado como conta (Notas Vertentes 9→3; Notas Piraquara 24→17, e some uma 2ª passada paga). A verdade do gerador contava cabeçalho de ano (Faturamento 24M 16→15; Mapa Piraquara 18→17; Notas Piraquara 5→4). A DMPL "4,7×" era medida errada: a IA devolve movimento × componente, e 14 lidas = 14 células. **NÃO explicado:** BP Piraquara Montagens 43 lidas × 32, e +1 na DMPL Canastra (precisa da saída da IA de produção).
4. **0231** (`1444e06`, `233e428`, `5bc3fc3`): `fn_tipo_sem_dado_por_natureza` e `fn_pessoa_decidiu_sem_dado`. Só a pendência DESTA causa resolvida por pessoa conta como decisão (ALTO da 2ª revisão: uma cota resolvida à mão calava o balanço para sempre). `run.sh` rc 0, 3.270 ok.
5. **`.xlsx` com mais de uma aba** (`3075c8d`, `e5252d9`): o n8n lia só a primeira (as 4 planilhas do book-espelho perderam a 2ª; real: Endividamento Krauspenhar.xlsx gravou 0 linhas). 3 nós novos (Copiar Como ZIP, Ler Abas do XLSX [Compression], Expandir Abas), `sheetName` por item. Decisão do dono: ler no n8n, arquivo intacto. `.xls` fica de fora (shortcut declarado). **As premissas sobre os nós nativos foram lidas no FONTE de n8n-nodes-base@2.46.6; NÃO provadas na instância.** Só a republicação prova.
6. **Portal** (`fd74c24`, `55f2e88`, `5ead9d3`, `b95944e`): causa e ação em português para a pendência da 0231 e para as 5 frases novas de planilha. CI (`d8a2b18`): o job do n8n gera o book-espelho, instala o portal e o pdftotext.

**Revisão independente:** 3 passadas. 1ª: 3 MÉDIOS + 3 BAIXOS; 2ª: 1 ALTO + 1 BAIXO; 3ª: nenhum ALTO nem MÉDIO.

**Suítes remedidas em 10/11 (local):** n8n 757/0; banco `run.sh` rc 0 (3.270 ok); leitor 65/0; hooks 11/0; os 12 `verificar-*` rc 0 (kit-basico 167/0, export 894/0); e2e 46/0; variações 0 achados; medidores rc 0; geradores e fixtures sem diff; tsc, eslint e `next build` rc 0. **O CI do GitHub NÃO rodou nesta branch (não há PR).**

**Pendências fechadas em 10/11 (2ª parte):**
- **Mandatos de teste apagados** como Sócio de teste (originais pelo Storage, com a trilha da 0224; depois `fn_excluir_caso`): "P4 linha de base - Espelho" (3 docs), "S124 — Espelho" (11) e "S124 — Planilhas de várias abas" (5). 19 originais removidos, 0 objetos restantes, 3 eventos `caso_excluido`. 82 → 80 mandatos; sonda 0 ausentes.
- **Corpos em produção = repositório:** md5 de `fn_registrar_campos_extraidos`, `fn_versao_extracao_concluida`, `fn_pessoa_decidiu_sem_dado`, `fn_tipo_sem_dado_por_natureza` e `fn_registrar_documento` iguais ao banco montado do repositório; ACL igual.
- **Contingências e Estoque "iguais":** a 2ª aba delas ("Instruções", "Plan2") tem 0 linha com número no arquivo. A contagem igual está certa.
- **Régua do Mapa de Dívida (16 para 26)** — `70735ef`: linha de planilha que termina em célula vazia era emendada na seguinte (5 contratos numa linha) e `__EMPTY_N` contava como conta. Corrigido em `cobertura.mjs`; régua continua exata em 20 de 20 PDFs de produção. PR #281 mergeado (`d316bd3`), ingestão republicada (63 nós batem). **Provado ao vivo:** o mesmo Mapa de Dívida agora dá régua 26 = 26 lidas, 0 falha (mandato de teste criado e apagado em seguida).
- **Procuração sem tipo:** não é defeito. A IA leu o conteúdo (confiança 0,99) e a taxonomia não tem tipo de procuração. A pendência da 0231 é o caminho desenhado.
- **BP Piraquara Montagens (43 × 32), explicado:** o PDF mostra cada grupo uma vez; a IA repetiu 11 linhas de subtotal ("Disponível", "Fornecedores"...) com os mesmos valores. É duplicação da leitura, não erro da régua. Separar duplicata de repetição legítima exige a coordenada da linha: vai para a **P11/P12** (a bijeção já prevê "duplicação vira pendência com o número da linha").
- **DMPL Canastra (29 × 28), explicado, não é defeito:** a 29ª célula é o "Total" da realização da reserva, que o PDF mostra como "-"; a IA gravou valor vazio (sem inventar zero) e o gerador não conta "-".
- Achado de passagem, sem fatia: na DMPL, `periodo_coluna` vem vazio e a `chave` é o componente do PL, não o movimento.

**P6 com os balancetes REAIS (10/11, enviados pelo dono; mesmo hash dos originais, lidos de novo porque o fingerprint mudou; US$ 0,93):**

| Documento | Descartadas por desalinhamento antes → depois | Pares gravados |
|---|---|---|
| Valtra `Balancete 1º semestre 2025` | **29 → 0** (a P6 provada no real) | 2.040 → 2.832 |
| Valtra `Balancete 1º semestre 2026` | 0 → 1 | 2.429 → 2.468 |
| Krauspenhar `balancete_janaago26` | **38 → 303** (causa nova, não a da P6) | 1.248 → 1.516 |

- Valtra 2026 e Krauspenhar ainda têm 9–10 blocos com cobertura < 85% depois da 2ª passada (declarado na pendência, não silencioso).
- **Krauspenhar, causa achada na resposta real da IA (execução 9586):** o `Extrair Texto` entrega os números COLADOS e fora de ordem (saldo anterior grudado no código da conta, saldo atual grudado no débito). 146 linhas vêm com 5 valores (o código no meio) e 144 com 3. A guarda que descarta está CERTA: tirar o código poria o saldo atual na coluna Débito.
- **P6b (PR #282, NÃO mergeado ao fechar a sessão):** `fracaoDeNumerosColados` em `cobertura.mjs`; acima de 25% das linhas com número, o documento vai pela MESMA rota de imagem da P6, com motivo `numeros-colados`. Calibrado: Krauspenhar 72,3% (dispara); Valtra 9,4% e 6,2% (não); 4 books + 20 capturados de produção 0,0% em 96 documentos. Regra 2: 4 testes reprovam sem o detector. N8N 763/0; régua exata 20/20.
  - Fixture **anonimizada** (dígitos por permutação fixa, palavras por rótulo sintético): o controle de segurança da sessão bloqueou o commit com dado real do cliente. Decisão do dono: opção A.
  - CI do #282: dois tropeços de ordem/derivado já corrigidos (canastra e distress gerados ANTES da suíte do n8n; grafo regerado). Ao fechar, aguardava as suítes no `b4fb4cf`; Sonar verde.
- **Não anonimizado, de propósito:** `N8N/test/aritmetica.test.mjs` (já no `main` antes desta sessão) tem valores reais do mesmo balancete. Ficam no histórico do git de qualquer jeito, e o teste confere identidades aritméticas (saldo anterior + débito − crédito = saldo atual) que uma permutação de dígitos quebraria.

**Próxima sessão, nesta ordem:**
1. PR #282: conferir CI verde no head, mergear, republicar a ingestão (`preparar-republicacao` + `conferir-publicado`).
2. Reenviar `balancete_janaago26.pdf` ao mandato KRAUSPENHAR (`33b58a89-0d77-417a-8859-e193c61e8db8`) e medir: descartadas por desalinhamento (303 antes), pares gravados (1.516), `leitura_pdf = 'ocr'` com motivo `numeros-colados`, custo. O original agora ESTÁ no Storage (enviado em 10/11). Se a imagem não resolver, a P6b não fecha: dizer o número.
3. Os blocos com cobertura < 85% no Valtra 2026 e no Krauspenhar: medir depois do passo 2 antes de abrir fatia.
4. Seguir o plano: P7b, P8, P9, P10. P11/P12 continuam no plano (o dono decidiu não antecipar).

## SESSÃO 123 (09/11/2026) — P7: 0230 APLICADA em produção; o #276 (P4, 0229) entrou junto; a medição por documento parou em 09/11

> **Última migration DAQUELA sessão: `0230_o_documento_sem_dado_financeiro_pago_a_cada_reenvio.sql` — APLICADA EM PRODUÇÃO em 09/11/2026.** (A 0231 veio na S124.)
> - Sonda antes: 339 itens, na 0229. Ensaio em transação revertida: 342, 0 faltando.
> - Depois: 342 itens, os 3 da 0230 presentes. O corpo das duas funções em produção tem o mesmo md5 do banco montado do repositório. ACL de `fn_registrar_documento` igual. Mandatos: 81 antes e depois.
> - A sonda acusa 1 ausente (`envio_segredo_no_vault`) pela API: é a leitura do Vault negada a esse papel, não o segredo faltando. Dentro da transação do ensaio deu 0 faltando.

- **P7 (o reenvio retoma só o que falhou):**
  - Defeito: o reenvio só pulava documento com linha gravada. Certidão, organograma e contrato social (zero linha por natureza) eram pagos a cada reenvio.
  - Correção: `fn_versao_extracao_concluida`. Pula também quando o último evento declara `tem_dado_financeiro = false` sem falha, o tipo é societário (menos CONTINGENCIAS), a medição não contou conta e não há `extracao_falhou` aberta.
  - Simulado em produção (1.571 documentos): 29 deixam de ser pagos, nenhum com falha aberta, nenhum passa a ser pago.
  - Aceite no teste: lote de 4 com 1 falha total, reenviado inteiro, paga 1. Com o critério antigo pagava 2.
  - O n8n não precisa de republicação por causa da 0230.
- **Duas versões foram reprovadas na revisão antes de aplicar:**
  1. Reextrair falha COM linha. Só 3 de ~75 dessas falhas são do serviço, e a versão nova tirava da Modelagem a linha já aceita. Fica para a P8.
  2. Confiar na declaração da IA para qualquer tipo. Dos 71 que ela pularia, 41 eram de tipo financeiro.
- **ACHADO ALTO, anterior à P7 e NÃO corrigido:** 41 documentos de tipo financeiro com zero linha, `tem_dado_financeiro = false` e sem `extracao_falhou`.
  - Reais: AMOBELEZA (10 `.txt` de BALANCO, DRE e FATURAMENTO_24M), Krauspenhar (1 MAPA_DIVIDA `.xlsx`, sem nenhuma pendência aberta), AMO teste 00 (2 EXTRATO_BANCARIO).
  - Teste e sintéticos: 28, todos DF_AUDITADA ou NOTAS_EXPL.
  - Causa traçada pelo revisor: quando a IA diz "sem dado", a guarda de cobertura (`build-workflow.mjs:1933-1934`) e o Sinal 3 se calam. Anotado na semana 3 do plano (P12, a bijeção).
- **Lacunas declaradas:**
  - Falha com linha continua reaproveitada até o prompt mudar (P8).
  - O orçamento do lote não desconta o reaproveitado. Não foi construído: 0 recusas de orçamento desde 17/09 e nenhuma atribuível a isso; mexer no guarda de gasto sem caso medido é o risco do v31.
  - A fila com botão no portal é a P7b (só 9 de 496 falhas têm o original no Storage).
  - O comentário do IF "Extracao ja feita?" no gerador ainda diz "tem linha". Corrigir quando o gerador for mexido (exige regerar o workflow).
- **#276 (P4, 0229):** estava em produção e fora do `main`. A republicação de 09/11 saiu do `main` e desfez a metade n8n dela. Medido: em 06 e 07/11, 69 de 69 eventos `extracao_sombra` levam a medição; em 09/11, 0 de 5. O ramo foi mesclado aqui, com os derivados regerados.
- **Pendente do dono:** merge do #278 e republicar a ingestão, para a medição por documento voltar. Fechar o #276.

## SESSÃO 122 (09/11/2026) — #275 em produção e testado AO VIVO; defeito do Storage achado e corrigido

- **#275 mergeado** (`7b29e80`, deploy pronto). Na tela de produção: a falha de extração mostra a causa em português e a ação certa, com o técnico recolhido; o botão da conta não traz mais o e-mail.
- **Testes ao vivo** num mandato criado pelo portal e apagado depois:
  - Recusa de TAMANHO (16,5 MB) grava a etapa `tamanho` em 1 linha.
  - Recusa de ORÇAMENTO (3 docs, US$ 45,27) grava 1 linha; antes eram 3.
  - Lote válido (2 PDFs do Vertentes): cobertura 1,0000, 0 falhas, US$ 0,0095. O original abre pelo portal.
- **Defeito novo, achado no teste:** o lote recusado deixava os arquivos no Storage, porque o upload vinha antes do orçamento. Agora o upload só acontece depois de "Lote cabe?" (nó "Reanexar Original"). Ingestão republicada (60 nós conferidos). Retestado: recusa não guarda nada e o lote aceito guarda e referencia. 0 órfãos no bucket.
- **Varredura do portal novo:** 81 mandatos, 1.458 verificações, **0 falhas**. 128 exports com o Excel recalculado e sem erro de fórmula (o `#VALUE!` sumiu). 115 recusas legítimas. 12 avisos de lentidão (21–33 s).
- **Pendente do dono:** o CI do GitHub falhou sem rodar jobs (possível cota ou limite do Actions). Conferir em Settings → Billing.
- **P6 (desalinhamento de colunas):**
  - Causa: o PDF lido como texto cola as células por espaço, e a célula em branco some.
  - Correção: tabela com linha curta vai à IA como imagem. A guarda continua estrita.
  - Provado AO VIVO com o BP COMBINADO sintético: antes, 0 linhas e 32 descartadas; agora 185 linhas, 32/32 contas e 0 descartadas, a US$ 0,0071.
  - Conferido contra o GABARITO: ativo combinado 158.113, as três eliminações iguais, e a coluna em branco não recebeu valor.
  - **Não retestado com os balancetes reais** (Krauspenhar, Valtra): o original não está no Storage (só 72 de 2.138 versões têm original guardado). Precisa que o dono reenvie os dois PDFs.
  - Lacuna declarada: balancete com uma célula por linha no texto não é detectado.

## SESSÃO 121 (09/11/2026) — semana 1 fechada: P4, P5 e P1d; ingestão REPUBLICADA

- **Republicação:** ingestão republicada no n8n em 09/11, 18:04 UTC, com autorização do dono. `preparar-republicacao.mjs` + `conferir-publicado.mjs`: os 59 nós batem com o repositório. A P1d (a recusa grava a etapa real e 1 linha só) e a régua da P4 (cobertura entre 0 e 1, excedente declarado) passam a valer em produção.
- **P5:** a correção já estava publicada desde 28/10 (Agrupar Linhas XLSX/XLS). Faltava o teste de topologia, e ele foi escrito.
- **P4:** a linha de base (`Supabase/test/linha-de-base-extracao.sql`) rodou contra produção: 2.053 documentos, 79 mandatos. Os números do corpus estão no `PLANO_DE_EXECUCAO_2026-11.md`.
- **Plano reprogramado:** as semanas 2 a 6 andaram uma semana. O fim passa a 18/12.
- **Não provado ao vivo:** a gravação de 1 linha por recusa no Postgres real. Ela é afirmada pelo número de itens no teste, porque provocar uma recusa real exige um lote grande pelo portal.
- **Próximo:** semana 2, começando pela P6 (desalinhamento de colunas em balancete multi-coluna: Krauspenhar 38, Valtra 29, BP COMBINADO Vertentes 32).

## SESSÃO 120 (06/11/2026) — 0226, 0227 e 0228 APLICADAS em produção; P16 conferida no portal publicado; G2 e o `title=` do e-mail corrigidos

> **Última migration DAQUELA sessão: `0228_a_linha_sem_tipo_que_chegava_aceita_ao_excel.sql` — APLICADA EM PRODUÇÃO em 06/11/2026.**
> - Sonda antes: 331/331, na 0224.
> - Ensaio das três numa transação revertida: 334/334, e a foto (corpo e ACL das três funções) ficou idêntica depois.
> - Aplicadas uma por vez: 332 → 333 → 334, 0 faltando. A ACL das três funções não mudou.
> - As três suítes da P16 rodaram contra produção, em transação revertida, e passaram inteiras. Mandatos: 77 antes e depois.

**Portal publicado (`5d0061d`) visto como Sócio, só leitura.** O banco ficou igual antes e depois (eventos, decisões, md5 dos estados de pendência).
- A, B, C, E, F e F2 batem com o PR.
- O ✕ da equipe não foi exercitado: há 0 alocações em produção.
- "Reabrir pendência" grava em um clique, sem confirmação. Foi escolha do #274 e não foi clicado.

**Corrigido nesta sessão (o #274 não cumpria em produção):**
- **G2.** A heurística do acento mandava o motivo inteiro para a tela. 272 das 468 `extracao_falhou` abertas mostravam instrução de engenharia (`N8N/lib/provedor.mjs`, `TPM_CONTA`) e o colchete do provedor em inglês. E toda falha recebia "abra o arquivo / reenvie", inclusive chave inválida e falta de crédito: 347 pendências abertas são do serviço de IA.
- Agora a tela mostra a causa em português e a ação que a causa pede. O motivo inteiro vai para Detalhes técnicos. Medido nos 130 motivos reais: 0 com texto técnico à vista.
- **D.** `menu-conta.tsx` tinha `title={email}`. O portão só varria `valor-sensivel` e agora varre todo `title={…}`.
- **Varredura nova:** `Verificação/varredura-dos-mandatos.mts`. Abre cada aba (desktop e 390 px), cada documento e os três exports de TODO mandato visível. Sai com 2 quando não rodou.

**Varredura completa (retomada de 07/11, 00:03–02:20 UTC):**
- **Produção** (`5d0061d`): 79 mandatos, 2.391 páginas de documento, 120 exports baixados, `.xlsx` recalculados no LibreOffice. 3.458 verificações: 3.323 ok, 88 recusas legítimas, 17 avisos (só lentidão, até 32 s na Modelagem e em documentos grandes), 30 "FALHA". Dessas 30:
  - **25** eram a recusa legítima da apresentação ("ainda não tem o modelo institucional montado"), lidas como falha pelo script. Corrigido em `a558396`.
  - **4** eram defeito real: `#VALUE!` na guarda do giro agregado (Working Capital) quando a receita do último realizado é zero. Corrigido em `dd85ed3`. Com a correção, os 4 mandatos passam 72/72.
  - **1** era um 502 isolado da Vercel numa chamada RSC. Não se repetiu.
- **As 2 falhas da pausa** (`531ddabc`, `1be52ab4`) refeitas: 198/198 ok. Eram navegação concorrente do script.
- **Código deste PR** (build local apontado para produção): chegou a 79 de 80 mandatos antes do limite de 2 h. 0 falhas fora as recusas da apresentação, e 1 contexto destruído por navegação (`ca863527/revisao`), do mesmo tipo das da pausa.
- **CI e Sonar do #275:** verdes em `cb19043`. O Sonar S4036 (`soffice` pelo PATH) foi corrigido em `9c96dfe`. PR desinscrito.

**Não exercitado em produção:** a recusa de confirmar documento sem tipo pelo navegador (só pela suíte); "Reabrir pendência" (grava em 1 clique, sem confirmação; decidir se deve pedir); o ✕ da equipe (0 alocações).
**Pendente do dono:** decidir sobre o "Reabrir"; trocar a senha (passou pelo chat).

**Resíduo medido e deixado:** 738 linhas auto-aceitas em 23 documentos sem tipo, todas em 11 mandatos de teste. A 0228 vale só para a frente.

## SESSÃO 119b (06/11/2026) — P4: linha de base da leitura por documento (0229 APLICADA em 06/11; linha de base medida em 07/11)

> **Migration nova desta sessão: `0229_a_leitura_que_so_se_media_somada_por_lote.sql` — APLICADA EM PRODUÇÃO em 06/11/2026 (sonda 334→339).** Nasceu 0225 e foi renumerada para 0229 depois que a P16 (sessão paralela, PR #274) entrou com 0226–0228 já aplicadas em produção. A 0228 REESCREVE `fn_registrar_campos_extraidos` (auto-aceite exige tipo): a 0229 tem de reemitir o corpo DA 0228 com `p_medicao`, nunca o da 0204, senão desfaz a guarda da 0228 calada. `fn_registrar_campos_extraidos` ganha `p_medicao` (evento `extracao_sombra` leva a medição por documento) e nasce `fn_linha_de_base_extracao(caso)`. O n8n (`Juntar Blocos` → `Gravar Campos (Sombra)`) já passa `p_medicao` no repositório, NÃO republicado. **Ordem rígida: aplicar a 0229 e conferir a sonda ANTES de republicar o n8n** (n8n novo com banco antigo = toda extração falha com "p_medicao does not exist").

**RETOMADA FEITA (07/11, 00h–01h UTC):** os 4 books foram enviados e medidos; a linha de base está em `Arquitetura do Sistema/3 Estado e Execução/LINHA_DE_BASE_P4.md`. ACHADO ALTO: 8 de 11 arquivos do book-espelho (os de nome com acento) sumiram entre o portal e o Form do n8n sem nenhum registro de falha — investigar primeiro. Próximo: P5 com essa lista de achados.

**ATUALIZAÇÃO (06/11, ~21h UTC) — 0229 APLICADA e n8n REPUBLICADO; sessão PAUSADA pelo dono (limite de tokens).**
- Produção: 0229 aplicada (sonda 334→339, 0 ausentes; `campos_auto_aceite_exige_tipo` da 0228 continua presente; corpo de produção era idêntico ao da 0228 antes; só as ACL das duas funções da 0229 mudaram). n8n de ingestão `na1AEv3m8fjDXlwM` republicado a partir de `70f1a69` (PUT 200; `conferir-publicado` ok, 59 nós). Cópia do publicado ANTES ficou só no scratchpad da sessão (perdida ao fechar): para voltar, republicar a partir do commit `5d0061d` do main.
- PS: o protocolo S3 do Storage foi DESLIGADO no painel (autorizado pelo dono).
- PAROU NO MEIO: o envio do book-vertentes pelo portal (`Verificação/enviar-book.mts`, mandato **"P4 linha de base - Vertentes (sintetico)"**) foi disparado e o lote pode estar rodando/fechado em produção — conferir em `lote_execucao` desse caso. A medição NÃO foi rodada.
- Como retomar: (1) redefinir as senhas dos 3 usuários de teste (estavam só no scratchpad desta sessão); (2) rodar `Verificação/linha-de-base.mts` sobre o mandato acima com `LB_METRICAS="Dados de Teste/book-vertentes/pdf/METRICAS.json"` (gerar os books antes: ver COMANDOS-CANONICOS) e conferir que os documentos chegaram com `versao_medicao = p4-1`; (3) se sim, enviar canastra, distress e espelho (`Dados de Teste/book-espelho`, custo estimado US$ 0,45) e montar a tabela; (4) abrir o PR da branch `claude/tender-turing-vybcm8` (ainda SEM PR).
- Achados já medidos na P4: os originais reais (Valtra, Krauspenhar, AMO) NÃO estão guardados (0 de 140 versões no bucket); `medir-custo-book` reprova no espelho (DRE analítica e balancete custam US$ 0,08/chamada contra a estimativa de 0,055 que sustenta o teto); a régua conta 4 linhas numa procuração (verdade 0); um lote do Valtra de 05/10 ficou aberto sem fechar.

## SESSÃO 119 (06/11/2026) — P16 no código: os 5 temas ALTOS da vistoria P2 (0226–0228 aplicadas na S120)

> As três da P16 (0226, 0227, 0228) foram **aplicadas em produção na S120** (ver acima). Nasceram 0224–0226 e foram renumeradas depois que a 0224 (D16) entrou no `main`.

**O que entrou (branch `claude/dazzling-einstein-mhx4l1`), cada fatia com a regra 2 na mensagem do commit:**
- A: "Prosseguir sem resolução", "Não procede" e o ✕ da equipe pedem confirmação.
- B (0226): `fn_revisar_documento` recusa confirmar documento sem tipo; o portal lê `recusado`.
- C (0227): `fn_decidir_pendencia` aceita `reabrir`; botão "Reabrir pendência".
- D: modo discrição borra nomes (mandato, entidade, arquivo, e-mail) e nenhum elemento sensível tem `title=`.
- E: Início sem estouro de largura no celular (reproduzido com o CSS compilado; não é portão de CI).
- F/F2: a sugestão do realizado não mostra a conta de um ano ao lado da média; o aceite diz se foi pessoa ou automação.
- G1 (0228): auto-aceite exige documento com tipo. G2: extração que falhou em português, erro do provedor em "Detalhes técnicos".

**Fora (NÃO feito):** "Remover documento" (não existe ação); ⌘K e sino no modo discrição; `/casos/todos` e Modelagem com estouro (vistoria item 9); backfill das linhas já auto-aceitas sem tipo (não medido quantas); página do Balanço (é a P11). **Nada visto no navegador com dado real.**

## SESSÃO 118 (06/11/2026) — 0224 (D16) aplicada em produção, resíduo da S117 limpo, #269 fechado

> **Migration desta sessão: `0224_o_original_que_o_analista_apagava_sem_trilha.sql` — APLICADA EM PRODUÇÃO em 06/11/2026 (sonda 322→331, os 9 requisitos da 0224 presentes; ensaio com rollback e foto idêntica; ACL de funções e tabelas pré-existentes com hash igual; dial igual).** Toda exclusão de original no bucket `documentos` grava `documento_original_apagado` com o ator; mover/sobrescrever só Sócio; ninguém via `authenticated` grava essa ação à mão. A anterior, `0223`, segue aplicada.

**O que fechou (medido):**
- **#269 fechado sem merge** (era a P1b paralela; o `main` já tinha a 0218 do #268 e a 0221). **Sonar do #273:** a única issue (S5332, URL `http` falsa na sonda do intake) corrigida em `acb2677`; CI e Sonar verdes.
- **Resíduo da vistoria interrompida (04/11): nenhum.** 0 objetos-sonda, 0 mandatos "P2 escalada", pendência `19a85786` restaurada para `aberta`, 0 eventos de dial desde 04/11. O dial NÃO é "N2 global": é por estágio (N0/N1/N2) e não mudou.
- **`schema.sql` não estava parcial:** `run.sh` rc 0 (2.994 ok) sem diferença. O aviso da RETOMADA estava velho.
- **0224: sete revisões independentes até 0 achado.** Os ALTOS, em ordem:
  1. a API do Storage apaga como superusuário, e o ator sairia "sistema" sempre;
  2. a rota S3 não verifica o `Authorization` (o protocolo S3 está LIGADO no projeto);
  3. a guarda por path foi burlada por percent-encoding, e o desenho virou lista de permitidos sobre `storage.operation`;
  4. o Analista inseria o evento à mão pelo REST.

  Médios fechados: o JWT sem "Bearer"; chave de serviço e SQL direto não viram "Sistema"; as sondas de policy contam qualquer outra policy (inclusive `anon`); o índice em `documento_versao(arquivo_ref)`. Teste: 88 asserts, regra 2 medida guarda a guarda (tabela no cabeçalho da migration). `run.sh` 3.056 ok. Lição na ficha `storage-apaga-como-superusuario-ator-por-lista-de-permitidos`.
- **Prova em produção (06/11):**
  - Analista apagou pela API REST e o evento gravou o e-mail dela (`ator_origem = cabecalho_jwt`, `storage_operation = storage.object.delete`, `papel_sessao = service_role`).
  - Analista tentando mover: recusado. Analista inserindo o evento à mão: 42501. 0 forjados.
- **Vistoria por papel refeita contra produção** (`Verificação/vistoria-por-papel.mts`, sem `P2_ENVIAR`): o mesmo comportamento da versão anterior.
  - 168 células, nenhuma com erro de console ou resposta 4xx/5xx.
  - Escalada: 60 tentativas, 51 barradas, as 9 que passaram são as previstas pela 0216, 0 divergências.
  - Resíduo 0. As exclusões da escalada já aparecem na trilha nova com o autor certo, inclusive em `delete_many`.
- **Limpeza da S117:** os mandatos `b563851b` "S117 P2 sintetico" e `ada45333` "S117 P3 renomeio B" foram apagados como Sócio. Primeiro os 7 objetos pelo Storage (7 eventos com o Sócio e o nome original de cada arquivo), depois `fn_excluir_caso` (7 documentos, 25 pendências, 494 campos; 2 eventos `caso_excluido`). Ensaio com rollback antes. Os 3 usuários de teste ficam até a P20; as senhas foram redefinidas e estão só no scratchpad desta sessão.
- **Fichas:** 6 novas (as 5 lições da S117 e a do Storage). **Plano:** D6, D7, D15 e D16 registradas.

**Limitações e o que NÃO foi feito:**
- O ator livre em `evento_auditoria` vale para TODA outra ação desde a 0216 (o Analista grava qualquer ação com qualquer `ator` no próprio mandato). A 0224 fechou só `documento_original_apagado`. Precisa de fatia própria.
- Pelo S3 e pelo painel do Supabase a exclusão sai `storage:nao_identificado` ou `storage:chave_de_servico`: a trilha existe, mas sem pessoa. Desligar o S3 no painel (ninguém o usa) é decisão do dono, pendente.
- Quem tem acesso SQL ao banco forja a trilha. É um limite declarado no cabeçalho da 0224.
- Achados menores da verificação da S117 continuam sem correção (RETOMADA, item 6).

**Próximo:** P4 (linha de base da F3 e corpus de regressão), com teto de US$ 5 por book (D6).

---

**Sessões anteriores (até a 117, 04/11/2026):** [`Arquitetura do Sistema/3 Estado e Execução/ESTADO_ATE_2026-11-04.md`](Arquitetura%20do%20Sistema/3%20Estado%20e%20Execução/ESTADO_ATE_2026-11-04.md). O histórico completo está no `HANDOFF.md`.
