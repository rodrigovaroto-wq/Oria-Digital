# Benchmark de interface — concorrentes do portal de diligência financeira

Data da pesquisa: 12/11/2026. Só fontes públicas na web. Nenhum produto foi usado de fato.

**Aviso de método.** Quase tudo vem de página de marketing, documentação ou changelog do próprio fornecedor.
Onde a fonte é concorrente falando do outro, está marcado.
Tipografia, cor, movimento e estado de carregamento quase nunca aparecem em texto público.
Onde não achei, está escrito "não encontrado". Nada aqui foi inferido de screenshot que eu não li.

---

## 1. Quem são os mais próximos, e por quê

O portal faz três coisas ao mesmo tempo: (1) recebe e confere documentos do cliente contra uma lista,
(2) extrai números com proveniência até a página, (3) entrega um modelo em Excel.
Nenhum concorrente faz as três. Cada um cobre uma ou duas.

| # | Produto | Categoria | Por que entra | Proximidade |
|---|---|---|---|---|
| 1 | **F2** | Extração/spreading de demonstrações de empresa fechada, com IA | Ingere data room inteiro, normaliza para plano de contas da casa, rastreia cada número até a célula/parágrafo com destaque amarelo, exporta para template Excel. É o mais parecido com o pipeline. | Direto |
| 2 | **Daloopa** | Extração e normalização de dados financeiros (empresa aberta) | Padrão de mercado em "clique no número e vá à fonte". Convenção de cor azul/preto no Excel. Só cobre companhia aberta. | Direto no padrão de proveniência |
| 3 | **DataSnipper** | Add-in de Excel para auditoria (evidência ligada à célula) | Referência de como marcar no Excel "conferido" (verde) e "divergência" (vermelho) ligado a um retângulo no documento. Público é auditor/FDD. | Adjacente forte (conferência) |
| 4 | **Hebbia (Matrix)** | IA para diligência e pesquisa | Grade documentos × perguntas, cada célula com citação; usado para varrer data room. Referência de leitura de fatos em texto (contingências, partes relacionadas). | Adjacente forte (fatos em texto) |
| 5 | **Datasite (Diligence/Prepare/Acquire)** | Data room com analytics e IA | Tracker de checklist ligado a pastas, dashboard de prontidão, "readiness reviews" que acham lacunas, IA que sugere documento faltante. É o "Kit Básico" deles. | Adjacente forte (recebimento) |
| 6 | **DealRoom** | Data room + gestão de request list | Request list com status, responsável, prioridade, prazo; upload casa sozinho com a solicitação e a fecha; "findings" (achados) por solicitação; visão do vendedor restrita. É o mais próximo das "pendências". | Adjacente forte (pendências) |
| 7 | **Ansarada** | Data room com scorecard de prontidão | Scorecard de 0 a 100% de completude, barra de progresso, guia por tópico explicando por que cada documento importa. | Adjacente (checklist) |
| 8 | **Intralinks DealCentre AI** | Data room com IA | Categorização automática por taxonomia, sinalização de dado sensível. Pouco detalhe público de UI. | Adjacente fraco |

**Considerados e deixados de fora (com motivo):**
- **Rogo** — gera deck/modelo a partir de prompt; foco em banco de investimento sell-side, não em conferir documento do cliente. Granularidade da citação é disputada entre fontes (ver §2.9).
- **QoE automatizado** (QoEAgent, Finsider, Audit Sight) — existem, mas não achei UI pública descrita. Só press release e listagem. https://www.g2.com/products/qoeagent/reviews (403 no fetch), https://www.barchart.com/story/news/35038707/quality-of-earnings-software-launched-by-finsider-ai-ai-powered-qoe-reports-automation-platform-targets-60-faster-due-diligence-for-ma-deals
- **Valid8** — forense (prova de caixa), Sankey de fluxo de fundos. Útil como ideia, mas público é investigação. https://legaltechnology.com/valid8-debuts-new-data-extraction-and-visualisation-features-in-its-verified-financial-intelligence-software/
- **EY Diligence Edge** — plataforma de FDD da Big Four, oferecida no Brasil. Telas nomeadas (PMO, Process Heatmap, Instant Insights, visualizador de documento-fonte, Value Capture), mas não descritas. É uso interno do prestador, não produto que a boutique compra. https://www.ey.com/pt_br/services/strategy/dilligence-edge
- **Brasil** — não encontrei produto brasileiro que extraia demonstrações de data room com proveniência. Os mais próximos (Venture Metrix, Ex-Patria para M&A de energia) não descrevem extração financeira. https://startupi.com.br/venture-metrix-plataforma-ia-venture-capital/ , https://startups.com.br/negocios/ex-patria-cria-sistema-operacional-para-mas-de-energia-no-brasil/

---

## 2. O que cada um mostra na interface

### 2.1 F2
- **Proveniência:** "click any generated number or claim to instantly jump to the highlighted underlying evidence". Destaca "the specific paragraph, table row, or Excel cell in yellow". Cada dado leva coordenadas: arquivo, página, parágrafo ou célula. https://f2.ai/glossary/source-traceability
- **Proveniência que sobrevive a documento novo:** ao subir versão nova, troca os números "while preserving the original mapping and yellow-highlighted citations". Mesma fonte.
- **Audit Mode:** rastreia valor até arquivo, aba e célula, e inspeciona fórmula e precedentes (relato de busca sobre o press release; a página deu 403). https://www.businesswire.com/news/home/20260217775052/en/F2-Launches-Audit-Mode-Bringing-Defensible-AI-to-Private-Markets-Investors
- **Checklist / faltantes:** classifica documentos (rascunho vs. final); o analista pergunta no chat "qual balanço trimestral está faltando". https://www.f2.ai/blog/automated-financial-spreading
- **Mapeamento:** linha do cliente → plano de contas da casa (ex.: conta do QuickBooks → COGS). Tela de mapeamento não descrita. Mesma fonte.
- **Exportação:** empurra para o template Excel da casa ou para memo de comitê. Mesma fonte.
- **Painel lateral, carregamento, cor geral, tipografia:** não encontrado.

### 2.2 Daloopa
- **Proveniência:** "click any number in Excel to open its source location". O link aponta o lugar exato, não uma busca por palavra; o mesmo número pode apontar lugares diferentes (receita no segmento vs. na DRE). https://docs.daloopa.com/docs/data-sheets
- **Convenção de cor:** azul = número digitado vindo do documento (com link); preto = calculado. Linhas novas chegam destacadas em amarelo (cor de status de atualização, separada da origem). Mesma fonte.
- **Número derivado:** célula calculada ou trimestralizada abre o detalhamento da conta (ex.: o "12" derivado leva ao "42" acumulado divulgado), com visão em tabela do cálculo. Mesma fonte.
- **Link viaja com o número:** copiar o valor para e-mail leva o link junto. https://docs.daloopa.com/docs/data-sheets ; https://docs.daloopa.com/docs/company-pages-and-tabs
- **Inspect Cell:** clique direito numa célula do modelo do usuário, acha o dado mais parecido no banco (casa número e rótulo; aceita escala diferente, ex. 2.115,9 vs 2.115.907) e "Retrofit" adiciona o link de fonte, com opção de não sobrescrever o número do usuário. https://docs.daloopa.com/docs/daloopa-excel-add-in-inspect-cell
- **Página da empresa:** abas Overview / Earnings library / Update preview. "Key Changes" por período separa **Newly Disclosed Data** de **Restatements**. Toggle "Value / Update Time"; por padrão esconde linhas sem dado ("Show all rows" mostra). Conteúdo de IA rotulado como IA, com nota para conferir no documento; recurso experimental rotulado como tal. https://docs.daloopa.com/docs/company-pages-and-tabs
- **Destaque no documento-fonte ao abrir:** não encontrado na documentação.
- **Gráficos, tipografia, movimento:** não encontrado.

### 2.3 DataSnipper
- **Marcação de conferência:** o usuário desenha um retângulo no documento; a célula do Excel ligada recebe um "V" verde (Validation Snip). Divergência vira "X" vermelho (Exception Snip); clique direito converte verde em vermelho. https://knowledge.datasnipper.com/en/articles/694308-how-to-add-a-validation-snip-to-a-document ; https://knowledge.datasnipper.com/en/articles/714288-how-to-add-an-exception-snip-to-a-document
- **Visão geral das marcações:** seleciona células no Excel e lista as marcas no Document Viewer; passar o mouse mostra o documento ligado. https://knowledge.datasnipper.com/en/articles/714290-how-to-overview-all-snips-in-a-document
- **Várias fontes numa célula:** suportado. https://knowledge.datasnipper.com/how-to-set-multiple-snips-within-one-cell
- **Cor dos retângulos no visualizador, tipografia, carregamento:** não encontrado (a página de cores deu 404).

### 2.4 Hebbia (Matrix)
- **Layout:** grade em que linha = documento (ou empresa) e coluna = pergunta. "Add row", "Add column". Coluna "Source Documents" lista PDFs com ícone e contador "+11". https://www.hebbia.com/matrix/
- **Densidade:** muito alta. Célula contém mini-tabela (métrica/valor/base), texto curto com rótulo em negrito, lista com ícones. Mesma fonte.
- **Status em célula:** etiquetas "High / Medium / Low / Monitor only"; círculos verde/amarelo/vermelho; seta de tendência. Atribuição inline "confirmed / unconfirmed" com a fonte. https://www.hebbia.com/
- **Proveniência:** passar o mouse na resposta mostra o trecho marcado no documento original; a citação é clicável e leva ao PDF (relato de imprensa). https://dynamicbusiness.com/ai-tools/hebbia-revolutionizes-ai-interface-meet-the-matrix.html . "Enhanced citation previews" mostram a fonte sem sair do fluxo. https://www.hebbia.com/blog/the-disclosure-december-2025
- **Carregamento:** agentes preenchem as células em paralelo (imprensa, acima). Upload em lote ganhou barra de progresso e alerta de falha. https://www.hebbia.com/blog/the-disclosure-december-2025
- **Reuso:** "Blueprint" grava um fluxo de diligência e o compartilha como modelo (imprensa, acima). "Matrix Inputs": editar empresa/data/região recalcula todas as colunas (changelog dez/2025).
- **Saída:** cartão de PowerPoint por empresa ("9 slides") com seções "The situation / The opportunity / Why now / Key risk". https://www.hebbia.com/matrix/
- **Tema:** ícone de alternar modo claro/escuro aparece. https://www.hebbia.com/
- **Crítica pública de usuários:** usabilidade ruim com muitos documentos, curva de aprendizado. https://www.g2.com/products/hebbia-ai-2026-02-24/reviews

### 2.5 Datasite (Diligence, Prepare, Acquire)
- **Tracker (checklist):** "a single, central checklist, used by all involved"; mostra o que está na sala, o que falta e o que foi conferido. Cria a partir de Excel, cópia de projeto ou do zero. Gera a estrutura de pastas a partir do tracker. https://www.datasite.com/en/resources/insights/trackers-for-datasite-diligence-and-prepare
- **Dashboard:** aba "Dashboard" com visão em tempo real "from pre-launch readiness to live buyer engagement"; widgets rearranjáveis (relato de busca sobre a página de produto). "Dashboard" acompanha progresso e "flags gaps across the full index". https://datasite.com/en/products/prepare
- **Achar lacuna antes do comprador:** "Readiness reviews" (checagem com IA antes de abrir a sala). Mesma fonte. Em set/2026: "AI-powered recommendations that identify missing documents". https://www.datasite.com/en/resources/new-features
- **Coleta:** "Inbox" recebe arquivos do time por link de e-mail; "Secure uploads" dá um link único ao contribuidor. https://datasite.com/en/products/prepare
- **Q&A:** rota a pergunta ao especialista, trilha de auditoria; "Similar Questions" acha pergunta duplicada; resposta sugerida por IA (out/2026). https://www.datasite.com/us/en/products/diligence ; https://www.datasite.com/en/resources/new-features
- **Leitura de documento:** "Summarize", "Explain This", "Enhanced Review" compara informação de vários documentos lado a lado. https://www.datasite.com/us/en/products/diligence
- **Visualizador mobile:** pinch-to-zoom, lado a lado em tablet, leitura offline no iOS. https://www.datasite.com/en/resources/new-features
- **Cor de status, tipografia, % de progresso do tracker:** não encontrado.

### 2.6 DealRoom
- **Solicitação (pendência):** cada item tem status, responsável do vendedor, revisor interno, prioridade e prazo. https://dealroom.net/product/diligence
- **Fechamento automático:** arquivo arrastado é ligado à solicitação certa, arquivado na pasta e a solicitação é marcada completa. Mesma fonte.
- **Achados ("findings"):** o revisor registra risco/questão, dono, plano de mitigação e anexos contra a solicitação; gera relatório de riscos. Mesma fonte.
- **Visão do cliente:** o vendedor só vê as solicitações dele e comenta em thread; não vê revisor interno, outros vendedores nem achados. **"View as"** deixa conferir o que o outro lado vê antes de convidar. Comentário público ou privado por grupo. Mesma fonte.
- **Notificação:** mudança de status dispara alerta configurável. Mesma fonte.
- **IA:** extrai cláusulas (ex.: multa rescisória) com o trecho de apoio; templates de prompt compartilhados. Mesma fonte.
- **Barra de progresso, dashboard, cor:** não encontrado.

### 2.7 Ansarada
- **Scorecard de prontidão:** nota de 0 a 100% que mede completude e qualidade; sobe a cada upload; barras de progresso mostram quanto falta; guia por tópico explica o que é cada documento e por que importa. https://www.ansarada.com/blog/scorecards
- **Engajamento de compradores:** "Bidder Engagement Score" no dashboard da sala; "Line Card" mostra tendência no tempo. https://www.ansarada.com/features/ai . Alegação de 97% de acerto no dia 7 é do fornecedor.
- **Q&A:** coluna Status com estados longos e explícitos ("Answer awaiting approval", "Answer awaiting disclosure", "Disclosed - awaiting additional user notification"). Sem cor documentada. https://help.ansarada.com/en/articles/2599691-deal-room-q-a-statuses
- **AI-Sort:** classifica arquivo após upload. https://www.ansarada.com/features/ai
- **Cor, tipografia:** não encontrado.

### 2.8 Intralinks DealCentre AI
- Organiza arquivos que chegam numa taxonomia padrão, ajustável; sinaliza dado pessoal/sensível. https://www.intralinks.com/guides/beyond-vdr
- Dashboard, Q&A, gráficos, progresso: não descritos na página.

### 2.9 Rogo (referência)
- Felix gera deck, modelo Excel, Word e "dashboards" a partir de um prompt; "Library" guarda tudo que gerou. https://rogo.ai/news/may-product-update (redireciona para rogo.com)
- Citação: F2 diz "in-cell citations" (https://f2.ai/blog/f2-vs-rogo-buy-side-vs-sell-side-ai-comparison); Hebbia diz "response-level only" (https://www.hebbia.com/resources/hebbia-vs-rogo). Ambos são concorrentes. Não resolvido.

---

## 3. Tabela comparativa por padrão

| Padrão | Quem faz bem | Como | Fonte |
|---|---|---|---|
| Clique no número → fonte exata | F2, Daloopa | F2: abre o documento com destaque amarelo no parágrafo/linha/célula. Daloopa: link para o local exato, distingue o mesmo número em lugares diferentes. | f2.ai/glossary/source-traceability ; docs.daloopa.com/docs/data-sheets |
| Número derivado explica a conta | Daloopa | Célula calculada abre a decomposição e os componentes divulgados. | docs.daloopa.com/docs/data-sheets |
| Cor diz origem do número | Daloopa | Azul = do documento; preto = calculado; amarelo = novo. | idem |
| Marca de conferido vs. divergente | DataSnipper | V verde / X vermelho na célula, ligado a retângulo no documento. | knowledge.datasnipper.com (694308, 714288) |
| Citação sem sair da tela | Hebbia | Hover mostra o trecho; "citation previews". | dynamicbusiness.com ; hebbia.com/blog/the-disclosure-december-2025 |
| Reapresentação/restatement explícita | Daloopa | "Key Changes": Newly Disclosed vs Restatements por período. | docs.daloopa.com/docs/company-pages-and-tabs |
| Checklist com % de prontidão | Ansarada | Score 0–100%, barra de progresso, guia "por que importa". | ansarada.com/blog/scorecards |
| IA aponta documento faltante | Datasite, F2 | Datasite: "readiness reviews" e recomendação de faltantes. F2: pergunta no chat. | datasite.com/en/products/prepare ; datasite.com/en/resources/new-features ; f2.ai/blog/automated-financial-spreading |
| Upload casa com a solicitação e a fecha | DealRoom | Arrastar → liga à solicitação → arquiva → marca completa. | dealroom.net/product/diligence |
| Achado com dono e mitigação | DealRoom | Finding por solicitação: risco, dono, plano, anexo, relatório. | idem |
| Ver como o cliente vê | DealRoom | "View as" antes de convidar; comentário público/privado. | idem |
| Link de coleta para o cliente | Datasite | "Inbox" por e-mail, "Secure uploads" com link único. | datasite.com/en/products/prepare |
| Proveniência sobrevive à versão nova | F2 | Troca número, mantém mapeamento e citação. | f2.ai/glossary/source-traceability |
| Progresso de processamento em lote | Hebbia | Barra de upload, alerta de falha. | hebbia.com/blog/the-disclosure-december-2025 |
| Rótulo de "isto é IA, confira" | Daloopa | Conteúdo de IA rotulado; experimental rotulado. | docs.daloopa.com/docs/company-pages-and-tabs |
| Esconder linha vazia por padrão | Daloopa | "Show all rows" desligado por padrão. | idem |
| Saída para apresentação | Hebbia, Rogo, EY | PowerPoint gerado por empresa/achado. | hebbia.com/matrix ; rogo.ai/news/may-product-update ; ey.com/pt_br/... |
| Fluxo de fundos visual | Valid8 | Sankey entre contas e entidades. | legaltechnology.com/valid8-... |
| Tipografia, paleta, movimento | ninguém documenta | não encontrado em fonte pública | — |

---

## 4. O que eles fazem MELHOR que as telas (a)–(e), em ordem de impacto

Legenda: **[UI]** = só interface sobre dado que o banco já deveria ter (o portal grava proveniência até a página). **[DADO]** = exige coluna, tabela ou etapa nova.
O esforço supõe que a proveniência página-a-página já está gravada; se não estiver para algum número, o item sobe de categoria.

1. **Clique no número abre a página com o trecho destacado.**
   (i) Do número na tela (ou no Excel) para o PDF já rolado e com o valor marcado em amarelo, sem trocar de tela. (ii) F2 — https://f2.ai/glossary/source-traceability ; Daloopa — https://docs.daloopa.com/docs/data-sheets . (iii) Em reunião, o cliente pergunta "de onde veio isso?" e a resposta leva dois segundos. É a prova de que não é caixa-preta. (iv) Médio se já houver página; grande se precisar da caixa delimitadora (bbox) do valor. **[UI]** para abrir na página; **[DADO]** para o destaque exato (coordenadas na página).

2. **Número calculado mostra a conta e os componentes.**
   (i) Clicar num EBITDA ou num trimestre derivado mostra a decomposição e cada componente com sua fonte. (ii) Daloopa — https://docs.daloopa.com/docs/data-sheets . (iii) Responde ao "esse número bate?" sem abrir o Excel; mostra que ajuste não é mágico. (iv) Médio. **[UI]** se a derivação já está no banco/modelo; **[DADO]** se a regra de cálculo só existe na fórmula do export.

3. **Cor que diz a origem do número, e marca de conferido/divergente.**
   (i) Uma convenção fixa: "veio do documento", "calculado", "conferido por humano", "divergente". (ii) Daloopa (azul/preto/amarelo) — https://docs.daloopa.com/docs/data-sheets ; DataSnipper (V verde / X vermelho) — https://knowledge.datasnipper.com/en/articles/694308-how-to-add-a-validation-snip-to-a-document . (iii) Cliente de M&A lê em um olhar o que foi checado. Dá cara de papel de trabalho de auditoria. (iv) Pequeno na tela e no book. **[UI]** para origem; **[DADO]** para "conferido por quem e quando" se ainda não existir.

4. **Kit Básico com nota de prontidão e "por que este documento importa".**
   (i) Percentual de completude, barra por bloco, e uma linha por item explicando para que serve e o efeito de faltar. (ii) Ansarada — https://www.ansarada.com/blog/scorecards ; Datasite — https://datasite.com/en/products/prepare . (iii) O cliente entende o que falta e por quê, sem o assessor explicar item a item. Reduz idas e vindas. (iv) Pequeno. **[UI]** — com a ressalva da regra 1: o percentual não pode tratar "não verificado" como "presente".

5. **Upload do cliente casa com o item do checklist e fecha a pendência sozinho.**
   (i) Documento recebido é classificado, ligado ao item do Kit Básico, e a pendência "documento faltante" fecha com rastro. (ii) DealRoom — https://dealroom.net/product/diligence ; Datasite (gera pastas do tracker) — https://www.datasite.com/en/resources/insights/trackers-for-datasite-diligence-and-prepare . (iii) O cliente vê a lista andar enquanto envia. (iv) Médio. **[DADO]** se a ligação documento↔item e a transição automática ainda não existem.

6. **Link de coleta para o cliente (sem login) e "ver como o cliente vê".**
   (i) Link único por mandato para o cliente subir arquivos; e um modo "ver como cliente" que esconde notas internas e achados. (ii) Datasite "Inbox"/"Secure uploads" — https://datasite.com/en/products/prepare ; DealRoom "View as" — https://dealroom.net/product/diligence . (iii) Resolve o caso "cliente vê em reunião" sem medo de mostrar comentário interno. (iv) "Ver como": pequeno/médio **[UI]** se a visibilidade já é marcada. Link de coleta: grande **[DADO]** (token, permissão, segurança).

7. **Reapresentação (restatement) e "o que mudou desde a última versão".**
   (i) Por período, separar número novo de número que mudou em relação à versão anterior do documento, com as duas fontes. (ii) Daloopa "Key Changes: Newly Disclosed / Restatements" — https://docs.daloopa.com/docs/company-pages-and-tabs ; F2 mantém mapeamento na versão nova — https://f2.ai/glossary/source-traceability . (iii) Em reestruturação, balanço refeito é sinal de risco. Mostrar isso sozinho impressiona. (iv) Médio. **[DADO]** (versão do documento e comparação entre extrações).

8. **Pendência vira "achado" com dono, efeito e mitigação, e sai em relatório.**
   (i) Divergência ou contingência relevante promovida a achado: risco, dono, plano, anexos, e um relatório de achados por mandato. (ii) DealRoom "findings" — https://dealroom.net/product/diligence . (iii) É o que o cliente quer levar da reunião: lista de riscos, não lista de tarefas. (iv) Médio. **[DADO]** (campos de achado).

9. **Leitura de fatos em texto em grade: documento × pergunta, com citação por célula.**
   (i) Para contingências, partes relacionadas e eventos subsequentes, uma grade em que cada célula é uma resposta curta com citação e etiqueta (alto/médio/baixo, confirmado/não confirmado). (ii) Hebbia Matrix — https://www.hebbia.com/matrix/ ; https://dynamicbusiness.com/ai-tools/hebbia-revolutionizes-ai-interface-meet-the-matrix.html . (iii) Varre o data room inteiro numa tela e cada célula é verificável. (iv) Médio para a tela; **[UI]** se os fatos já têm citação gravada; **[DADO]** para a etiqueta "confirmado por humano".

10. **Progresso visível do processamento, por documento.**
    (i) Ao subir um lote: barra, contagem por estágio (recebido / extraído / conferido), e alerta explícito de falha. (ii) Hebbia (barra de upload e alerta de falha) — https://www.hebbia.com/blog/the-disclosure-december-2025 . (iii) Tira a dúvida "o sistema já leu meu arquivo?". Alinha com a regra 7 (estágio que não rodou não pode parecer limpo). (iv) Pequeno/médio. **[UI]** se o estado por estágio já é gravado; **[DADO]** se só há "processado sim/não".

11. **IA sugere o documento que falta, a partir do que chegou.**
    (i) "Você mandou o balancete de dez; falta o razão de dez" — sugestão derivada do que já foi lido. (ii) Datasite — https://www.datasite.com/en/resources/new-features ; F2 — https://www.f2.ai/blog/automated-financial-spreading . (iii) Mostra que o sistema entende o caso, não só guarda arquivo. (iv) Médio. **[DADO]** (regra ou inferência nova), mas pode começar por regra determinística sobre períodos já extraídos.

12. **Rótulo honesto de conteúdo gerado por IA e esconder linha vazia por padrão.**
    (i) Selo "gerado por IA — confira na fonte" e filtro padrão que oculta séries sem dado, com toggle "mostrar todas". (ii) Daloopa — https://docs.daloopa.com/docs/company-pages-and-tabs . (iii) Passa seriedade. (iv) Pequeno. **[UI]**. Atenção: esconder linha vazia **não** pode esconder ausência relevante — ver §5.

Itens vistos e **não** priorizados: Sankey de fluxo de fundos (Valid8) — bonito, mas exige razão/extrato conciliado, grande e **[DADO]**; score de engajamento de comprador (Ansarada) — não se aplica a portal interno de assessoria do lado do cliente.

---

## 5. O que NÃO vale copiar

1. **IA conversacional sem rastro.** Chat que responde "o EBITDA é 12,3" sem citação clicável. Até entre os líderes a granularidade da citação é disputada (Rogo: "in-cell" segundo F2, "response-level" segundo Hebbia). Se a resposta não abre a página, não entra. Fontes: https://f2.ai/blog/f2-vs-rogo-buy-side-vs-sell-side-ai-comparison ; https://www.hebbia.com/resources/hebbia-vs-rogo
2. **Score único de "prontidão" que mistura falta com não-verificado.** O 0–100% da Ansarada sobe "a cada upload" (https://www.ansarada.com/blog/scorecards). Upload não é conferência. Copiar isso viola a regra 1: o percentual precisa separar "recebido", "conferido" e "não aplicável", e mostrar o que não foi medido.
3. **Esconder linha vazia sem dizer.** O "Show all rows" desligado por padrão da Daloopa serve para empresa aberta, onde vazio é raro. Em empresa fechada, vazio é informação. Se esconder, mostrar "N linhas sem dado ocultas".
4. **Grade ultra densa com emoji de semáforo.** A Matrix da Hebbia empilha tabela, texto e ícones na mesma célula; usuários reclamam de usabilidade com muitos documentos (https://www.g2.com/products/hebbia-ai-2026-02-24/reviews). Para reunião com cliente, uma célula = uma afirmação + uma fonte.
5. **Precisão de IA anunciada sem medição.** "97% de acerto no dia 7" (Ansarada), "80% menos tempo" (DealRoom, Audit Sight), "74-point scan" (Finsider) são alegações de fornecedor. Não copiar número de marketing para a tela; mostrar só o que o próprio sistema mede.
6. **Dashboard de widgets arrastáveis.** O Dashboard da Datasite tem widgets rearranjáveis. Para uma boutique com poucos usuários, customização de layout é custo sem retorno; a tela (a) deve ter uma ordem fixa e pensada.
7. **Geração automática de deck "pronto para o cliente".** Hebbia e Rogo geram PowerPoint. O book em Excel com fórmula viva é o produto; um deck gerado sem revisão compete com ele e quebra a cadeia de proveniência.
8. **Gráfico decorativo.** Nenhum concorrente de extração (F2, Daloopa, DataSnipper) vende por gráfico; vendem por rastro. Gráfico só onde responde pergunta (ex.: evolução de receita com marca de restatement).

---

## Lacunas desta pesquisa

- Tipografia, paleta, movimento e estados de carregamento: **não encontrados** em nenhuma fonte pública de nenhum dos oito. Só daria para medir com demo ou trial.
- Páginas que falharam: F2 Audit Mode (403), G2 QoEAgent (403), Daloopa "one-click-audit" (404), DataSnipper cores (404).
- Rogo: a página de novidades de maio/2026 redireciona para rogo.com e não foi lida; o relato vem da busca.
