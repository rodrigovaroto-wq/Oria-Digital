# 13A — O plano de execução, do que não depende de ninguém ao que depende de terceiros

**Data:** 27/10/2026 · **Base:** Espec. 13, a planilha verificada `Plano_de_Captacao_v3.xlsx` (nesta
pasta; 179 linhas, 26 afirmações conferidas com fonte) e os anexos 13B (RFP) e 13C (piloto).

**Como ler.** Seis níveis, do mais fácil ao mais dependente. Um nível não espera o anterior acabar:
os níveis 0, 1 e 2 começam no mesmo dia. O que ordena é **de quem depende**:

| Nível | Depende de | Quanto custa | Quando começa |
|---|---|---|---|
| **0** | Só da engenharia | nada | hoje |
| **1** | Um cadastro gratuito (minutos) | nada | hoje |
| **2** | O dono, o jurídico e o cliente do mandato AMO | horas de gente | hoje |
| **3** | Uma conta paga sem negociação (cartão ou pré-pago) | R$ 100 a R$ 500 no piloto | depois do e-CNPJ da Oria (2.4) |
| **4** | Contrato negociado, saído do RFP | a cotar | depois do piloto |
| **5** | Terceiro ou regulador, sem garantia de resposta | — | em paralelo, sem bloquear nada |

As linhas citadas (L1 a L179) são as da aba "Plano por item" da planilha. As etapas (E0 a E8) são
as da Espec. 13 §4 e da fase F2E do roadmap.

**O que nenhum nível dispensa:** as sete regras do `CLAUDE.md`. Em especial, cada coletor grava
`encontrado`, `nada_encontrado`, `falhou` ou `nao_consultado` (regra 7). A verificação de 27/10
mostrou por que isso importa: a API do Comex Stat respondeu 503 e o endereço dos dados abertos do
CNPJ mudou. Nos dois casos, um coletor sem esse estado teria gravado "sem dados".

---

## Nível 0 — Só engenharia (começa hoje)

Ordem interna por dependência. Os itens 0.1 a 0.3 são a fundação; 0.4 a 0.7 rodam em paralelo
depois do 0.2.

| # | O que | Linhas | Etapa | Especialista | Pronto quando | Sinal de que rodou |
|---|---|---|---|---|---|---|
| **0.1** | **T0: segregação por mandato** (RLS por `caso_id`, leitura por papel, registro de leitura) | — | E1 | `migrations-postgres` | o usuário do mandato A lê 0 linhas do B em toda tabela | desligar a policy reprova o teste (asserts no commit) |
| **0.2** | **`consulta_externa`, `fato_externo`, `autorizacao`**, com o GRANT explícito exigido desde a `0214` | L175 | E2 | `migrations-postgres` | os quatro estados gravam e a consulta a PF sem autorização é recusada no banco | teste com os quatro estados, medido não-vazio |
| **0.3** | **`caso.momento`** (pré-mandato e mandato) | — | E3 | `migrations-postgres` + `portal-export` | o banco recusa documento em caso pré-mandato | a recusa derrubada reprova o teste |
| **0.4** | **Coletores públicos, onda A: macro** — BCB/SGS (**192 = INCC-DI, 7456 = INCC-M**, 24363 IBC-Br, crédito do SFN), Olinda (PTAX por moeda), SIDRA (PNAD, PIM, PMC, PMS), Ipeadata (EMBI+), BIS, Banco Mundial (Pink Sheet), ANBIMA (ETTJ diária) ou B3 (ajustes do DI1) | L5–L7, L9, L10, L12, L15, L26, L63, L64 | E2 | `n8n-workflow` | cada série validada contra um número publicado antes de entrar (a 7447, que um site chama de INCC-DI, é o IGP-10) | uma linha por série por rodada, inclusive `falhou` |
| **0.5** | **Coletores públicos, onda B: cadastro e listas por CNPJ/CPF** — Receita (dados abertos do CNPJ, endereço novo), PGFN (dívida ativa, trimestral), IBAMA (autos), MTE (trabalho escravo), CGU (PEP), Consumidor.gov, INPI (RPI), CVM e debêntures | L13, L61, L77, L100, L123, L124, L142, L153, L161 | E2 | `n8n-workflow` | consulta vazia aparece com data; endereço trocado aparece como `falhou` | uma linha por (entidade × fonte) por rodada |
| **0.6** | **Coletores públicos, onda C: setor** — CVM (DFP/ITR de pares), Novo CAGED, Comex Stat (quando a API voltar), CONAB, um regulador por vez (ANS, ANEEL, ANATEL, ANP) | L15, L17, L19, L25, L27 | E2 | `n8n-workflow` | o caso do book mostra as séries do seu CNAE | meses lidos × meses esperados |
| **0.7** | **Formulários do analista**: cenários com autor e motivo, ajustes de EBITDA, risco setorial, haircuts, política de crédito, proposta de reestruturação, pessoas-chave, avaliação da gestão | L3, L14, L20, L21, L23, L28, L37, L78, L79, L83, L133, L158, L165, L171, L179 | — | `portal-export` | o cenário sai do Excel e vira dado no banco | — |
| **0.8** | **Cálculos sobre dado que já existe**: concentração bancária, bloqueios SISBAJUD no extrato, concentração de clientes, teste do CADE | L91, L104, L119, L136 | — | `migrations-postgres` | — | um invariante por cálculo, medido não-vazio |
| **0.9** | **Ferramental do piloto** (13C §5): planilha-gabarito, script que compara a saída de cada fornecedor com o gabarito, relatório de métricas | — | — | `suites-invariantes` | o script roda sobre um gabarito sintético e reprova quando um processo some | — |

**O que o nível 0 entrega sozinho:** a fundação de segurança, o registro de consultas e cerca de 40
linhas da planilha com fonte gratuita, sem falar com ninguém de fora.

---

## Nível 1 — Cadastros gratuitos (minutos, sem contrato)

| # | O que | Para quê | Quem | Linhas |
|---|---|---|---|---|
| **1.1** | Chave da API do Portal da Transparência | CEIS e CNEP por CNPJ/CPF | engenharia, com o e-mail da Oria | L122 |
| **1.2** | Chave pública do DataJud (publicada na wiki do CNJ; sem ela a API responde 401) | andamento de processo por número | engenharia | L109 |
| **1.3** | Chave da API do FRED | juros dos EUA | engenharia | L11 |

---

## Nível 2 — O dono, o jurídico e o cliente (sem fornecedor)

| # | O que | Quem | Destrava | Observação |
|---|---|---|---|---|
| **2.1** | **Enviar o RFP** (13B) aos fornecedores da lista do 13B §8 | dono | o nível 4 | prazo de resposta sugerido: 15 dias corridos |
| **2.2** | **Autorização dos sócios e administradores do mandato AMO** para o piloto | jurídico + cliente | o piloto com PF | sem ela, o piloto roda só com as empresas (13C §3) |
| **2.3** | **Textos do jurídico**: autorização pré-mandato (uma página), termo de consentimento do Open Finance, linha da base legal no `10_DADOS_RETENCAO_E_LGPD.md` | jurídico interno (D12.6) | E3, E5, E7 | — |
| **2.4** | **e-CNPJ A1 da Oria** (pré-requisito P1 da Espec. 12) | dono, numa certificadora | o nível 3 inteiro (Integra, e-CAC, ReceitaNet BX) | compra direta, sem negociação |
| **2.5** | **Procuração eletrônica no e-CAC** de cada CNPJ do AMO para a Oria, só consulta (D12.1) | cliente | Integra, e-CAC, ReceitaNet BX no piloto | uma por CNPJ |
| **2.6** | **Material-gabarito do piloto** (13C §4): certidões já emitidas, relatório de contingências, mapa de dívida, Registrato dos sócios, matrículas conhecidas | analista do mandato | a medição do piloto | sem gabarito não há medição, só opinião |
| **2.7** | **Volume real** de mandatos e alvos por mês | dono | o custo do 13B e do piloto | a planilha usa 4 mandatos e 56 alvos por mês, uma suposição |
| **2.8** | **3 ECDs reais** (D8) | dono | F2T onda 1 | já pedido antes; segue pendente |

---

## Nível 3 — Contas pagas sem negociação (habilitam o piloto)

Os três se contratam pelo site, com pré-pago ou pós-pago, e servem para medir antes de assinar
qualquer contrato longo.

| # | Fornecedor | Como contrata | Custo para o piloto | Destrava | Linhas |
|---|---|---|---|---|---|
| **3.1** | **Infosimples** | conta no site, saldo pré-pago | franquia mínima de R$ 100/mês; R$ 0,20 por consulta até 500 | certidões (6 TRFs, CNDT, CEAT de 23 dos 24 TRTs, 15 TJs + TJDFT, CND estadual das 27 UFs, CND de dezenas de prefeituras), PGFN, e-CAC (DCTFWeb, PER/DCOMP, Caixa Postal) | L106, L114, L125, L130, L58, L112 |
| **3.2** | **Escavador** | créditos pré-pagos (validade de 90 dias) | valor base por pessoa, cobre 200 processos (o suporte usa R$ 4,50 como exemplo; a tabela real está no painel) | descoberta de processos por CPF/CNPJ | L102, L108, L110 |
| **3.3** | **SERPRO Integra Contador** | Loja SERPRO, pós-pago, com o e-CNPJ da Oria (2.4) | R$ 0,40 a R$ 0,96 por transação (fontes de terceiros; tabela na Loja) | relatório de situação fiscal (SITFIS), parcelamentos do Simples/MEI, DCTFWeb | L50, L51, L112 |

**Engenharia, junto:** um coletor por fornecedor gravando em `consulta_externa` (com `fornecedor` e
`custo`), e o piloto (13C) rodando sobre o mandato AMO.

---

## Nível 4 — Contratos negociados (saem do RFP e do piloto)

| # | Categoria | Candidatos | Destrava | Linhas | Decide com |
|---|---|---|---|---|---|
| **4.1** | **Bureau de crédito** | Serasa (relatório Concentre PJ), Boa Vista, Quod | protestos nacionais, ações, falências, sócios, score; crédito de clientes e fornecedores; o deck pré-mandato (E5, E6) | L82, L92, L107, L137, L145 | RFP + piloto |
| **4.2** | **Agregador de Open Finance PJ** | Pluggy, Belvo; Klavi como alternativa (foco em PF) | extrato automático, limites de cheque especial, operações de crédito (E7) | L70, L76, L85 | RFP; piloto só com consentimento do cliente |
| **4.3** | **Provedor processual com volume** | JUDIT (R$ 6,00 por mil processos; faixa mínima de R$ 1 mil/mês), Jusbrasil | troca do Escavador se o volume passar do ponto em que o mínimo compensa | L110 | piloto |
| **4.4** | **Núclea** (indicadores de boleto, cartão e TED) | Núclea | plausibilidade de receita e concentração (E8) | L70, L72 | RFP |
| **4.5** | **ONR / SAEC** (matrículas por API) | ONR | matrículas em escala | L128 | RFP; até lá, pedido manual no SAEC |
| **4.6** | Opcionais | FGV Dados, licença CEPEA, clipping de notícias | marginal: as alternativas gratuitas cobrem quase tudo | L5, L18, L24, L126, L164 | só se o piloto mostrar falta |

---

## Nível 5 — Depende de terceiro ou regulador, sem garantia

Nenhum destes bloqueia os níveis anteriores. Cada um tem um caminho manual que vale até a resposta
chegar, e o caminho manual aparece no sistema como fonte com o efeito nomeado (regra 1).

| # | O que | Por que é incerto | Caminho até lá |
|---|---|---|---|
| **5.1** | Agenda de recebíveis de cartão (cessão, gravame, trava) | a consulta exige que o cliente autorize um **financiador**, e a Oria não é | o cliente exporta do portal da credenciadora |
| **5.2** | eSocial por procurador | o acesso por procuração foi anunciado em 2020 e não está confirmado; não há web service de download | export do sistema de folha (canal C) |
| **5.3** | FGTS Digital por API para terceiros | o procurador entra com certificado; a API é para softwares de folha | extrato e guias pelo cliente |
| **5.4** | Consentimento PJ de Open Finance | exige os representantes legais e expira em silêncio quando há vários sócios | OFX pelo cliente |
| **5.5** | Robô no ReceitaNet BX | quebra quando a Receita muda a tela (D12.5) | o pedido cai para o contador |
| **5.6** | Registrato (SCR) | só o titular baixa; consultoria não acessa | o sócio envia o PDF |
| **5.7** | Certidões de TJ em 11 UFs sem cobertura do agregador | o agregador não cobre AC, AL, AM, AP, ES, MG, PE, PR, RN, RO, SE | o cliente pede a certidão no tribunal |

---

## A sequência, em semanas (estimativa; esforço não medido)

| Semana | Engenharia | Dono, jurídico e cliente |
|---|---|---|
| 1 | 0.1 T0 · 0.2 `consulta_externa` · 1.1 a 1.3 chaves | 2.1 envia o RFP · 2.4 compra o e-CNPJ · 2.7 volume real |
| 2 | 0.3 momento · 0.4 coletores macro · 0.9 ferramental do piloto | 2.2 autorização dos sócios do AMO · 2.5 procurações · 2.6 gabarito |
| 3 | 0.5 coletores de cadastro · contas do nível 3 e seus coletores | 2.3 textos do jurídico |
| 4 | **piloto, rodada** (13C §6) · 0.6 e 0.7 | respostas do RFP chegam (prazo de 15 dias) |
| 5 | **piloto, conferência e relatório** · 0.8 | — |
| 6 | — | **decisão D13.3 e D13.6** com o relatório do piloto; contratos do nível 4 |
| 7 em diante | coletores do nível 4 · E6 (deck pré-mandato) · E7 e E8 conforme os contratos | nível 5, conforme as respostas |

**A primeira entrega visível** é o deck pré-mandato (E6), que depende de 0.1 a 0.3, do bureau (4.1)
e do provedor processual (3.2 ou 4.3). Sem o bureau, o deck sai com cadastro, sanções e processos,
e mostra "protestos e histórico de pagamento: não pesquisado" com o efeito.
