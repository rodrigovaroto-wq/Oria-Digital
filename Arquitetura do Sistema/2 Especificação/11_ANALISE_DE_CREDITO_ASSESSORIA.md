# 11 — Análise de crédito pela ótica da assessoria: Etapas 1 a 4

**Data:** 05/10/2026 · **Base:** `main` em `4b536bc` · **Natureza:** especificação. Nada aqui está
implementado; o que já existe está apontado com o arquivo que o prova. **Decisões do dono de
05/10/2026 incorporadas (§7):** D1, D3, D4, D7 e D8 decididas; D6 decidida em 13/10/2026 (ver a tabela); D5 e D9 em aberto.

**Origem, em ordem de autoridade:**

1. **As anotações da reunião do dono** (05/10/2026), reproduzidas na íntegra no §0. **São o fator
   decisivo:** onde elas e qualquer outra fonte divergirem, elas mandam.
2. O *Manual de Análise de Crédito com Estrutura Macro* (top-down, 10 etapas), produzido na mesma
   sessão a partir das metodologias de S&P, Moody's e Fitch, BIS, Resolução CMN 4.966 e dados de
   mercado de out/2026. É a moldura. As anotações são o conteúdo.
3. O que o sistema já tem, conferido nesta árvore: `ARQUITETURA_ALVO_E_ROADMAP.md`, as migrations
   da taxonomia (`0002`, `0187`), os índices macro (`N8N/lib/macro.mjs`) e os fatos materiais
   (`0148`/`0149`).

---

## A diferença de lente, em uma frase

O manual responde à pergunta do **credor**: *"empresto ou não?"*. A Oria, como assessoria do
devedor, responde à pergunta oposta: *"como entregar ao banco um dossiê mais completo, mais
profundo e mais rastreável do que ele montaria sozinho?"*. A posição da assessoria tem duas
vantagens:

| | Credor | Assessoria (Oria) |
|---|---|---|
| **Acesso** | O que o cliente decide mostrar, mais birôs | **Dentro da empresa:** SPED, razão, CAP, CAR, extratos, contratos, gestão |
| **Profundidade** | Aceita o índice declarado | Mostra **como o índice se forma**, documento a documento |
| **Tempo** | Fotografia na concessão, revisão anual | Acompanha o mandato inteiro, com versões |
| **Rastreabilidade** | Planilha do analista | **Cada número com documento, página e reconciliação** (L1 do roadmap) |
| **Postura** | Defensiva: procurar o motivo para negar | Antecipatória: achar **antes do banco** o que o banco vai achar, e já levar explicado |

A última linha define o produto. Toda descoberta negativa (fornecedor em RJ, processo contra
sócio, receita fiscal menor que a contábil) **vale mais achada por nós do que pelo banco**. Achada
por nós, chega à mesa explicada, com mitigante. Achada pelo banco, chega como surpresa e custa
credibilidade ao mandato inteiro.

---

## §0 — As anotações da reunião (fonte primária, na íntegra)

> primeira coisa
> Quais os segmentos que essa empresa atua?
> Associações de classe que representam aquele segmento?
> Periódicos, revistas, jornais, estudos de mercado, que tragam informações pertinentes daquele setor.
>
> Mapear a cadeia de suprimentos
> Quais o produtos, quais os principais fornecedores
> Qualidade de credito, competitividade do fornecedor
> câmbio influencia na cadeia de suprimentos, exposição cambial
>
> Onde buscar os indicadores do setor, quais indicadores.
>
> Quais matérias setorias talvez você tenha (cliente).
> Riscos regulatórios que podem afetar o setor. Clamor social, popularidade do produto.
> Indice de reclamação, Procon e Reclame aqui, notícias impopulares sobre a empresa, mídias sociais, ministério público, meio ambiente e etc.
>
> processos contra sócios, processos contra administradores
>
> Precisamos saber analisar Expedes fiscais, CAP, CAR, Extratos bancários. Esse é o principal fator que muda a analise como um todo

**Leitura adotada.** "Expedes fiscais" = **SPEDs fiscais** (ECD, ECF, EFD ICMS/IPI,
EFD-Contribuições). **CAP** = contas a pagar (aging de fornecedores). **CAR** = contas a receber
(aging de clientes). **Extratos bancários incluem OFX como formato de primeira classe**, por
pedido expresso do dono na mesma conversa ("adicione OFX tbm"), ao lado do PDF e do CSV do
internet banking. Ver §4.6.1. **Leitura confirmada pelo dono em 05/10/2026 (D1).**

### As notas numeradas, e onde cada uma vive neste documento

| # | Nota | Etapa | Seção |
|---|---|---|---|
| N1 | Segmentos em que a empresa atua | 2 | §2.1 |
| N2 | Associações de classe do segmento | 2 | §2.2 |
| N3 | Periódicos, revistas, jornais, estudos de mercado | 2 | §2.2 |
| N4 | Cadeia de suprimentos: produtos, fornecedores, crédito e competitividade do fornecedor, câmbio | 2 (mapa) + 4 (dado) | §2.4, §4.3 |
| N5 | Onde buscar os indicadores do setor, e quais | 2 | §2.3 |
| N6 | Materiais setoriais que o cliente tenha | 2 | §2.2 |
| N7 | Riscos regulatórios, clamor social, popularidade do produto | 3 | §3.3 |
| N8 | Reputação: Procon, Reclame Aqui, notícias, mídias sociais, Ministério Público, meio ambiente | 3 | §3.4 |
| N9 | Processos contra sócios e administradores | 3 | §3.5 |
| N10 | **SPED fiscal, CAP, CAR, extratos — "o principal fator que muda a análise como um todo"** | 4 | **§4 inteiro** |
| N10b | **OFX** (acrescentado pelo dono na mesma conversa) | 4 | §4.6.1 |

### O que as notas dizem sobre a ordem

1. **A nota N10 é a única que o dono qualificou**, e qualificou como a que muda tudo. Por isso a
   Etapa 4 não é "a análise financeira": é a **trilha transacional**, que confere a análise
   financeira contra o que realmente aconteceu no caixa, no fisco e nos títulos. É também a
   prioridade de construção (§6).
2. **A nota N4 cruza duas etapas.** O mapa da cadeia é uma pergunta setorial (Etapa 2), mas o
   **dado** que o responde com precisão está no SPED e no CAP (Etapa 4). É por isso que N10 "muda
   a análise como um todo": sem a trilha transacional, a cadeia de suprimentos é o que o cliente
   declara; com ela, é o que as notas fiscais mostram.
3. **As notas não falam de macro.** A Etapa 1 continua no documento porque o sistema já a tem
   pronta (§1) e porque a exposição cambial da N4 precisa dela. O que é novo nela é pouco.

---

## Como cada etapa está descrita

Toda etapa segue o mesmo molde, para poder virar fatia de construção sem reinterpretação:

- **Pergunta que responde**, na voz da assessoria.
- **Insumos:** do cliente (tipo da taxonomia, existente ou novo), públicos (fonte, forma de
  acesso) e já no sistema.
- **Procedimento** passo a passo.
- **Saída:** o que vai ao dossiê, com fórmula quando houver número.
- **As regras da casa aplicadas à etapa**, sempre as mesmas quatro:
  - **(R1) Ausência:** o que acontece quando o insumo não veio. Branco + nota com o motivo e o
    efeito, nunca zero nem "nada encontrado".
  - **(R7) Sinal de execução:** como se distingue "rodou e não achou" de "não rodou".
  - **Quem decide:** o sistema calcula ou aproxima; o analista julga. O teto de autonomia vem de
    `.claude/memory/teto-de-autonomia-por-natureza.md`.
  - **Proveniência:** de onde o número vem, em nível de linha ou registro.
- **Estado hoje** e **encaixe no roadmap.**

---

## ETAPA 1 — Contexto macroeconômico

**Pergunta:** em que ambiente a empresa vai gerar caixa e refinanciar dívida nos próximos 12 a 36
meses, e o que o banco vai supor sobre isso?

### 1.1 O que já existe — e é a parte mais pronta das quatro

| Item | Onde | Estado |
|---|---|---|
| Séries históricas mensais: IPCA, IGP-M, INPC, Selic e CDI acumulados no mês | `N8N/lib/macro.mjs` (`SERIES_MACRO`), BCB/SGS + IBGE/SIDRA | 🟢 coletado por workflow agendado |
| Expectativas Focus: IPCA, Selic, IGP-M, PIB, câmbio | `N8N/lib/macro.mjs` (`INDICADORES_FOCUS`) | 🟢 |
| Histórico × expectativa divergente | `fn_divergencias_indice_macro` (`0025`) | 🟢 |
| Premissa `indice_macro` consumindo as séries na projeção | `premissa_catalogo` (`0038`) | 🟢 |
| CDI parcial sem Focus deixa de virar juro zero | commits `bf19d42`, `e7362f6` | 🟢 |
| **Cenários como dado** (base, estresse, severo) | — | 🔴 só no Excel; não existe tabela `cenario` (F8) |

### 1.2 O que a assessoria acrescenta

1. **Ciclo de crédito, além do ciclo econômico.** É o que o banco usa e o sistema ainda não coleta:
   - concessão e inadimplência de PJ: BCB/SGS (séries de crédito do SFN por porte e modalidade);
   - pedidos de recuperação judicial e inadimplência de empresas: Serasa Experian (indicadores
     mensais publicados, sem API aberta, portanto coleta manual ou licença);
   - spread médio de PJ: BCB/SGS.

   **Por quê:** em out/2026 a Selic caiu para 13,75% (Copom, set/2026), mas 2025 fechou com
   recorde de 2.466 empresas em RJ e julho de 2026 com 9,2 milhões de CNPJs inadimplentes (Serasa).
   Com juro caindo e inadimplência recorde, o banco está na **fase seletiva** do ciclo, e o
   dossiê precisa ser escrito para essa fase: liquidez e refinanciamento primeiro, crescimento
   depois.
2. **Câmbio histórico (PTAX), não só a expectativa.** A exposição cambial da N4 (§2.4, §4.3) precisa
   do dólar mês a mês para medir o efeito de choques passados na margem. A série existe no BCB/SGS.
3. **O cenário de estresse que o banco vai rodar, antecipado.** Desde 01/01/2025 a Resolução CMN
   4.966 obriga o banco a provisionar por perda esperada **com cenários macro prospectivos**. O
   banco vai estressar o cliente de qualquer jeito. A assessoria entrega primeiro a projeção nos
   três cenários, com o ponto de ruptura dos covenants calculado.

### 1.3 Regras

- **(R1)** Série macro que não chegou fica em branco com a nota do efeito. O padrão já existe
  (`bf19d42`: "CDI parcial e sem Focus virava juro ZERO").
- **(R7)** O workflow macro grava a coleta por série. Série sem coleta no mês é distinguível de
  série coletada com valor estável.
- **Quem decide:** o choque de cada cenário é decisão do analista, registrada com autor e motivo.
  É o critério S1 do STRATEGY GATE.

### 1.4 Encaixe

Ciclo de crédito e PTAX: **constrói agora**. São séries novas no mesmo workflow, sem tocar o
caminho crítico. Cenários: **F8**, depois do motor (F7). Construir antes deixa o cenário fixo no
código, como alerta a "Paralelização PROIBIDA" do roadmap.

---

## ETAPA 2 — Setor, segmento e cadeia de suprimentos  *(notas N1–N6)*

**Pergunta:** em que mercados a empresa realmente atua, como esses mercados estão, onde ela compra
e quão frágil é a cadeia que a abastece?

### 2.1 Segmentos de atuação (N1)

O segmento declarado no contrato social raramente é o segmento econômico real. A assessoria
monta o mapa a partir de **três fontes que se conferem entre si**:

| Fonte | O que dá | Acesso |
|---|---|---|
| Cadastro CNPJ da Receita (CNAE principal e secundários, por estabelecimento) | O segmento **declarado** | Dados abertos do CNPJ (RFB), por CNPJ |
| **ECF, registro Y540** (receita de vendas por atividade econômica) | O segmento **faturado**, com o peso de cada um | SPED enviado pelo cliente (§4.2) |
| Faturamento por produto ou linha (FATURAMENTO_24M, gerencial) | O segmento **gerido** | Cliente |

**Procedimento:**

1. Para cada entidade do perímetro (F1 já resolve as entidades), coletar CNAE principal e
   secundários de **todos os estabelecimentos**, não só da matriz.
2. Se houver ECF, ler o Y540 e calcular o mix de receita por CNAE.
3. Confrontar: CNAE secundário com receita relevante no Y540 e ausente da apresentação do cliente
   é **pergunta ao cliente**. O contrário (segmento apresentado como estratégico e sem receita
   fiscal) também.
4. Classificar cada segmento numa **divisão CNAE** (2 dígitos). É a chave que liga o caso ao
   catálogo de fontes setoriais (§2.2) e de indicadores (§2.3).

**Saída:** tabela *segmento × entidade × % da receita × fonte*, com a divergência declarada.

### 2.2 Fontes setoriais: associações, periódicos, estudos e material do cliente (N2, N3, N6)

A recomendação é um **catálogo de fontes por divisão CNAE**, que cresce a cada mandato. É um dado
do sistema, não conhecimento na cabeça de quem fez o caso anterior. A forma é a mesma inversão da
`0038` (premissa) e da `0120` (pergunta): a fonte vira **linha numa tabela**.

| Campo do catálogo | Exemplo |
|---|---|
| divisão CNAE | 10 — Fabricação de produtos alimentícios |
| tipo | associação · periódico · estudo · órgão regulador · indicador oficial |
| nome | ABIA — Associação Brasileira da Indústria de Alimentos |
| o que oferece | anuário do setor, faturamento agregado, pauta regulatória |
| acesso | público · assinatura · associado |
| última verificação | data em que alguém confirmou que a fonte existe e publica |

**Semente inicial, por tipo, a validar caso a caso** (exemplos de associações reais; a lista
cresce com os mandatos):

- **Associações de classe:**
  - ABRAS (supermercados), ABAD (atacado distribuidor), ABIA (alimentos), ABPA (proteína animal);
  - ABIOVE (óleos vegetais), ÚNICA (cana e etanol), ABIMAQ (máquinas e equipamentos);
  - ABIQUIM (química), ABINEE (eletroeletrônico), ANFAVEA (veículos), ABIT (têxtil);
  - ABIHPEC (higiene e cosméticos), CBIC (construção), ABRAMAT (materiais de construção);
  - ABRASCE (shoppings), FEBRABAN (bancos).
  - Pelo princípio do §0, a associação certa é a do segmento faturado (§2.1), não a do CNAE
    declarado.
- **Indicadores oficiais e sondagens:**
  - IBGE: PIM-PF (indústria), PMC (comércio), PMS (serviços), PAIC (construção), PIA;
  - FGV IBRE: sondagens de confiança da indústria, comércio, serviços e construção;
  - CNI: sondagem industrial e utilização da capacidade;
  - CEPEA (agro);
  - Comex Stat (comércio exterior por NCM);
  - Novo CAGED (emprego por CNAE).
- **Periódicos e estudos:** Valor Econômico e Valor Setorial, revistas da associação do segmento,
  estudos setoriais do BNDES e do Ipea, relatórios setoriais das agências de rating (S&P, Fitch,
  Moody's) e relatórios de bancos de investimento quando o cliente tiver acesso.
- **Órgãos reguladores:** ANVISA, ANEEL, ANS, ANATEL, ANP, ANTT, ANAC, MAPA, CADE, BCB e CVM,
  conforme o segmento.

**Material do cliente (N6).** O cliente quase sempre tem material setorial: estudo contratado,
apresentação da associação, relatório de consultoria, benchmark de concorrentes. Hoje não há onde
pô-lo. Proposta: **tipo novo `ESTUDO_SETORIAL`** (complementar, escopo `caso`) e uma **pergunta
ao cliente** com gatilho `sempre` no banco de perguntas (`0120`): *"Que estudos, relatórios ou
apresentações sobre o seu setor a empresa tem?"*, com motivo, risco e impacto.

> **DECIDIDO pelo dono em 05/10/2026 (D4): o tipo `ESTUDO_SETORIAL` será criado.** O roadmap
> (§9, item 13) desaconselhava tipo novo antes de a F2 dar consumidor aos existentes; a F2 está
> com D6 verde em produção desde 22/09, então a restrição formal caiu. A condição para não abrir
> um 28º tipo mudo: o tipo nasce **com consumidor declarado** em `taxonomia_tipo_cobertura`. O
> leitor de fatos (§3.4) extrai do estudo afirmações com trecho e página, e é esse o consumidor.
> Sem ele, o tipo entra como `sem_consumidor` com motivo e efeito (`0187`), nunca em silêncio.

### 2.3 Indicadores do setor: onde buscar e quais (N5)

| Família | Indicadores | Fonte |
|---|---|---|
| **Volume e demanda** | produção física, vendas reais, volume de serviços, lançamentos e vendas (imobiliário), safra | IBGE (PIM, PMC, PMS), CONAB, associação |
| **Preço e custo** | IPA por setor (FGV), preço do insumo dominante (commodity), INCC, custo de frete | FGV, CEPEA, CBOT/LME, ANTT |
| **Confiança e capacidade** | índice de confiança setorial, utilização da capacidade instalada | FGV IBRE, CNI |
| **Emprego** | saldo de admissões por CNAE | Novo CAGED |
| **Comércio exterior** | exportação e importação por NCM do produto e do insumo | Comex Stat |
| **Crédito e estresse do setor** | inadimplência e RJs por setor, rebaixamentos de rating do setor | Serasa, BCB, agências |
| **Rentabilidade de pares** | margem EBITDA, alavancagem e giro de empresas comparáveis | demonstrações de companhias abertas (CVM) e emissores de debêntures |

**Quais são decisivos por setor:** a Seção 12 do manual (mapa de sensibilidade e fichas por setor)
é o ponto de partida. Cada ficha vira, no catálogo, a lista de indicadores da divisão CNAE.

**A régua da assessoria:** o indicador só entra no dossiê com **série de pelo menos 5 anos,
cobrindo uma recessão** (2015–16 é a referência brasileira), e com a empresa **posicionada contra
ele**: "o setor cresceu X%, a empresa cresceu Y%". Indicador do setor sem a empresa ao lado é
contexto, não análise.

### 2.4 Cadeia de suprimentos e exposição cambial (N4)

É aqui que a Etapa 2 depende da Etapa 4. A cadeia é montada **do dado fiscal para a narrativa**, e
não o contrário.

**Procedimento:**

1. **Produtos e insumos.** EFD ICMS/IPI, registro **0200** (cadastro de itens com NCM) cruzado com
   **C170** (itens das notas de entrada). Saída: os 20 insumos de maior valor comprado e a
   participação de cada um no CPV.
2. **Principais fornecedores.** EFD **C100** (notas de entrada) agregadas por participante
   (**0150**, que traz o CNPJ). Saída: os 20 maiores fornecedores, % das compras e concentração
   (índice HHI e participação dos 5 maiores). **Confere com o CAP** (§4.4): fornecedor grande nas
   compras e ausente do aging é pagamento à vista ou dado faltando. Fornecedor grande no aging e
   pequeno nas compras é atraso acumulado.
3. **Qualidade de crédito do fornecedor.** Para cada um dos 20 maiores, pelo CNPJ:
   - situação cadastral na Receita;
   - recuperação judicial ou falência (certidões e notícias);
   - protestos (CENPROT);
   - sanções (CEIS/CNEP).

   **Por quê:** o risco de quem compra é o fornecedor crítico quebrar e romper o abastecimento,
   mais do que ele cobrar. Com 30% das RJs de 2025 no agronegócio, um cliente que compra insumo
   agrícola de um fornecedor em RJ carrega risco de ruptura que nenhum índice próprio mostra.
4. **Competitividade e substituibilidade.** Para cada insumo crítico: quantos fornecedores
   alternativos aparecem na própria EFD (o mesmo NCM comprado de outro CNPJ), há quanto tempo o
   fornecedor principal atende (primeiro ano em que aparece no 0150), e se há contrato de
   fornecimento (`CONTRATOS_COM`). Insumo com **fornecedor único e sem alternativa histórica** é
   o achado que vai em destaque.
5. **Exposição cambial direta.** Pelo CFOP das notas:
   - **importações** (entradas CFOP 3.xxx) ÷ compras totais = exposição de custo;
   - **exportações** (saídas CFOP 7.xxx) ÷ receita = proteção natural.
6. **Exposição cambial indireta.** O insumo nacional cotado em dólar (grãos, aço, resinas,
   celulose, combustível) não aparece no CFOP. Identifica-se pelo NCM do 0200 contra uma lista
   de commodities, e se confirma com a correlação histórica entre o preço médio pago (C170) e a
   PTAX.
7. **Exposição líquida:**

   ```
   Exposição líquida (12m) = custo dolarizado (direto + indireto)
                           − receita dolarizada (exportação + preço indexado)
                           ± dívida em moeda estrangeira (MAPA_DIVIDA)
                           ∓ hedge contratado (derivativo, NDF)
   Sensibilidade = Δ EBITDA para ±10% e ±20% no câmbio
   ```

**Saída:** mapa da cadeia com nomes, CNPJs, % das compras, situação de crédito e substituibilidade.
Mais a exposição cambial líquida com sensibilidade, cada número apontando para a nota fiscal ou o
registro que o gerou.

### 2.5 Regras

- **(R1)** Sem EFD, os passos 1, 2, 4, 5 e 6 do §2.4 ficam **declarados não feitos**, com o
  efeito: "cadeia montada pelo que o cliente declarou, sem conferência fiscal". Nunca se apresenta
  uma lista de fornecedores tirada só do gerencial como se fosse a fiscal.
- **(R7)** Consulta externa de crédito do fornecedor grava, por fornecedor e fonte, a data da
  consulta e o resultado. "Consultado em 05/10, nada encontrado" é diferente de "não consultado".
  Esta é a regra 7 aplicada a fonte externa, e é onde ela mais vai ser violada se não for desenhada.
- **Quem decide:** concentração, HHI e exposição são cálculo (Classe A). "Fornecedor crítico" e
  "insumo sem substituto" são julgamento (Classe C): o sistema aproxima, o analista marca.
- **Proveniência:** cada fornecedor da lista aponta para os registros 0150/C100 de origem.

### 2.6 Estado e encaixe

| Item | Estado | Encaixe |
|---|---|---|
| Segmento por CNAE / Y540 | 🔴 | Constrói agora (cadastro externo, §5) + leitor ECF (§4.2) |
| Catálogo de fontes setoriais | 🔴 | Constrói agora: tabela + seed, sem dependência |
| Indicadores setoriais com série | 🔴 | Depois do catálogo. Comparação entre mandatos espera F4 (roadmap §9, item 15) |
| Cadeia de suprimentos | 🔴 | **Depende do leitor de EFD (§4.2).** Sem ele, não há o que construir com segurança |
| `ESTUDO_SETORIAL` + pergunta | 🔴 | Decisão do dono (§2.2) |

---

## ETAPA 3 — Negócio, reputação, regulação e pessoas  *(notas N7–N9)*

**Pergunta:** o que pode acontecer com esta empresa que não está no balanço: regulação, opinião
pública, fiscalização, processos, e as pessoas que a dirigem?

### 3.1 O que já existe

| Item | Onde | Estado |
|---|---|---|
| Tipos para documentos societários e legais: `CONTRATO_SOCIAL`, `ORGANOGRAMA`, `DOCS_SOCIOS`, `CERTIDOES`, `CONTINGENCIAS`, `SITUACAO_FISCAL`, `DEBITOS_TRIB`, `AVAIS_FIANCAS` | `0002` | 🟢 existem, **todos `sem_consumidor`** exceto o localizador de seção do contrato social (`0187`) |
| Fatos materiais lidos do texto: continuidade operacional, ressalva do auditor, covenant rompido, dívida reclassificada… | `fato_tipo_catalogo` (`0148`, `0149`) | 🟢 com trecho ≥ 20 caracteres obrigatório |
| Perímetro e grupo econômico, inclusive controle comum sem holding | F1 (`0181`, ficha `grupo-por-controle-comum-sem-holding`) | 🟡 em curso |
| Banco de perguntas ao cliente | `0120` | 🟡 11 de 36 seedadas |
| Política de LGPD por tipo (`pii`, `pii_sensivel`) | `0002`, `2 Especificação/10` | 🟡 |

### 3.2 Posição competitiva e gestão

O que o manual descreve na Etapa 3 (escala, diversificação, vantagem competitiva, governança,
política financeira, sucessão) continua valendo. A assessoria acrescenta a **evidência**:

- **Concentração de clientes** pela EFD (saídas C100 por participante) e pelo CAR (§4.5), não pela
  declaração do cliente.
- **Quem são os administradores de fato:** QSA da Receita × contrato social × organograma. A
  divergência entre os três é pergunta. A F1 já tem `papel_no_grupo` para isso.
- **Remuneração e retiradas dos sócios** pela ECF (registro Y600: identificação e remuneração de
  sócios) e pelo extrato (§4.6: transferências a CPFs dos sócios). Retirada relevante com a
  empresa em estresse é o primeiro ponto que o banco questiona.

### 3.3 Riscos regulatórios, clamor social e popularidade do produto (N7)

**Procedimento:**

1. **Agenda regulatória do segmento.** Pelos órgãos do catálogo (§2.2): consultas públicas
   abertas, revisões tarifárias, normas em tramitação, mudança tributária. Em 2026, a transição
   do IBS/CBS (reforma do consumo) é item obrigatório para todo setor com cadeia longa ou
   benefício fiscal de ICMS.
2. **Dependência regulatória da empresa.** Licenças e outorgas de que a operação depende
   (ambiental, sanitária, concessão), com vencimento. Sem licença vigente, a operação para, e isso
   é risco de continuidade, não de reputação.
3. **Clamor social e popularidade do produto.** O produto está sob pressão social (ultraprocessado,
   tabaco, bets, agrotóxico, plástico de uso único, crédito consignado…)? Há projeto de lei,
   campanha ou boicote em curso? A pergunta para o dossiê: **qual a probabilidade de a demanda ou a
   permissão de vender mudar por pressão não econômica nos próximos 3 anos**, e qual o efeito na
   receita.

**Saída:** matriz *risco × probabilidade (alta/média/baixa) × efeito estimado na receita ou no
custo × horizonte × fonte*. O efeito é obrigatório (R1): "risco regulatório alto" sem efeito
nomeado não entra.

### 3.4 Reputação: reclamações, notícias, redes, Ministério Público, meio ambiente (N8)

| Dimensão | Fonte | Acesso | Indicador |
|---|---|---|---|
| Reclamações de consumidor (federal) | Consumidor.gov.br | **Dados abertos**: base completa mensal em CSV no portal do Ministério da Justiça | volume mensal, índice de solução, satisfação, prazo de resposta, tendência de 24 meses |
| Procon | Sindec e portais estaduais (Procon-SP tem dados abertos) | Dados abertos parciais, por estado | reclamações fundamentadas, atendidas × não atendidas |
| Reclame Aqui | reclameaqui.com.br | **Sem API pública**: consulta manual do analista, ou licença | nota, índice de resposta, de solução e de "voltaria a fazer negócio" |
| Notícias | imprensa geral e setorial | Busca por razão social, nome fantasia, marcas e sócios | volume, tom e tema (fraude, acidente, demissão em massa, atraso salarial, RJ de cliente) |
| Mídias sociais | redes da empresa e menções | Manual ou ferramenta de monitoramento licenciada | crises recentes e tendência |
| Ministério Público | MPF, MPT, MPs estaduais; ações civis públicas | Pelos processos (§3.5) e pelas notícias; TAC por consulta ao órgão | ações e TACs em curso, objeto, valor |
| Meio ambiente | IBAMA: autos de infração e embargos | **Dados abertos** (dadosabertos.ibama.gov.br), por CPF/CNPJ | autos, valor, situação, área embargada |
| Trabalho | Cadastro de Empregadores (trabalho análogo à escravidão, MTE) | Lista pública semestral | presença na lista (efeito: restrição de crédito em bancos signatários de pactos) |
| Integridade | CEIS, CNEP, CEPIM (CGU) | **API do Portal da Transparência**, por CNPJ/CPF | sanções vigentes, órgão e fundamento (inclusive Lei 12.846) |
| Dívida ativa | Lista de devedores da PGFN | Dados abertos da PGFN | valor inscrito, situação, parcelamento |
| Protestos | CENPROT (cartórios) | Consulta pública por CNPJ/CPF | quantidade e valor |

**Procedimento:**

1. Montar a **lista de nomes a pesquisar**: razão social e CNPJ de cada entidade do perímetro,
   nomes fantasia e marcas, sócios e administradores (QSA + contrato social).
2. Rodar as fontes com acesso por dado aberto ou API **automaticamente**. Registrar fonte, data,
   parâmetro e resultado, **inclusive o vazio**.
3. As fontes manuais (Reclame Aqui, redes, notícias) entram como **tarefa do analista** com
   checklist, e o resultado volta como fato com fonte e data.
4. Notícias e material textual passam pelo **leitor de fatos** (o mesmo padrão de
   `fato_tipo_catalogo`, `0148`): a IA extrai afirmações com **trecho literal e fonte**, e
   classifica pelo catálogo (novos tipos de fato: `sancao_vigente`, `auto_ambiental`,
   `acao_mp`, `crise_reputacional`, `lista_trabalho_escravo`, `devedor_pgfn`…). **A IA não dá
   nota de reputação.** Ela aproxima a evidência, o analista conclui. É Classe C, teto N1.

**Saída:** quadro de reputação por dimensão, com tendência e cada achado com fonte, data e trecho.

### 3.5 Processos contra a empresa, os sócios e os administradores (N9)

A pesquisa precisa cobrir, além da empresa, **as pessoas**: sócios (inclusive PF por trás de
holdings), administradores estatutários e procuradores relevantes.

| Esfera | Como obter | Observação |
|---|---|---|
| Cível, falência e recuperação | Certidões de distribuição dos TJs (estadual) e TRFs (federal), por CPF/CNPJ | A certidão é a via oficial e é o que o banco pede |
| Trabalhista | CNDT (TST) + certidões dos TRTs | A CNDT só mostra débito em execução, não o passivo trabalhista em curso |
| Criminal | Certidões criminais estaduais e federais, por CPF | Para sócios e administradores |
| Execução fiscal | Certidões da Justiça Federal + dívida ativa da PGFN | Cruza com `SITUACAO_FISCAL` |
| Metadados processuais | **API pública do DataJud (CNJ)** | **Não busca por CPF/CNPJ**: só por número de processo. Serve para acompanhar os processos já identificados, não para descobrir |
| Descoberta por nome/documento | Provedores comerciais de consulta processual | **Decisão do dono:** custo, contrato e base legal LGPD |
| Bloqueios judiciais | Extrato (§4.6): débitos SISBAJUD/"bloqueio judicial" | O extrato mostra o que a certidão demora a mostrar |

**Procedimento:**

1. Gerar, por pessoa e esfera, a **lista de certidões a pedir** ao cliente. Elas entram como
   `CERTIDOES` (já existe), com a validade de 90 dias que a taxonomia já declara.
2. Ler cada certidão: positiva ou negativa, quantidade de processos, números. **A leitura é
   determinística no layout de cada tribunal sempre que possível; IA só no resíduo.**
3. Para cada processo identificado: classe, assunto, valor da causa, polo (ativo ou passivo),
   fase, último andamento (DataJud pelo número) e **provisão no balanço** (`CONTINGENCIAS`, notas
   explicativas).
4. **Reconciliar:** processo relevante na certidão e ausente do relatório de contingências é
   pendência (é o "Contingências vs certidões" da Classe C da `04_RECONCILIACAO`). Ação
   trabalhista em massa e ação do MP pesam mais que o valor da causa.

**LGPD e confidencialidade — DECIDIDO pelo dono em 05/10/2026 (D7).** Todo mandato tem NDA
assinado. O dado fica num banco **extremamente seguro e privado, sem possibilidade de vazamento**.
É o requisito. O que ele exige do sistema está no §7.1, porque **hoje o sistema não o cumpre**:
qualquer usuário autenticado lê todos os mandatos (`10_DADOS_RETENCAO_E_LGPD.md` §4).
`DOCS_SOCIOS` já é `pii_sensivel`, e as certidões de PF herdam a mesma classe.

### 3.6 Regras

- **(R1)** Certidão não entregue = "não pesquisado" + efeito ("passivo judicial do sócio X
  desconhecido"). Nunca "sem processos".
- **(R7)** Cada fonte externa grava o registro da consulta, mesmo vazia. Um quadro de reputação
  sem o registro de consulta de uma dimensão **mostra a dimensão como não pesquisada**.
- **Validade:** consulta e certidão têm prazo. O dossiê mostra a data, e a tela marca como vencida
  a que passou de 90 dias.
- **Quem decide:** tudo nesta etapa é Classe C. O sistema coleta e aproxima, o analista julga. Teto
  N1, por natureza (`teto-de-autonomia-por-natureza`).

### 3.7 Estado e encaixe

| Item | Estado | Encaixe |
|---|---|---|
| Cadastro CNPJ (QSA, CNAE, situação) | 🔴 | **Constrói agora**: é o insumo da F1 também |
| Consultas abertas (CEIS/CNEP, IBAMA, consumidor.gov, PGFN, lista do MTE) | 🔴 | **Constrói agora**: aditivo, sem dependência do DATA GATE (não é dado financeiro) |
| Leitura de certidões e reconciliação com contingências | 🔴 | F2 (dar consumidor a `CERTIDOES`/`CONTINGENCIAS`) |
| Leitor de fatos sobre notícias e material externo | 🟡 | Estende `0148` com tipos de fato novos |
| Provedor comercial de processos | ⚪ | Decisão do dono |

---

## ETAPA 4 — A trilha transacional: SPED, CAP, CAR e extratos  *(nota N10)*

**Pergunta:** o que as demonstrações dizem confere com o que aconteceu no fisco, nos títulos e no
caixa?

> **Por que esta é a nota que "muda a análise como um todo".** Demonstração financeira é uma
> **declaração**: balanço e DRE dizem o que a empresa afirma. SPED, CAP, CAR e extrato são
> **registros de transação**: a nota fiscal emitida, o título em aberto, o dinheiro que entrou e
> saiu. Para o banco, a demonstração é o ponto de partida. Para a assessoria, é a hipótese a
> conferir. Toda conclusão das etapas anteriores muda de grau de confiança quando a trilha
> transacional confirma ou contradiz:
> - a concentração de clientes;
> - a cadeia de fornecedores;
> - a receita, o prazo médio, o caixa;
> - as retiradas dos sócios.

### 4.1 A decisão de arquitetura que esta etapa exige

**Os quatro insumos não podem passar pela extração por IA do caminho atual.** O motivo está
medido, não suposto:

- Os extratos reais do mandato AMO **não passam pela ingestão**: são cerca de 125 a 150 mil itens
  e estouram o limite de tamanho (`ARQUITETURA_ALVO_E_ROADMAP.md`, F2, "Aceite financeiro da F2 —
  NÃO VERIFICADO").
- A exigência lexical sobre relatório itemizado foi **reprovada** contra produção: 17 pendências
  falsas em 64 pares caso × tipo, e 22 aprovações por linha residual (`0185` descartada; ficha
  `conceito-nao-esta-no-rotulo-de-relatorio-itemizado`).
- SPED é texto delimitado por `|` com **leiaute oficial publicado**. Mandar para um modelo de
  linguagem um arquivo cujo leiaute é lei é pagar para introduzir erro.

**Decisão proposta:** uma **trilha transacional determinística**, paralela à extração por IA.

```
                         ┌─ PDF/imagem/xlsx de demonstração ─► extração IA (caminho atual)
  Roteador de formato ───┤
  (já existe, 1.4)       └─ SPED .txt  (começa com |0000|)   ─┐
                            OFX / CNAB 240-400 / CSV bancário ├─► LEITORES DETERMINÍSTICOS
                            aging CAP/CAR em xlsx/csv         ─┘   (sem IA; leiaute → registro)
                                                                        │
                                       evidência transacional com proveniência por ARQUIVO+LINHA
                                                                        │
                                       reconciliações novas (fn_reconciliar_*) contra o BP/DRE
```

- **Princípio da casa respeitado:** determinístico primeiro, IA só no resíduo
  (`00_VISAO_E_ESCOPO`). A IA entra só para classificar a **descrição livre** de um lançamento
  bancário que as regras não resolveram, sob o dial (N0/N1).
- **Proveniência em grão mais fino que o atual.** A extração por IA aponta para documento e
  página. A trilha transacional aponta para o **registro**: "linha 48.112 do arquivo, registro
  C100, chave da NF-e…".
- **`campo_extraido` não muda.** As tabelas são novas, acima ou ao lado, como manda o roadmap
  (§9, item 9). Esboço:
  - `documento_fiscal_registro`: SPED, um registro por linha relevante;
  - `titulo_aberto`: CAP/CAR;
  - `lancamento_bancario`.

### 4.2 SPED — o que ler de cada escrituração

| Escrituração | Registros a ler | Para quê |
|---|---|---|
| **ECD** (contábil) | `0000` (entidade, período) · `I050` (plano de contas) · **`I051` (mapeamento para o plano referencial da RFB)** · `I150`/`I155` (saldos **mensais** por conta) · `I200`/`I250` (lançamentos, sob demanda) · `J100` (BP) · `J150` (DRE) | O balancete **mensal** oficial, assinado e transmitido, contra o balancete e as demonstrações que o cliente enviou |
| **ECF** | `L100` (BP referencial) · `L300` (DRE referencial) · `M300` (LALUR) · **`Y540`** (receita por atividade) · **`Y600`** (sócios e remuneração) | Receita fiscal, segmento faturado (§2.1), sócios e retiradas (§3.2), lucro real × contábil |
| **EFD ICMS/IPI** | `0150` (participantes, com CNPJ) · `0200` (itens, com NCM) · `C100` (notas) · `C170` (itens das notas) · `C190` (analítico por CFOP) · `E110` (apuração do ICMS) · `H010` (inventário) · bloco `K` (estoque escriturado, quando houver) | Clientes e fornecedores reais, insumos, câmbio por CFOP (§2.4), estoque fiscal, ICMS a recolher |
| **EFD-Contribuições** | `A100` (serviços) · `C100`/`C180` (vendas) · `M200`/`M600` (apuração de PIS/COFINS) | Receita para quem é de serviço ou não tem EFD ICMS/IPI |
| *(opcional)* **NF-e em XML** | emitente, destinatário, itens, CFOP, valor | Quando o cliente não tem a EFD organizada, ou para meses ainda não escriturados |

**Um achado de arquitetura que merece medição antes de qualquer promessa.** O `I051` da ECD é o
**mapeamento, feito pelo próprio contador, de cada conta do plano da empresa para o plano de
contas referencial da Receita**. É exatamente o problema da **F4** (conta canônica), que o roadmap
chama de "o buraco que segura tudo". Se o `I051` vier preenchido com qualidade nos mandatos reais,
ele é uma resolução `exata` gratuita para boa parte das contas. **Hipótese, não fato:** medir em
pelo menos três ECDs reais quantas contas analíticas têm I051 e quantas desse mapeamento um
analista confirmaria.

**Reconciliações que o SPED habilita** (todas Classe A ou B da `04_RECONCILIACAO`):

| # | Reconciliação | Classe | Divergência típica e leitura |
|---|---|---|---|
| S1 | DRE enviada × ECD `J150` × ECF `L300` | A | Demonstração "gerencial" diferente da transmitida ao fisco. **O achado mais importante possível**: qual é a verdadeira? |
| S2 | Balancete enviado × ECD `I155` do mesmo mês, conta a conta | A | Ajustes feitos depois da transmissão, ou balancete montado para a apresentação |
| S3 | Receita da DRE × Σ saídas da EFD (`C190`, CFOPs de venda) × faturamento 24m | B | Receita sem nota (informalidade) ou nota sem receita (devolução, bonificação, operação intragrupo) |
| S4 | Estoque do BP × inventário `H010` | B | Estoque contábil inflado. Na distress, o primeiro lugar onde se esconde perda |
| S5 | ICMS a recolher do BP × `E110` × `SITUACAO_FISCAL` | B | Imposto apurado e não pago, ou não declarado no passivo |
| S6 | Lucro contábil × LALUR (`M300`) | C | Adições e exclusões relevantes, com a explicação do analista |

### 4.3 Cadeia de suprimentos pelo dado fiscal

É a execução dos passos do §2.4 sobre os registros da EFD. Repetido aqui só para fixar a
dependência: **sem 4.2, o §2.4 não tem dado.**

### 4.4 CAP — contas a pagar

**Insumo:** `AGING_AP` (tipo existente, `sem_consumidor` desde a `0187`). Formatos: relatório do
ERP em xlsx ou csv, às vezes PDF. Colunas mínimas: fornecedor (nome **e CNPJ**), documento,
emissão, vencimento, valor, valor em aberto. Colunas desejáveis: natureza (mercadoria, serviço,
frete, imposto), situação (negociado, protestado).

**Leitor:** determinístico, reconhecendo as colunas pelo cabeçalho. A lição da `0185`: em
relatório itemizado **o rótulo é o item** (`41518 - WELLA BRASIL LTDA.`), e o conceito "fornecedor"
é o **tipo do documento**. O leitor não procura o conceito no rótulo, procura a estrutura da tabela.

**Procedimento e saídas:**

1. **Total do aging × fornecedores no BP** (ECD `I155` da conta de fornecedores, mesma data-base).
   Classe A. O `book-distress` já gera esse caso fechando: 12 fornecedores, total 14.900 =
   fornecedores do BP.
2. **Aging por faixa:** a vencer · vencido 1–30 · 31–60 · 61–90 · 91–180 · >180 dias, em valor e em
   número de fornecedores.
3. **Concentração:** os 10 maiores credores, % do total, HHI.
4. **Fornecedor crítico em atraso:** cruza com o §2.4. Atraso com quem não tem substituto é risco
   de ruptura operacional, não só financeiro.
5. **Prazo real de pagamento (DPO efetivo):** a data da baixa vem do **extrato** (§4.6), não da
   política. DPO contratado × DPO efetivo × DPO contábil (BP ÷ compras da EFD × 360).
6. **Partes relacionadas:** fornecedor cujo CNPJ está no perímetro ou no grupo (F1). Vai para a
   reconciliação intragrupo, e **não** entra como dívida operacional de terceiros.
7. **Passivo escondido:** título vencido há mais de 180 dias, renegociado ou protestado é
   **dívida**, não fornecedor. O mesmo critério do commit `01430ea` ("'capital de giro' no passivo
   é dívida financeira"). Risco sacado e forfait que aparecem no aging com o banco como credor vão
   para a dívida ajustada.

### 4.5 CAR — contas a receber

**Insumo:** `AGING_AR` (tipo existente, `sem_consumidor`). Mesmo leitor do CAP, com o cliente no
lugar do fornecedor.

**Procedimento e saídas:**

1. **Total do aging × clientes no BP.** Classe A.
2. **Aging por faixa**, como no CAP.
3. **PDD estimada × PDD contabilizada.** Aplica-se ao aging a perda histórica por faixa (quando há
   histórico de baixa) ou a régua do setor. Diferença material é ajuste ao PL e ao EBITDA, a
   decisão é do analista.
4. **Concentração de clientes:** os 10 maiores, % do total, HHI, confirmados pela EFD (saídas por
   participante, §3.2).
5. **Crédito do cliente:** os 20 maiores pelo CNPJ (situação, RJ, protestos), como no §2.4 passo 3.
   **Cliente relevante em RJ é recebível a provisionar**, e é o tipo de achado que o banco acha
   primeiro se a assessoria não achar antes.
6. **Recebível já comprometido:** duplicata descontada, cessão a FIDC, trava de cartão,
   antecipação. O título continua no aging, mas **não é livre**. Cruza com `MAPA_DIVIDA`,
   `GARANTIAS` e com o extrato (entradas de antecipação). Recebível dado em garantia e contado
   como liquidez é o erro clássico do quadro de fontes e usos.
7. **Prazo real de recebimento (DSO efetivo):** entrada no extrato × vencimento do título.

### 4.6 Extratos bancários

**Insumo:** `EXTRATO_BANCARIO` (tipo existente, `sem_consumidor`). Formatos, do melhor para o
pior:

1. **OFX**, padrão de mercado e estruturado;
2. **CNAB 240/400** de extrato, posicional e com leiaute da FEBRABAN;
3. **CSV/xlsx** do internet banking, com cabeçalho variável por banco;
4. **PDF**, que exige leitura de tabela com o mesmo leitor da extração, mas determinístico por
   leiaute de banco sempre que possível.

**Via alternativa, a decidir:** compartilhamento por **Open Finance**. A PJ pode consentir no
compartilhamento de contas e transações, por representante legal, com finalidade e prazo
definidos. Isso elimina o arquivo e o formato, mas exige ser participante ou contratar um
agregador. **Decisão do dono**, com custo e LGPD.

**Procedimento e saídas:**

1. **Conciliação de saldo:** saldo final do extrato em cada fechamento × caixa e bancos do BP
   (`I155`). Classe A, por conta bancária. O `book-distress` já gera o caso fechando: 12 meses,
   676 = caixa do BP.
2. **Cobertura:** todas as contas do CNPJ estão presentes? A lista de contas vem do BP (contas
   analíticas de bancos), do `MAPA_DIVIDA` e do Registrato/SCR do cliente. **Conta bancária que
   existe e não veio é pendência** (R1), porque o caixa conciliado sem ela é parcial.
3. **Classificação dos lançamentos**, por regra primeiro (palavra-chave da descrição, CNPJ da
   contraparte, código do histórico do banco) e IA no resíduo, sob o dial:

   | Entradas | Saídas |
   |---|---|
   | recebimento de clientes | fornecedores |
   | antecipação/desconto de recebíveis | folha e encargos |
   | empréstimo novo | tributos |
   | aporte de sócio | juros e amortização |
   | intragrupo | **retirada ou transferência a sócio** |
   | resgate de aplicação | intragrupo |
   | outros | tarifas, IOF |
   | | **bloqueio judicial** |
   | | outros |
4. **Os sinais que só o extrato mostra:**
   - dias com saldo negativo e uso de cheque especial ou conta garantida;
   - tarifas de excesso de limite;
   - cheque devolvido;
   - **bloqueio judicial (SISBAJUD)**, que alimenta o §3.5;
   - pagamento a sócios ou a CPFs ligados com a empresa em estresse;
   - recebimento concentrado num único pagador não declarado como cliente relevante;
   - antecipação recorrente de recebíveis, que é **dívida de curtíssimo prazo** que não aparece no
     `MAPA_DIVIDA`.
5. **Caixa efetivo mensal:** entradas e saídas operacionais, financeiras e de sócios. É o **dado**
   do 13 semanas, que o roadmap (§4.2) manda entrar cedo, na F2, separado da projeção semanal, que
   espera o motor.
6. **Prazos efetivos:** DPO e DSO reais (§4.4 passo 5, §4.5 passo 7).

#### 4.6.1 OFX — o formato preferido, e o que ler dele

O OFX (*Open Financial Exchange*) é o formato que os bancos brasileiros relevantes exportam pelo
internet banking e que ERPs e sistemas contábeis importam. Depois de uma API, é o melhor insumo de
extrato que existe: **estruturado, com saldo declarado pelo banco e com identificador único por
lançamento**. Na lista de documentos, a regra deve ser pedir OFX ao cliente antes de PDF.

**Duas famílias de arquivo, e o leitor precisa ler as duas:**

| Versão | Forma | Como reconhecer |
|---|---|---|
| OFX 1.x (1.02, 1.03, 1.6) | **SGML**: tags sem fechamento obrigatório (`<TRNAMT>-150.00` sem `</TRNAMT>`) | cabeçalho em texto (`OFXHEADER:100`, `DATA:OFXSGML`, `CHARSET:1252`) antes de `<OFX>` |
| OFX 2.x (2.0+) | **XML** bem-formado | `<?xml ...?>` + `<?OFX OFXHEADER="200" ...?>` |

A expectativa é que a maior parte dos bancos brasileiros exporte o 1.x em SGML, com `CHARSET:1252`
ou `8859-1`. **Medir na primeira rodada real, não supor.** Daí duas exigências para o leitor:

- **não pode depender de um parser XML puro**;
- **precisa respeitar o charset declarado.** Senão, uma descrição acentuada como "PAGAMENTO
  FORNECEDOR" vira lixo, e a classificação por regra (§4.6 passo 3) falha **em silêncio**.

**O que ler:**

| Elemento | Conteúdo | Uso |
|---|---|---|
| `<BANKACCTFROM>`: `BANKID`, `BRANCHID`, `ACCTID`, `ACCTTYPE` | banco (código COMPE), agência, conta, tipo | identidade da conta, para a cobertura de contas (§4.6 passo 2) |
| `<CURDEF>` | moeda | conta em moeda estrangeira não soma com BRL. É o mesmo comportamento do export (roadmap §9, item 12) |
| `<BANKTRANLIST>`: `DTSTART`, `DTEND` | período coberto pelo arquivo | **A cobertura de período vem daqui, não das datas dos lançamentos.** Dentro de `DTSTART–DTEND`, período sem lançamento é período sem movimento. Fora dele, é período **sem extrato** (R1) |
| `<STMTTRN>`: `TRNTYPE`, `DTPOSTED`, `TRNAMT`, **`FITID`**, `CHECKNUM`, `REFNUM`, `MEMO`/`NAME` | cada lançamento | O lançamento em si. `TRNTYPE` (CREDIT, DEBIT, FEE, SRVCHG, INT, XFER, CHECK, PAYMENT, DIRECTDEBIT…) é a primeira regra de classificação, antes da descrição |
| `<LEDGERBAL>`: `BALAMT`, `DTASOF` | **saldo declarado pelo banco** | o controle positivo do arquivo (abaixo) |
| `<AVAILBAL>` | saldo disponível | A diferença para o `LEDGERBAL` é bloqueio, limite ou valor retido. Alimenta o §3.5 |
| `<CCSTMTRS>` (em vez de `<STMTRS>`) | **fatura de cartão de crédito corporativo** | dívida de curtíssimo prazo e despesa que muitas vezes não passa pelo CAP |
| `<INVSTMTRS>` | extrato de investimentos | aplicações financeiras, conferidas com `APLIC_FINANC` |

**Os três controles que o OFX dá de graça (regras 2 e 7):**

1. **O saldo amarra.** Saldo inicial (o `LEDGERBAL` do arquivo anterior da mesma conta) +
   Σ`TRNAMT` = `LEDGERBAL.BALAMT` final. Se não amarrar, o arquivo está **truncado ou editado**:
   falha visível, nunca conciliação aceita. É o equivalente do registro `9999` do SPED (§4.8).
2. **O `FITID` deduplica.** O cliente vai mandar arquivos com períodos sobrepostos (jan–mar e
   mar–mai). O `FITID` é único por conta no banco emissor, então o mesmo lançamento em dois
   arquivos é **o mesmo lançamento**. É o que a dedup por fingerprint da `0118` faz com o
   documento inteiro. Sem isso, o caixa do mês sobreposto dobra e nada acusa.
   **Hipótese a medir:** há bancos que geram `FITID` diferente para o mesmo lançamento em
   exportações distintas. Teste na primeira rodada real: exportar o mesmo período duas vezes e
   comparar os `FITID`. Onde forem instáveis, a dedup cai para (conta, data, valor, descrição),
   que é mais fraca, e o dossiê declara qual chave foi usada.
3. **Período declarado × lançamentos.** Lançamento fora do `DTSTART–DTEND` indica arquivo
   malformado.

**O que o OFX não tem, e por isso CSV e PDF continuam necessários:**

- **Contraparte estruturada.** O CNPJ ou CPF de quem paga ou recebe, quando aparece, vem no texto
  livre do `MEMO`. Extrai-se por regra (máscara de CNPJ/CPF no texto), e IA só no resíduo.
- **Histórico longo.** A exportação OFX costuma ter janela limitada pelo banco. Os 24 meses de
  histórico podem existir só em PDF. **Medir por banco**, porque a janela varia.
- **Saldo diário.** O OFX traz o saldo final. O saldo de cada dia (para "dias com saldo
  negativo") é **reconstruído** somando os lançamentos. Reconstruído não é declarado, e o dossiê
  diz qual é qual.

**Proveniência:** cada lançamento aponta para arquivo + `FITID` (ou arquivo + posição, quando o
banco não traz `FITID`). É mais fino que página e mais estável que número de linha.

### 4.7 O que a trilha transacional devolve às etapas anteriores

| Achado da Etapa 4 | Muda o quê |
|---|---|
| Receita fiscal ≠ receita da DRE (S1, S3) | **Todos** os indicadores da análise financeira e a credibilidade do dossiê |
| Mix de receita por CNAE (Y540) | Os segmentos da Etapa 2 e as fontes setoriais escolhidas |
| Fornecedores e insumos reais (EFD) | A cadeia de suprimentos e a exposição cambial (N4) |
| Clientes reais e concentração (EFD + CAR) | A posição competitiva da Etapa 3 |
| Retiradas de sócios (extrato + Y600) | Governança e política financeira (Etapa 3) |
| Bloqueio judicial (extrato) | Processos (N9), antes de a certidão mostrar |
| Antecipação, cessão e desconto (extrato + CAR) | Dívida ajustada e liquidez real (manual, Etapas 4 e 6) |
| Estoque fiscal × contábil (H010) | PL ajustado e capital de giro |
| DPO e DSO efetivos | Ciclo de caixa e premissas de giro do modelo (`dias_de_giro`) |

### 4.8 Regras

- **(R1)** Cada insumo da trilha tem um **estado declarado por entidade e período**: recebido e
  lido · recebido e ilegível (com o motivo) · não recebido. O dossiê nunca mostra "conciliação OK"
  sobre um conjunto parcial de contas bancárias ou de meses. **Mês sem extrato é mês sem extrato,
  não mês sem movimento**: é a regra R9 do roadmap ("semana ausente é pendência, nunca zero")
  aplicada ao mês.
- **(R7)** O leitor de SPED grava quantas linhas leu por registro e o total do `9999` (encerramento
  do arquivo, que traz a contagem de linhas declarada). Linhas lidas ≠ declaradas = arquivo
  truncado, e isso é **falha visível**. É o controle positivo que a ficha
  `verificador-sem-controle-positivo` exige, e o SPED o traz de graça.
- **Quem decide:**
  - conciliações de saldo, totais e contagens são Classe A, e o sistema decide;
  - receita fiscal × contábil é Classe B, com banda de materialidade;
  - "qual DRE é a verdadeira", "esse recebimento é de cliente ou de sócio" e "esse título vencido
    é dívida" são Classe C: o sistema aproxima e o analista decide.
- **Escala:** o leitor não pode carregar 150 mil lançamentos na memória de um nó Code (ficha
  `stack-overflow-push-arr-node22-limite-empirico`; a S103 já perdeu uma planilha grande na pilha
  do Merge). Leitura em fluxo, gravação em lote.
- **PII:** extrato tem CPF de empregado, sócio e terceiros, e folha tem salário. `EXTRATO_BANCARIO`
  sobe para `pii_sensivel`, e nenhum lançamento é gravado antes do requisito de segurança do §7.1
  (D7).
- **Opcional, mas usado de forma ativa e clara (D3, decidido em 05/10/2026).** SPED, CAP, CAR e
  extrato **não são obrigatórios**: não entram no Kit Básico e a ausência deles não trava o
  mandato. Isso não os torna passivos. O sistema tem três obrigações quando eles vierem e uma
  quando não vierem:
  1. **Identificar pelo conteúdo, não pelo nome.** SPED começa com `|0000|` e traz o tipo de
     escrituração no próprio registro; OFX declara o cabeçalho (`OFXHEADER`); CNAB tem leiaute
     posicional reconhecível. Um arquivo `relatorio_final.txt` que é uma ECD é tratado como ECD. O
     roteador de formato (parte 1.4 de `COMO_O_SISTEMA_FUNCIONA.md`) ganha esses reconhecedores
     antes da classificação pelo nome.
  2. **Usar sem o analista pedir.** Chegou ECD, as reconciliações S1 e S2 rodam sozinhas. Chegou
     OFX, a conciliação de saldo roda. Chegou aging, o total × BP roda.
  3. **Mostrar o uso de forma explícita.** O dossiê e a tela do caso trazem um quadro **"Trilha
     transacional"** por entidade e período, com três estados: *usado* (quantas linhas, quais
     reconciliações rodaram e o resultado), *recebido e não lido* (com o motivo) e *não recebido*.
     Cada número do dossiê que foi confirmado ou contradito pela trilha carrega essa marca.
  4. **Quando não vier:** a ausência aparece como **nota com o efeito**, não como pendência
     bloqueante. Exemplo: "sem SPED: receita conferida só contra o que o cliente declarou". É a
     regra 1 aplicada a um insumo opcional: o banco precisa saber o que **não** foi conferido.

### 4.9 Estado e encaixe

| Item | Estado hoje | Encaixe |
|---|---|---|
| Tipos `SPED`, `AGING_AP`, `AGING_AR`, `EXTRATO_BANCARIO` | 🟢 existem, todos **`sem_consumidor`** (`0187`); **zero SPED em produção** | — |
| Book sintético com aging e extrato fechando no BP | 🟢 `book-distress` (F2.4, `cc9f8f5`), **sem fixture SQL** | Vira a fixture da trilha |
| Leitor de SPED (ECD, ECF, EFD) | 🔴 | **F2**: é dar consumidor ao tipo `SPED`. Aditivo, o leiaute é oficial e o risco é baixo |
| Leitor de CAP/CAR | 🔴 | **F2** (consumidor de `AGING_AP`/`AGING_AR`), sem exigência lexical |
| Leitor de extrato (OFX/CNAB/CSV) | 🔴 | **F2** para o DADO, como o roadmap §4.2 já decide. A projeção semanal é **F10**, depois do motor |
| Reconciliações S1–S6, CAP/CAR × BP, extrato × caixa | 🔴 | F2/F6: as de saldo e total podem nascer já; as que dependem de conta canônica esperam F4 |
| Uso do `I051` como resolução de conta | ⚪ hipótese | **Medir** em ECDs reais antes de propor para a F4 |
| Indicadores derivados (DPO/DSO efetivos, exposição cambial, HHI) | 🔴 | Os **factuais** (sobre o realizado) cabem na F2 como diagnóstico factual. Os **projetados** esperam F7 e F11 |

---

## §5 — O que atravessa as quatro etapas: fonte externa como dado

As Etapas 2 e 3 trazem algo que o sistema nunca teve: **dado que não vem do cliente**. Hoje tudo
chega por documento enviado. A recomendação é um modelo único para toda consulta externa, para que
a regra 7 valha por construção e não por disciplina:

```
consulta_externa(
  caso, entidade|pessoa, fonte, parametro,          -- o que se perguntou, a quem
  consultado_em, validade_ate,                      -- quando, e até quando vale
  resultado ∈ {encontrado, nada_encontrado, falhou, nao_consultado},
  evidencia (payload bruto ou arquivo), autor (sistema|analista)
)
fato_externo(consulta_id, tipo (do catálogo), trecho, valor, data_do_fato)
```

- `nada_encontrado` e `nao_consultado` são **estados diferentes**, e o dossiê os mostra de forma
  diferente. Esse é o ponto da regra 7 inteiro.
- `falhou` (API fora, CAPTCHA, timeout) não pode virar `nada_encontrado`. É a família do
  `.claude/memory/credencial-do-n8n-quebra-sem-deixar-rastro.md`.
- A **validade** força a reconsulta: certidão vale 90 dias, e reputação, sanção e protesto vencem
  na data em que o dossiê é atualizado.
- A consulta manual do analista (Reclame Aqui, redes, notícias lidas por ele) usa **a mesma
  tabela**, com `autor = analista`. Assim o dossiê não distingue a origem na apresentação, mas o
  banco distingue na auditoria.

---

## §6 — Plano de construção proposto, em fatias

Ordem pela nota do dono (N10 primeiro) e pelo que o roadmap permite construir sem retrabalho. Cada
fatia leva o critério de pronto e o **sinal positivo de execução** (regra 7). Toda fatia segue as
sete regras do `CLAUDE.md`: invariante medido não-vazio, uma fatia por commit, porquê com número.

| # | Fatia | Fase | Depende de | Pronto quando | Sinal de que rodou |
|---|---|---|---|---|---|
| **T0** | **Requisito de segurança da D7** (§7.1): segregação por mandato, leitura por papel, registro de leitura, retenção | F17, **antecipada** | — | usuário do mandato A recebe 0 linhas do mandato B em toda tabela da trilha; leitura de extrato gera evento | teste de RLS com dois usuários e dois casos, medido não-vazio (desligar a policy reprova) |
| **T1** | Leitor de **ECD** (`0000`, `I050`, `I051`, `I155`, `J100`, `J150`) + reconciliações S1 e S2 | F2 | — | ECD do book reconcilia com o BALANCETE e a DRE do mesmo book; ECD alterada em 1 conta reprova | linhas lidas por registro == `9999` declarado |
| **T2** | Leitor de **extrato OFX** (1.x SGML e 2.x XML, charset declarado, `FITID`, `LEDGERBAL`, cartão via `CCSTMTRS`) + CSV + conciliação de saldo × caixa do BP + cobertura de contas | F2 | **T0** | `book-distress` exportado também em OFX: 12 meses, 676 = caixa do BP; remover um mês reprova como "mês ausente", não como saldo zero; o mesmo período em dois arquivos não dobra o caixa (`FITID`); um lançamento apagado do OFX reprova no saldo amarrado | Σ`TRNAMT` + saldo inicial == `LEDGERBAL`, por arquivo; meses lidos × meses esperados, por conta |
| **T3** | Leitor de **CAP/CAR** + total × BP + aging por faixa + concentração | F2 | — | `book-distress`: 14.900 = fornecedores do BP | títulos lidos × linhas do arquivo |
| **T4** | Leitor de **EFD ICMS/IPI** (`0150`, `0200`, `C100`, `C170`, `C190`, `H010`) + S3, S4 + cadeia de suprimentos + câmbio por CFOP | F2 | T1 (data-base) | book com EFD sintética: os 20 maiores fornecedores conferem com o CAP | idem T1 |
| **T5** | Leitor de **ECF** (`Y540`, `Y600`, `L300`) + mix por CNAE + sócios | F2 | T1 | Y540 soma a receita da `L300` | idem T1 |
| **T6** | `consulta_externa` + Receita CNPJ (QSA, CNAE) + CEIS/CNEP + IBAMA + consumidor.gov + PGFN + lista do MTE | lateral | — | consulta vazia aparece como `nada_encontrado` com data; API derrubada aparece como `falhou` | uma linha por (entidade × fonte) por rodada, inclusive vazia |
| **T7** | Crédito dos 20 maiores fornecedores e clientes (T4/T3 × T6) | lateral | T3, T4, T6 | fornecedor em RJ no book aparece marcado | idem T6 |
| **T8** | Catálogo de fontes setoriais por divisão CNAE + seed + pergunta "material setorial" | lateral | T5 (segmento faturado) | caso do book mostra as fontes da sua divisão | — |
| **T9** | Certidões e contingências: leitura + reconciliação processo × provisão | F2 | T6, **T0** | processo da certidão ausente das contingências abre pendência | certidões lidas × pessoas da lista |
| **T10** | Leitor de fatos sobre notícias e material externo (tipos de fato novos) | estende `0148` | T6 | fato sem trecho literal é recusado (como hoje) | — |
| **T11** | Medição do `I051` (D8): em ECDs reais, % de contas analíticas com mapeamento referencial e % que o analista confirma | entrada da F4 | T1 + **ECDs reais do dono** | número publicado por ECD, com a amostra | contas lidas × contas com `I051` |
| — | Indicadores projetados, cenários, 13 semanas projetado, rating sombra | F7 · F8 · F10 · F11 | DATA GATE | — | — |

**T0 vem antes de T2 e de T9**, que gravam extrato e certidão de PF. T1, T3 e T6 não gravam PII
sensível e podem começar antes.

**Uma onda paralela possível**, pelo critério de `5 Prompts/03-onda-paralela.md`: **T0 ∥ T1 ∥ T3 ∥
T6**. São quatro frentes com arquivos e tabelas disjuntos e sem dependência entre si. A T2 entra
na onda seguinte, porque depende da T0. Se a T0 aplicar RLS às tabelas que T1, T3 e T6 criam,
deixa de ser disjunta delas: nesse caso as policies dessas tabelas nascem dentro de cada fatia, e
a T0 cobre só as tabelas que já existem. Conferir a
disjunção antes de despachar: se dois deles tocarem o roteador de formato do n8n na mesma onda, os
conjuntos deixam de ser disjuntos.

**Material de teste:** o `book-distress` já tem aging e extrato fechando no BP e é determinístico. Falta:

1. SPED sintético (ECD, EFD e ECF) do mesmo grupo fictício, gerado pelo mesmo gerador, para que as
   três pontas se confiram (a disciplina das fixtures do `CLAUDE.md`);
2. pelo menos **um SPED real** de mandato, porque a regra 4 proíbe provar comportamento de
   produção com fixture inventada, e o `I051` real é a pergunta do §4.2.

---

## §7 — Decisões do dono

**Respostas do dono em 05/10/2026.** As decisões tomadas valem como requisito. As abertas ficam
abertas, sem recomendação transformada em decisão.

| # | Decisão | Estado | O que fica valendo |
|---|---|---|---|
| D1 | "Expedes fiscais" = SPEDs; CAP/CAR = contas a pagar e a receber | ✅ **decidido** | A leitura do §0 está confirmada |
| D2 | Trilha transacional **determinística** separada da extração por IA | ⚪ não perguntada à parte | Segue como proposta do §4.1. A D3 a pressupõe: só um leitor determinístico identifica o arquivo pelo conteúdo |
| D3 | Os quatro tipos são obrigatórios? | ✅ **decidido: não são obrigatórios**, mas o sistema **identifica quando vierem e os usa de forma ativa e clara** | §4.8: identificação pelo conteúdo, uso automático, quadro "Trilha transacional", ausência como nota com efeito e nunca como pendência bloqueante |
| D4 | Tipo novo `ESTUDO_SETORIAL` | ✅ **decidido: criar** | §2.2: nasce com consumidor declarado (leitor de fatos) |
| D5 | Provedor comercial de processos | 🟡 **em pesquisa desde 26/10/2026** (D13.3 da Espec. 13): Exato Digital × API processual, medido no mandato AMO | Até lá, certidões (§3.5) |
| D6 | Open Finance para extratos | 🔁 **REVISTA em 26/10/2026: reabre** (D13.1 da Espec. 13). Antes, em 13/10/2026: não | OFX e CNAB `E` continuam; o Open Finance entra como fonte a mais quando houver consentimento (Espec. 13, Etapa 7) |
| D7 | Segurança e base legal do dado sensível | ✅ **decidido: NDA em todo mandato; banco extremamente seguro e privado, sem possibilidade de vazamento** | §7.1: o que isso exige, e a constatação de que hoje não está cumprido |
| D8 | Medir o `I051` em ECDs reais | ✅ **decidido: medir** | Fatia T11. **Precisa de ECDs reais**, que só o dono fornece (pelo menos três, de mandatos diferentes) |
| D9 | Reclame Aqui e redes sociais | ⚪ **em aberto**: "analisar e pensar como utilizar" | O §3.4 mantém a dimensão, e ela aparece como "não pesquisada" (R7) até haver decisão |

### 7.1 O que a D7 exige do sistema, e o que existe hoje

A decisão é clara: **o dado fica num banco seguro e privado, sem possibilidade de vazamento**. O
repositório mede que hoje isso **não** é verdade, e a diferença precisa ser dita antes de o
primeiro extrato ser gravado, não depois.

| Requisito da D7 | Estado hoje, medido | Fonte |
|---|---|---|
| Quem não trabalha no mandato não vê o mandato | 🔴 **qualquer usuário autenticado lê todos os mandatos.** A policy de leitura é "autenticado pode tudo" desde a `0003` | `10_DADOS_RETENCAO_E_LGPD.md` §4 |
| Leitura controlada por papel | 🔴 o papel (`0107`) controla a escrita do Portão 2, não a leitura | idem |
| Saber quem leu o quê | 🔴 a trilha registra o que foi **decidido**, não o que foi **lido** | idem |
| Onde o dado fica, retenção e destruição ao fim do mandato | 🟠 **[A CONFIRMAR]** no próprio documento: região, retenção do arquivo e do dado extraído, obrigação de destruição | idem, §1–§2 |
| Arquivo original durante o processamento | 🟠 passa pelo n8n; a retenção dos logs de execução está **[A CONFIRMAR]** | idem, §5 |

**Consequência para o roadmap.** O `ARQUITETURA_ALVO_E_ROADMAP.md` (§9, item 8) adiou
"multi-tenancy / RLS por caso" porque "não bloqueia o caminho crítico". **Com a D7 e com a
trilha transacional, passa a bloquear**: extrato, certidão de sócio PF e folha não podem ser
gravados num banco em que todo usuário lê todo mandato. Por isso existe a fatia **T0**, que
antecipa da F17 o mínimo para a trilha:

1. **segregação por mandato:** RLS por `caso_id` em toda tabela nova da trilha, e nas antigas
   que guardam dado do cliente;
2. **leitura por papel:** o analista vê os mandatos a que foi atribuído, e o sênior os que
   supervisiona;
3. **registro de leitura** das tabelas sensíveis (extrato, certidões, documentos dos sócios) em
   `evento_auditoria`;
4. **resposta aos [A CONFIRMAR]** do documento 10 (região, backup, retenção, destruição). É uma
   hora do dono com o console do Supabase aberto, não engenharia.

**Uma observação sobre o NDA, para registro, sem mudar a decisão.** O NDA cobre a
confidencialidade entre a Oria e o cliente. O extrato e as certidões trazem dados de **terceiros
que não assinaram o NDA**: empregados, sócios PF, fornecedores PF. Para esses titulares a LGPD
continua se aplicando. A base legal mais provável é a execução do contrato com o cliente ou o
legítimo interesse, e isso pede **uma linha** no documento 10, não uma mudança de rumo. Quem
confirma a redação é o jurídico da Oria.

---

## §8 — O que este documento não cobre, dito de propósito

- **Etapas 5 a 10 do manual** (projeção, liquidez projetada, garantias como instrumento, rating
  sombra, parecer, monitoramento). As anotações tratam de 1 a 4. As 5–10 dependem do MODEL GATE e
  do CREDITOR GATE e já estão no roadmap como F7–F16.
- **Leiautes por versão.** ECD, ECF e EFD mudam de leiaute ano a ano (a ECD está no leiaute 9). O
  leitor precisa ler o código de versão do `0000` e tratar cada versão que encontrar. Este
  documento lista os registros, não os campos por versão. Quem implementar abre o Manual de
  Orientação e o Guia Prático da versão do arquivo real.
- **Os layouts de extrato de cada banco.** OFX e CNAB são padrões. CSV e PDF não são, e cada banco
  é um caso, medido sobre arquivos reais.
- **Nenhum número de calibração** (banda de materialidade das reconciliações S3–S5, limiar de HHI,
  régua de PDD por faixa). Pela regra 2, limiar se mede sobre dado real, não se arbitra em
  documento.

---

## Referências externas

- Anotações da reunião do dono, 05/10/2026 (§0), e o acréscimo do OFX na mesma conversa.
- S&P Global Ratings, *Corporate Methodology*; Moody's, *Rating Methodology: Corporates*; Fitch,
  *Corporate Rating Criteria* e *Criteria Essentials* (2024–2026).
- Receita Federal: *Manual de Orientação do Leiaute 9 da ECD*; *Guia Prático da EFD-ICMS/IPI*;
  manuais da ECF e da EFD-Contribuições (sped.rfb.gov.br).
- CNJ: API pública do DataJud (Res. 331/2020; datajud-wiki.cnj.jus.br/api-publica). Metadados
  por número de processo, sem índice público por CPF/CNPJ.
- Ministério da Justiça: dados abertos do Consumidor.gov.br (base completa mensal, CSV).
- CGU: API do Portal da Transparência (CEIS, CNEP, CEPIM, CEAF).
- IBAMA: plataforma de dados abertos, autos de infração e embargos por CPF/CNPJ.
- MTE: Cadastro de Empregadores (Portaria Interministerial nº 18/2024), atualização semestral.
- Open Finance Brasil: API de contas e consentimento para PJ.
- Serasa Experian: indicadores de recuperação judicial (2025) e de inadimplência das empresas
  (jul/2026); BCB, comunicado do Copom (set/2026).
