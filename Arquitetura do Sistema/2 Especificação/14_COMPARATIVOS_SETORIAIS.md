# 14 — Análise Comparativa: onde cortar custo e onde crescer receita

**Data:** 10/11/2026 · **Natureza:** especificação e plano. Nada aqui está implementado.
Trechos marcados **[A CONFIRMAR]** não foram verificados na fonte primária: recorte, formato e
acesso precisam ser conferidos na etapa 0 (§6) antes de virar código. O que foi verificado em
pesquisa pública nesta data cita a fonte no fim (§9). Pesquisa pública não é contrato: tabela,
recorte e defasagem só valem depois de testados contra a API ou o arquivo.

**Origem, em ordem de autoridade:**

1. As **decisões do dono em 10/11/2026** (§1), tomadas em conversa.
2. A **Especificação 13** (`13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md`), §3: a tabela
   `consulta_externa` e os quatro estados de uma consulta. Esta especificação **reusa** os dois, não
   cria um mecanismo paralelo.
3. O **roadmap** (`3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`), §9 item 15: "benchmark
   setorial exige conta canônica estável entre casos. Depois de F4 é quase de graça; antes,
   impossível". Por isso a fase nova, **F6C**, depende da F4.
4. O **prompt da apresentação de crédito** (`6 Referência/apresentacao-credito/PROMPT_MESTRE_ORIA_v3.md`),
   que já pede "comparativo com a média do setor", com fonte ou `n/d`. Hoje esse comparativo não
   tem de onde vir; esta especificação é a origem dele.

---

## Resumo

Uma seção nova no mandato, **Análise Comparativa**, entre a aprovação (go/no-go) e a modelagem.
Ela compara o cliente com empresas parecidas, com o setor e com a região de cada unidade dele, em
seis quadros (§4): mercado, receita, índices, despesas, dívida e oportunidades. Cada desvio vira uma
**oportunidade**. O analista aceita ou recusa cada uma. **A aceita vira alavanca na modelagem e
aparece na apresentação de crédito**; a recusada fica registrada com o motivo.

```
Aprovação (go/no-go) ──► ANÁLISE COMPARATIVA ──► Modelagem ──► Book Excel ──► Apresentação de crédito
                          │                         ▲                            ▲
                          └── oportunidade aceita vira alavanca ─────────────────┘
```

---

## §1 — Decisões do dono (10/11/2026)

| # | Decisão |
|---|---|
| D14.1 | **Empresas comparáveis: só quem publica balanço.** Companhias listadas na CVM, mais as companhias fechadas que publicam balanço (emissoras de dívida registradas na CVM). |
| D14.2 | **A comparação é sempre por índice** (margem, % da receita, prazos, alavancagem), nunca por valor absoluto. O cliente médio e a listada grande só são comparáveis em proporção. |
| D14.3 | **Amostra mínima: 4 empresas.** Com menos de 4, o comparativo mostra `n/d` com o motivo ("3 empresas no CNAE 10.6; mínimo 4"). |
| D14.4 | **O CNAE é a chave de busca do setor.** Os números do setor vêm do IBGE pela API SIDRA, uma pesquisa por setor. |
| D14.5 | **Liquidez, alavancagem e os demais índices de balanço do setor vêm da CVM**, agrupada por CNAE. O IBGE não traz balanço. |
| D14.6 | **Região: só o estado do cliente, e só quando o IBGE publica o recorte.** Célula escondida por sigilo vira `n/d — sigilo IBGE`, nunca zero. |
| D14.7 | **Fontes adicionadas:** RAIS, juros por modalidade e crédito agregado do Banco Central, CNPJ aberto da Receita e Serasa (§2). **Damodaran foi avaliado e removido** (D14.13). |
| D14.8 | **Os blocos de despesa ficam na própria seção, não no Kit Básico.** O analista preenche quantidade e valor de cada despesa, e o sistema calcula sozinho o custo unitário, compara com a média da região e mostra ao lado a economia se o custo for trazido para a média. Cada bloco também mostra o **percentual da receita** gasto com aquele custo, comparado com o percentual do setor. |
| D14.9 | **O cálculo é por região de operação, nunca generalista.** Cliente com operação em vários estados tem cada despesa calculada por unidade, contra a referência do lugar daquela unidade (§3). |
| D14.10 | **Dívida em duas camadas:** a taxa implícita, calculada sozinha da DRE e do balanço, e o bloco "Dívida", um contrato por linha, comparado com a taxa média do Banco Central da mesma modalidade no mês da contratação (§4.5). |
| D14.11 | **Receita em três medidas:** crescimento do cliente contra o setor no estado, participação de mercado e margem bruta contra as empresas da CVM (§4.2). |
| D14.12 | **Crédito agregado do Banco Central é contexto do setor, não comparação** com o cliente. Vai para o quadro de mercado e para a apresentação de crédito (§4.1). |
| D14.13 | **Damodaran removido.** Os dados por setor são do agregado dos mercados emergentes, sem o Brasil separado; a comparação com as empresas da CVM cobre o mesmo uso com dado brasileiro. |
| D14.14 | **Período padrão: últimos 12 meses do cliente**, com o ano de cada referência ao lado. Referência anual com defasagem (IBGE anual, RAIS) entra só como percentual ou índice, nunca como valor em R$ de outro ano. |

---

## §2 — As fontes, o que cada uma responde e como se busca

### 2.1 Fontes de comparação

| Fonte | Responde | Chave | Acesso | Custo | Defasagem |
|---|---|---|---|---|---|
| **CVM — listadas e fechadas registradas** | Margens, liquidez, alavancagem, cobertura de juros, prazos, giro, por empresa; agrupado por CNAE vira a referência de balanço do setor | CNAE da empresa (pelo CNPJ aberto) | Dados abertos da CVM: DFP (anual) e ITR (trimestral). Conjuntos confirmados; **[A CONFIRMAR se as emissoras só de dívida estão no mesmo conjunto]** | grátis | trimestral |
| **IBGE — PIA-Empresa (indústria)** | Receita, pessoal, matéria-prima, energia, aluguéis, fretes, despesas operacionais | divisão/grupo CNAE; estado | API SIDRA **[A CONFIRMAR número da tabela por estado]**. Quebra de série a partir de 2024 (Nota Técnica PIA-Empresa 01/2026): não comparar anos antes e depois da quebra | grátis | ~2 anos |
| **IBGE — PAC (comércio), PAS (serviços), PAIC (construção)** | Idem para cada setor; margem de comercialização no comércio | idem; o estado é o menor recorte que existe | API SIDRA **[A CONFIRMAR quais despesas saem separadas por estado]** | grátis | ~2 anos |
| **IBGE — PMC, PMS (mensais) e PIM regional** | Receita nominal e volume de vendas do comércio e de serviços, por atividade e por estado; produção física da indústria por estado | atividade; estado | API SIDRA | grátis | ~45 dias |
| **RAIS (Ministério do Trabalho)** | Remuneração média e quantidade de vínculos por setor, estado e município; desde a RAIS 2023, montada só com dados do eSocial | CNAE + município; cargo (CBO) | Ferramenta online e microdados anuais públicos **[A CONFIRMAR remuneração por cargo e município ao mesmo tempo]** | grátis | anual |
| **CNPJ aberto (Receita Federal)** | Matriz e filiais do cliente (unidades); estabelecimentos ativos, abertos e fechados do mesmo CNAE por município e estado; CNAE das empresas da CVM | CNPJ raiz; CNAE + município | Arquivos abertos mensais | grátis | mensal |
| **Banco Central — taxa média de juros por modalidade** | Taxa média das operações **novas** de crédito para empresas, ponderada pelo valor, por modalidade (capital de giro até 365 dias, acima de 365 dias, rotativo, total, desconto, conta garantida...); exclui BNDES e recursos direcionados | modalidade + mês | Séries temporais SGS (ex.: 20722, 20723, 20724, 20725 anuais; 25442 a 25444 mensais) | grátis | mensal |
| **Banco Central — SCR.data (crédito agregado)** | Carteira ativa, inadimplência (parcela com atraso acima de 90 dias ÷ carteira) e ativo problemático, por estado, porte, modalidade e **seção** do CNAE (o nível mais grosso) | seção CNAE + porte + estado | Painel e dados abertos | grátis | ~30 dias |
| **Serasa** | Indicadores de empresas médias de capital fechado | CNAE + porte | Contrato | **pago** | **[A CONFIRMAR produto e preço]** |

**A regra de toda fonte, sem exceção:** número com **fonte e ano** ao lado; **mediana e quartis**,
nunca média (a média esconde a dispersão do setor); amostra abaixo do mínimo vira `n/d` com motivo;
consulta que falhou fica `falhou`, nunca "nada encontrado" (os quatro estados da Espec. 13 §3).

### 2.2 Fontes de preço por unidade (custo unitário)

Comparar "aluguel acima da média" exige o **m²**; energia, o **kWh**; água, o **m³**; frete, o **km**.
Nenhum desses está na DRE. A quantidade vem dos blocos de despesa da própria seção (§4.4),
digitada pelo analista ou extraída pela IA do documento anexado.

| Despesa | Referência de preço | Recorte |
|---|---|---|
| Energia elétrica | **ANEEL** — tarifa por distribuidora e classe; **CCEE** — preço do mercado livre | distribuidora da unidade |
| Água e esgoto | **SINISA** (antigo SNIS) e agências estaduais — tarifa média por prestador | município |
| Aluguel comercial | **FipeZAP comercial** (R$/m² de locação) **[A CONFIRMAR cidades cobertas]**; reajuste pelo **IGP-M** e **IVAR (FGV)** | cidade |
| Frete rodoviário | **ANTT** — piso mínimo por km, eixos e tipo de carga | rota |
| Diesel | **ANP** — levantamento semanal de preços | município |
| Folha | **RAIS** (§2.1) | cargo + município, ou estado |
| Taxa de cartão | **Banco Central** — estatísticas de cartões | Brasil |
| Tarifas bancárias | **Banco Central** — tarifas por banco | banco |
| Seguros | **SUSEP** — estatísticas por ramo e estado | estado |
| Dívida | **Banco Central** — taxa por modalidade (§2.1) | modalidade + mês |

**Fora do escopo desta fase** (sem base pública de preço por unidade, ou dependente de leitura
fiscal que só chega na F2T): forma de cobrança do frete (km, viagem, hora); insumos e matéria-prima
(IPA, CEPEA, SINAPI medem variação, não preço do cliente); preço de importação e exportação (Comex
Stat, só depois da F2T onda 5); carga tributária (só depois da F2T onda 1). Entram como fase própria
quando houver pedido de um mandato.

---

## §3 — Operação em várias regiões (D14.9)

Uma média nacional aplicada a um cliente com fábrica em Goiás e centro de distribuição em São Paulo
não diz nada. O cálculo segue estes passos:

1. **Localizar as unidades.** O sistema lista todos os estabelecimentos do CNPJ do cliente (matriz e
   filiais, com estado e município) pelo **CNPJ aberto**, para cada empresa do perímetro (F1). O
   analista confirma a lista e acrescenta o que não tem CNPJ próprio (galpão alugado, obra, ponto
   de apoio).
2. **Preencher por unidade.** Cada bloco de despesa recebe quantidade e valor por unidade. Despesa
   que o cliente só tem consolidada pode ser rateada pelo analista, e o rateio fica escrito.
3. **Custo unitário por unidade:** valor ÷ quantidade (R$/kWh, R$/m², R$/m³, R$/km).
4. **Referência do lugar da unidade:** mediana do município quando a fonte publica, senão do estado.
   Se o estado não tem referência, a unidade fica `n/d — sem referência para <UF>`. A média nacional
   só entra se o analista escolher, e aparece rotulada como "referência nacional (UF sem dado)".
5. **Economia até a média, por unidade:** (custo unitário − referência) × quantidade, em 12 meses.
   Só quando o cliente está acima. Abaixo, mostra "abaixo da média" e economia zero, nunca negativa.
6. **Total do cliente:** soma das economias das unidades, com a tabela por unidade ao lado. O total
   nunca esconde de qual unidade veio.
7. **Percentual da receita** de cada custo contra o mesmo percentual no setor (IBGE pelo CNAE, no
   recorte do estado quando publicado; CVM onde o IBGE não separa a despesa). Despesa que o setor
   não publica separada fica `n/d — o setor não publica esta despesa separada`. Cada bloco tem duas
   leituras independentes: **o preço** (custo unitário contra a região) e **o peso** (percentual
   contra o setor). Preço na média com peso acima indica consumo alto, não tarifa alta, e a
   hipótese escrita diz isso.
8. **Índices de setor com várias regiões** (margem, prazos, crescimento): ponderados pela receita de
   cada unidade quando o analista a informar. Sem receita por unidade, a comparação usa o estado da
   matriz e diz isso na tela.

---

## §4 — A seção no portal, quadro por quadro

Os seis quadros aparecem nesta ordem. Período padrão: últimos 12 meses do cliente (D14.14).

### 4.1 Mercado

| Mostra | Cálculo | Fonte |
|---|---|---|
| Unidades do cliente | lista por estado e município, confirmada pelo analista (§3, passo 1) | CNPJ aberto |
| Concorrência local | estabelecimentos ativos do mesmo CNAE no município e no estado; abertos e fechados em 12 meses | CNPJ aberto |
| Crescimento do setor | variação de 12 meses da receita nominal e do volume do setor em cada estado de operação | PMC, PMS, PIM |
| Risco de crédito do setor (contexto, D14.12) | carteira ativa e inadimplência do porte e da seção CNAE do cliente, em cada estado | SCR.data |

Este quadro **não gera oportunidade**: é contexto para o analista e para a apresentação de crédito.

### 4.2 Receita (D14.11)

| Mostra | Cálculo | Fonte | Oportunidade quando |
|---|---|---|---|
| Crescimento contra o setor | receita do cliente nos últimos 12 meses ÷ 12 meses anteriores − 1, contra a variação do setor no estado | PMC, PMS ou PIM | o cliente cresceu menos que o setor: perdeu mercado |
| Participação de mercado | receita do cliente no estado ÷ receita do setor no estado | PIA, PAC, PAS, PAIC | — (contexto: mede o espaço para crescer) |
| Margem bruta | lucro bruto ÷ receita líquida, contra mediana e quartis dos pares | CVM | abaixo do 1º quartil: preço baixo ou custo de produto alto |

### 4.3 Índices

Contra mediana e quartis das empresas da CVM do mesmo CNAE (mínimo 4, D14.3):
margem EBITDA, margem líquida, liquidez corrente, prazo médio de recebimento, prazo médio de
pagamento, prazo médio de estoque, ciclo financeiro, **cobertura de juros** (EBIT ÷ despesa de
juros, nas faixas que o Banco Central usa: abaixo de 1, entre 1 e 2, 2 ou mais) e **dívida líquida
÷ EBITDA**. Índice fora do intervalo entre o 1º e o 3º quartil abre oportunidade.

### 4.4 Despesas (D14.8)

Um bloco por despesa, uma linha por unidade. Campos e cálculo:

| Bloco | Campos por unidade (12 meses) | Preço comparado com | Peso comparado com |
|---|---|---|---|
| Energia | kWh, demanda contratada (kW), classe tarifária, valor | tarifa ANEEL da distribuidora e classe; se o consumo permite migrar, o mercado livre (CCEE) | % da receita, setor |
| Água | m³, valor | tarifa média do prestador (SINISA) | % da receita, setor |
| Aluguel | m², valor mensal, índice de reajuste do contrato | R$/m² da cidade (FipeZAP); reajuste aplicado contra o índice | % da receita, setor |
| Frete | km, eixos, tipo de carga, valor | piso ANTT da mesma carga | % da receita, setor |
| Diesel | litros, valor | preço médio ANP do município | — |
| Folha | por cargo: pessoas, salário médio; encargos à parte | mediana RAIS do cargo no município, ou no estado | % da receita e receita por funcionário, setor |
| Cartão | valor transacionado, taxa paga | taxa média do Banco Central | — |
| Tarifas bancárias | banco, pacote, valor | tarifa pública do mesmo banco | — |
| Seguros | ramo, valor segurado, prêmio | média SUSEP do ramo e estado | — |

Para cada linha: custo unitário, referência, **economia até a média** (§3, passo 5) e o percentual
da receita (§3, passo 7). Bloco não preenchido fica `n/d — bloco não preenchido`, com o efeito
escrito: "custo unitário não comparado; só a proporção sobre a receita".

**Folha tem duas leituras.** Salário acima da mediana do cargo pode ser justificado (antiguidade,
especialização), e a hipótese diz isso. A **receita por funcionário** abaixo do setor aponta excesso
de quadro, que costuma ser a oportunidade maior.

### 4.5 Dívida (D14.10)

1. **Taxa implícita, automática:** despesa de juros ÷ dívida bruta média dos 12 meses, contra a taxa
   média de capital de giro total do Banco Central no mesmo período. A taxa do Banco Central é de
   operação **nova** e a do cliente é sobre o **saldo inteiro**, que inclui contratos antigos: por
   isso a diferença aparece como **sinal**, não como prova, e a tela diz isso.
2. **Bloco "Dívida", preenchido pelo analista:** um contrato por linha, com credor, modalidade,
   saldo, taxa, indexador e data de contratação. Cada contrato é comparado com a série do Banco
   Central da mesma modalidade no mês em que foi contratado. Economia = (taxa do contrato − taxa
   média) × saldo, em 12 meses. Contrato com recurso direcionado (BNDES) não é comparado com a série
   de recursos livres: fica `n/d — recurso direcionado`.
3. O bloco também alimenta o mapa de dívida da modelagem, que hoje não recebe taxa (F2.2 do roadmap:
   0 dos 51 mapas em produção com taxa, medido em 22/09/2026).

### 4.6 Oportunidades

Uma linha por desvio dos quadros 4.2 a 4.5: quadro, unidade, índice do cliente, referência, fonte e
ano, diferença em R$ em 12 meses, hipótese em texto e grau de confiança. A **IA** escolhe os pares
(CNAE, porte, estado), aponta os desvios relevantes e escreve a hipótese; o **número** sempre vem
da tabela de referência. O analista **aceita**, **recusa com motivo** ou **pede mais dado ao
cliente**. A aceita vira **alavanca** (F8, "alavancas operacionais como categoria") e entra na
modelagem e na apresentação.

---

## §5 — O que muda no sistema

1. **Coletores**, um por fonte, gravando em `consulta_externa` (Espec. 13 §3) com os quatro
   estados: `encontrado`, `nada_encontrado` (com data), `falhou` (com motivo) e `nao_consultado`.
   Fontes públicas atualizam por agenda própria; o mandato lê a versão vigente e grava qual usou.
2. **Tabela de referência por setor e região**: mediana, quartis, tamanho da amostra, fonte, ano e
   recorte (Brasil, estado ou município). Calculada em SQL, de forma determinística. **A IA não
   calcula referência.**
3. **Índices do cliente** calculados da **conta canônica** (F4): sem ela, "despesa com frete" de uma
   empresa não é comparável com a de outra.
4. **Unidades do cliente**, os **blocos de despesa** e o **bloco Dívida** como dado do mandato,
   versionados como as premissas.
5. **Oportunidades** com a decisão do analista e a ligação com a alavanca da F8.
6. **A seção no portal**, entre a aprovação e a modelagem, com os seis quadros do §4.
7. **Apresentação de crédito**: o capítulo de comparativo setorial lê a tabela de referência, com a
   coluna `Setor (fonte, ano)` que o prompt mestre já prevê; o contexto de mercado (§4.1) entra no
   capítulo de setor.

---

## §6 — O plano, em etapas

| Etapa | Escopo | Depende de | Critério de pronto |
|---|---|---|---|
| **0 — Conferir as fontes** | Cada [A CONFIRMAR]: números das tabelas SIDRA e despesas por estado; RAIS por cargo e município; emissoras só de dívida na CVM; cobertura do FipeZAP; cotação da Serasa | — | Cada fonte da §2 com acesso testado e o resultado escrito nesta especificação |
| **1 — Coletores públicos** | CVM, IBGE (anuais e mensais), RAIS, CNPJ aberto, Banco Central (juros e SCR.data) | etapa 0 · Espec. 13 etapa 2 (`consulta_externa`) | Desligar um coletor aparece como `nao_consultado`, não como vazio (medido) |
| **2 — Referência por setor e região** | Mediana, quartis e amostra; mínimo de 4 empresas; sigilo do IBGE como `n/d`; quebra de série da PIA respeitada | etapa 1 | Setor com 3 empresas devolve `n/d` com o motivo (medido não-vazio) |
| **3 — Mercado, receita e índices** | Quadros 4.1 a 4.3 sobre a conta canônica | etapa 2 · **F4** | Toda linha cita fonte e ano |
| **4 — Unidades e despesas** | Localizar as unidades; blocos de despesa por unidade; preço, peso e economia | etapa 3 · F1 (perímetro) | Cliente com 2 estados mostra 2 cálculos, cada um contra a referência do seu estado; unidade sem referência mostra `n/d`, não a média nacional (medido) |
| **5 — Dívida** | Taxa implícita e bloco Dívida contra a série do Banco Central | etapa 1 | Contrato com recurso direcionado não é comparado com recurso livre (medido) |
| **6 — Oportunidades e decisão** | Quadro 4.6; aceitar, recusar, pedir dado; alavanca na modelagem | etapas 3 a 5 | A aceita aparece na modelagem como alavanca; a recusada fica com motivo |
| **7 — Apresentação** | Capítulo de comparativo setorial e de mercado | etapa 6 · F15 | Número do comparativo no PPT igual ao do banco |
| **8 — Serasa** | Coletor pago, se a etapa 0 aprovar o custo | etapa 1 · decisão do dono | Idem etapa 1 |

---

## §7 — Regras (as sete do projeto, aplicadas aqui)

- **Diferença contra a referência é hipótese, não economia garantida.** A tela e a apresentação
  dizem "possível economia", nunca "economia". O cliente não pode ler promessa.
- **Ausência não é dado.** Setor sem amostra, célula em sigilo, bloco não preenchido, estado sem
  referência: `n/d` com o motivo **e o efeito**.
- **Coletor que não rodou não parece coletor que não achou nada** (regra 7): `nao_consultado` e
  `falhou` são estados visíveis, nunca uma referência vazia.
- **Nenhum número sem fonte e ano**, inclusive no texto que a IA escreve.

---

## §8 — O que esta especificação não cobre

- Concorrente de capital fechado que não publica balanço (só pelo Serasa, etapa 8).
- Preço de venda do cliente contra concorrentes, fora do comércio exterior.
- As despesas listadas como fora do escopo na §2.2.
- A inadimplência do próprio cliente no sistema financeiro, que exige autorização dele (Registrato
  ou bureau, Espec. 13).
- Projeção do efeito da alavanca: isso é a modelagem (F7, F8), não esta fase.

---

## §9 — Fontes consultadas em 10/11/2026

- Banco Central, taxas médias de juros para empresas, recursos livres, capital de giro (séries
  20725 e 25444, e o metadado da metodologia):
  https://dadosabertos.bcb.gov.br/dataset/20725-taxa-media-de-juros-das-operacoes-de-credito-com-recursos-livres---pessoas-juridicas---capita
- Banco Central, metodologia do SCR.data: https://www.bcb.gov.br/content/estabilidadefinanceira/scr/scr.data/scr_data_metodologia.pdf
- Banco Central, Relatório de Estabilidade Financeira (faixas da cobertura de juros):
  https://www.bcb.gov.br/content/publicacoes/ref/202410/RELESTAB202410-refPub.pdf
- IBGE, PIA-Empresa: https://www.ibge.gov.br/estatisticas/economicas/industria/9042-pesquisa-industrial-anual.html
- IBGE, questionário da PIA-Empresa: https://biblioteca.ibge.gov.br/visualizacao/instrumentos_de_coleta/doc5717.pdf
- IBGE, notas técnicas da PAS: https://biblioteca.ibge.gov.br/visualizacao/periodicos/150/pas_2022_v24_notas_tecnicas.pdf
- IBGE, PIM regional: https://www.ibge.gov.br/estatisticas/economicas/industria/9296-pesquisa-industrial-mensal-producao-fisica-regional.html
- Ministério do Trabalho, sumário da RAIS 2025: https://www.gov.br/trabalho-e-emprego/pt-br/assuntos/estatisticas-trabalho/rais/rais-2025/SumrioExecutivo_RAIS20251.pdf
- CVM, dados abertos DFP e ITR: https://dados.cvm.gov.br/dataset/groups/cia_aberta-doc-dfp ·
  https://dados.cvm.gov.br/dataset/cia_aberta-doc-itr
- Damodaran, dados por setor (avaliado e removido, D14.13): https://pages.stern.nyu.edu/~adamodar/New_Home_Page/datacurrent.html
