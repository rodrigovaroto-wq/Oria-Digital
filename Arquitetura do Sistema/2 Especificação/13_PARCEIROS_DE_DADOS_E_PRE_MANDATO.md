# 13 — Parceiros de dados e o momento pré-mandato

**Data:** 26/10/2026 · **Base:** `fbeeb9c` · **Natureza:** especificação e plano. Nada aqui está
implementado. Trechos marcados **[A CONFIRMAR]** dependem da resposta do fornecedor antes de virar
código. O que vem de pesquisa pública cita a fonte no fim. Pesquisa pública não é contrato: preço,
cobertura e regime regulatório só valem depois de confirmados por escrito.

**Origem, em ordem de autoridade:**

1. **As anotações da reunião do dono** (§0, na íntegra) e as **cinco respostas do dono em
   26/10/2026** (§7).
2. A **Especificação 11** (`11_ANALISE_DE_CREDITO_ASSESSORIA.md`): §3.5 (processos), §5
   (`consulta_externa`, fonte externa como dado), §6 (fatias T0, T6, T9) e §7 (D5, D6, D7).
3. A **Especificação 12** (`12_FONTES_OFICIAIS_E_CAPTACAO.md`): §9 (canais de captação), §12
   (pré-requisitos e kickoff) e a D12.4.

**Esta especificação estende as duas, não as substitui.** Ela acrescenta três coisas que nenhuma
das duas tinha: o **momento** (pré-mandato, antes de existir NDA), os **fornecedores de dado** como
parceiros nomeados e a **revisão da D6/D12.4** (Open Finance volta ao plano).

---

## Resumo

| Nota da reunião | O que vira | Onde está no plano |
|---|---|---|
| Momento: pré ou pós-mandato | `caso.momento`. No pré-mandato o caso só recebe **consultas**, nunca documento | Etapa 3 |
| Parceiros por função | Matriz função × momento × parceiro (§1), que vai para os slides e a planilha | §1 |
| KB no Obsidian como dataroom | **Descartada pelo dono em 26/10/2026** (D13.2). O dataroom continua no SharePoint e no link de envio da Espec. 12 §11 | — |
| Apresentação pré-mandato puxando o bureau | Coletor de bureau e o `.pptx` de crédito alimentado por consulta externa | Etapas 5 e 6 |
| Núclea | Indicadores agregados de boleto, cartão e TED como **teste de plausibilidade**, não como conciliação | Etapa 8 |
| Exato Digital | Candidata à D5 (processos), **em comparação** com uma API processual direta, medida no mandato AMO | Etapa 4 |
| Clavi (Klavi) | Open Finance reaberto (D13.1). Agregador a escolher entre Klavi, Pluggy e Belvo | Etapa 7 |

**Três premissas da reunião que a pesquisa corrigiu** (§2):

1. **A Núclea não tem dado de Pix.** O Pix é liquidado no SPI do Banco Central. A Núclea só tem o
   Pix Automático.
2. **O que a Núclea vende sobre um CNPJ é agregado** (score, percentil, faixas de valor anônimas,
   janela de 1 ou 12 meses). Não dá para cruzar com o OFX transação a transação, só por
   plausibilidade.
3. **A Oria não pode receber Open Finance diretamente.** Só instituição autorizada pelo Banco
   Central participa. É preciso um agregador que seja receptor, ou que use um, e a Oria entra como
   parceira não regulada (Resolução Conjunta 4/2022).

**O pré-requisito que não muda:** a segregação por mandato (T0 da Espec. 11). Bureau de sócio,
processo criminal e extrato não podem ser gravados num banco em que todo usuário autenticado lê
todo mandato. É assim hoje (Espec. 11 §7.1).

---

## §0 — As anotações da reunião (fonte primária, na íntegra)

> Adicionar nos slides/planilha
>
> Momento - Pré mandato ou Pós mandato
>
> Parceiros - possíveis parceiros que solucionam pelo menos uma parte das funções do sistema
>
> ----
>
> KB no obsidian para conseguir consultar e editar de forma visual como um dataroom para os
> clientes conseguirem adicionar toda a documentação deles e depois cruzarmos esse input deles os
> dados e documentações que captarmos por outras fontes.
>
> Precisamos de uma apresentação pré mandato puxando o biro dos clientes
>
> Nuclea - empresa para captar dados e liquidação de boletos
>
> Exato Digital - puxar processos da empresa e de todos os sócios
>
> Clavi - puxar os dados do Openfinance trabalhados

**Leitura adotada.** "Biro" = bureau de crédito. "Clavi" = **Klavi** (klavi.ai): não existe
fornecedor de Open Finance chamado Clavi, e a Klavi é a que casa com "dados do Open Finance
trabalhados".

---

## §1 — Função × momento × parceiro (para os slides e a planilha)

O **momento** separa o que a Oria pode fazer antes de assinar o mandato (sem NDA, sem termo de
kickoff, sem documento do cliente) do que só faz depois.

| Função do sistema | Momento | Parceiro possível | Alternativas a cotar | Estado no sistema |
|---|---|---|---|---|
| Cadastro CNPJ, QSA, CNAE, situação | Pré e pós | dado público (Receita, dados abertos) | APIs comerciais de CNPJ | 🔴 T6 |
| Sanções e listas (CEIS/CNEP, PGFN, IBAMA, MTE) | Pré e pós | dado público (Portal da Transparência) | — | 🔴 T6 |
| **Bureau de crédito** da empresa e dos sócios | **Pré** e pós | a escolher | Serasa Experian, Boa Vista (Equifax), Quod | 🔴 Etapa 5 |
| **Processos** da empresa e dos sócios (descoberta) | Pré e pós | **Exato Digital** | Jusbrasil API, JUDIT, Escavador | 🔴 Etapa 4 |
| Certidões (a prova oficial do processo) | Pós | o cliente, ou o próprio provedor de processos [A CONFIRMAR] | — | 🟡 tipo `CERTIDOES` existe, sem leitor (T9) |
| **Indicadores de boleto, cartão e TED** | Pré (com autorização) e pós | **Núclea** | Quod (score combinado com a Núclea) | 🔴 Etapa 8 |
| Agenda de recebíveis de cartão (cessão, gravame, antecipação) | Pós | Núclea ou outra registradora [A CONFIRMAR] | CERC, TAG, B3; export do portal da credenciadora | ⚪ depende de resposta (Etapa 8b) |
| **Extrato e transações por Open Finance** | Pós | **Klavi** | Pluggy, Belvo | 🔴 Etapa 7 |
| Extrato por arquivo (OFX, CNAB) | Pós | — (o cliente) | — | 🟡 F2T onda 2 |
| SPED, eSocial, XML fiscal | Pós | — (procuração e contador) | SERPRO Integra Contador (D12.3) | 🟡 F2T |
| Dataroom (o cliente sobe documentos) | Pós | SharePoint (já contratado, Opção B do `f0/02`) | — | 🟡 envio direto ao Storage (Espec. 12 §11, peça 2) |
| Extração, book, modelo FP&A, apresentação | Pós (a apresentação também no pré) | sistema próprio | — | 🟢 existe |

---

## §2 — O que cada parceiro entrega, e o que isso permite

### 2.1 Open Finance: Klavi, Pluggy, Belvo

**O que a Klavi publica:** conexão de contas PF e PJ com cadastro, extrato, fatura de cartão e
transações categorizadas, em mais de 35 fontes. Seu produto principal é score e renda de **pessoa
física**; para PJ existe a conexão, mas a camada analítica publicada é de PF. A CIP (hoje Núclea) é
sócia desde 2022. Clientes citados: BV, Serasa, Vivo.

**O ponto regulatório.** Só instituição autorizada pelo Banco Central participa do Open Finance. Em
2023 a Klavi não era participante e operava pela Iniciador. Depois recebeu autorização para
**iniciar pagamentos** (ITP), o que não confirma que ela seja **receptora de dados**. **[A
CONFIRMAR]** quem é a instituição receptora em cada fornecedor.

**O atrito conhecido em PJ:** o consentimento de empresa com mais de um sócio trava e expira sem
aviso (Let's Money, 2026). Para este sistema isso é a regra 7: "consentimento expirado" e "conta sem
movimento" têm de ser estados distintos, e o primeiro nunca vira o segundo.

**O ganho sobre o OFX:** o caixa se atualiza sem o cliente mandar arquivo, e várias contas e bancos
vêm por uma autorização. O padrão do Open Finance também tem APIs de **empréstimos e cartões PJ**
(`business-loans`, `business-credit-cards`). Se o agregador as entregar [A CONFIRMAR], elas se
confrontam com o `MAPA_DIVIDA`, e isso o OFX não faz.

**O que o Open Finance não entrega:** a venda no cartão, por bandeira e antes da taxa, e as cessões
de recebíveis. Isso fica na registradora (2.3).

**Alternativas.** A Pluggy publica cerca de meio milhão de CNPJs conectados. A Belvo serve
contabilidades (Conta Azul, Nibo) com dado PJ e agrega recebíveis de cartão por fora do Open
Finance regulado. Para uso PJ, as duas podem encaixar melhor que a Klavi, que é desenhada para base
grande de PF. A escolha sai do RFP da Etapa 0.

### 2.2 Processos: Exato Digital e APIs processuais

**O que a Exato publica:** plataforma de background check (KYC, compliance, due diligence; integra
com a Gupy). Consulta mais de 300 fontes: Receita, Jusbrasil, tribunais, polícia, bureaus. O
relatório sai em 3 a 5 minutos. O site anuncia **R$ 39,90 por relatório avulso**, plano empresarial
a partir de 50 por mês, e API "conforme o plano" [A CONFIRMAR].

**Onde serve:** triagem rápida de **sócios e administradores PF**, que é o que a apresentação
pré-mandato precisa.

**Onde provavelmente não basta:** a Espec. 11 §3.5 pede, por processo, valor da causa, polo, fase e
último andamento, para cruzar com a provisão de contingências (T9). A Exato tira processo do
Jusbrasil. Uma API processual direta (Jusbrasil, JUDIT, Escavador) devolve isso estruturado e com
monitoramento.

**O que nenhum provedor substitui:** a certidão, que é a prova oficial e o que o banco pede. O
próprio Jusbrasil documenta que processo em segredo de justiça não volta. A R1 da Espec. 11
continua: **o provedor descobre, a certidão prova.**

**Como a D5 se decide:** pelo teste da Etapa 4, que mede quantos processos cada provedor encontra
contra as certidões do mandato AMO. Não por catálogo.

### 2.3 Núclea

**O que a Núclea é:** a antiga CIP. Liquida boletos (SILOC) e cartões entre bancos (SLC), registra
100% dos boletos do país e é uma das registradoras de recebíveis de cartão (com CERC, TAG e B3).

**O que ela vende sobre um CNPJ** (relatório de consulta e indicadores de crédito PJ):
- liquidez, concentração de clientes e fornecedores, tendência, autoliquidação de boletos,
  percentil de recebimento e de pagamento;
- valor transacionado em **faixas anônimas**, score de inadimplência em 90 dias e projeção de 12
  meses;
- janela de último mês ou 12 meses, com até um mês de defasagem;
- cobrança só por consulta com resultado, pelo Núclea Conecta.

**O que isso permite, e o que não permite:**
- **Conciliação linha a linha com o OFX: não.** O dado é agregado.
- **Pix: não.** O Pix não passa pela Núclea. O Pix do cliente só se observa por OFX ou Open
  Finance.
- **Plausibilidade: sim.** "Receita declarada R$ X; entradas no extrato Y; a Núclea põe o
  recebimento em boleto, cartão e TED na faixa Z." Também dá para confrontar a concentração de
  sacados com o contas a receber.
- **Regra 1:** o próprio relatório avisa que "sem dados de transação" não é erro (empresa nova,
  sazonalidade, movimento fora de boleto). O sistema mostra isso como **não observado**, nunca como
  zero.

**O dado que mais vale numa reestruturação:** a **agenda de recebíveis de cartão na registradora**,
que diz quanto está cedido, gravado ou antecipado (cessão fiduciária e trava bancária na RJ). Três
problemas:
- a consulta exige que o lojista autorize um **financiador**, e a Oria não é financiador;
- a agenda se espalha por várias registradoras;
- **[A CONFIRMAR] com a Núclea** se uma consultoria acessa com autorização do cliente. A mesma
  pergunta vale para a "Consulta de Status de Boletos" e a duplicata escritural.

### 2.4 Bureau de crédito

- **Opções:** Serasa Experian, Boa Vista (Equifax) e Quod. A Quod tem score combinado com a Núclea,
  o que pode virar um contrato só.
- **Conteúdo típico do relatório PJ:** pendências, protestos, RJ e falência, ações, quadro
  societário, score.
- **Preço:** não é público; vai para a cotação.

**Base legal no pré-mandato [jurídico interno, como na D12.6].** Antes do mandato não há NDA. A
base de "proteção do crédito" da LGPD é discutível para uma consultoria que não concede crédito. O
caminho mais seguro é **uma autorização de uma página**, assinada pelo prospect na primeira
reunião, cobrindo a empresa e os sócios PF. Sem autorização registrada, o sistema não consulta
sócio PF (Etapa 3).

---

## §3 — O que muda no sistema

Quatro peças novas, todas sobre o modelo que a Espec. 11 §5 já desenhou.

**1. `consulta_externa`** (T6 da Espec. 11), com quatro colunas a mais do que o §5 de lá previa:
- `fornecedor`: trocar de parceiro vira trocar um coletor, não remodelar o banco;
- `base_legal`: autorização pré-mandato, termo de kickoff, consentimento Open Finance, dado público;
- `autorizacao_id`: a autorização que permitiu a consulta. Sem ela, a consulta a PF é recusada no
  banco;
- `custo`: o preço por consulta, para o custo por caso ser medido e não estimado (lição do
  `CUSTO_IA.md`).

Os quatro estados continuam: `encontrado`, `nada_encontrado`, `falhou`, `nao_consultado`. `falhou`
nunca vira `nada_encontrado`.

**2. `caso.momento ∈ {pre_mandato, mandato}`.** É uma dimensão nova, pelo mesmo raciocínio da
`0114`: `status` diz onde o caso está no trabalho, `fechado_em` diz se ainda está na mesa, e
`momento` diz **o que a Oria pode fazer com ele**. No pré-mandato o banco recusa documento e
consulta PF sem autorização. A passagem a mandato é registrada com autor e data e preserva as
consultas.

**3. `autorizacao`**: o documento assinado (autorização pré-mandato, termo de kickoff,
consentimento Open Finance), com escopo, pessoas cobertas, validade e revogação. Ela é a única
coisa que libera consulta a PF e coleta de Open Finance. É o cofre da Espec. 12 §11 peça 4, com
escopo menor (uma autorização, não uma credencial).

**4. O Open Finance como mais uma fonte da trilha de extrato**, não como um caminho paralelo:
- a transação bruta é a evidência, e a categoria do agregador é sugestão;
- deduplicação contra o OFX quando os dois existirem, para o caixa não dobrar;
- `consentimento_open_finance` com estado (`ativo`, `pendente`, `expirado`, `revogado`), para
  "expirou" nunca virar "sem movimento".

---

## §4 — O plano, em etapas

Cada etapa segue as sete regras do `CLAUDE.md`: uma fatia por commit, invariante **medido
não-vazio** (desligar a correção, contar os asserts que reprovam, religar), porquê com número no
comentário e no commit, e sinal positivo de que rodou. **Uma etapa só começa com a anterior
aceita**, salvo onde a coluna "em paralelo" diz o contrário.

Os números de migration são os próximos livres na hora (hoje o próximo é `0215`). Toda tabela nova
concede o próprio GRANT (a `0214`: desde 30/10/2026 o Supabase não concede mais sozinho).

| Etapa | O que eu faço (artefatos) | Depende de | Em paralelo com | Pronto quando | Sinal de que rodou |
|---|---|---|---|---|---|
| **0 — Decisões e cotações** | Escrevo o RFP de cada frente (§5), com as perguntas fixas e a tabela de comparação; registro cada resposta aqui, na tabela da §7 | dono (envia e recebe) | qualquer etapa | D13.3 a D13.6 respondidas por escrito; preço por consulta de cada fornecedor escolhido na §7 | — (decisão, não código) |
| **1 — T0: segregação por mandato** (Espec. 11 §7.1) | Migration de RLS por `caso_id` nas tabelas com dado do cliente; leitura por papel (analista vê os mandatos atribuídos); registro de leitura em `evento_auditoria` nas tabelas sensíveis; teste SQL com dois usuários e dois casos; tipo `policy` na sonda | — | Etapa 0, Etapa 2 (se as policies das tabelas da Etapa 2 nascerem nela) | usuário do mandato A recebe 0 linhas do mandato B em toda tabela; a leitura de tabela sensível gera evento | desligar a policy faz o teste reprovar (número de asserts no commit) |
| **2 — T6: `consulta_externa`** + fontes públicas | Migration de `consulta_externa`, `fato_externo` e `autorizacao` (§3); coletor n8n das fontes públicas (Receita CNPJ/QSA/CNAE, CEIS/CNEP, PGFN, IBAMA, lista do MTE) disparado na criação do caso; suíte do coletor em `N8N/test` | Etapa 1 para as tabelas com PF | Etapa 0 | consulta vazia aparece como `nada_encontrado` com data; API derrubada aparece como `falhou`; fonte não consultada aparece como `nao_consultado` | uma linha por (entidade × fonte) por rodada, inclusive a vazia |
| **3 — Momento pré-mandato** | Migration de `caso.momento`, com a recusa no banco (documento em caso pré-mandato; consulta PF sem `autorizacao` válida); função de passagem a mandato com autor e data; no portal, a criação do caso em pré-mandato, o registro da autorização e o selo de momento na lista | Etapa 2 | — | inserir documento em caso pré-mandato falha no banco; consultar sócio PF sem autorização falha; a passagem a mandato preserva as consultas | os dois `check` derrubados fazem o teste reprovar |
| **4 — Processos (fecha a D5)** | Coletor do provedor em `consulta_externa` (empresa e cada sócio e administrador); **teste comparativo no mandato AMO** (8 empresas e os sócios): Exato × uma API processual, contra as certidões; o número publicado aqui; depois a T9 (leitura das certidões e processo × contingências) | Etapas 2 e 3 · contrato de teste (Etapa 0) | Etapa 5 (arquivos disjuntos: coletor próprio) | a D5 decidida com o número medido; processo de certidão ausente das contingências abre pendência | processos encontrados × certidões, por pessoa e por provedor |
| **5 — Bureau** | Coletor do bureau escolhido em `consulta_externa` (empresa e sócios, só com autorização); leitura dos campos (pendências, protestos, RJ, ações, score) em `fato_externo` | Etapas 2 e 3 · contrato (Etapa 0) · autorização do jurídico | Etapa 4 | consulta a PF sem autorização é recusada; protesto do bureau aparece no dossiê com data e validade | uma consulta por pessoa coberta pela autorização, inclusive a vazia |
| **6 — Apresentação pré-mandato** | Em `portal/src/lib/apresentacao/`, a base do deck passa a aceitar `consulta_externa` como origem (cadastro, sanções, bureau, processos), sem documento; `verificar-apresentacao.mts` ganha o caso pré-mandato | Etapas 4 e 5 | — | toda dimensão sem consulta aparece como "não pesquisado" com o efeito; nenhum número no slide sem `consulta_externa` de origem | a suíte reprova um slide com número sem fonte (medido não-vazio) |
| **7 — Open Finance** | Migration de `consentimento_open_finance` e da origem Open Finance na trilha de extrato; coletor do agregador escolhido; deduplicação contra o OFX; se o agregador entregar, o confronto empréstimos PJ × `MAPA_DIVIDA`; o `book-distress` passa a gerar também o extrato no formato do agregador | Etapa 1 · leitor de extrato da F2T onda 2 · contrato (Etapa 0) | Etapa 8 | o extrato sintético por Open Finance fecha no caixa do BP igual ao OFX; o mesmo período nos dois formatos não dobra o caixa; consentimento expirado aparece como "não observado desde <data>", não como saldo zero | Σ transações + saldo inicial = saldo final, por conta e período; meses lidos × meses esperados |
| **8 — Núclea (indicadores)** | Coletor do relatório de CNPJ em `consulta_externa`; três testes de plausibilidade, Classe C (o analista julga): faixa de recebimento × entradas do extrato × receita declarada; concentração × CAR; tendência × DRE | Etapa 2 · contrato (Etapa 0) | Etapa 7 | divergência fora da faixa abre pendência para o analista; "sem dados de transação" aparece como não observado | uma consulta por entidade do perímetro por rodada |
| **8b — Agenda de recebíveis** | Só se a Núclea confirmar acesso por autorização do cliente: coletor da agenda. Se não confirmar: o cliente exporta do portal da credenciadora e o arquivo entra como tipo novo, pelo canal C da Espec. 12 | resposta da Núclea (Etapa 0) | — | cessão e gravame aparecem no `MAPA_DIVIDA` como garantia | — |

**Ordem e paralelismo** (critério de `5 Prompts/03-onda-paralela.md`):
- **0 ∥ tudo.** É decisão e cotação, não código.
- **1 → 2 → 3** em série: cada uma usa a tabela ou a regra da anterior.
- **4 ∥ 5** depois da 3: coletores e arquivos disjuntos.
- **6** depois de 4 e 5.
- **7 ∥ 8**, com a 7 esperando também o leitor de extrato da F2T onda 2.

**O caminho mais curto até a primeira entrega visível** é 0 → 1 → 2 → 3 → 5 → 6: a apresentação
pré-mandato com cadastro, sanções e bureau. Processos entram no mesmo deck quando a 4 fechar.

**Os especialistas, por etapa:**
- `migrations-postgres`: 1, 2, 3, as tabelas da 7 e a T9 da 4;
- `n8n-workflow`: os coletores de 2, 4, 5, 7 e 8;
- `portal-export`: 3 (tela) e 6;
- `suites-invariantes`: cada invariante novo medido não-vazio;
- `revisor-defeito-silencioso`: todo diff, nunca o autor;
- `estado-e-handoff`: fecha cada etapa.

---

## §5 — O que o dono faz (Etapa 0)

### Perguntas a cada fornecedor

| Fornecedor | Perguntas |
|---|---|
| **Klavi, Pluggy, Belvo** | (1) Qual instituição recebe o dado no Open Finance, e qual o papel contratual da Oria? (2) Entregam empréstimos e cartões PJ, além do extrato? (3) Quanto histórico vem na primeira coleta? (4) Avisam quando o consentimento expira ou trava por alçada de sócio? (5) Entregam a transação bruta junto da categoria? (6) Preço por conexão, por consulta ou por mês? |
| **Exato Digital** | (1) Relatório de exemplo de PJ e de PF. (2) Quais tribunais e esferas cobre (cível, trabalhista, criminal, federal)? (3) Traz valor da causa, polo e fase por processo? (4) Tem monitoramento? (5) Emite certidões? (6) Preço da API e acesso de teste |
| **API processual** (Jusbrasil ou JUDIT) | As mesmas, mais: acesso de teste para o comparativo da Etapa 4 |
| **Núclea** | (1) Uma consultoria pode contratar o relatório de CNPJ? (2) Existe consulta autorizada pelo cliente à agenda de recebíveis, ao status dos boletos que ele emitiu e às duplicatas? (3) Qual a granularidade máxima com autorização do cliente? (4) Preço por consulta |
| **Bureaus** (Serasa, Boa Vista, Quod) | (1) Conteúdo do relatório PJ com sócios. (2) Preço por consulta. (3) A Quod combina com a Núclea num contrato só? |

### O que o jurídico interno escreve

1. **A autorização pré-mandato** (uma página): empresa e sócios PF, para quê, por quanto tempo,
   quem acessa.
2. **O termo de consentimento do Open Finance** no kickoff (volta o K2 da Espec. 12 §12).
3. **A linha da base legal** no `10_DADOS_RETENCAO_E_LGPD.md` para dado de PF consultado em
   bureau e em processo.

### Material para a Etapa 4

Lista dos sócios e administradores do mandato AMO e as certidões que já existirem. É o arranjo real
que a regra 4 exige para medir o provedor.

---

## §6 — Regras

- **(R1)** Fonte não consultada = "não pesquisado" + efeito ("passivo judicial do sócio X
  desconhecido"). Nunca "sem achados".
- **(R2)** Consentimento expirado = "não observado desde <data>". Nunca saldo zero nem "sem
  movimento".
- **(R3)** Indicador agregado (Núclea) é plausibilidade, não conciliação: abre pendência para o
  analista e nunca muda um número do book.
- **(R4)** Categoria do agregador é sugestão. A evidência é a transação bruta.
- **(R5)** Nada de PF é consultado sem `autorizacao` válida registrada. A recusa é no banco, não
  na tela.
- **(R6)** Toda consulta grava fornecedor e custo. O custo por caso é medido.
- **(R7)** Consulta tem validade. Certidão vale 90 dias; bureau e indicadores vencem quando o
  dossiê é atualizado. A tela marca a vencida.

---

## §7 — Decisões do dono

**Respostas do dono em 26/10/2026.** As tomadas valem como requisito. As abertas ficam abertas, sem
recomendação transformada em decisão.

| # | Decisão | Estado | O que fica valendo |
|---|---|---|---|
| D13.1 | Reabrir o Open Finance (D6 da Espec. 11 = D12.4 da Espec. 12) | ✅ **decidido em 26/10/2026: reabre** | Volta o contrato com agregador e o consentimento no kickoff (K2). O OFX continua como caminho quando não houver consentimento. Etapa 7 |
| D13.2 | KB no Obsidian como dataroom | ✅ **decidido em 26/10/2026: descartada** | O dataroom continua no SharePoint e no link de envio direto (Espec. 12 §11, peça 2) |
| D13.3 | Provedor de processos (= D5 da Espec. 11) | 🟡 **em pesquisa**: "pesquisar a fundo e entender se vale a pena" | Etapa 4: o comparativo no mandato AMO decide, com número |
| D13.4 | Bureau no pré-mandato | ✅ **decidido em 26/10/2026: precisamos** | Etapas 3, 5 e 6. Falta escolher o fornecedor (D13.6) e a autorização do jurídico |
| D13.5 | Uso da Núclea | ✅ **decidido em 26/10/2026**: examinar liquidação de boletos e transações de Pix e cartão, cruzando com o OFX | **Ajustado pela pesquisa (§2.3):** Pix fora (não passa pela Núclea); boleto e cartão só agregados, por plausibilidade. A agenda de recebíveis depende de resposta (Etapa 8b) |
| D13.6 | Qual agregador, qual bureau, qual provedor de processos | ⚪ **aberta** | Sai do RFP da Etapa 0 |

---

## §8 — O que este documento não cobre, dito de propósito

- **Portal do cliente.** O cliente continua sem login (`7 Marca/PRODUCT.md`). O dataroom é o
  SharePoint ou o link de envio.
- **Reclame Aqui e redes sociais** (D9 da Espec. 11). Continuam abertos.
- **Iniciação de pagamento** pelo Open Finance. Só leitura de dado.
- **Score próprio.** Os scores dos fornecedores entram como fato externo com a fonte. O sistema não
  os combina num número seu.

---

## Fontes

- Klavi: [sobre nós](https://klavi.ai/sobre-nos) · [crédito e risco](https://klavi.ai/credito-risco) · [Finsiders, aporte com a CIP (2022)](https://finsidersbrasil.com.br/noticias-sobre-fintechs/em-aporte-de-us-15-milhoes-klavi-traz-cip-e-vivo-para-o-captable/) · [Finsiders, Open Finance regulado (2023)](https://finsidersbrasil.com.br/reportagem-exclusiva-fintechs/a-klavi-agora-tem-a-chave-do-open-finance-regulado/) · [Let's Money, autorização para iniciar pagamentos](https://www.letsmoney.com.br/fintech/klavi-recebe-aval-para-iniciar-pagamentos-via-open-finance/)
- Open Finance PJ: [Let's Money, consentimento com vários sócios](https://www.letsmoney.com.br/open-finance/open-finance-pj-burocracia-socios-credito/) · [Open Finance Brasil](https://openfinancebrasil.org.br/) · [Resolução Conjunta 4/2022](https://static.poder360.com.br/2022/03/bc-resolucao-conjunta-4-2022.pdf)
- Alternativas: [Pluggy](https://finsidersbrasil.com.br/negocios-em-fintechs/fintech-pluggy-capta-us-35-milhoes-de-olho-em-novos-produtos/) · [Belvo](https://startups.com.br/fintech/belvo-preve-conectar-5-milhoes-de-contas-via-open-finance-no-brasil/) · [recebíveis de cartão fora do Open Finance](https://economicnewsbrasil.com.br/2022/07/30/plataforma-de-open-finance-ira-agregar-dados-de-recebiveis-de-cartao-de-credito/)
- Exato Digital: [site](https://www.exato.digital/) · [integração com a Gupy](https://www.gupy.io/integracao/exato) · [Capterra](https://www.capterra.com/p/10033151/Exato-Digital/)
- Processos: [Jusbrasil, busca por CPF/CNPJ](https://api.jusbrasil.com.br/docs/consulta_processual_por_cpf_cnpj/index.html) · [JUDIT](https://produto.judit.io/api)
- Núclea: [relatório de CNPJ](https://www.nuclea.com.br/relatorio-de-consulta-de-cnpj/) · [indicadores de crédito PJ](https://institucional.nuclea.com.br/inteligencia-de-dados-para-credito-pj) · [registro e liquidação de recebíveis](https://www.nuclea.com.br/liquidacao-e-registro-de-recebiveis/) · [SILOC](https://www.nuclea.com.br/liquidacao-de-operacoes-de-credito-siloc/) · [SLC](https://www.nuclea.com.br/liquidacao-de-cartoes-slc/)
- Registradoras: [Finsiders, entrevista com o CEO da CERC](https://finsidersbrasil.com.br/reportagem-exclusiva-fintechs/entrevista-fernando-fontes-ceo-da-cerc-registro-de-duplicata-eletronica-vai-alavancar-crescimento-das-fintechs-de-credito-para-pmes) · [B3, opt-in e agenda](https://www.b3.com.br/data/files/4F/22/3D/17/BA81E910014981E9AC094EA8/Manual%20de%20Operacoes%20-%20Recebiveis%20de%20Cartao.pdf)
- Bureaus: [Tecnospeed, API de bureau](https://blog.tecnospeed.com.br/?p=7046) · [Serasa, relatórios de crédito via API](https://www.serasaexperian.com.br/images-cms/wp-content/uploads/2024/06/Pack-GTM-Conteudo-e-Features-dos-Relatorios-de-Credito-via-APIs.pdf)
