# Plano de execução do MVP — de 16/11/2026 até o primeiro mandato real

**Data:** 11/11/2026, sessão 127 · **Base:** `main` em `28e3081` · **Migration mais nova no
repositório:** `0271` (escrita, não aplicada) · **Em produção:** até a `0241`.

**Este plano NÃO substitui o `PLANO_DE_EXECUCAO_2026-11.md`.** O anterior fica como está e continua
sendo o mapa da aplicação completa (111 etapas, fim em 19/01/2027). Este é um recorte: o mínimo
para um analista da Oria rodar um mandato real com confiança. **Aprovado pelo dono em 11/11/2026 (DM0).**
A ordem deste plano passa a valer para o caminho até o MVP.

**O que entra a mais do que o plano anterior previa para esta fase:**
1. Arquivos volumosos: contas a receber, contas a pagar, OFX, CNAB e razão, com centenas de
   milhares ou milhões de linhas (Trilha B).
2. Rastreamento de processos e de notícias da empresa, dos sócios e dos familiares (Trilha C).

---

## 0. O que é o MVP, em uma frase

**O analista sobe os documentos de um mandato — inclusive as bases volumosas — e recebe um book
em Excel em que nada some e nada chega errado sem aviso, junto de um dossiê de processos e
notícias da empresa e das pessoas ligadas a ela, em que toda fonte diz se rodou.**

A doutrina não muda (`PRONTIDAO_POR_ESTAGIO.md` §1): o produto é confiança no dado, não análise
automática. A modelagem continua sendo a do Excel, em fórmula.

### O portão do MVP (critério de pronto)

O MVP fecha quando **todas** as linhas abaixo estiverem no alvo, medidas, ou com o desvio explicado.

| Medida | Hoje (medido) | Alvo do MVP |
|---|---|---|
| Documento real com extração falha ou incompleta | 33–71% (lotes de set–out) | **≤ 5%**, cada um com causa nomeada |
| Falha silenciosa (documento sem linha e sem pendência) | não medida | **0** |
| Linha do documento com destino declarado | indecidível hoje (sem `ln`) | **≥ 99,9%** |
| Base volumosa: linhas lidas × linhas do arquivo | não existe leitura de conteúdo | **igualdade**, ou cada linha descartada com motivo |
| Aging AR/AP: Σ saldo em aberto × Clientes/Fornecedores do BP na data-base | `AGING_AR` e `AGING_AP` sem consumidor (`0187`) | **fecha**, ou divergência declarada no book |
| OFX: saldo inicial + Σ transações × saldo final, por conta e mês | só o envelope é lido | **fecha em toda conta e mês**, ou divergência declarada |
| Base de 1M de linhas lida no navegador | ECD de 10M lida em 37,5 s (sessão 108) | **AR, AP e OFX de 1M** lidos sem travar a aba, tempo medido |
| Pessoa ligada ao mandato com estado por fonte | não existe | **100%**: `encontrado`, `nada_encontrado`, `falhou` ou `nao_consultado`, com data |
| Processo atribuído a pessoa só pelo nome | não existe | **0 contado como confirmado**; homônimo vai ao analista |
| Consulta a pessoa física sem autorização registrada | não existe | **recusada no banco** (medido não-vazio) |
| Custo por book (extração) | até US$ 1,10 | **≤ US$ 5** (`medir-custo-book.mjs`) |
| Custo das consultas externas por mandato | não medido | **gravado por consulta**; teto definido pelo dono (DM6) |

---

## 1. Ponto de partida, medido (não lembrado)

**Extração.** Fase 0 e Fase 1 do plano anterior entregues: P1–P9 e P16 no ar em 11/11. P10 rodou
só nos sintéticos (66 de ~206 documentos, US$ 0,28) e achou duas regressões silenciosas no
Canastra, já explicadas pelo PR #288. P11 (texto numerado) está em curso na Claude Oria 2:
`0270` e `0271` escritas e não aplicadas.

**Arquivo grande.** Os fatos que decidem a Trilha B:
- O n8n não lê arquivo grande. `getBinaryDataBuffer` derruba a instância inteira (3M de linhas de
  SPED, 355 MB). A memória do n8n é ~600 MB + ~50× o arquivo, num pod de 2 GB. Por isso o teto
  `TETO_BYTES_POR_ARQUIVO` é de 15 MiB (ficha `n8n-binario-grande-derruba-a-instancia`).
- O leitor no navegador já existe e já está no portal (`Leitor/lib` + `portal/src/lib/envio-oficial.ts`,
  num Web Worker): 10M de linhas de ECD em 37,5 s com 61 MB de heap, e só o resumo sai da máquina.
- Ele reconhece OFX e CNAB pelos bytes (`Leitor/lib/familia.mjs`), mas **só registra o envelope**.
  O conteúdo é "onda 2 da F2T" (`Leitor/lib/resumo.mjs:182`).
- O zip já é lido em fluxo, entrada por entrada (`Leitor/lib/zip.mjs`, `DecompressionStream`).
  Um `.xlsx` é um zip, então ler planilha grande em fluxo reaproveita esse código.
- Hoje a planilha acima de 15 MiB é recusada com a frase "planilha grande: divida em partes"
  (`envio-oficial.ts:516`). Esse é o contorno atual, e ele é manual.
- `AGING_AR`, `AGING_AP` e `EXTRATO_BANCARIO` existem na taxonomia, mas são `sem_consumidor` na
  `0187`: nenhuma função SQL os lê. Aging que não fecha com o BP passa sem aviso.
- O Supabase de produção está no **plano gratuito** (`PLANO_DE_EXECUCAO_2026-11.md` §1). O
  limite de tamanho do banco desse plano decide o que pode ser gravado linha a linha
  (ver DM1). **Medido em 11/11/2026 (MB0):** o banco tem 111 MB (`campo_extraido` é 54 MB) e o
  Storage tem 75 MB em 186 arquivos. O teto do Storage é **50 MiB por arquivo**.

**Processos e notícias.** Nada implementado:
- A Espec. 13 (`13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md`) já desenhou `consulta_externa`,
  `autorizacao` e o momento pré-mandato, com os quatro estados de consulta e as regras R1–R7.
- A escolha do provedor de processos (D13.3 e D13.6) está aberta. O RFP e o roteiro do piloto
  estão escritos (`13_anexos/13B` e `13C`).
- **Notícias não aparecem em nenhuma especificação:** `buscar.mjs "consulta_externa noticias"` dá
  NADA ENCONTRADO (1.108 nós). É assunto novo no projeto.
- **Familiares também não.** O banco conhece controle comum por pessoa física (`0181`–`0183`),
  mas não a relação de parentesco. D2 ("controle familiar conta como controle comum?") está aberta.
- A RLS por mandato está no ar (`0216`). O registro de leitura em tabela sensível não está (19.3
  do plano anterior).

---

## 2. As cinco trilhas

Cada fatia segue o `/rodada`: medir antes, achar a causa, corrigir, medir depois. Invariante novo é
**medido não-vazio** (regra 2), e todo diff passa pelo `revisor-defeito-silencioso`. O código de
cada fatia é **M** (de MVP), para não colidir com os P e as etapas do plano anterior.

### Trilha A — Extração que não perde linha (núcleo, já em curso)

É a Fase 2 do plano anterior, menos a P14. Sem ela, nada do resto vale.

| # | Fatia | Antigo | Pronto quando |
|---|---|---|---|
| **MA1** | **Regressão paga no corpus real.** Reenvio dos originais do Valtra, Krauspenhar e AMO; tabela antes × depois | P10 | Tabela por documento publicada; custo de cada book ≤ US$ 5 |
| **MA2** | **A coordenada.** Texto numerado e `ln` na linha extraída. Junto, o tipo "composição do imobilizado" na taxonomia (mesma mudança de prompt, uma re-extração em vez de duas) | P11 | Toda linha extraída do corpus cita a linha do texto de onde veio |
| **MA3** | **A bijeção.** Toda linha do documento tem destino: conta, cabeçalho ou descarte com motivo. Buraco, duplicação e origem inventada viram pendência bloqueante | P12 | Os 3 documentos do Araucária acusam o buraco nomeado (97−68, 150−102, 20−13) |
| **MA4** | **A literalidade.** Valor sem trecho literal correspondente na linha citada abre pendência | P13 | A guarda reprova com valor inventado (medido) |
| **MA5** | **Portão da extração.** Regressão final e a tabela do §0 nas linhas de extração | P15 | Linhas de extração do portão no alvo, ou cada desvio explicado |

**Fica de fora:** a P14 (re-perguntar só o buraco). Ela reduz custo, e custo não é o gargalo: o
lote mais caro saiu US$ 1,10 contra o teto de US$ 5. A MA3 já acusa o buraco. Quando o buraco
fechar à mão vira rotina, a P14 volta.

### Trilha B — Bases volumosas: contas a receber, contas a pagar, OFX, CNAB e razão

**A decisão de arquitetura, herdada e não reaberta:** o arquivo grande é lido **no navegador do
analista**, em fluxo, pelo `Leitor/lib` (decisão do dono de 13/10, D12.9). Ele não passa pelo n8n
nem pela IA. A IA vê só o cabeçalho e uma amostra, para propor o mapeamento das colunas. Nunca vê
as linhas.

Por quê, com número: um aging de 500 mil títulos pela extração por IA custaria a extração de
milhares de páginas e não teria como provar que leu tudo. Pelo leitor, a contagem de linhas é
aritmética, e o custo da IA é o de uma amostra de 30 linhas.

| # | Fatia | Pronto quando | Sinal de que rodou |
|---|---|---|---|
| **MB0** | **Medir antes.** (1) Tamanho do banco de produção e o limite do plano. (2) Gerador sintético de volume no padrão do `book-distress`: AR, AP e OFX de 10 mil, 100 mil e 1M de linhas, que **fecham com o BP** do book. (3) Um arquivo real de AR e um de AP de mandato, se o dono tiver: formato, tamanho, colunas, ERP de origem | Os três números publicados aqui; os arquivos sintéticos fecham com o BP por construção | O gerador tem teste que reprova se o total não fechar |
| **MB1** | **Leitor tabular em fluxo** (CSV e XLSX). CSV pelo mesmo `QUEBRA` do envelope; XLSX lendo `sheetN.xml` em fluxo pelo `zip.mjs`, sem carregar a planilha inteira. Encoding pelos bytes (latin1 × UTF-8 × windows-1252, lição de `campos.mjs#latin1`). Conta toda linha: lida, cabeçalho, total, em branco, descartada com motivo | 1M de linhas de CSV e de XLSX lidas no Web Worker, tempo e heap medidos; linhas lidas = linhas do arquivo | Cada leitura grava a contagem por destino, inclusive zero |
| **MB2** | **Mapeamento de colunas.** A IA recebe cabeçalho + 30 linhas e propõe: data de emissão, vencimento, valor original, saldo em aberto, contraparte, CNPJ/CPF, documento, situação. O analista confirma na tela. O mapeamento confirmado é guardado pela impressão digital do cabeçalho e reaproveitado no próximo arquivo do mesmo ERP | Coluna obrigatória não achada = campo em branco + nota com o efeito ("sem vencimento: o aging não pode ser calculado"), nunca valor por palpite | Mapeamento com autor e data; arquivo sem mapeamento confirmado não vira dado |
| **MB3** | **Contas a receber.** Aging por faixa (a vencer, 1–30, 31–60, 61–90, 91–180, 181–360, >360), concentração (10 maiores clientes e % do total), títulos vencidos por cliente. Conciliação: Σ saldo em aberto na data-base × Clientes do BP. `AGING_AR` deixa de ser `sem_consumidor` | Os sintéticos de 10 mil a 1M fecham; um AR com divergência plantada abre pendência com a diferença | Divergência zero é gravada como "conferido, 0", não como ausência |
| **MB4** | **Contas a pagar.** O mesmo, contra Fornecedores do BP, mais o vencido por fornecedor (sinal de aperto de caixa). `AGING_AP` deixa de ser `sem_consumidor` | Igual à MB3 | Igual à MB3 |
| **MB5** | **OFX.** Conteúdo lido (1.x SGML e 2.x XML, versões em `leiautes.mjs`). Deduplicação por `FITID`. Por conta e mês: saldo inicial + Σ transações = saldo final; meses lidos × meses esperados. Saldo do fim do mês da data-base × Caixa e equivalentes do BP | Os sintéticos fecham; mês faltando aparece como "não recebido", nunca como movimento zero | Uma linha por conta × mês, inclusive o mês sem arquivo |
| **MB6** | **CNAB de retorno e razão contábil.** CNAB 240 e 400: liquidações por dia e por sacado, para cruzar com o AR. Razão em CSV/XLSX: Σ por conta × mês, conferido contra o balancete do mesmo período | Razão sintético fecha com o balancete; CNAB liquidado reduz o AR do mesmo título | Contagem de registros por tipo, igual ao trailer do arquivo |
| **MB7** | **O que vai para o banco e para o book.** Banco: o agregado (contraparte × faixa × data-base; conta × mês) e os N maiores itens; o arquivo bruto no Storage, com hash. Book: abas "Aging AR", "Aging AP" e "Caixa mensal (OFX)", com proveniência e a nota de cada divergência. Detalhe linha a linha só se a DM1 permitir | O export mostra as três abas nos sintéticos; célula sem dado = branco + nota | `verificar-export.mts` reprova aba com número sem origem (medido não-vazio) |

**Por que o banco guarda o agregado e não a linha (proposta, decide a DM1):** é o mesmo critério
da ECD (o resumo de 10M de linhas tem 3,4 MB contra 1,95 GB da carga bruta). O agregado responde
aging, concentração e conciliação. O título individual continua acessível: o arquivo bruto fica no
Storage e o navegador o relê quando o analista pede o detalhe.

### Trilha C — Processos e notícias: empresa, sócios e familiares

**A regra que governa a trilha inteira:** o provedor **descobre**, a certidão **prova** (R1 da
Espec. 11). E fonte que não rodou nunca aparece como "nada encontrado" (R1 da Espec. 13, regra 7
do projeto).

**Quem é rastreado:**
- A empresa e cada entidade do perímetro (CNPJ).
- Sócios e administradores: vêm do QSA da Receita, de forma automática.
- Familiares: **declarados pelo analista ou pelo cliente**, com a relação (cônjuge, filho, pai…)
  e a fonte da declaração. **O sistema não infere parentesco** por sobrenome: isso seria
  fabricar vínculo.

| # | Fatia | Pronto quando | Sinal de que rodou |
|---|---|---|---|
| **MC0** | **Decisões e jurídico** (só o dono faz; ver §4). Base legal LGPD para consultar PF; texto da autorização; provedor de processos; fonte de notícias; teto de custo por mandato | DM2 a DM6 respondidas por escrito | — (decisão, não código) |
| **MC1** | **As tabelas.** `pessoa_vinculada` (empresa, sócio, administrador, familiar; relação; fonte; quem declarou), `autorizacao` (escopo, pessoas cobertas, validade, revogação) e `consulta_externa` (fonte, fornecedor, base legal, custo, estado, validade). RLS por mandato desde o nascimento. Leitura de tabela sensível grava `evento_auditoria` | Consulta a PF sem `autorizacao` válida é **recusada no banco**; usuário do mandato A não lê nada do B | Desligar a recusa faz o teste reprovar (número de asserts no commit) |
| **MC2** | **Fontes públicas da empresa.** Receita (CNPJ, QSA, CNAE), CEIS/CNEP, PGFN (dívida ativa). O QSA preenche `pessoa_vinculada` | Uma linha por entidade × fonte por rodada, inclusive a vazia; API fora do ar = `falhou` | Fonte desligada no teste aparece como `nao_consultado`, nunca como vazio |
| **MC3** | **Piloto de processos no mandato AMO** (Espec. 13, Etapa 4). Provedor por API (Jusbrasil, JUDIT ou Escavador) × as certidões que o mandato já tem, por pessoa | Número publicado: processos que o provedor achou × processos das certidões, por pessoa e por provedor. **A D13.3 sai daqui, com número** | — (medição) |
| **MC4** | **Coletor de processos.** Para cada pessoa vinculada: número CNJ, tribunal, classe, polo, valor da causa, fase, último andamento. **Achado por CPF/CNPJ = confirmado. Achado só pelo nome = "possível homônimo"**, vai ao analista e não entra em total nenhum até ele confirmar | Homônimo plantado no teste não entra no total (medido); processo em segredo de justiça é dito como limite da fonte | Uma consulta por pessoa × provedor por rodada, inclusive a vazia |
| **MC5** | **Processo × contingências.** Processo com a empresa no polo passivo e valor relevante, ausente da provisão de contingências extraída, abre pendência para o analista | O cruzamento acha o processo plantado ausente; não acusa o que está provisionado (controle positivo) | Contagem de processos cruzados × provisão, por entidade |
| **MC6** | **Notícias.** Busca por razão social, nome fantasia e **nome do sócio junto com o nome da empresa** (nome de PF sozinho traz homônimo demais). Guarda título, veículo, data, link e trecho; **não guarda o texto da matéria** (direito autoral). A IA classifica só título + trecho: tema (recuperação judicial, fraude, trabalhista, ambiental, operação policial, operação comercial) e se a notícia é mesmo sobre aquela pessoa. O analista confirma | Fonte fora do ar = `falhou`, nunca "nenhuma notícia"; notícia de homônimo plantada não entra como confirmada | Uma consulta por pessoa × fonte por rodada, inclusive a vazia |
| **MC7** | **Monitoramento.** Reconsulta periódica (cron), com validade por fonte (R7: certidão 90 dias). Processo novo, andamento novo ou notícia nova vira alerta no mandato | Consulta vencida aparece como vencida na tela; um processo novo plantado gera o alerta | O cron grava a rodada mesmo quando nada muda |
| **MC8** | **O dossiê.** No portal, por pessoa: processos, notícias e o estado de cada fonte, com data e efeito ("passivo judicial do sócio X não pesquisado"). No book, a aba "Processos e notícias" | Nenhuma dimensão sem consulta aparece vazia; toda célula aponta para a `consulta_externa` de origem | `verificar-export.mts` reprova número sem fonte (medido não-vazio) |

**Notícias, por que a fonte é decisão (DM5):** RSS de busca de notícias e bases públicas como o
GDELT são grátis, mas cobrem mal a imprensa regional e não garantem estabilidade. Clipping pago
cobre melhor e custa por mês. O piloto da MC6 mede a cobertura das duas num mandato real antes de
contratar. **[A CONFIRMAR]** quais fontes grátis aceitam uso automatizado pelos termos de uso.

**Processos, por que não dá para fazer só com fonte pública:** a API pública do DataJud (CNJ)
serve para acompanhar processo já conhecido pelo número. **[A CONFIRMAR]** se ela permite busca
por parte; até onde se sabe, não. Descobrir processo por CPF/CNPJ exige provedor pago.

### Trilha D — Perímetro e aceite financeiro

| # | Fatia | Antigo | Pronto quando |
|---|---|---|---|
| **MD1** | **Fechar o perímetro**, só se o primeiro mandato for um grupo. Depende de D2 a D4 | 5.1 | Perímetro declarado pela tela nos mandatos de teste |
| **MD2** | **Aceite financeiro nos books de teste**, agora com as bases volumosas: os sintéticos de AR, AP e OFX da MB0 entram no book e fecham com o BP | 5.2 | ≥ 95% dos documentos com linha, toda diferença explicada, e as três conciliações da Trilha B fechando |

### Trilha E — Portal e operação mínimos

| # | Fatia | Antigo | Pronto quando |
|---|---|---|---|
| **ME1** | **Só os defeitos que travam o uso**, tirados do lote 2 | P17 (parte) | Cada defeito reproduzido antes e conferido depois no navegador |
| **ME2** | **Tela de envio das bases volumosas**: escolher o tipo (AR, AP, extrato, razão), progresso da leitura, confirmação do mapeamento, resultado das conciliações | novo | Vistoria com o Analista de teste, subindo um AR sintético de 1M de linhas |
| **ME3** | **Proteger o `main`** e Sonar no CI | 19.1 | Push direto no `main` recusado |
| **ME4** | **Teste de restauração do backup** | 19.2 | Restauração feita e conferida pela sonda num banco à parte |
| **ME5** | **Registro de leitura** das tabelas com dado de PF (processos, notícias, autorização) | 19.3 (parte) | Leitura de tabela sensível gera evento com o ator |

---

## 3. Ordem, contas e datas

**Premissa, para o dono corrigir:** as três contas do plano anterior, 5 sessões por semana cada,
a partir de 16/11. A divisão respeita os donos de diretório do `STATUS_POR_ETAPA_2026-11-11.md`.

| Conta | Trilhas | Por quê |
|---|---|---|
| **Claude Oria 2** | A, MD1, ME1, ME2 | Já é dona da extração (`SYSTEM_PROMPT`, ingestão) e do `portal/src/**` |
| **Claude Pessoal** | MB0, MB1, MB5, MB6 (só com dado sintético) | Já é dona do `Leitor/`. O gerador e o leitor são testados com sintético; nenhum dado de cliente nessa conta |
| **Claude Oria** | MB2, MB3, MB4, MB7, Trilha C, MD2, ME3–ME5 | É dona do `export.ts` e das reconciliações. **A Trilha C toca dado de PF real, então não pode ir para a Claude Pessoal** |

| Semana | Claude Oria 2 | Claude Pessoal | Claude Oria |
|---|---|---|---|
| **1** (16–20/11) | MA1, MA2 | MB0, início da MB1 | MC1, MC2, ME3 |
| **2** (23–27/11) | MA3, MA4 | MB1 (XLSX), MB5 | MB2, MB3, MB4 · MC3 se o contrato de teste chegou |
| **3** (30/11–04/12) | MA5, ME1, ME2 | MB6 | MB7, MC4, MC5 |
| **4** (07–11/12) | MD1 (se for grupo) | folga para retrabalho | MC6, MC7, MC8, ME4, ME5 |
| **5** (14–18/12) | — | — | MD2 e **portão do MVP** |

**Total:** cerca de 33 fatias. **Fim estimado: 18/12/2026**, com o portão do MVP. Sem a Claude
Pessoal, a Trilha B passa para a Claude Oria e o fim vai para meados de janeiro.

**O que mais pode atrasar, em ordem de risco:**
1. **MC3 e MC4 dependem de contrato com provedor de processos.** Sem acesso de teste até 27/11,
   a MC4 sai do MVP e o dossiê entra só com fontes públicas e notícias, dizendo "processos não
   pesquisados" com o efeito.
2. **MA1 depende do reenvio dos originais reais**, que só o dono faz.
3. **A DM1 (limite do banco)**: se o plano do Supabase não comportar nem o agregado, a Trilha B
   para até o dono decidir.

**Dependências entre trilhas:**
- MB3 e MB4 precisam do BP extraído (Trilha A) só para a conciliação. A leitura e o aging não
  dependem dela e podem andar antes.
- MC5 precisa da nota de contingências extraída (Trilha A).
- MD2 precisa de MA5 e MB7.
- Migrations: Claude Oria a partir da `0242`, Claude Oria 2 a partir da `0272`, Claude Pessoal a
  partir da `0300` (faixas do `STATUS_POR_ETAPA`).

---

## 4. Decisões do dono que este plano precisa

| # | Decisão | Bloqueia | Recomendação |
|---|---|---|---|
| **DM0** ✅ 11/11 | **Aprovado.** Este recorte vale; a P26 (conta canônica) sai da frente | — | — |
| **DM1** ✅ 11/11 | **Só o resumo no banco; o arquivo original guardado à parte.** Consequência medida na MB0: o original de 1M de linhas não cabe cru no Storage (teto de 50 MiB). Em gzip, o CSV cabe com folga (21,9 MB) e o .xlsx por pouco (47,5 MB); guardar em partes tem de existir desde a MB7 | — | — |
| **DM2** ✅ 11/11 | **O jurídico escreve** a base legal e o texto da autorização para sócios e familiares | MC1 em produção, MC4, MC6 | — |
| **DM3** | Quem declara os familiares: o analista, o cliente no kickoff, ou os dois | MC1 | Os dois, sempre com a fonte gravada |
| **DM4** | Provedor de processos (= D13.3 e D13.6): pedir acesso de teste a dois provedores para o piloto da MC3 | MC3, MC4 | **JUDIT e Escavador**; Jusbrasil de reserva. Os três vendem API com busca por CPF/CNPJ e monitoramento (13B §8). A Exato fica fora do piloto de processos: é relatório de triagem que tira processo do Jusbrasil, e a MC4 precisa de valor, polo e fase estruturados (Espec. 13 §2.2). Pedir com o RFP de `13_anexos/13B` (categoria B) |
| **DM5** | Fonte de notícias: grátis (RSS de busca, GDELT) ou clipping pago | MC6 | Começar pela grátis no piloto; contratar só se a cobertura medida não bastar |
| **DM6** | Teto de custo das consultas externas por mandato (o US$ 5 por book cobre só a extração) | MC4, MC6 | Definir depois do piloto, com o preço medido |
| **DM7** | Arquivos reais de AR, AP e OFX de um mandato, para a MB0 e o aceite | MB0 (parte real), MD2 | Mandar os de um mandato já em curso |
| **D2–D4** | As do plano anterior (perímetro) | MD1 | Só se o primeiro mandato for grupo |
| **D5** | Autonomia: dois estágios aceitam sozinhos sem concordância medida, um deles a extração | Portão do MVP | Para o MVP, forçar revisão humana nesses dois até a concordância ser medida |

---

## 5. O que fica fora do MVP (continua no plano anterior)

Cada item segue no `PLANO_DE_EXECUCAO_2026-11.md` e volta depois do portão do MVP.

| Fica fora | Etapas no plano anterior | Por que dá para esperar |
|---|---|---|
| Re-perguntar só o buraco | 2.5 (P14) | Otimiza custo, que não é o gargalo |
| Conta canônica completa | 3.1–3.6 (P26–P30, F4) | Maior esforço do roadmap (mais de 6 sessões). As conciliações de hoje funcionam sobre a taxonomia atual |
| Rastreabilidade por SQL | 4.1–4.3 (F5) | A proveniência já é gravada e já vai em nota no Excel |
| Eliminação intragrupo e combinado | 5.3–5.5 (F6) | Só necessário em grupo com operação entre as empresas |
| Motor de cálculo | 6.1–6.5 (F7) | O Excel já faz a modelagem em fórmula |
| Cenários, dívida, 13 semanas, diagnóstico, valuation, credores, reestruturação | Fases 7 a 13 | É análise; a doutrina deixa fora do produto |
| Deck `.pptx` | Fase 14 | 80% pronto; termina se sobrar sessão |
| Lote 2 do portal inteiro, Produto/Responsável, tempo até aprovar, SMTP | 15.1 (resto), 15.2–15.4 | Conforto, não bloqueio |
| Área do cliente e multiempresa | 15.5–15.9 | Ninguém de fora usa o sistema no MVP |
| SPED, EFD, NF-e, eSocial, logística, captação automática | 16.1–16.9 (menos OFX e CNAB, que entraram na Trilha B) | O cliente manda os arquivos; captação é automação |
| Bureau, Open Finance, Núclea, deck pré-mandato | 17.4–17.7 | Processos e notícias entraram (Trilha C); o resto da F2E espera |
| Análise comparativa do setor | Fase 18 | ~10 sessões, depende da conta canônica |
| Conversão cambial | 19.4 | Só para cliente com moeda estrangeira |

---

## 6. O que este plano NÃO conferiu

- O tamanho atual do banco de produção e o limite exato do plano do Supabase (vai na MB0).
- Se o XLSX de 1M de linhas cabe no navegador com o `zip.mjs` em fluxo. A ECD de 10M coube, mas
  a planilha tem XML muito mais verboso por linha. A MB1 mede; se não couber, o contorno é pedir
  CSV ao cliente, dito na tela.
- A cobertura real de qualquer provedor de processos ou fonte de notícias. Nenhum número de
  cobertura aqui é medido; a MC3 e a MC6 medem.
- Os termos de uso das fontes de notícias grátis e da API do DataJud (marcados [A CONFIRMAR]).
- As datas: são estimativa com 5 sessões por semana por conta, sem atrito de integração. Com o
  atrito de ~15% do `STATUS_POR_ETAPA`, some cerca de uma semana.

---

## 7. Andamento

### MB0 — feita em 11/11/2026 (sessão 127)

- **Banco de produção** (leitura pela API de gerenciamento): 111 MB; `campo_extraido` 54 MB com
  133 mil linhas; Storage 75 MB em 186 arquivos; Postgres 17.6. **Teto do Storage: 50 MiB por
  arquivo** (`fileSizeLimit` = 52.428.800). O plano da organização não veio na resposta da API
  (`plan: null`): o limite de tamanho do banco do plano gratuito fica [A CONFIRMAR] no painel.
- **Gerador e conferidor** em `Dados de Teste/volume/`. AR, AP e OFX de 10 mil, 100 mil e 1M de
  linhas, cujos totais são os do book-distress (Σ AR = 24.917 mil = Clientes do BP; Σ AP = 14.900
  mil = Fornecedores; OFX fecha mês a mês com o extrato e no caixa de 676 mil). 92 de 92
  conferências nos três tamanhos; 14 testes no CI.
- **Revisão independente** (`revisor-defeito-silencioso`): 2 achados altos e 6 médios, corrigidos
  no segundo commit. O mais caro: o .xlsx da primeira versão não tinha `sharedStrings.xml` (o
  openpyxl em write_only grava `inlineStr`), formato que nenhum arquivo real tem.
- **Tamanhos medidos de 1M de linhas:** AR .csv 133,1 MB (gzip 21,9); AP .csv 133,1 MB; AR .xlsx
  57,2 MB (gzip 47,5); OFX 20,3 MB (142.851 transações). Tabela completa no `README.md` de lá.
- **O que isso muda na MB7:** o original vai ao Storage **comprimido no navegador** (o
  `CompressionStream` já existe no navegador) e, acima de 50 MiB comprimido, **em partes** com o
  hash do arquivo inteiro. O .xlsx sintético de 1M cabe comprimido por 5 MB; um real com mais
  colunas não cabe.
- **Não feito:** arquivo real de AR e AP (DM7, depende do dono).
- **Próxima:** MB1, o leitor tabular em fluxo, medido sobre estes arquivos no Chromium.

### MB1 — feita em 11/11/2026 (sessão 127), com os sintéticos

- **`Leitor/lib/tabela.mjs`**: `lerTabela(blob, { aoLinha })` lê CSV (windows-1252, UTF-8, UTF-16,
  com e sem BOM; aspa no começo da célula protege separador e quebra de linha) e XLSX (tabela de
  strings, texto em linha, datas por estilo, calendário de 1904, prefixo de namespace, primeira aba
  visível) em fluxo, o mesmo código no Node e no navegador. Toda linha recebe um destino
  ESTRUTURAL: `antes_do_cabecalho`, `cabecalho` (inclusive o repetido), `corpo`, `em_branco` ou
  `largura_divergente`, mais os sinais `rotulo_de_total` e `poucas_celulas`.
- **O que a revisão independente mudou:** a primeira versão classificava "dado" e "total" pela
  contagem de células e errava sem erro nos dois sentidos (título em aberto fora da tabela,
  subtotal como dado). **Decidir se a linha do corpo é título passa para a MB2**, que tem o
  mapeamento. Também: aspa solta, releitura de codificação no meio do caminho, aba errada e XML
  com prefixo. 4 achados altos, 5 médios, todos com teste.
- **Medido no Chromium, 1M de linhas:** CSV em 2,7 s com 45 MB de heap; XLSX em 18,7 s com 69 MB.
  Resumo idêntico ao do Node. Detalhe em `Leitor/medicao-n8n/README.md`.
- **Prova:** `Leitor/test/tabela.test.mjs`, 31 testes no CI (95 no Leitor). As 29 correções,
  desligadas uma a uma, reprovam de 1 a 4 testes cada.
- **O que a MB2 herda:** decidir título × subtotal × lixo com o mapeamento; pegar o deslocamento de
  coluna que cabe na largura (o saldo deixa de ser número); converter o número do XLSX, que pode
  vir em notação científica ou com 17 dígitos.
- **Não feito:** ligar ao Web Worker e à tela do portal (é a ME2); medir dentro do worker; arquivo
  real (DM7).
- **Próxima:** MB2, o mapeamento de colunas confirmado pelo analista.

### MB2 — biblioteca feita em 11/11/2026 (sessão 127), com os sintéticos; a migration 0242 vem em commit próprio

- **`Leitor/lib/mapeamento.mjs`**: propõe o mapeamento (sinônimo do nome + tipo dos valores da
  amostra) e o FORMATO do arquivo (vírgula ou ponto decimal; dia/mês ou mês/dia, com a evidência),
  valida, e aplica a cada linha da MB1: `titulo` (contraparte, vencimento que é data, saldo que é
  número), `subtotal` ou `rejeitada` com o campo e o valor. Sem autor, data e formato confirmados,
  recusa. Confere a soma lida com o total do próprio arquivo (`confere`, `diverge` ou
  `sem_total_no_arquivo`).
- **Decisão de escopo:** a IA NÃO propõe o mapeamento, ao contrário do que a linha MB2 previa.
  Sinônimo + tipo acerta as 11 colunas dos sintéticos sem custo nem rede, e o analista confirma de
  qualquer jeito. Volta se arquivos reais (DM7) mostrarem cabeçalhos fora dos sinônimos.
- **Achado no caminho:** decidir vírgula/ponto e dia/mês valor a valor erra sem erro ("1.250",
  "03/04/2025"). Passou a ser formato do arquivo, confirmado e guardado no banco.
- **Medido no Chromium, 1M de linhas, idêntico ao Node:** o caminho inteiro da tela (1ª leitura só
  até a amostra, `soAmostra`, + proposta + 2ª leitura aplicando) leva 5,5 s no CSV e 22,0 s no XLSX.
  999.995 títulos, 0 rejeitadas, Σ saldo = 24.917.000,00 = Clientes do BP, conferência `confere`.
- **Prova:** `Leitor/test/mapeamento.test.mjs`, 23 testes; 27 correções desligadas reprovam de 1 a
  5 testes cada (120 testes no Leitor).
- **Não feito:** a tela de confirmação (ME2); arquivo real (DM7).

