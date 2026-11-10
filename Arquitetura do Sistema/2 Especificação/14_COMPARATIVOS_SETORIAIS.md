# 14 — Comparativos setoriais: onde cortar custo e onde crescer receita

**Data:** 10/11/2026 · **Natureza:** especificação e plano. Nada aqui está implementado.
Trechos marcados **[A CONFIRMAR]** vêm do conhecimento geral das fontes, não de consulta feita
nesta data: recorte, formato e acesso de cada fonte precisam ser conferidos antes de virar código.

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

Uma seção nova no mandato, **Análise Comparativa**, entre a aprovação (go/no-go) e a modelagem. Ela compara
os índices do cliente com empresas parecidas, com o setor e com a região, e lista
**oportunidades**: onde o cliente gasta acima da referência ou vende abaixo dela. O analista aceita
ou recusa cada uma. **A aceita vira alavanca na modelagem e aparece na apresentação de crédito**;
a recusada fica registrada com o motivo.

```
Aprovação (go/no-go) ──► COMPARATIVOS ──► Modelagem ──► Book Excel ──► Apresentação de crédito
                          │                  ▲                              ▲
                          └── oportunidade aceita vira alavanca ────────────┘
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
| D14.7 | **Fontes adicionadas:** RAIS, juros por modalidade e crédito agregado do Banco Central, CNPJ aberto da Receita, Damodaran e Serasa (§2). |
| D14.8 | **Os blocos de despesa ficam na própria seção Análise Comparativa, não no Kit Básico.** O analista preenche quantidade e valor de cada despesa (kWh, m², m³, km...), e o sistema calcula sozinho o custo unitário, compara com a média da região e mostra ao lado a economia se o custo for trazido para a média. |
| D14.9 | **O cálculo é por região de operação, nunca generalista.** Cliente com operação em vários estados tem cada despesa calculada por unidade, contra a referência do lugar daquela unidade (§3.1). |

---

## §2 — As fontes, o que cada uma responde e como se busca

### 2.1 Fontes decididas

| Fonte | Responde | Chave | Acesso | Custo | Defasagem |
|---|---|---|---|---|---|
| **CVM — listadas e fechadas registradas** | Margens, liquidez, alavancagem, prazos, giro, por empresa; agrupado por CNAE vira a referência de balanço do setor | CNAE da empresa (do CNPJ aberto, §2.1 linha 7) | Dados abertos da CVM: DFP (anual) e ITR (trimestral), arquivo CSV **[A CONFIRMAR formato e se as emissoras só de dívida estão no mesmo conjunto]** | grátis | trimestral |
| **IBGE — PIA (indústria)** | Receita, custos de pessoal, matéria-prima, despesas operacionais por setor | divisão/grupo CNAE; estado quando houver | API SIDRA | grátis | ~2 anos **[A CONFIRMAR]** |
| **IBGE — PAC (comércio)** | Idem, comércio; margem de comercialização | idem | API SIDRA | grátis | ~2 anos |
| **IBGE — PAS (serviços)** | Idem, serviços | idem | API SIDRA | grátis | ~2 anos |
| **IBGE — PAIC (construção)** | Idem, construção | idem | API SIDRA | grátis | ~2 anos |
| **RAIS (Ministério do Trabalho)** | Salário médio por setor e por município; tamanho de quadro | CNAE + município | Microdados públicos **[A CONFIRMAR forma de acesso atual]** | grátis | anual |
| **CNPJ aberto (Receita Federal)** | Quantas empresas do mesmo setor estão abertas na região do cliente; o CNAE das empresas da CVM | CNAE + município/UF | Arquivos abertos mensais | grátis | mensal |
| **Banco Central — juros por modalidade** | Juro médio do mercado em cada modalidade de crédito (capital de giro, conta garantida, desconto de recebíveis...) | modalidade | API de séries temporais (SGS) | grátis | mensal |
| **Banco Central — crédito agregado** | Endividamento e inadimplência por setor, porte e estado | setor + porte + UF | Dados agregados do SCR **[A CONFIRMAR recorte setor × porte × UF]** | grátis | mensal |
| **Damodaran** | Múltiplos e margens por setor (mercados emergentes) | setor Damodaran ↔ CNAE (tabela de-para nossa) | Planilhas públicas anuais | grátis | anual |
| **Serasa** | Indicadores de empresas médias de capital fechado | CNAE + porte | Contrato | **pago** | **[A CONFIRMAR produto e preço]** |

**A regra de toda fonte, sem exceção:** número com **fonte e ano** ao lado; **mediana e quartis**,
nunca média (a média esconde a dispersão do setor); amostra abaixo do mínimo vira `n/d` com motivo;
consulta que falhou fica `falhou`, nunca "nada encontrado" (os quatro estados da Espec. 13 §3).

### 2.2 Custo unitário: frete, aluguel, energia, água e outros

**O ponto que decide se esta parte funciona:** comparar "aluguel acima da média" exige saber o
**m²**; energia exige o **kWh**; água, o **m³**; frete, o **km e o peso**. Nenhum desses está na DRE.
Sem a quantidade, o sistema só pode dizer "aluguel é 8% da receita contra 5% no setor", nunca "o
m² está caro". Por isso a seção Análise Comparativa tem **blocos de despesa** para preencher,
um por despesa e por unidade (§3.1). A coluna da direita diz onde a quantidade costuma estar; o
analista pode digitar ou anexar o documento para a IA extrair.

| Despesa | Fonte de referência | O que compara | Quantidade necessária, e de onde vem |
|---|---|---|---|
| **Frete rodoviário** | **ANTT — piso mínimo de frete**: tabela oficial por km, por número de eixos e por tipo de carga, com custo de carga e descarga | R$ por km pago pelo cliente × piso da ANTT para a mesma carga | km, eixos, tipo de carga: dos **CT-e** do cliente (F2T onda 5) |
| **Frete: forma de cobrança** (km, viagem, hora, peso, % da nota) | **Não há base pública por região** **[A CONFIRMAR]**. Fonte possível: índices de entidades do setor de transporte (NTC&Logística) e plataformas de frete, pagos | Só dá para comparar o **custo efetivo por km e por tonelada**, seja qual for a forma de cobrança | CT-e + contrato com a transportadora |
| **Diesel** | **ANP — levantamento semanal de preços** por município | Preço pago × preço médio da cidade | Notas de abastecimento (NF-e, F2T onda 3) |
| **Aluguel comercial** | **Índice FipeZAP comercial** (R$/m² de locação por cidade) **[A CONFIRMAR cidades cobertas]**; reajuste pelo **IGP-M e IVAR (FGV)** | R$/m² do contrato × mediana da cidade; reajuste aplicado × índice | m² e valor: **contrato de locação** |
| **Energia elétrica** | **ANEEL — tarifas por distribuidora e classe** (dados abertos); **CCEE — preço do mercado livre** | Tarifa paga × tarifa regulada da classe; e se o consumo permite migrar para o mercado livre | kWh, demanda e classe: **contas de luz** (a IA extrai do PDF) |
| **Água e esgoto** | **SINISA (antigo SNIS)** e agências reguladoras estaduais: tarifa média por prestador e município | R$/m³ pago × tarifa média do prestador | m³: **contas de água** |
| **Taxa de cartão (MDR)** | **Banco Central — estatísticas de cartões** (taxa média de desconto) | Taxa paga à adquirente × média do mercado | Extrato da adquirente ou contrato |
| **Tarifas bancárias** | **Banco Central — tarifas por banco** | Pacote pago × tarifa pública do mesmo banco | Extratos (F2T onda 2) |
| **Seguros** | **SUSEP — estatísticas por ramo e UF** | Prêmio sobre o valor segurado × média do ramo | Apólices |
| **Folha** | **RAIS** (§2.1) | Salário médio por cargo/setor/município × folha do cliente | Folha ou eSocial (F2T onda 4) |
| **Insumos e matéria-prima** | **IBGE — IPA/IPCA por item**; **CEPEA/ESALQ** (agro); **SINAPI** (construção, por estado) | Variação de preço paga × índice do insumo | Notas de compra (NF-e) |
| **Importação e exportação** | **Comex Stat (MDIC)**: preço médio FOB por produto (NCM) e por estado | Preço por kg importado ou exportado × média do Brasil e do estado | DI/DUIMP e DU-E (F2T onda 5) |
| **Tributos** | **CVM e IBGE** (§2.1): carga efetiva do setor | Carga efetiva do cliente × mediana do setor; regime tributário | ECF (F2T onda 1) |

**Ordem sugerida dentro desta tabela, por valor e por dado já previsto:** folha (RAIS), energia
(ANEEL), frete (ANTT, depende dos CT-e) e aluguel. Os demais entram sob demanda do mandato.

---

## §3 — O que muda no sistema

1. **Coletores**, um por fonte, gravando em `consulta_externa` (Espec. 13 §3) com os quatro
   estados: `encontrado`, `nada_encontrado` (com data), `falhou` (com motivo) e `nao_consultado`.
   Fontes públicas atualizam por agenda própria (trimestral, mensal, anual); o mandato lê a versão
   vigente e grava qual usou.
2. **Tabela de referência por setor**: mediana, quartis, tamanho da amostra, fonte, ano, recorte
   (Brasil ou UF). Calculada em SQL, de forma determinística. **A IA não calcula referência.**
3. **Índices do cliente**, calculados da **conta canônica** (F4). Por isso a F6C vem depois da F4:
   sem conta canônica, "despesa com frete" de uma empresa não é comparável com a de outra.
4. **Oportunidades**: uma linha por desvio, com conta, índice do cliente, referência, fonte e ano,
   diferença em R$ por ano, hipótese em texto e grau de confiança. A **IA** escolhe os pares (CNAE,
   porte, UF), aponta os desvios relevantes e escreve a hipótese; o **número** sempre vem da tabela
   de referência.
5. **Decisão do analista**: aceitar, recusar com motivo ou pedir mais dado ao cliente. A aceita vira
   **alavanca** (F8, "alavancas operacionais como categoria") e entra na modelagem e na apresentação.
6. **Blocos de despesa na seção Análise Comparativa** (D14.8), não no Kit Básico: energia, água,
   aluguel, frete, diesel, folha, cartão, tarifas bancárias, seguros. Cada bloco pede quantidade e
   valor por unidade do cliente (§3.1), digitados ou extraídos pela IA do documento anexado. Bloco
   não preenchido fica `n/d — bloco não preenchido`, com o efeito escrito: "custo unitário não
   comparado; só a proporção sobre a receita".
7. **Seção Análise Comparativa no portal**, entre a aprovação e a modelagem: o quadro do cliente
   contra pares, setor e região, os blocos de despesa com o cálculo ao lado, e a lista de
   oportunidades com os botões de decisão.

### 3.1 Operação em várias regiões (D14.9)

Uma média nacional aplicada a um cliente com fábrica em Goiás e centro de distribuição em São Paulo
não diz nada. O cálculo segue estes passos:

1. **Localizar as unidades.** O sistema lista todos os estabelecimentos do CNPJ do cliente (matriz e
   filiais, com estado e município) pelo **CNPJ aberto da Receita**, para cada empresa do perímetro
   (F1). O analista confirma a lista e acrescenta o que não tem CNPJ próprio (galpão alugado, obra,
   ponto de apoio).
2. **Preencher por unidade.** Cada bloco de despesa recebe quantidade e valor por unidade. Despesa
   que o cliente só tem consolidada pode ser rateada pelo analista, e o rateio fica escrito.
3. **Custo unitário por unidade:** valor ÷ quantidade (R$/kWh, R$/m², R$/m³, R$/km).
4. **Referência do lugar da unidade:** mediana do município quando a fonte publica, senão do estado.
   Se o estado não tem referência, a unidade fica `n/d — sem referência para <UF>`. A média nacional
   só entra se o analista escolher, e aparece rotulada como "referência nacional (UF sem dado)".
5. **Economia até a média, por unidade:** (custo unitário − referência) × quantidade, por ano. Só
   quando o cliente está acima. Abaixo, mostra "abaixo da média" e economia zero, nunca negativa.
6. **Total do cliente:** soma das economias das unidades, com a tabela por unidade ao lado. O total
   nunca esconde de qual unidade veio.
7. **Índices de setor (margem, prazos) com várias regiões:** ponderados pela receita de cada
   unidade quando o analista a informar. Sem receita por unidade, a comparação usa o estado da
   matriz e diz isso na tela.
8. **Apresentação de crédito**: o capítulo de comparativo setorial passa a ler esta tabela, com a
   coluna `Setor (fonte, ano)` que o prompt mestre já prevê.

---

## §4 — O plano, em etapas

| Etapa | Escopo | Depende de | Critério de pronto |
|---|---|---|---|
| **0 — Conferir as fontes** | Confirmar cada [A CONFIRMAR] da §2: formato, recorte, acesso, defasagem; cotação da Serasa | — | Cada fonte da §2.1 com acesso testado e o resultado escrito nesta especificação |
| **1 — Coletores públicos** | CVM, IBGE (SIDRA), RAIS, CNPJ aberto, Banco Central, Damodaran, gravando em `consulta_externa` | etapa 0 · Espec. 13 etapa 2 (`consulta_externa`) | Cada coletor grava os quatro estados; desligar um coletor aparece como `nao_consultado`, não como vazio (medido) |
| **2 — Referência por setor** | Mediana, quartis e amostra por CNAE e UF; mínimo de 4 empresas; sigilo do IBGE como `n/d` | etapa 1 | Setor com 3 empresas devolve `n/d` com o motivo (medido não-vazio) |
| **3 — Índices do cliente e oportunidades** | Índices sobre a conta canônica; oportunidade por desvio; hipótese escrita pela IA | etapa 2 · **F4** | Toda oportunidade cita fonte e ano; nenhuma referência sem fonte |
| **4 — Tela e decisão** | Seção Análise Comparativa; aceitar, recusar, pedir dado | etapa 3 | A aceita aparece na modelagem como alavanca; a recusada fica com motivo |
| **5 — Custo unitário por região** | Localizar as unidades (§3.1); blocos de despesa por unidade; custo unitário, referência do lugar e economia até a média; folha, energia, frete e aluguel primeiro (§2.2) | etapa 4 · F1 (perímetro) · F2T ondas 4 e 5 só para extrair de eSocial e CT-e | Cliente com 2 estados mostra 2 cálculos, cada um contra a referência do seu estado; unidade sem referência mostra `n/d`, não a média nacional (medido) |
| **6 — Apresentação** | Capítulo de comparativo setorial lendo a tabela de referência | etapa 4 · F15 | Número do comparativo no PPT igual ao do banco |
| **7 — Serasa** | Coletor pago, se a etapa 0 aprovar o custo | etapa 1 · decisão do dono | Idem etapa 1 |

---

## §5 — Regras (as sete do projeto, aplicadas aqui)

- **Diferença contra o setor é hipótese, não economia garantida.** A tela e a apresentação dizem
  "possível economia", nunca "economia". O cliente não pode ler promessa.
- **Ausência não é dado.** Setor sem amostra, célula em sigilo, bloco de despesa não preenchido:
  `n/d` com o motivo **e o efeito**.
- **Coletor que não rodou não parece coletor que não achou nada** (regra 7): `nao_consultado` e
  `falhou` são estados visíveis, nunca uma referência vazia.
- **Nenhum número sem fonte e ano**, inclusive no texto que a IA escreve.

---

## §6 — O que esta especificação não cobre

- Comparação com concorrente de capital fechado que não publica balanço (só pelo Serasa, etapa 7).
- Preço de venda do cliente contra concorrentes (aumento de faturamento por preço). Só onde houver
  base pública por produto, como o Comex Stat para exportação.
- Projeção do efeito da alavanca: isso é a modelagem (F7, F8), não esta fase.
