# Plano de execução do Oria Digital (único, em vigor)

**Plano único** pedido pela decisão K1. Substitui todos os planos anteriores, que ficam como histórico
com uma nota "superado por" (lista em [`99_historico/README.md`](../99_historico/README.md)).
**Sem calendário** (K2): só sequência, dependências e critério de pronto.

- **Base:** registro de decisões [v0.1.3](../07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.3.html)
  e [workflow v0.3.0](../02_workflow_e_arquitetura/oria_digital_workflow_v0.3.0.html).
- **Situação conferida no código** em 19/11/2026, `main` em `e85ac9c`, migration mais nova `0302`.
  O banco de produção **não** foi consultado para este plano: o que está no banco é confirmado pela
  sonda (`select … from fn_instalacao_conferir() where not presente`).
- **Quem constrói hoje** (K3): o dono e o Claude. O Claude implementa, revisa e documenta; **nunca
  aprova**. Os papéis que dependem de pessoas que ainda não existem estão marcados
  **[a contratar]** ou **[a indicar]**.

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

O que cada decisão quer dizer está em [`04_regras_de_negocio/REGRAS_E_DEFINICOES.md`](../04_regras_de_negocio/REGRAS_E_DEFINICOES.md);
os agentes, em [`03_agentes/AGENTES.md`](../03_agentes/AGENTES.md); papéis e publicação, em
[`05_governanca/`](../05_governanca/MEMORIA_AUTOAPRIMORAMENTO_E_GOVERNANCA.md).

## 2. Visão geral: fases e portões

```
FASE 0  Fundação ─────────────► G0  pronto para o 1º mandato do piloto
FASE 1  Piloto com a Partners ─► G1  piloto concluído e medido   (1ª entrega da v1, K6)
FASE 2  Restante da v1 ────────► G2  pronto para o 1º cliente além da Partners
FASE 3  Evolução operacional ──► G3  produção definitiva
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
| Leitores determinísticos de SPED/EFD/CNAB/OFX/XML (`Leitor/`); leitor tabular e mapeamento de colunas (`Leitor/lib/tabela.mjs`, `mapeamento.mjs`, `0272`); aging conciliado com o balanço (`0274`, `0277`, aplicadas); proveniência por linha (`0125`, `0270`); séries macro do BCB (`0025`, `N8N/lib/macro.mjs`); gabarito rotulável (`0126`, `0130`); Kit pelo banco (`0300`, `0301`); Excel em fórmula; conferências de balanço, caixa e DRE; trilha só de acréscimo (`evento_auditoria`); RLS por mandato e papéis Sócio/Analista/Leitura (`0216`); custo por lote (`0115`, `0135`) | Dois dialetos de IA (OpenAI e Gemini) sem troca automática (`N8N/lib/provedor.mjs`); extração por IA sem IA revisora; envio por token sem área do cliente; dial de autonomia com a extração **em N2 sem medição** (`0041_dial_manda.sql:419`); `CODEOWNERS` que pede e não exige revisão | Agentes (todos), Supervisor, Auditor-agente; captação de Registrato, Open Finance, Focus/CVM/IBGE/CAGED; cruzamento com fonte externa; dossiê de processos e notícias; PDF; link número → página; organização (multi-cliente); papel Técnico; verificação em duas etapas; backup fora do Supabase; chave do n8n de mínimo privilégio (usa `service_role`); cadeia de hashes; expurgo; ambientes dev/teste separados; anonimização; monitoramento; feature flag |

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
| **0.5** | **Extração de volta a N1** (D6) até haver medição | P1 | — | Claude · Dono aplica | CORRIGIR. `0041_dial_manda.sql:419` põe `extracao_linhas_financeiras` em N2 com origem `sistema:0041`, sem medição | Dial em N1 em produção (sonda); linha extraída pede confirmação humana; teste reprova se voltar a N2 sem as ~300 amostras |
| **0.6** | **Proteção do `main`** (K4): regra de proteção com PR obrigatório, revisão do dono e CI verde | P1 | — | Dono (clique no GitHub) · Claude confere | CORRIGIR. `.github/CODEOWNERS` pede e não exige; proteção **não conferida** (ESTADO, sessão 132) | Push direto no `main` recusado (tentativa registrada) |
| **0.7** | **Contrato de dados com cada provedor de IA** (D1, K4): cláusulas-padrão da ANPD | P1 | 0.1 (quais provedores) | Dono · Advogado | DESENVOLVER | Contrato assinado com cada provedor usado no piloto; arquivo de referência guardado fora do repositório |
| **0.8** | **RIPD** (I5): relatório de impacto à proteção de dados — mapa de dados, fluxos e controles | P1 | 0.1, 0.7 | Claude (parte técnica) · Advogado (parte jurídica) | DESENVOLVER | Parte técnica escrita; parte jurídica validada por advogado |
| **0.9** | **Três ambientes** (H8): desenvolvimento, teste descartável por mudança, produção; nenhuma credencial de produção fora dela | P2 | 0.1 | Claude · Dono | CORRIGIR. Existe o banco de teste do CI (`Supabase/test/run.sh`, `tdf_test`) e a produção; não há dev separado | Os três existem; varredura não acha credencial de produção fora dela |
| **0.10** | **Anonimização** de dado real para teste (H8, F4) | P2 | 0.9 | Claude | DESENVOLVER | Cópia anonimizada de um mandato real roda a suíte; varredura não acha CNPJ/CPF/nome reais |
| **0.11** | **Alinhar duas especificações técnicas ao registro**: `Arquitetura do Sistema/2 Especificação/10_DADOS_RETENCAO_E_LGPD.md` (I2, H1, H7, H8) e `06_HUMAN_IN_THE_LOOP.md` (E1, E2, R1) | P3 | — | Claude · Dono | CORRIGIR. A 10 ainda marca os prazos [A CONFIRMAR]; a 06 ainda cita "revisor sênior / gerente" (linha 14) | As duas especificações não contradizem o registro v0.1.3 |

### Portão G0 — pronto para o primeiro mandato do piloto

Todos os itens **P1** da Fase 0 fechados (0.1 a 0.8) **e** os itens P1 da Fase 1 que o primeiro mandato
usa (marcados "G0" abaixo). Conferência: sonda sem ausências, backup e restauração medidos, contrato e
RIPD assinados.

---

## 5. FASE 1 — Piloto com a Oria Partners (primeira entrega da v1, K6)

Trilhas paralelas. Duas trilhas só andam juntas se não tocam os mesmos arquivos (seção 10).

### Trilha A — Book Excel confiável

Absorve as trilhas A, B e D do `PLANO_MVP_2026-11` e o `PLANO_LINHA_A_LINHA`.

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.A1 | **Leitura das bases volumosas** (AR, AP) em fluxo e mapeamento de colunas | P1 · G0 | — | Claude | FEITO com sintéticos: `Leitor/lib/tabela.mjs`, `mapeamento.mjs`, `0272` (aplicada). **Falta arquivo real** (DM7) | AR e AP reais da Partners lidos; linhas lidas = linhas do arquivo, ou descarte com motivo |
| 1.A2 | **Aging conciliado com o balanço** | P1 · G0 | 1.A1 | Claude | FEITO: `Leitor/lib/aging.mjs`, `0274` e `0277` aplicadas. A ligação na rodada (`fn_reconciliar_caso`) é decisão do dono | Σ aberto × Clientes/Fornecedores fecha, ou a divergência aparece no book |
| 1.A3 | **Tela de envio das bases volumosas** (antiga ME2): tipo, progresso, confirmação do mapeamento, resultado | P1 · G0 | 1.A1 | Claude (portal) | DESENVOLVER | Vistoria no navegador com um analista de teste, base de 1M de linhas sem travar a aba |
| 1.A4 | **OFX lido e conciliado** (antiga MB5): saldo inicial + Σ transações = saldo final, por conta e mês | P1 | — | Claude (Leitor) | CORRIGIR. Só o envelope do OFX é lido (`Leitor/lib/familia.mjs`) | Fecha em toda conta e mês, ou a divergência é declarada |
| 1.A5 | **A linha tem endereço** (antigas MA2–MA4): toda linha extraída com `ln`; toda linha do documento com destino; valor sem trecho literal abre pendência | P1 · G0 | 1.B1 | Claude (n8n + banco) | CORRIGIR. Coluna `ln` existe (`0270`) e `fato_financeiro` (`0302`) está aplicada, mas **0 das 138.931 linhas têm `ln`** (ESTADO, sessão 131) | Linha com destino declarado ≥ 99,9%; falha silenciosa = 0 |
| 1.A6 | **Regressão no corpus real e portão da extração** (antigas MA1, MA5) | P1 · G0 | 1.A5, 1.B1 | Claude · Dono paga a rodada | DESENVOLVER (sem registro de conclusão) | Documento com extração falha ou incompleta ≤ 5%, cada um com causa; custo por book ≤ US$ 5 (`medir-custo-book.mjs`) |
| 1.A7 | **Aceite financeiro do book** (antiga MD2) | P1 | 1.A2, 1.A6 | Dono | DESENVOLVER | ≥ 95% dos documentos com linha; toda diferença explicada |
| 1.A8 | **Perímetro do grupo** (antiga MD1), só se o 1º mandato for grupo | P2 | — | Claude | FEITO em parte: `0179`–`0183` (entidade, perímetro, controle comum) | Perímetro declarado pela tela no mandato |

### Trilha B — Extração (D3), captação externa e cruzamento (Conferidor)

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.B1 | **Extração por código primeiro**; IA só onde o código falhar (D3) | P1 · G0 | — | Claude | CORRIGIR. Leitores existem para estruturados; PDF vai direto à IA (`N8N/lib/extract.mjs`) | Cada formato tem caminho declarado (código ou IA) e o motivo; contagem de páginas por caminho |
| 1.B2 | **IA revisora** em PDF e imagem; estruturados conferidos em SQL (D3) | P1 | 1.B1, 0.1 (provedor) | Claude | DESENVOLVER | Toda extração de PDF/imagem tem revisão registrada; divergência vira pendência |
| 1.B3 | **Captação do Registrato/SCR** (C5): obrigatório no Kit; o cliente baixa no gov.br e envia | P1 · G0 | 1.G1 | Claude (Leitor + banco) | DESENVOLVER | Registrato lido; item obrigatório do Kit; ausente = pendência com efeito |
| 1.B4 | **Captação de SPED** (ECD, ECF, EFD) como fonte externa do cruzamento | P1 | — | Claude | FEITO em parte: leitura (`Leitor/`, suíte "envio oficial"). Falta usá-lo como referência | SPED lido vira fonte de referência do cruzamento |
| 1.B5 | **Cruzamento** extração × captação: externo com maior peso, **os dois valores guardados**, veredito (divergências · resolvido pela régua B3b-1 · humano · sugestões), divergência relevante vira achado (D3) | P1 · G0 | 1.B3, 1.B4, 1.A4, 1.D4 | Claude (banco) | DESENVOLVER. Hoje só existe reconciliação interna (`fn_registrar_reconciliacao`) | Num mandato de teste com divergência plantada, o veredito a aponta; os dois valores consultáveis; teste reprova se um valor for sobrescrito |
| 1.B6 | **Proveniência por dado** (N-C7a): fonte, data de coleta, autorização, versão do diagnóstico | P1 | 1.B7 | Claude (banco) | CORRIGIR. Proveniência por linha e ano existe (`0125`, `0270`); faltam autorização e versão | Todo dado do book responde as 4 perguntas |
| 1.B7 | **Registro de autorização geral por cliente** (N-C7b): data, fontes, finalidade | P1 · G0 | — | Claude (banco) | DESENVOLVER | Consulta externa sem autorização registrada é **recusada no banco** (medido não-vazio) |

### Trilha C — Dados de mercado captados e atualizados (agente Mercado)

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.C1 | **Séries macro do BCB** (IPCA, IGP-M, INPC, Selic, CDI) | P1 | — | Claude | FEITO: `0025`, `N8N/lib/macro.mjs`, `N8N/workflow.macro.json`. Agendamento **a conferir** | Série com data da última atualização visível e alerta quando vencida |
| 1.C2 | **Juros por modalidade e Focus** (BCB) | P1 | — | Claude (n8n + banco) | DESENVOLVER | Séries gravadas com data e fonte; atualização automática medida |
| 1.C3 | **CVM** (empresas do setor), **IBGE** e **CAGED/RAIS** | P1 | — | Claude | DESENVOLVER | Idem, por fonte; fonte que falhou aparece como "falhou", não como vazia |
| 1.C4 | **Painel de frescor**: cada fonte com última atualização, estado e efeito | P2 | 1.C1–1.C3 | Claude (portal) | DESENVOLVER | Fonte vencida aparece vencida |
| 1.C5 | Demais fontes do slide 5 (ANEEL/CCEE, ANTT/ANP, SUSEP, FipeZAP) | P3 | 1.C3 | Claude | DESENVOLVER | Por fonte, como 1.C3. **Pode ir para a Fase 2** se o piloto não precisar (decisão do dono) |

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
| 1.D9 | **Custo medido por etapa e por agente**, alerta acima de US$ 5 por diagnóstico (D5) | P1 | 1.D3 | Claude | CORRIGIR. Custo por lote existe (`0115`, `0135`), não por agente | Relatório por diagnóstico com custo por etapa e agente; alerta disparado num caso de teste |
| 1.D10 | **Observabilidade da IA** (H5), na ferramenta escolhida | P2 | 0.1, 1.D3 | Claude | DESENVOLVER | Toda chamada de agente rastreável (entrada, saída, custo, tempo) |

### Trilha E — Agentes de análise do piloto

Cada agente: definir as frentes de diligência que cobre (B6), construir sobre 1.D1, medir no gabarito.

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.E1 | **Conferidor** (D3-3): veredito do cruzamento | P1 · G0 | 1.B5, 1.D4 | Claude | DESENVOLVER | Veredito num mandato real da Partners, revisado pelo analista |
| 1.E2 | **Dívida**: mapa, covenants, capacidade, cruzamento com o Registrato | P1 · G0 | 1.B3, 1.D4 | Claude | CORRIGIR. Mapa da dívida existe (`portal/src/lib/mapa-da-divida.ts`); covenants não | Mapa conciliado com o Registrato; covenant rompido vira crítico |
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
| 1.G1 | **Envio e acompanhamento pelo cliente** (A5): link seguro por mandato (G3) | P1 · G0 | 1.F5 | Claude (portal) | CORRIGIR. Envio por token existe (`N8N/lib/assinatura-do-envio.mjs`, `0216`, `0223`); desenho aprovado em `DESENHO_QUATRO_FUNCOES_2026-11.md` §2 | Cliente envia e vê o Kit e o andamento do próprio mandato, e nada mais (teste) |
| 1.G2 | **O cliente não vê os agentes** (L6): vê diagnóstico, fonte de cada número e aprovação humana | P2 | 1.G1 | Claude (portal) | DESENVOLVER | Varredura das telas do cliente não acha nome de agente |

### Trilha H — Dossiê de processos e notícias

Absorve a trilha C do `PLANO_MVP_2026-11` (MC0–MC8).

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.H1 | **Decisões e jurídico** (antiga MC0): base legal para consultar pessoa física, texto da autorização, provedor de processos, fonte de notícias | P1 | 1.B7 | Dono · Advogado | DESENVOLVER | As quatro respostas registradas |
| 1.H2 | **Pessoas vinculadas e fontes públicas da empresa** (Receita/QSA, CEIS/CNEP, PGFN) | P1 | 1.H1 | Claude | DESENVOLVER. Zero ocorrência em código | Uma linha por entidade × fonte por rodada, inclusive a vazia |
| 1.H3 | **Processos** por CPF/CNPJ (provedor) e cruzamento com contingências; achado só pelo nome = possível homônimo | P1 | 1.H1, 1.H2 | Claude · Fornecedor | DESENVOLVER | Nenhum processo achado só pelo nome contado como confirmado |
| 1.H4 | **Notícias** por razão social e por sócio + empresa | P2 | 1.H1 | Claude | DESENVOLVER | Título, veículo, data, link e trecho por notícia |
| 1.H5 | **O dossiê** no portal e no book, com o estado de cada fonte (encontrado, nada encontrado, falhou, não consultado) | P1 | 1.H2–1.H4 | Claude | DESENVOLVER | Nenhuma pessoa vinculada sem estado por fonte |

### Trilha I — Entregáveis

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.I1 | **Excel com cada número ligado ao documento e à página** ou à fonte externa (G4) | P1 | 1.A5, 1.B6 | Claude (export) | CORRIGIR. Excel em fórmula existe (`portal/src/lib/export-modelagem.ts`); zero link | Cada número do book abre a página de origem |
| 1.I2 | **Relatório em PDF** com autoria Oria Digital e "limitações relevantes" | P1 | 1.F3 | Claude | DESENVOLVER. Nenhuma biblioteca de PDF no portal | PDF de um mandato real revisado pelo segundo revisor |
| 1.I3 | **Relatório interno** completo (erros, pendências, auditoria) × do cliente | P2 | 1.D5 | Claude | CORRIGIR. O relatório interno existe como as telas do mandato | Os dois relatórios saem do mesmo diagnóstico, com conteúdo diferente por regra |

### Trilha J — Medição e gabarito

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 1.J1 | **Medição automática por mandato** (J6): dias, horas de analista, custo de IA e dados, erros por etapa e agente, achados em R$ | P1 · G0 | 1.D9 | Claude | DESENVOLVER. Custo por lote existe; o resto não | Painel por mandato com as 6 medidas preenchidas num mandato real |
| 1.J2 | **Gabarito de 30–50 páginas reais**, conferido célula a célula, com parte oculta (D4, F5) | P1 | — | **Quem monta: [a indicar]** (D4) · Claude prepara | CORRIGIR. Gabarito rotulável existe (`0126`, `0130`); quantas amostras estão rotuladas não foi medido | 30–50 páginas rotuladas; parte oculta inacessível ao agente |

### Portão G1 — piloto concluído e medido

- Pelo menos um mandato real da Partners do envio à entrega, com **segundo revisor**.
- As 6 medidas da J6 preenchidas; o [modelo de projeção](../01_negocio/MODELO_DE_PROJECAO.md) recebe os
  primeiros valores.
- Conferidor, Dívida, Caixa e Mercado medidos no gabarito; Supervisor e Auditor rodaram (sinal positivo
  de execução, regra 7).
- Todas as fontes de mercado com data de atualização.

---

## 6. FASE 2 — Restante da v1

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 2.1 | **Agente Captador** formal (extração + captação como agente) | P2 | G1 | Claude | DESENVOLVER | Rodada com o Captador no lugar das funções do piloto, sem regressão no gabarito |
| 2.2 | **Agente Risco** (processos, protestos, bureaus, dívida ativa) | P2 | 1.H5, 2.4 | Claude | DESENVOLVER | Risco classificado com a fonte |
| 2.3 | **Agente Estrategista** e motor de cenários: cortes, renegociação, simulação de propostas aos credores (B7) | P2 | G1 | Claude | CORRIGIR. Plano em 3 cenários existe (`portal/src/lib/modelo-institucional.ts`); simulação não | Proposta simulada (carência, desconto, dinheiro novo) em fórmula; humano decide |
| 2.4 | **Integrador de dados pagos** (C2) com teto por mandato (N-C6b) | P2 | Cotação; 1.B7 | Dono (contrato) · Claude | DESENVOLVER | Custo gravado por consulta; consulta acima do teto bloqueada |
| 2.5 | **Open Finance** via integradora regulada (C4); upload manual sempre disponível | P2 | Parceria (Res. Conjunta 21/2026) | Dono · Fornecedor · Claude | DESENVOLVER | Extrato por Open Finance concilia como o OFX (1.A4) |
| 2.6 | **Agente Entregas** e apresentação a credores (G4) | P2 | 1.I1, 1.I2 | Claude | CORRIGIR. Apresentação `.pptx` existe (suíte em `.github/workflows/suites.yml`) | Apresentação com a prova de cada número |
| 2.7 | **Ajustes de EBITDA e QoE** sugeridos com evidência, aplicados só com aceite (B8) | P2 | 1.D7 | Claude | DESENVOLVER | Nenhum ajuste aplicado sem aceite (teste) |
| 2.8 | **Monitoramento** com agenda por cliente (G1) | P1 | G1 | Claude | DESENVOLVER. Único agendamento em código é o macro | Reconsulta periódica gera alerta em mudança |
| 2.9 | **Relatório periódico** (G2) e **alertas só no portal interno** | P1 | 2.8 | Claude | DESENVOLVER | Relatório mensal de um mandato em acompanhamento, revisado antes de ir ao cliente |
| 2.10 | **Autoaprimoramento — fase A** (F1, F1-3, F4, F5, F6, E4): só propõe prompts e regras; relatório semanal; erros validados pelo Auditor; bloqueio de escrita sobre o que mede | P2 | G1, 1.D5, 1.J2 | Claude · **Técnico** decide | DESENVOLVER | Relatório semanal gerado; tentativa de escrever no gabarito reprova |
| 2.11 | **Publicação por chave liga/desliga** e caminho gradual (F2, F3); migrations "acrescenta primeiro, remove depois"; erro grave fora da rotina com duas autorizações (v0.1.2 §10.2) | P2 | 0.9 | Claude | DESENVOLVER. O dial é autonomia, não chave de publicação | Desligar a chave numa cópia deixa os diagnósticos antigos iguais (teste de reversão) |
| 2.12 | **Retenção em três camadas** e expurgo com bloqueio por processo (I2) | P2 | Parecer jurídico | Claude · Advogado | DESENVOLVER | Expurgo de um mandato de teste apaga originais e preserva entregáveis; bloqueio impede |
| 2.13 | **Benchmarks próprios anonimizados** (C7) | P3 | 0.10, parecer jurídico | Claude | DESENVOLVER | Base sem dado identificável; mandato sem cláusula fica de fora |
| 2.14 | **Consultoria-cliente** vê os mandatos dos clientes dela (L4) | P2 | 1.F5 | Claude | DESENVOLVER | Teste de vazamento entre consultorias reprova sem a política |
| 2.15 | **Trilha de auditoria com cadeia de hashes** e cópia externa imutável (H6) | P1 | 0.1 | Claude | CORRIGIR. Trilha só de acréscimo existe (`0215`, `0224`), sem hash encadeado | Alterar um evento quebra a cadeia e gera alerta (teste) |
| 2.16 | **Login com verificação em duas etapas** (G3) | P1 | 1.G1 | Claude (portal) | DESENVOLVER | Login sem segundo fator recusado |

### Portão G2 — pronto para o primeiro cliente além da Partners

2.15 e 2.16 fechados (H6, G3), isolamento por organização provado (1.F5, 2.14), RIPD revisto para o
novo cliente, e o primeiro cliente definido (A6).

---

## 7. FASE 3 — Evolução operacional

| ID | Tarefa | Prio. | Depende de | Papel | Situação | Pronto quando |
|---|---|---|---|---|---|---|
| 3.1 | **Produção definitiva** (H1, H7): plano pago, backup contínuo, região São Paulo, cópia separada dos arquivos | P1 | 0.1, G1 | Dono · Claude | DESENVOLVER | Perda máxima de minutos medida |
| 3.2 | **Teste de recuperação trimestral** (H7) | P1 | 3.1 | Claude | DESENVOLVER | Volta em ≤ 4 h, banco + arquivos, tempo anotado |
| 3.3 | **Subir etapas a N2** com ~300 amostras e parte cega (D6) | P2 | 1.J2, 1.E5 | Claude · Dono rotula | DESENVOLVER | Limite inferior ≥ 98% por etapa e tipo de documento |
| 3.4 | **Gabarito refeito a cada semestre** (D4) | P2 | 1.J2 | [a indicar] | DESENVOLVER | Rodada semestral registrada |
| 3.5 | **Segundo revisor sempre** quando houver equipe (E1) | P2 | Contratação | **[a contratar]** | DESENVOLVER | Nenhuma autoaprovação, mesmo interna |
| 3.6 | **Preços e tetos** (J1, N-C6b, D5) a partir do piloto | P1 | G1 | Dono | DESENVOLVER | Valores registrados numa nova versão do registro |
| 3.7 | **Técnico separado do Sócio** (E2, K3) | P2 | Contratação | **[a contratar]** | DESENVOLVER | Mudança técnica aprovada por pessoa diferente do dono |

## 8. FASE 4 — Arquitetura final e futuro (condicionada)

| ID | Tarefa | Condição | Situação |
|---|---|---|---|
| 4.1 | **Autoaprimoramento — fase B**: código, ferramentas e migrations (F1-1, F1-2) | ≥ 50 erros validados em ≥ 3 etapas **e** ≥ 60% de propostas aprovadas (mín. 10); decisão do Técnico e do Sócio | DESENVOLVER |
| 4.2 | **Certificado digital e procuração** do cliente (C3): e-CAC, NF-e, FGTS | Política de segurança + parecer jurídico | DESENVOLVER |
| 4.3 | **Registradoras de recebíveis** (C6): CERC, B3, Núclea | Parceria ou participante autorizado | DESENVOLVER |
| 4.4 | **Banco dedicado** para cliente regulado (H4) | Cliente que exigir | DESENVOLVER |
| 4.5 | **Autosserviço** (A4) | Decisão futura | DESENVOLVER |

## 9. O que depende de pessoas, terceiros ou decisões

- **Pessoas** (K3): analista da Partners como segundo revisor (1.F2) **[a indicar]**; quem monta o gabarito
  (1.J2, D4) **[a indicar]**; Técnico separado (3.7) e equipe para segundo revisor sempre (3.5) **[a contratar]**.
- **Terceiros e decisões em aberto:** lista viva em
  [`08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md`](../08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md).

## 10. Paralelismo

Duas tarefas só andam ao mesmo tempo quando **não dependem uma da outra e não tocam os mesmos
arquivos** (`Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`). Quem comita é sempre a sessão
principal, uma tarefa por vez.

| Onda | Em paralelo | Por que não colidem |
|---|---|---|
| **1** | 0.1 (documento) · 0.2/0.3 (backup, fora do código) · 0.5 (migration do dial) · 1.A4 (`Leitor/`) · 1.C2 (n8n macro) | Documento × infraestrutura × uma migration × `Leitor/` × um gerador do n8n |
| **2** | 0.4 (n8n, credencial) · 1.F5 (migration de organização) · 1.A3 (portal, tela de envio) · 1.J2 (rotulagem) | n8n × banco × portal × trabalho do dono |
| **3** | 1.D1 + 1.D6 (banco: contrato e réguas) · 1.B3 (`Leitor/` + Kit) · 1.H1 (jurídico) | Migrations em sequência dentro da onda; `Leitor/` à parte |
| **4** (depois de 0.1) | 1.D3 → 1.D4/1.D5 (orquestração) · 1.B5 (banco: cruzamento) · 1.G1 (portal do cliente) | Plataforma nova × banco × portal |
| **5** | 1.E1–1.E4 (um agente por vez, mesma base) · 1.I1/1.I2 (export) · 1.H2–1.H5 | Agentes × export × dossiê |

Migrations nunca vão em paralelo entre si: a numeração é sequencial e a sonda conta por número.

## 11. Mapeamento dos planos anteriores

| Plano anterior | Para onde foi |
|---|---|
| `PLANO_MVP_2026-11` trilhas A, B, D | Fase 1, trilha A (MB0–MB3 e MB3c já feitas: 1.A1, 1.A2) |
| `PLANO_MVP_2026-11` trilha C | Fase 1, trilha H |
| `PLANO_MVP_2026-11` trilha E (ME1–ME5) | 1.A3 (ME2), 0.6 (ME3), 0.3 (ME4), 1.B7 e 2.15 (ME5) |
| `PLANO_LINHA_A_LINHA` | 1.A5, 1.A6 |
| `DESENHO_QUATRO_FUNCOES_2026-11` | O desenho técnico segue válido; a área do cliente virou 1.G1; o achado, 1.B5 |
| `ARQUITETURA_ALVO_E_ROADMAP` fases F0–F4 | As decisões por componente seguem como referência técnica; as fases foram substituídas por este plano |
| `MAPA_DE_EXECUCAO` B6 (operação) | 0.2, 0.3, 0.6 |
| `STATUS_POR_ETAPA_2026-11-11` (111 etapas) | Inventário usado nas trilhas; as etapas de valuation, recuperação de credores e apresentação de crédito ficam para depois da v1, salvo decisão do dono |

## 12. Andamento

Atualizado ao fim de cada rodada (agente `estado-e-handoff`, comando `/fechar`): o item, a situação
nova e a evidência. O estado do dia continua no `ESTADO.md`.

| Data | Item | Situação | Evidência |
|---|---|---|---|
| 19–23/11/2026 | Plano criado (Fase 4) | — | Este arquivo; PR da Fase 4 |
