# Plano de execução do Oria Digital (único, em vigor)

**Plano único** pedido pela decisão K1. Substitui todos os planos anteriores, que ficam como histórico
com uma nota "superado por" (lista em [`99_historico/README.md`](../99_historico/README.md)).
**Sem calendário** (K2): só sequência, dependências e critério de pronto.

- **Base:** registro de decisões [v0.1.6](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.6.html)
  e [workflow v0.3.0](../02_workflow_e_arquitetura/oria_digital_workflow_v0.3.0.html).
- **Situação conferida no código** em 19/11/2026, `main` em `e85ac9c`, migration mais nova `0302`.
  O banco de produção **não** foi consultado para este plano: o que está no banco é confirmado pela
  sonda (`select … from fn_instalacao_conferir() where not presente`).
- **Quem constrói hoje** (K3): o dono e o Claude. O Claude implementa, revisa e documenta; **nunca
  aprova**. Os papéis que dependem de pessoas que ainda não existem estão marcados
  **[a contratar]** ou **[a indicar]**.

## 0. Prioridade em vigor (decisão do dono, 24/11/2026)

Antes de seguir a ordem das fases abaixo, a construção começa pelo que a Oria faz sozinha, com dado
grátis e sem depender de parceiro, contrato ou demo:

| Ordem | Fase | Itens deste plano que ela cobre | Detalhe |
|---|---|---|---|
| 1 | **A — Fontes públicas grátis** | 0.2 e 0.3 (versão mínima), 1.K1 (catálogo), 1.C1–1.C5, 1.H2 (só empresas), 1.C4, parte do 1.H5 | [`FASE_A_FONTES_PUBLICAS.md`](FASE_A_FONTES_PUBLICAS.md) |
| 2 | **B — Book confiável** | 1.A1–1.A10, 1.B3, 1.B4, 1.B6, 1.I1 | A detalhar quando a A fechar |
| 3 | **C — Conferência e análises** | 1.B5, 1.K2, a parte de motor de 1.E2–1.E4 (dívida, caixa 13 semanas, juro × mercado) | A detalhar quando a B fechar |

- **Depois das três fases:** as plataformas prontas (Direct Data, JUDIT, Serasa) e o restante do plano.
- **O que não mudou:** os itens P1 da Fase 0 continuam exigidos antes do primeiro mandato real (G0).
- **A registrar na v0.1.7 do registro:** a ordem e as decisões da §2 do detalhe da Fase A, e a D6-2 (régua de autonomia N2 passa a 95% no limite inferior, decisão do dono de 25/11/2026).

## 1. Como ler

Cada item tem:

| Coluna | O que diz |
|---|---|
| **ID** | Fase.número (ex.: `1.D3`, a trilha D da fase 1, item 3) |
| **Prio.** | **P1** bloqueia o portão da fase · **P2** necessário à fase · **P3** melhora, pode escorregar para a fase seguinte sem quebrar o portão |
| **Depende de** | IDs ou portões que precisam estar prontos antes |
| **Papel** | Quem faz / quem aprova. Dono = hoje Sócio, Analista e Técnico ao mesmo tempo |
| **Situação** | **FEITO** (existe e atende), **CORRIGIR** (existe e precisa mudar), **DESENVOLVER** (não existe), sempre com a evidência (arquivo, migration, suíte) |
| **Pronto quando** | O critério medível. Item só fecha com a medida feita, não com o código escrito (regra 7 do `CLAUDE.md`) |

**G0–G3 são os portões deste plano.** Quando um item cita uma decisão do registro com o mesmo
nome (G1 monitoramento, G2 relatório, G3 acesso do cliente), o texto diz "decisão G1", "decisão G3".

**FEITO exige a medida.** Um item só passa a FEITO quando a medida do "pronto quando" foi feita, e a linha
de Andamento cita onde ela está (teste, sonda, número). Código que existe sem a medida é CORRIGIR.

O que cada decisão quer dizer está em [`04_regras_de_negocio/REGRAS_E_DEFINICOES.md`](../04_regras_de_negocio/REGRAS_E_DEFINICOES.md);
os agentes, em [`03_agentes/AGENTES.md`](../03_agentes/AGENTES.md); papéis e publicação, em
[`05_governanca/`](../05_governanca/MEMORIA_AUTOAPRIMORAMENTO_E_GOVERNANCA.md).

## 2. Visão geral: fases e portões

```
FASE 0  Fundação ─────────────► G0  pronto para o 1º mandato do piloto
FASE 1  Piloto com a Partners ─► G1  piloto concluído e medido   (1ª entrega da v1, K6)
FASE 2  Restante da v1 ────────► G2  pronto para o 1º cliente além da Partners
FASE 3  Evolução operacional ──► G3  produção para vários clientes
FASE 4  Arquitetura final e futuro (condicionada a gatilhos, parcerias e pareceres)
```

- **A Fase 0 e a Fase 1 andam em paralelo** (K4, R2): a construção do piloto começa já, sem se prender
  a uma plataforma. O que precisa estar pronto **antes do primeiro mandato** é o portão G0.
- O **estudo comparativo de infraestrutura (0.1) é a primeira entrega** (R2). Os itens que dependem da
  plataforma escolhida (orquestração dos agentes, observabilidade, hospedagem) esperam por ele; os
  demais não.

## 3. Ponto de partida (medido no código, 19/11/2026)

| Já existe e serve ao piloto | Existe em parte | Não existe |
|---|---|---|
| Leitores determinísticos de SPED/EFD/CNAB/OFX/XML (`Leitor/`); leitor tabular e mapeamento de colunas (`Leitor/lib/tabela.mjs`, `mapeamento.mjs`, `0272`); aging conciliado com o balanço (`0274`, `0277`, aplicadas); proveniência por linha (`0125`, `0270`); séries macro do BCB e expectativas do Focus, com agendamento diário (`0025`, `N8N/lib/macro.mjs`, `N8N/workflow.macro.json`); gabarito rotulável (`0126`, `0130`); Kit pelo banco (`0300`, `0301`); Excel em fórmula; conferências de balanço, caixa e DRE; trilha só de acréscimo (`evento_auditoria`); RLS por mandato e papéis Sócio/Analista/Leitura (`0216`); custo por lote (`0115`, `0135`) | Dois dialetos de IA (OpenAI e Gemini) sem troca automática (`N8N/lib/provedor.mjs`); extração por IA sem IA revisora; envio por token sem área do cliente; dial de autonomia com a extração **em N2 sem medição** (`0041_dial_manda.sql:419`) e a classificação de documentos em N2 "declarada, não medida" (`0127_o_dial_obedecido.sql:493`); `CODEOWNERS` que pede e não exige revisão | Agentes (todos), Supervisor, Auditor-agente; captação de Registrato, Open Finance, juros por modalidade, CVM, CAGED/RAIS (o IBGE entra só no IPCA, como conferência cruzada); cruzamento com fonte externa; dossiê de processos e notícias (há só os fatos em texto `litigio_relevante` e `garantia_dada` da `0148`); PDF; link número → página **no Excel** (no portal ele existe: `portal/src/lib/original-do-documento.ts`, `hrefDoOriginal` com a página); organização (multi-cliente); papel Técnico; verificação em duas etapas; backup fora do Supabase; chave do n8n de mínimo privilégio (usa `service_role`); cadeia de hashes; expurgo; ambientes dev/teste separados; anonimização; monitoramento; feature flag |

O inventário das **111 etapas** do plano anterior (20 completas em 11/11/2026) continua no git
(`STATUS_POR_ETAPA_2026-11-11.md`, ver [`99_historico/`](../99_historico/README.md)) e foi a base das
trilhas abaixo.

---

## 4. FASE 0 — Fundação (antes do primeiro mandato do piloto)

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| **0.1** | **Estudo comparativo de infraestrutura** (R2, H1, H2, H3, H5): ≥ 5 opções por item — coordenação dos agentes, hospedagem dos agentes, banco de dados, automação/coleta, observabilidade da IA, arquivos e evidências, provedores de IA (D1, D2) — com custo, complexidade e capacidade (memória, processamento, disco). LangGraph, Cloud Run, Supabase, n8n e Langfuse são **candidatos** | P1 | — | Claude pesquisa e escreve · Dono decide | DESENVOLVER. Candidatos listados no workflow v0.3.0, bloco "Infraestrutura" | Documento em `Business Plan/06_execucao/` com a matriz por item, a recomendação e a **decisão do dono registrada** (nova versão do registro); custo mensal estimado por cenário |
| **0.2** | **Backup provisório** (H1-1): cópia diária automática, criptografada, do banco **e dos arquivos**, fora do Supabase | P1 | — | Claude · Dono aprova | DESENVOLVER. Nenhum workflow de backup em `.github/workflows/`; `Supabase/README.md` só tem `pg_dump --schema-only` | 7 cópias diárias seguidas existem fora do provedor, criptografadas, com tamanho e hash registrados |
| **0.3** | **Teste de restauração** (H7): banco + arquivos num ambiente à parte | P1 | 0.2 | Claude · Dono confere | DESENVOLVER. MAPA B6.3 marcava "escrito", mas era só documento | Restauração feita; a sonda dá a mesma contagem do original; tempo real anotado; perda ≤ 1 dia |
| **0.4** | **n8n com mínimo privilégio** (H2, H4): trocar a chave `service_role` por uma chave restrita; nenhum mandato real novo no n8n atual | P1 | — | Claude · Dono aplica | CORRIGIR. Credencial "Supabase Storage (service_role)" em `N8N/README.md` | Chave nova com só as permissões usadas; teste que tenta ler fora do escopo **reprova** (medido não-vazio) |
| **0.5** | **Extração e classificação de documentos de volta a N1** (D6, D6-1) até haver medição | P1 | — | Claude · Dono aplica | CORRIGIR. `0041_dial_manda.sql:419` põe `extracao_linhas_financeiras` em N2 com origem `sistema:0041`, sem medição. **E existe promoção automática** que devolveria as duas etapas a N2 sozinha: `trg_auto_promover_dial` dispara a cada `decisao` (`0137_a_promocao_automatica_do_dial.sql:347`) e promove com `n_minimo_veredito` = 30 (`0136`) e concordância ≥ 0,95 (`0126`); o freio só liga quando o autor não começa com `sistema:` (`fn_mudar_dial`, definição vigente em `0139_reafirmar_nao_apaga_medicao.sql:92`; nasceu na `0137:201`). Rebaixar por migration com autor `sistema:` **não** basta: é preciso desligar `estagio_autonomia.auto_promocao` nas duas etapas (ou subir o critério em `golden_criterio` para a régua da D6). **A classificação de documentos** (`classificacao_doc_checklist`) também está em N2 sem gabarito (`0127_o_dial_obedecido.sql:493`); volta a N1 pela decisão D6-1 (registro v0.1.4) | Dial da extração e da classificação em N1 em produção (sonda), com `auto_promocao` desligada nas duas; teste: **30 decisões humanas seguidas não promovem** nenhuma das duas (medido não-vazio); linha extraída e documento classificado pedem confirmação humana; teste reprova se qualquer das duas voltar a N2 sem as ~300 amostras |
| **0.6** | **Proteção do `main`** (K4): regra de proteção com PR obrigatório, revisão do dono e CI verde | P1 | — | Dono (clique no GitHub) · Claude confere | CORRIGIR. `.github/CODEOWNERS` pede e não exige; proteção **não conferida** (ESTADO, sessão 132) | Push direto no `main` recusado (tentativa registrada) |
| **0.7** | **Contrato de dados com cada provedor de IA** (D1, K4): cláusulas-padrão da ANPD | P1 | 0.1 (quais provedores) | Dono · Advogado | DESENVOLVER | Contrato assinado com cada provedor usado no piloto; arquivo de referência guardado fora do repositório |
| **0.8** | **RIPD** (I5): relatório de impacto à proteção de dados — mapa de dados, fluxos e controles | P1 | 0.1, 0.7 | Claude (parte técnica) · Advogado (parte jurídica) | DESENVOLVER | Parte técnica escrita; parte jurídica validada por advogado |
| **0.9** | **Três ambientes** (H8): desenvolvimento, teste descartável por mudança, produção; nenhuma credencial de produção fora dela | P2 | 0.1 | Claude · Dono | CORRIGIR. Existe o banco de teste do CI (`Supabase/test/run.sh`, `tdf_test`) e a produção; não há dev separado | Os três existem; varredura não acha credencial de produção fora dela |
| **0.10** | **Anonimização** de dado real para teste (H8, F4) | P2 | 0.9 | Claude | DESENVOLVER | Cópia anonimizada de um mandato real roda a suíte; varredura não acha CNPJ/CPF/nome reais |
| **0.11** | **Alinhar duas especificações técnicas ao registro**: `Arquitetura do Sistema/2 Especificação/10_DADOS_RETENCAO_E_LGPD.md` (I2, H1, H7, H8) e `06_HUMAN_IN_THE_LOOP.md` (E1, E2, R1) | P3 | — | Claude · Dono | CORRIGIR. A 10 ainda marca os prazos [A CONFIRMAR]; a 06 ainda cita "revisor sênior / gerente" (linha 14) | As duas especificações não contradizem o registro vigente (v0.1.6) |
| **0.12** | **Infraestrutura de produção do piloto** (H1-1, H1, H2, H7): o piloto conta como produção real. No banco e na automação escolhidos pelo estudo: backup contínuo, cópia separada dos arquivos, região São Paulo; automação (n8n ou o substituto) **fora da instância atual** | P1 | 0.1, 0.3 | Claude · Dono contrata e aplica | DESENVOLVER. Hoje: banco no plano gratuito sem backup; n8n numa instância compartilhada (decisão H2: ali só até a produção real) | Num teste de recuperação real (banco + arquivos): perda máxima de minutos e volta em até 4 h, medidas; nenhum mandato do piloto roda na instância atual do n8n |
| 0.13 | **Registrar as decisões do score do dado externo** ([Espec. 15](../../Arquitetura%20do%20Sistema/2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md), §11 e §5A.5) numa nova versão do registro | P2 | — | Claude escreve · Dono confirma | **FEITO (24/11/2026).** [Registro v0.1.6](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.6.html), seção 22: D15, D15.1–D15.15, D4-1 e J7. Medido: da v0.1.5 só mudaram 3 caracteres (número da versão e data); 90 → 108 decisões com âncora | v0.1.6 publicada com as decisões D15 e as 7 regras; a Espec. 15 e este plano citam o código delas |

### Portão G0 — pronto para o primeiro mandato do piloto

Todos os itens **P1** da Fase 0 fechados (0.1 a 0.8 e 0.12, a infraestrutura de produção do piloto) **e** os itens P1 da Fase 1 que o primeiro mandato
usa (marcados "G0" abaixo). Conferência: sonda sem ausências além de `envio_segredo_no_vault` (falso ausente conhecido: a leitura da sonda não alcança o Vault; `ESTADO.md`, sessão 131), backup e restauração medidos, metas de produção (H7) medidas no 0.12, contrato e
RIPD assinados.

---

## 5. FASE 1 — Piloto com a Oria Partners (primeira entrega da v1, K6)

Trilhas paralelas. Duas trilhas só andam juntas se não tocam os mesmos arquivos (seção 10).

### Trilha A — Book Excel confiável

Absorve as trilhas A, B e D do `PLANO_MVP_2026-11` e o `PLANO_LINHA_A_LINHA`.

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.A1 | **Leitura das bases volumosas** (AR, AP) em fluxo e mapeamento de colunas | P1 · G0 | — | Claude | CORRIGIR (feito com sintéticos, não medido com arquivo real): `Leitor/lib/tabela.mjs`, `mapeamento.mjs`, `0272` (aplicada). **Falta arquivo real** (DM7) | AR e AP reais da Partners lidos; linhas lidas = linhas do arquivo, ou descarte com motivo |
| 1.A2 | **Aging conciliado com o balanço** | P1 · G0 | 1.A1 | Claude | CORRIGIR (feito e medido contra os balanços de produção, não num book real do piloto): `Leitor/lib/aging.mjs`, `0274` e `0277` aplicadas; ligado na rodada (`fn_reconciliar_caso`) pela `0278`, aplicada em 13/11/2026 por decisão do dono | Σ aberto × Clientes/Fornecedores fecha, ou a divergência aparece no book |
| 1.A3 | **Tela de envio das bases volumosas** (antiga ME2): tipo, progresso, confirmação do mapeamento, resultado | P1 · G0 | 1.A1 | Claude (portal) | DESENVOLVER | Vistoria no navegador com um analista de teste, base de 1M de linhas sem travar a aba |
| 1.A4 | **OFX lido e conciliado** (antiga MB5): saldo inicial + Σ transações = saldo final, por conta e mês | P1 · G0 | — | Claude (Leitor) | CORRIGIR. Só o envelope do OFX é lido: contagem de transações e presença do saldo (`Leitor/lib/envelope.mjs`) | Fecha em toda conta e mês, ou a divergência é declarada |
| 1.A5 | **A linha tem endereço** (antigas MA2–MA4): toda linha extraída com `ln`; toda linha do documento com destino; valor sem trecho literal abre pendência | P1 · G0 | 1.B1 | Claude (n8n + banco) | CORRIGIR. Coluna `ln` existe (`0270`) e `fato_financeiro` (`0302`) está aplicada, mas **0 das 138.931 linhas têm `ln`** (ESTADO, sessão 131) | Linha com destino declarado ≥ 99,9%; falha silenciosa = 0 |
| 1.A6 | **Regressão no corpus real e portão da extração** (antigas MA1, MA5) | P1 · G0 | 1.A5, 1.B1 | Claude · Dono paga a rodada | DESENVOLVER (sem registro de conclusão) | Documento com extração falha ou incompleta ≤ 5%, cada um com causa; custo por book medido e registrado (`medir-custo-book.mjs`), com alerta acima de US$ 5 (D5: o teto só é fixado depois do piloto) |
| 1.A7 | **Aceite financeiro do book** (antiga MD2) | P1 | 1.A2, 1.A6 | Dono | DESENVOLVER | ≥ 95% dos documentos com linha; toda diferença explicada |
| 1.A8 | **Perímetro do grupo** (antiga MD1), só se o 1º mandato for grupo | P2 | — | Claude | CORRIGIR (em parte): `0179`–`0183` (entidade, perímetro, controle comum) | Perímetro declarado pela tela no mandato |
| 1.A9 | **CNAB de retorno e razão contábil** (antiga MB6): liquidações por dia e por sacado, cruzadas com o AR; razão em CSV/XLSX, Σ por conta × mês contra o balancete | P2 | 1.A1 | Claude (`Leitor/`) | CORRIGIR. A família CNAB é reconhecida no envelope (`Leitor/lib/familia.mjs`); o conteúdo do CNAB de retorno e o razão não são lidos | Liquidações cruzadas com o AR e razão conferido contra o balancete, ou divergência declarada |
| 1.A10 | **Número novo × número reapresentado, por período** (função 3 do `DESENHO_QUATRO_FUNCOES_2026-11.md`, aprovada em 13/11): quando o balanço de um ano traz o anterior com outro número, o book mostra o igual, o novo e o reapresentado | P2 | 1.A5 | Claude (banco + export) | DESENVOLVER. Não há nada em código (nenhuma ocorrência de "reapresentad" nas migrations); o desenho técnico está no §3 do DESENHO | Num mandato de teste com um ano reapresentado, o book marca cada número como igual, novo ou reapresentado, e a diferença aparece |

### Trilha B — Extração (D3), captação externa e cruzamento (Conferidor)

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.B1 | **Extração por código primeiro**; IA só onde o código falhar (D3) | P1 · G0 | — | Claude | CORRIGIR. Leitores existem para estruturados; PDF vai direto à IA (`N8N/lib/extract.mjs`) e **XLSX/CSV também vão ao modelo**, convertidos em texto (`N8N/lib/spreadsheet.mjs`): o balancete em planilha, caso comum, ainda não passa pelo código primeiro | Cada formato tem caminho declarado (código ou IA) e o motivo; contagem de páginas por caminho |
| 1.B2 | **IA revisora** em PDF e imagem; estruturados conferidos em SQL (D3) | P1 | 1.B1, 0.1 (provedor) | Claude | DESENVOLVER | Toda extração de PDF/imagem tem revisão registrada; divergência vira pendência |
| 1.B3 | **Captação do Registrato/SCR** (C5): obrigatório no Kit; o cliente baixa no gov.br e envia | P1 · G0 | 1.G1 | Claude (Leitor + banco) | DESENVOLVER | Registrato lido; item obrigatório do Kit; ausente = pendência com efeito |
| 1.B4 | **Captação de SPED** (ECD, ECF, EFD) como fonte externa do cruzamento | P1 · G0 | — | Claude | CORRIGIR (em parte): leitura (`Leitor/`, suíte "envio oficial"). Falta usá-lo como referência | SPED lido vira fonte de referência do cruzamento |
| 1.B5 | **Cruzamento** extração × captação: externo com maior peso, **os dois valores guardados**, veredito (divergências · resolvido pela régua B3b-1 · humano · sugestões), divergência relevante vira achado (D3) | P1 · G0 | 1.B3, 1.B4, 1.A4, 1.D6 | Claude (banco) | DESENVOLVER. Hoje só existe reconciliação interna (`fn_registrar_reconciliacao`) | Num mandato de teste com divergência plantada, o veredito a aponta; os dois valores consultáveis; teste reprova se um valor for sobrescrito |
| 1.B6 | **Proveniência por dado** (N-C7a): fonte, data de coleta, autorização, versão do diagnóstico | P1 | 1.B7 | Claude (banco) | CORRIGIR. Proveniência por linha e ano existe (`0125`, `0270`); faltam autorização e versão | Todo dado do book responde as 4 perguntas |
| 1.B7 | **Registro de autorização geral por cliente** (N-C7b): data, fontes, finalidade | P1 · G0 | — | Claude (banco) | DESENVOLVER | Consulta externa sem autorização registrada é **recusada no banco** (medido não-vazio) |

### Trilha C — Dados de mercado captados e atualizados (agente Mercado)

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.C1 | **Séries macro do BCB** (IPCA, IGP-M, INPC, Selic, CDI) | P1 | — | Claude | CORRIGIR. Captação existe: `0025`, `N8N/lib/macro.mjs`; agendamento diário no `N8N/workflow.macro.json` (`scheduleTrigger`). Execução em produção **não conferida**; **não há alerta de frescor** (série vencida não avisa) | Série com data da última atualização visível e alerta quando vencida |
| 1.C2 | **Focus e juros por modalidade** (BCB) | P1 · G0 | — | Claude (n8n + banco) | CORRIGIR. Focus já é captado (expectativas anuais de IPCA, Selic, IGP-M, PIB e câmbio em `indice_macro_expectativa`, `0025`; `N8N/lib/macro.mjs`, `INDICADORES_FOCUS`). Juros por modalidade: DESENVOLVER | Juros por modalidade gravados com data e fonte; atualização automática medida para as duas séries; alerta quando vencida |
| 1.C3 | **CVM** (empresas do setor), **IBGE** e **CAGED/RAIS** | P1 · G0 | — | Claude | IBGE: em parte (IPCA via SIDRA, só como conferência cruzada, `N8N/lib/macro.mjs`). CVM e CAGED/RAIS: DESENVOLVER | Idem, por fonte, com alerta quando vencida; fonte que falhou aparece como "falhou", não como vazia |
| 1.C4 | **Painel de frescor**: cada fonte com última atualização, estado e efeito | P2 | 1.C1–1.C3 | Claude (portal) | DESENVOLVER | Fonte vencida aparece vencida |
| 1.C5 | Demais fontes do slide 6 (ANEEL/CCEE, ANTT/ANP, SUSEP, FipeZAP) | P1 | 1.C3 | Claude | DESENVOLVER | Por fonte, como 1.C3 (inclusive o alerta quando vencida). A K6 pede **todos** os dados de mercado no piloto: tirá-lo do piloto exige decisão registrada do dono |

### Trilha D — Base dos agentes

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.D1 | **Contrato agente × motor** (B2, B4): entrada por permissão, saída estruturada que cita número do motor e evidência; agente que devolve número próprio é recusado | P1 · G0 | — | Claude | DESENVOLVER | Teste com um agente que inventa um número: a saída é recusada (medido não-vazio) |
| 1.D2 | **Memória central** por organização e mandato; agentes sem memória própria | P1 | 1.F5 | Claude (banco) | CORRIGIR. Base central existe; separação por organização não | Agente de um mandato não lê outro (teste reprova se ler) |
| 1.D3 | **Orquestração e hospedagem dos agentes**, na plataforma escolhida | P1 · G0 | **0.1** | Claude | DESENVOLVER. Hoje: estados no banco + n8n disparando | Uma rodada completa de ponta a ponta num mandato de teste, com estado persistido e retomável |
| 1.D4 | **Supervisor/Orquestrador** (B3, B3b-1, L5): 1ª rodada independente, consolidação, debate sem limite fixo, decide só baixo impacto, notifica toda divergência | P1 · G0 | 1.D1, 1.D3, 1.D6 | Claude | DESENVOLVER | Num caso com divergência plantada acima da régua, vai ao humano; abaixo, decide e notifica; os especialistas da 1ª rodada não veem conclusões alheias |
| 1.D5 | **Auditor Independente** (B4, B5): revisa a execução, usa o motor, até 3 tentativas (nunca recalcular), depois resumo + dossiê ao analista (N-B5a) | P1 · G0 | 1.D1, 1.D3 | Claude | DESENVOLVER. O equivalente hoje são as conferências SQL e o Portão 2 | Erro plantado é pego; após 3 falhas chega à fila com resumo e dossiê |
| 1.D6 | **Réguas parametrizadas e versionadas**: baixo impacto (B3b-1) e gravidade (G5); agente só sobe o nível | P1 · G0 | — | Claude (banco) | DESENVOLVER. "Severidade" existe nas pendências, sem régua por impacto | Mudar a régua gera versão nova; teste reprova se um agente descer o nível |
| 1.D7 | **Fila de decisão humana** (N-B5a, N-B5b, E5): campos estruturados, justificativa obrigatória, evidência, prazos por gravidade, aviso na metade, escalonamento ao Sócio | P1 · G0 | 1.D6 | Claude (banco + portal) | CORRIGIR. Pendências existem (`0001`, `0109`); prazos e escalonamento não | Pendência crítica vencida sobe ao Sócio (teste com relógio simulado) |
| 1.D8 | **Dois ou mais provedores de IA** com troca automática por tarefa e roteamento por região do cliente (D1, D2) | P1 | 0.1, 0.7 | Claude (n8n) | CORRIGIR. Dois dialetos por variável `IA_PROVEDOR` (`N8N/lib/provedor.mjs`), sem troca automática | Provedor derrubado em teste → a tarefa segue no outro; cliente "só Brasil" nunca sai do Brasil |
| 1.D9 | **Custo medido por etapa e por agente**, alerta acima de US$ 5 por diagnóstico (D5) | P1 · G0 | 1.D3 | Claude | CORRIGIR. Custo por lote existe (`0115`, `0135`), não por agente | Relatório por diagnóstico com custo por etapa e agente; alerta disparado num caso de teste |
| 1.D10 | **Observabilidade da IA** (H5), na ferramenta escolhida | P2 | 0.1, 1.D3 | Claude | DESENVOLVER | Toda chamada de agente rastreável (entrada, saída, custo, tempo) |

### Trilha E — Agentes de análise do piloto

Cada agente: definir as frentes de diligência que cobre (B6), construir sobre 1.D1, medir no gabarito. O dado externo que cada um usa passa pelo portão dele (Espec. 15, §5A), em modo sombra no piloto (Trilha K).

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.E1 | **Conferidor** (D3-3): veredito do cruzamento | P1 · G0 | 1.B5, 1.D4 | Claude | DESENVOLVER | Veredito num mandato real da Partners, revisado pelo analista |
| 1.E2 | **Dívida**: mapa, covenants, capacidade, cruzamento com o Registrato | P1 · G0 | 1.B3, 1.D4 | Claude | CORRIGIR. Mapa da dívida existe (`portal/src/lib/mapa-da-divida.ts`); covenants só como fato lido do texto do documento: `covenant_rompido`, gravidade crítica (`0148_o_fato_que_o_documento_diz_em_texto.sql:92`, extraído em `N8N/lib/extract.mjs`). Não há covenant calculado a partir dos contratos e índices | Mapa conciliado com o Registrato; covenant calculado a partir do contrato e dos índices do motor; rompido vira crítico, conferido contra o fato `covenant_rompido` do texto |
| 1.E3 | **Caixa**: liquidez, giro, 13 semanas (calendário × permanente) | P1 · G0 | 1.A2, 1.A4, 1.D4 | Claude | CORRIGIR. NCG e aging existem; 13 semanas não | Fluxo de 13 semanas em fórmula no book, a partir do OFX e do aging |
| 1.E4 | **Mercado**: juro por contrato × BCB, despesa × setor e região | P1 · G0 | 1.C2, 1.C3, 1.D4 | Claude | DESENVOLVER | Cada contrato com a taxa de mercado ao lado e a fonte |
| 1.E5 | **Medição de cada agente no gabarito** (D4, D6) | P1 | 1.J2, 1.E1–1.E4 | Claude · Dono rotula | DESENVOLVER | Acerto por agente publicado; agente abaixo do alvo fica em N1 |

### Trilha F — Aprovação, papéis e isolamento

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.F1 | **Papel Técnico** separado (E2): aprova mudança técnica; quem propõe não aprova | P1 · G0 | — | Claude (banco) | DESENVOLVER. Papéis hoje: `socio`, `analista`, `leitura` (`0216`) | Tentativa de autoaprovação reprova no banco |
| 1.F2 | **Segundo revisor** (E1, R1): obrigatório no que vai para fora ou tem ressalva; no piloto, analista da Partners, só nos mandatos da Partners | P1 · G0 | 1.F1, 1.F5 | Claude · **Analista da Partners [a indicar]** | DESENVOLVER | Diagnóstico para fora sem segundo revisor não sai (teste); o revisor não vê outros mandatos |
| 1.F3 | **Limite de ressalvas** (E3, E3-1) e seção "limitações relevantes" | P1 | 1.D6, 1.D7 | Claude | DESENVOLVER | 4ª ressalva alta exige Sócio; o PDF traz a seção |
| 1.F4 | **Botão "Conferência"** por documento e estados do Kit recebido → extraído → cruzado → conferido (E6) | P1 · G0 | 1.B5 | Claude (portal + banco) | CORRIGIR. Estados recebido, extraído e conferido existem; "cruzado" e o botão não | Kit mostra os 4 estados; conferência registra quem, quando, qual versão |
| 1.F5 | **Organização + RLS por organização** (H4) e **teste automático de vazamento**, que precisa reprovar | P1 · G0 | — | Claude (banco) | DESENVOLVER. RLS por mandato existe (`0216`, `Supabase/test/acesso_por_caso.test.sql`); organização não | Teste de vazamento entre duas organizações reprova com a política desligada e passa com ela |
| 1.F6 | **Versões de diagnóstico aprovadas preservadas**; nova conclusão passa por nova aprovação (v0.1.2 §8, N-B5c) | P1 | 1.D7 | Claude | CORRIGIR. Histórico de versões de documento existe; de diagnóstico, não | Reabrir um diagnóstico gera versão nova; a aprovada continua consultável |

### Trilha G — Portal do cliente

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.G1 | **Envio e acompanhamento pelo cliente** (A5): link seguro por mandato (decisão G3) | P1 · G0 | 1.F5 | Claude (portal) | CORRIGIR. Envio por token existe (`N8N/lib/assinatura-do-envio.mjs`, `0216`, `0223`); desenho aprovado em `DESENHO_QUATRO_FUNCOES_2026-11.md` §2 | Cliente envia e vê o Kit e o andamento do próprio mandato, e nada mais (teste) |
| 1.G2 | **O cliente não vê os agentes** (L6): vê diagnóstico, fonte de cada número e aprovação humana | P2 | 1.G1 | Claude (portal) | DESENVOLVER | Varredura das telas do cliente não acha nome de agente |

### Trilha H — Dossiê de processos e notícias

Absorve a trilha C do `PLANO_MVP_2026-11` (MC0–MC8).

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.H1 | **Decisões e jurídico** (antiga MC0): base legal para consultar pessoa física, texto da autorização, provedor de processos, fonte de notícias | P1 | 1.B7 | Dono · Advogado | DESENVOLVER | As quatro respostas registradas |
| 1.H2 | **Pessoas vinculadas e fontes públicas da empresa** (Receita/QSA, CEIS/CNEP, PGFN) | P1 | 1.H1 | Claude | DESENVOLVER. Zero ocorrência em código | Uma linha por entidade × fonte por rodada, inclusive a vazia |
| 1.H3 | **Processos** por CPF/CNPJ (provedor) e cruzamento com contingências; achado só pelo nome = possível homônimo | P1 | 1.H1, 1.H2 | Claude · Fornecedor | DESENVOLVER. Só existe o fato `litigio_relevante` lido do texto do documento (`0148`) | Nenhum processo achado só pelo nome contado como confirmado |
| 1.H4 | **Notícias** por razão social e por sócio + empresa | P1 | 1.H1 | Claude | DESENVOLVER | Título, veículo, data, link e trecho por notícia |
| 1.H5 | **O dossiê** no portal e no book, com o estado de cada fonte (encontrado, nada encontrado, falhou, não consultado) | P1 | 1.H2–1.H4 | Claude | DESENVOLVER | Nenhuma pessoa vinculada sem estado por fonte |

### Trilha I — Entregáveis

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.I1 | **Excel com cada número ligado ao documento e à página** ou à fonte externa (G4) | P1 | 1.A5, 1.B6 | Claude (export) | CORRIGIR. Excel em fórmula existe (`portal/src/lib/export-modelagem.ts`); zero link | Cada número do book abre a página de origem |
| 1.I2 | **Relatório em PDF** com autoria Oria Digital e "limitações relevantes" | P1 | 1.F3 | Claude | DESENVOLVER. Nenhuma biblioteca de PDF no portal | PDF de um mandato real revisado pelo segundo revisor |
| 1.I3 | **Relatório interno** completo (erros, pendências, auditoria) × do cliente | P2 | 1.D5 | Claude | CORRIGIR. O relatório interno existe como as telas do mandato | Os dois relatórios saem do mesmo diagnóstico, com conteúdo diferente por regra |

### Trilha K — Score de confiabilidade do dado externo ([Espec. 15](../../Arquitetura%20do%20Sistema/2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md))

Pedido do dono (23–24/11/2026): cada dado captado **fora** do cliente passa por um portão em cada
agente, e só o de alta confiabilidade segue sozinho. **No piloto, os vetos e os pisos já bloqueiam**
(D15.4): veto reprova, piso falho (inclusive as travas) manda para REVISÃO, que qualquer analista
pode liberar com justificativa (D15.3). **O score ponderado e a cobertura rodam em modo sombra**
(calculam, gravam e mostram, sem barrar); o bloqueio pelo score vem na Fase 3 (3.8, 3.9), depois de medido. Os pesos, mínimos e pisos de cada agente estão
**só** na Espec. 15, §5A (uma fonte por assunto); aqui fica a ordem de construção.

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.K1 | **Catálogo das fontes externas** (`fonte_externa`, Espec. 15 §7): origem (A1), periodicidade e prazo crítico (B2), origem compartilhada (A4), se o dado é opinativo, base legal típica | P2 | 0.13 | Claude (banco) | DESENVOLVER | Toda fonte captada no piloto (1.B3, 1.B4, 1.C1–1.C5, 1.H2–1.H4) está no catálogo; fonte sem origem declarada aparece como "sem origem", nunca em branco |
| 1.K2 | **Vetos do portão no banco** (§4, passo 1): origem não declarada, validade por registro, custódia de documento oficial trazido pelo cliente (recibo do SPED e do Registrato), prazo crítico pela data do uso, "nada consta" sem execução e sem cobertura (regra 2), base legal **por destino** (regra 1). Reusa o que já é P1 em 1.B7 (autorização), 1.C3 (falhou ≠ vazio) e 1.H3 (homônimo) | P1 | 1.K1, 1.B7 | Claude (banco) | DESENVOLVER | Cada veto com invariante medido não-vazio (regra 2 do projeto): plantar a falha, ver o portão reprovar, contar os asserts |
| 1.K3 | **Portão de cada agente do piloto: pisos bloqueando, score em sombra** (§5A, D15.4): notas por dimensão com estado (medida, `na`, `nm`), cobertura, teto da fonte em estreia (regra 7); `avaliacao_dado`, `portao_regra` e `portao_decisao`; portões do **Captador** (quarentena), **Conferidor**, **Mercado**, **Caixa**, **Dívida** e do **book**. Reusa o dial (`fn_dial_permite_auto`, `0127`) em N0 | P1 | 1.K2, 1.B5, 1.B6, 1.D3 | Claude (banco) | DESENVOLVER. Os 13 casos de referência existem em `15_anexos/casos_do_score.py` | Toda observação externa usada num mandato do piloto tem avaliação e decisão de portão gravadas por agente, nenhuma em branco; as decisões gravadas para os 13 casos batem com `casos_do_score.py` (o script é o oráculo do teste) |
| 1.K4 | **Propagação pelo menor score** (regra 3) e **frescor pela data do uso** (regra 4): número calculado herda o menor score e o pior resultado dos insumos | P2 | 1.K3, 1.I1 | Claude (banco + export) | DESENVOLVER | Num mandato de teste, uma soma com um insumo em REVISÃO sai em REVISÃO no book (teste reprova sem a propagação) |
| 1.K5 | **Painel do score**, ao lado do painel de frescor (1.C4): por dado e por agente, o resultado, o score, a cobertura e o motivo | P2 | 1.K3, 1.C4 | Claude (portal) | DESENVOLVER. Proposta visual: `15_anexos/Portoes_de_Confiabilidade_Oria_v2.html` | Dado em REVISÃO mostra o motivo e o efeito; dado não avaliado aparece como não avaliado, nunca como aprovado |

**Em que fase nasce o portão de cada agente.** O portão nasce junto com o agente que o usa. Nenhum
item de agente passa a depender da Trilha K: o agente funciona sem o portão, e o 1.K3 liga o portão
de cada um quando fica pronto (pisos bloqueando, score em sombra).

| Agente | Item do agente | Fase do portão | O que entra junto |
|---|---|---|---|
| Captador (funções do piloto) | Trilhas B e C | 1 (1.K3) | Quarentena na entrada; conflito guarda as duas versões |
| Conferidor | 1.E1 | 1 (1.K3) | Agregador nunca serve de régua; dado opinativo não serve de referência |
| Mercado | 1.E4 | 1 (1.K3) | Frescor pela data do uso (1.K4) |
| Caixa | 1.E3 | 1 (1.K3) | Em extrato, o saldo tem de fechar |
| Dívida | 1.E2 | 1 (1.K3) | Recibo do Registrato como veto de custódia (1.K2) |
| Supervisor | 1.D4 | 1 | **Sem pesos:** só repassa o dado APROVADO no portão do agente de destino |
| Auditor | 1.D5 | 1 | **Sem pesos:** confere todo uso no `portao_decisao`, mais 5% dos aprovados e todos os que passaram com até 5 pontos de folga (regra 6) |
| Book (Excel) | 1.I1 | 1 (1.K3, 1.K4) | Portão "Entregas" aplicado a cada número do book |
| Risco | 2.2 | 2 (2.18) | Dado opinativo passa só aqui, rotulado como opinião; "nada consta" só com cobertura |
| Estrategista | 2.3 | 2 (2.18) | Nenhum dado opinativo nem contestado como premissa |
| Entregas (agente) | 2.6 | 2 (2.18) | Base legal por destino: sigilo bancário e licença de bureau para terceiros |
| Captador formal | 2.1 | 2 (2.18) | Assume o portão de entrada das funções do piloto |
| Monitoramento | 2.8 | 2 (2.18) | Reabre o portão quando o score de um dado em uso cai abaixo do mínimo |
| Autoaprimoramento | 2.10 | 2 (2.19) | **Sem pesos:** lê os furos de portão e propõe ajustes; quem aplica é um humano |
| Todos | — | 3 (3.8, 3.9) | Calibração e bloqueio de verdade |

### Trilha J — Medição e gabarito

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.J1 | **Medição automática por mandato** (J6): dias, horas de analista, custo de IA e dados, erros por etapa e agente, achados em R$ | P1 · G0 | 1.D9 | Claude | DESENVOLVER. Custo por lote existe; o resto não | Painel por mandato com as 6 medidas preenchidas num mandato real |
| 1.J2 | **Gabarito de 30–50 páginas reais**, conferido célula a célula, com parte oculta (D4, F5) | P1 | — | **Dono** (D4-1) · Claude prepara | CORRIGIR. Gabarito rotulável existe (`0126`, `0130`); quantas amostras estão rotuladas não foi medido | 30–50 páginas rotuladas; parte oculta inacessível ao agente |

### Portão G1 — piloto concluído e medido

- Todos os itens P1 da Fase 1 fechados (a regra da seção 1). Em particular:
- Pelo menos um mandato real da Partners do envio à entrega, com **segundo revisor**.
- As 6 medidas da J6 preenchidas; o [modelo de projeção](../01_negocio/MODELO_DE_PROJECAO.md) recebe os
  primeiros valores.
- Conferidor, Dívida, Caixa e Mercado medidos no gabarito; Supervisor e Auditor rodaram (sinal positivo
  de execução, regra 7).
- Todas as fontes de mercado do piloto (1.C1–1.C3 e 1.C5) com data de atualização e alerta de frescor.
- O **dossiê de processos e notícias** (1.H5) entregue no mandato, com o estado de cada fonte (K6).

---

## 6. FASE 2 — Restante da v1

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 2.1 | **Agente Captador** formal (extração + captação como agente) | P2 | G1 | Claude | DESENVOLVER | Rodada com o Captador no lugar das funções do piloto, sem regressão no gabarito |
| 2.2 | **Agente Risco** (processos, protestos, bureaus, dívida ativa) | P2 | 1.H5, 2.4 | Claude | DESENVOLVER. Base: fatos `litigio_relevante` e `garantia_dada` (`0148`) | Risco classificado com a fonte |
| 2.3 | **Agente Estrategista** e motor de cenários: cortes, renegociação, simulação de propostas aos credores (B7) | P2 | G1 | Claude | CORRIGIR. Plano em 3 cenários existe (`portal/src/lib/modelo-institucional.ts`); simulação não | Proposta simulada (carência, desconto, dinheiro novo) em fórmula; humano decide |
| 2.4 | **Integrador de dados pagos** (C2) com teto por mandato (N-C6b) | P2 | Cotação; 1.B7 | Dono (contrato) · Claude | DESENVOLVER | Custo gravado por consulta; consulta acima do teto bloqueada |
| 2.5 | **Open Finance** via integradora regulada (C4); upload manual sempre disponível | P2 | Parceria (Res. Conjunta 21/2026) | Dono · Fornecedor · Claude | DESENVOLVER | Extrato por Open Finance concilia como o OFX (1.A4) |
| 2.6 | **Agente Entregas** e apresentação a credores (G4) | P2 | 1.I1, 1.I2 | Claude | CORRIGIR. Apresentação `.pptx` existe (suíte em `.github/workflows/suites.yml`) | Apresentação com a prova de cada número |
| 2.7 | **Ajustes de EBITDA e QoE** sugeridos com evidência, aplicados só com aceite (B8) | P2 | 1.D7 | Claude | DESENVOLVER | Nenhum ajuste aplicado sem aceite (teste) |
| 2.8 | **Monitoramento** com agenda por cliente (decisão G1) | P1 | G1 | Claude | DESENVOLVER. Único agendamento em código é o macro | Reconsulta periódica gera alerta em mudança |
| 2.9 | **Relatório periódico** (decisão G2) e **alertas só no portal interno** | P1 | 2.8 | Claude | DESENVOLVER | Relatório mensal de um mandato em acompanhamento, revisado antes de ir ao cliente |
| 2.10 | **Autoaprimoramento — fase A** (F1, F1-3, F4, F5, F6, E4): só propõe prompts e regras; relatório semanal; erros validados pelo Auditor; bloqueio de escrita sobre o que mede | P2 | G1, 1.D5, 1.J2 | Claude · **Técnico** decide | DESENVOLVER | Relatório semanal gerado; tentativa de escrever no gabarito reprova |
| 2.11 | **Publicação por chave liga/desliga** e caminho gradual (F2, F3); migrations "acrescenta primeiro, remove depois"; erro grave fora da rotina com duas autorizações (v0.1.2 §10.2) | P2 | 0.9 | Claude | DESENVOLVER. O dial é autonomia, não chave de publicação | Desligar a chave numa cópia deixa os diagnósticos antigos iguais (teste de reversão) |
| 2.12 | **Retenção em três camadas** e expurgo com bloqueio por processo (I2) | P2 | Parecer jurídico | Claude · Advogado | DESENVOLVER | Expurgo de um mandato de teste apaga originais e preserva entregáveis; bloqueio impede |
| 2.13 | **Benchmarks próprios anonimizados** (C7) | P2 | 0.10, parecer jurídico | Claude | DESENVOLVER. A decisão C7 diz "desde já"; fica na Fase 2 porque depende do parecer jurídico (C7, seção 19.13) e da anonimização (0.10) | Base sem dado identificável; mandato sem cláusula fica de fora |
| 2.14 | **Consultoria-cliente** vê os mandatos dos clientes dela (L4) | P1 | 1.F5 | Claude | DESENVOLVER | Teste de vazamento entre consultorias reprova sem a política |
| 2.15 | **Trilha de auditoria com cadeia de hashes** e cópia externa imutável (H6) | P1 | 0.1 | Claude | CORRIGIR. Trilha só de acréscimo existe (`0215`, `0224`), sem hash encadeado | Alterar um evento quebra a cadeia e gera alerta (teste) |
| 2.16 | **Login com verificação em duas etapas** (decisão G3) | P1 | 1.G1 | Claude (portal) | DESENVOLVER | Login sem segundo fator recusado |
| 2.17 | **RIPD revisto para o primeiro cliente além da Partners** (I5): dados, fluxos e controles do novo cliente | P1 | 0.8, 2.14 | Claude (parte técnica) · Advogado (parte jurídica) | DESENVOLVER | RIPD revisto, com a parte jurídica validada por advogado, antes do primeiro mandato do novo cliente |
| 2.18 | **Portões do score dos agentes da Fase 2**, em modo sombra ([Espec. 15](../../Arquitetura%20do%20Sistema/2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md), §5A): Risco (opinião só aqui, rotulada; "nada consta" com cobertura), Estrategista, Entregas (base legal por destino, regra 1), Captador formal (assume o portão de entrada) e monitoramento (reabre o portão quando o score cai) | P2 | 1.K3, e o item de cada agente (2.1, 2.2, 2.3, 2.6, 2.8) | Claude | DESENVOLVER | Cada agente da Fase 2 grava a decisão de portão de todo dado externo que usa; os casos de bureau, processo e "nada consta" de `casos_do_score.py` batem com o gravado |
| 2.19 | **Revisão semanal dos furos de portão e alerta de carimbo** (regra 5): toda liberação humana de REVISÃO entra na revisão semanal (E4); portão em que o humano libera sem alterar mais de 95% dos casos gera alerta de calibração | P2 | 2.10, 1.K3 | Claude · **Técnico** decide | DESENVOLVER | Relatório semanal lista os furos por portão; alerta disparado num caso de teste com 96% de liberação sem alteração |

### Portão G2 — pronto para o primeiro cliente além da Partners

Todos os itens P1 da Fase 2 fechados: 2.8 e 2.9 (monitoramento e relatório periódico, que a v1 inclui pela
decisão A2), 2.14 (isolamento entre consultorias, com 1.F5), 2.15 e 2.16 (decisões H6 e G3) e 2.17 (RIPD
revisto para o novo cliente). E o primeiro cliente além da Partners definido pelo dono (decisão A6, nas
pendências).

---

## 7. FASE 3 — Evolução operacional

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 3.1 | **Produção para vários clientes** (H1, H7): redimensionar banco, arquivos e automação pela capacidade e pelo custo medidos no piloto, antes do primeiro cliente além da Partners. A infraestrutura de produção do próprio piloto é o 0.12 | P1 | 0.12, G1 | Dono · Claude | DESENVOLVER | Perda máxima de minutos medida |
| 3.2 | **Teste de recuperação trimestral** (H7) | P1 | 3.1 | Claude | DESENVOLVER | Volta em ≤ 4 h, banco + arquivos, tempo anotado |
| 3.3 | **Subir etapas a N2** com ~300 amostras e parte cega (D6) | P2 | 1.J2, 1.E5 | Claude · Dono rotula | CORRIGIR. O mecanismo de promoção existe (`0126` golden set, `0136` veredito, `0137` promoção automática, `0218` recorte), mas com a régua antiga: 30 vereditos e 0,95 de concordância. Não existe rebaixamento automático por piora | `golden_criterio` com ~300 amostras por etapa e tipo de documento, parte cega, limite inferior ≥ 95% (D6, D6-2); `auto_promocao` religada só depois; **piora medida rebaixa automaticamente** (D6), com teste que reprova sem o rebaixamento |
| 3.4 | **Gabarito refeito a cada semestre** (D4) | P2 | 1.J2 | [a indicar] | DESENVOLVER | Rodada semestral registrada |
| 3.5 | **Segundo revisor sempre** quando houver equipe (E1) | P2 | Contratação | **[a contratar]** | DESENVOLVER | Nenhuma autoaprovação, mesmo interna |
| 3.6 | **Preços e tetos** (J1, N-C6b, D5) a partir do piloto | P1 | G1 | Dono | DESENVOLVER | Valores registrados numa nova versão do registro |
| 3.7 | **Técnico separado do Sócio** (E2, K3) | P2 | Contratação | **[a contratar]** | DESENVOLVER | Mudança técnica aprovada por pessoa diferente do dono |
| 3.8 | **Calibração do score do dado externo** ([Espec. 15](../../Arquitetura%20do%20Sistema/2%20Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md), §9): gabarito do dado externo (parte cega), taxa de erro medida por resultado (APROVADO, REVISÃO) e por agente; ajuste de pesos, mínimos e teto **primeiro em `casos_do_score.py`**, depois no §5A; teto da fonte em estreia revisto quando ela tiver 30 conferências | P2 | 1.K3, 1.J2, 3.4 | Claude · Dono rotula e decide | DESENVOLVER | Taxa de erro por resultado e por agente publicada, com intervalo; se APROVADO erra tanto quanto REVISÃO, o desenho volta à mesa (decisão registrada) |
| 3.9 | **Bloqueio de verdade, em degraus, por agente** (§9, passo 6): alerta → ressalva → bloqueio, com **rebaixamento automático** quando o erro medido piora (D6), como no 3.3 | P2 | 3.8 | Claude · Dono fixa os pisos | DESENVOLVER | Cada portão ligado cita a decisão que fixou o piso; teste reprova sem o portão; piora medida rebaixa o portão sozinha |

### Portão G3 — produção para vários clientes

Todos os itens P1 da Fase 3 fechados: 3.1 e 3.2, com as metas da decisão H7 medidas num teste de recuperação real (banco + arquivos):
perda máxima de minutos e volta em até 4 h. 3.6 fechado (preços e tetos registrados). Os itens P2 da
Fase 3 podem seguir depois do portão.

## 8. FASE 4 — Arquitetura final e futuro (condicionada)

| ID | Tarefa | Condição | Situação |
|---|---|---|---|
| 4.1 | **Autoaprimoramento — fase B**: código, ferramentas e migrations (F1-1, F1-2) | ≥ 50 erros cometidos ou achados pelos agentes, validados pelo Auditor, em ≥ 3 etapas ou agentes (F1-1, F1-3) **e** ≥ 60% das propostas aprovadas pelo Técnico, mínimo de 10, sem causar piora (F1-2); decisão do Técnico e do Sócio | DESENVOLVER |
| 4.2 | **Certificado digital e procuração** do cliente (C3): e-CAC, NF-e, FGTS | Política de segurança + parecer jurídico | DESENVOLVER |
| 4.3 | **Registradoras de recebíveis** (C6): CERC, B3, Núclea | Parceria ou participante autorizado | DESENVOLVER |
| 4.4 | **Banco dedicado** para cliente regulado (H4) | Cliente que exigir | DESENVOLVER |
| 4.5 | **Autosserviço** (A4) | Decisão futura | DESENVOLVER |

## 9. O que depende de pessoas, terceiros ou decisões

- **Pessoas** (K3): analista da Partners como segundo revisor (1.F2) **[a indicar]** (o dono indica depois, 24/11/2026);
  o gabarito do piloto é montado pelo dono (1.J2, D4-1); Técnico separado (3.7) e equipe para segundo revisor sempre (3.5) **[a contratar]**.
- **Terceiros e decisões em aberto:** lista viva em
  [`08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md`](../08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md).

## 10. Paralelismo

Duas tarefas só andam ao mesmo tempo quando **não dependem uma da outra e não tocam os mesmos
arquivos** (`Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`). Quem comita é sempre a sessão
principal, uma tarefa por vez.

As ondas abaixo são as **camadas de dependência** das Fases 0 e 1, tiradas da coluna "Depende de": um
item só entra numa onda quando tudo de que ele depende está numa onda anterior. Todo item das duas
fases está em exatamente uma onda. **Dentro de uma onda**, os itens andam juntos só se tocam áreas
diferentes (banco · n8n · portal · `Leitor/` · trabalho do dono ou de terceiros); dois itens de banco na
mesma onda vão um depois do outro.

| Onda | Itens (prioridade P1 em negrito) |
|---|---|
| **1** | **0.1** · **0.2** · **0.4** · **0.5** · **0.6** · 0.11 · **1.A1** · **1.A4** · 1.A8 · **1.B1** · **1.B4** · **1.B7** · **1.C1** · **1.C2** · **1.C3** · **1.D1** · **1.D6** · **1.F1** · **1.F5** · **1.J2** · 0.13 |
| **2** | **0.3** · **0.7** · 0.9 · **1.A2** · **1.A3** · **1.A5** · 1.A9 · **1.B2** · **1.B6** · 1.C4 · **1.C5** · **1.D2** · **1.D3** · **1.D7** · **1.F2** · **1.G1** · **1.H1** · 1.K1 |
| **3** | **0.8** · 0.10 · **0.12** · **1.A6** · 1.A10 · **1.B3** · 1.D10 · **1.D4** · **1.D5** · **1.D8** · **1.D9** · **1.F3** · **1.F6** · 1.G2 · **1.H2** · **1.H4** · **1.I1** · **1.K2** |
| **4** | **1.A7** · **1.B5** · **1.E2** · **1.E3** · **1.E4** · **1.H3** · **1.I2** · 1.I3 · **1.J1** |
| **5** | **1.E1** · **1.F4** · **1.H5** · **1.K3** |
| **6** | **1.E5** · 1.K4 · 1.K5 |

O estudo de infraestrutura (0.1) está na onda 1 e é a primeira entrega (R2); a orquestração dos agentes
(1.D3) depende dele e só começa na onda 2.

Migrations nunca vão em paralelo entre si: a numeração é sequencial e a sonda conta por número.

## 11. Mapeamento dos planos anteriores

| Plano anterior | Para onde foi |
|---|---|
| `PLANO_MVP_2026-11` trilhas A, B, D | Fase 1, trilha A (MB0–MB3 e MB3c já feitas: 1.A1, 1.A2; MB5 → 1.A4; MB6 → 1.A9; MB7 → 1.A1–1.A3 (o agregado no banco e as abas de aging no book); MD1 → 1.A8; MD2 → 1.A7) |
| `PLANO_MVP_2026-11` trilha C | Fase 1, trilha H |
| `PLANO_MVP_2026-11` trilha E (ME1–ME5) | 1.A3 (ME2), 0.6 (ME3), 0.3 (ME4), 1.B7 e 2.15 (ME5). ME1 (defeitos do lote 2 que travam o uso) **não virou item**: a lista não foi reconferida nesta fase; está nas pendências |
| `PLANO_LINHA_A_LINHA` | 1.A5, 1.A6 |
| `DESENHO_QUATRO_FUNCOES_2026-11` | O desenho técnico segue válido. Função 1 (o envio fecha o item do Kit): feita (`0300`, `0301`). Função 2 (área do cliente): 1.G1. Função 3 (novo × reapresentado): 1.A10. Função 4 (a pendência vira achado): 1.B5 |
| `ARQUITETURA_ALVO_E_ROADMAP` fases F0–F4 | As decisões por componente seguem como referência técnica; as fases foram substituídas por este plano |
| `MAPA_DE_EXECUCAO` B1 (aceite da rodada real de 02/09) | Superado pelo aceite do book do piloto (1.A6 e 1.A7) |
| `MAPA_DE_EXECUCAO` B2 (recalibrar cobertura) | 1.A6 (regressão no corpus real e portão da extração) |
| `MAPA_DE_EXECUCAO` B3 (autonomia sem rotulagem) | Decidida em 21/08 (`0136`); revista pela D6 e D6-1: itens 0.5 e 3.3 |
| `MAPA_DE_EXECUCAO` B4 (dívidas do output) | Cenários: 2.3; apresentação a credores: 2.6. A aplicação da `0205` em produção não foi conferida nesta fase: está nas pendências |
| `MAPA_DE_EXECUCAO` B5 (eficiência) | Sem item: o próprio MAPA a dava como quase fechada e sem nada crítico |
| `MAPA_DE_EXECUCAO` B6 (operação) | 0.2, 0.3, 0.6 |
| `MAPA_DE_EXECUCAO` B7 (dado que não temos) | Dependências de terceiros, nas pendências (seção 2) |
| `MAPA_DE_EXECUCAO` B8 (fontes oficiais, Espec. 12) | 1.B3 e 1.B4 (Registrato e SPED); as fontes que exigem credencial do cliente (eSocial, e-CAC): 4.2 |
| `MAPA_DE_EXECUCAO` B9 (parceiros de dados, Espec. 13) | 1.H3 (processos), 2.4 (integrador), 2.5 (Open Finance), 4.3 (registradoras) |
| `PLANO_DE_EXECUCAO_2026-11` (30 fatias, 6 semanas) | Sem mapeamento item a item: foi o plano que o `PLANO_MVP_2026-11` recortou; o que dele seguia aberto está nas linhas do PLANO_MVP acima |
| `PRONTIDAO_POR_ESTAGIO` | Sem mapeamento item a item: é um inventário de 20/08/2026; os pontos abertos dele estão cobertos pelas trilhas A e B e pelos itens 0.5 e 3.3 |
| `1 Visão e Doutrina/03_MVP_E_ROADMAP` | Sem mapeamento item a item: o MVP "workflow completo em modo conservador" virou o piloto (Fase 1) e o roadmap "construir → calibrar" virou os itens 0.5 e 3.3 (autonomia medida) |
| `STATUS_POR_ETAPA_2026-11-11` (111 etapas) | Inventário usado nas trilhas; as etapas de valuation e recuperação de credores ficam para depois da v1, salvo decisão do dono; a apresentação a credores é o item 2.6 (decisão G4: depois do piloto) |

## 12. Andamento

Atualizado ao fim de cada rodada (agente `estado-e-handoff`, comando `/fechar`): o item, a situação
nova e a evidência. O estado do dia continua no `ESTADO.md`.

| Data | Item | Situação | Evidência |
|---|---|---|---|
| 19–23/11/2026 | Plano criado (Fase 4) | — | Este arquivo; PR da Fase 4 |
| 23/11/2026 | 2.18, 2.19 (novos) | DESENVOLVER | Pedido do dono: score de confiabilidade do dado externo e portões por etapa. Desenho e pesquisa na Espec. 15; nada construído |
| 24/11/2026 | 0.13, 1.K1–1.K5, 2.18, 2.19 (refeitos), 3.8, 3.9 | DESENVOLVER | O score do dado externo distribuído pelas fases (Espec. 15 §5A v2, aprovado pelo dono): decisões na Fase 0; base e portões dos agentes do piloto em sombra na Fase 1 (Trilha K); agentes da Fase 2; calibração e bloqueio na Fase 3. Os antigos 2.18 (catálogo e sombra) e 2.19 (portões) foram absorvidos pela 1.K1–1.K3 e pela 3.8–3.9 |
| 24/11/2026 | 0.13 | FEITO | Registro v0.1.6 (seção 22): D15, D15.1–D15.15, D4-1, J7. Respostas do dono que mudaram o plano: pisos bloqueiam já no piloto (D15.4, o 1.K3 vira P1); qualquer analista libera o dado em REVISÃO (D15.3); o dono monta o gabarito do piloto (D4-1, 1.J2) |
