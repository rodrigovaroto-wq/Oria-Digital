# 15 — Score de confiabilidade dos dados externos e os portões por etapa

**Data:** 23/11/2026 · **Natureza:** desenho e pesquisa. **Nada aqui está implementado e nada será
construído agora** (pedido do dono). O objetivo é deixar pronto o raciocínio, as decisões a tomar e
as limitações, para que a construção comece sem mudar de rota.

Números de limiar marcados **[A CALIBRAR]** são lugares reservados, não propostas: eles só são
fixados depois do modo sombra (§9). Escrever um número agora seria a regra 1 ao contrário — um
limiar inventado tem a mesma aparência de um limiar medido.

**Origem, em ordem de autoridade:**

1. O **pedido do dono em 23/11/2026** (§0).
2. A **Especificação 13**, §3 e §6: a tabela `consulta_externa`, os quatro estados de uma consulta
   (`encontrado`, `nada_encontrado`, `falhou`, `nao_consultado`), a `autorizacao` e a validade (R7).
   **Este score se apoia nelas, não cria um mecanismo paralelo.**
3. As regras de negócio (`Business Plan/04_regras_de_negocio/REGRAS_E_DEFINICOES.md`): D3 (o
   externo tem o maior peso no cruzamento, os dois valores ficam guardados), B3b-1 (régua do que se
   resolve sozinho), G5 e G5-1 (gravidade), D6 (≥ 300 amostras e limite inferior ≥ 98% para subir
   autonomia).
4. A **doutrina de autonomia** (`1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md`): o dial N0–N3 e a
   função `fn_dial_permite_auto(estágio, confiança)` (`0127`). **O portão do score usa esse mesmo
   mecanismo** (degrau 2 da escada do `CLAUDE.md`: já existe, reuse).
5. A pesquisa pública de 23/11/2026, com as fontes no fim (§13).

---

## Resumo

- **O que é:** uma avaliação de cada dado que o Oria **busca fora** (BCB, IBGE, CVM, Receita,
  tribunais, bureau, Open Finance, Núclea…), por várias dimensões — não só quantidade e qualidade,
  mas origem, histórico de acerto, independência, concordância, frescor, identidade e custódia.
- **Para que serve:** pôr um **portão** em cada etapa do processo. Cada etapa declara o mínimo que
  exige de cada tipo de dado. Abaixo do mínimo, a etapa **para**, **segue com ressalva** ou **vai ao
  humano** — nunca segue em silêncio.
- **A conclusão central da pesquisa:** **um número único não serve para barrar.** Uma média esconde
  um zero numa dimensão (regras 1 e 7). O portão decide em camadas: **vetos → piso por dimensão →
  classe → score ponderado pelos pesos do agente** (§5A). O score sozinho nunca aprova.
- **Pesos e mínimos por agente (§5A):** proposta inicial, de julgamento, conferida em 12 casos. Roda
  em modo sombra até a calibração.
- **A limitação central:** concordância não é verdade. Duas fontes que copiam a mesma origem
  concordam no erro. E quando o dado externo **diverge do cliente**, isso é o achado que a Oria
  procura, não defeito da fonte: essa divergência **não** pode baixar o score do externo.
- **Como sai do papel:** primeiro em **modo sombra (N0)** — calcula, grava, mostra, não barra. Só
  depois de medir se a classe prevê o erro (gabarito), os pisos são fixados e os portões ligados,
  um de cada vez.

---

## §0 — O pedido do dono (23/11/2026)

> Adicionar no planejamento e na documentação uma pendência: uma parte de **score** dos documentos e
> dados que conseguimos captar **de fora** — não os importados no sistema, mas os extraídos das
> fontes exteriores. Score não só por quantidade ou qualidade dos dados, mas por diversos outros
> fatores, por exemplo a **auditoria** desses dados: qual a **confiabilidade**, o quanto conseguimos
> confiar neles enquanto **batem com os que já temos**. A partir disso, um score **para cada tipo de
> dado**, para termos uma **barreira, um portão, a cada fragmento do processo**: um **mínimo de score
> de qualidade e confiabilidade** em que uma etapa pode ser barrada ou continuada. Não vamos construir
> agora; é para pensar e estruturar como fazer na prática, **definir os limites e identificar as
> limitações**.

---

## §1 — Escopo: o que é "dado externo"

| Canal | O que é | Exemplos | Neste score? |
|---|---|---|---|
| **E1 — o sistema busca direto** | API, arquivo público ou parceiro, sem passar pelo cliente | SGS/Focus (BCB), SIDRA (IBGE), CVM, CAGED/RAIS, dados abertos do CNPJ, tribunais e APIs processuais, bureau, Núclea, Open Finance | **Sim** |
| **E2 — documento oficial de terceiro, trazido pelo cliente** | Emitido por um terceiro (fisco, BCB, cartório), mas o arquivo chega pelo upload | SPED (ECD/ECF/EFD) com recibo, Registrato/SCR, certidões | **Recomendado: sim** (D15.1), com a dimensão de custódia (§3, B7) pesando mais |
| **I — documento do cliente** | Produzido pela própria empresa | Balancete, DRE, aging, planilhas | **Não.** Já tem o seu controle: extração, gabarito (`0126`) e dial |

**Por que E2 entra (recomendação):** é ele que serve de referência no cruzamento (itens 1.B3 e 1.B4
do plano). Mas um SPED entregue pelo cliente pode ser uma versão não transmitida, ou retificada
depois. A norma de auditoria diz a mesma coisa: resposta que chega por intermediário é mais fraca do
que a obtida direto (ISA 505, A11). Por isso, em E2, conferir o recibo de transmissão ou o hash é
condição para o dado contar como externo.

---

## §2 — Por que um número só não serve para barrar

1. **A média compensa o que não pode ser compensado.** Um dado 100% completo, fresco e válido, mas
   que é **de outra empresa** (homônimo num processo), tira média alta. O manual da OCDE/JRC de
   indicadores compostos chama isso de agregação compensatória, e propõe regras não compensatórias
   quando uma fraqueza não pode ser coberta por uma força.
2. **A contabilidade já resolve isso pelo elo mais fraco.** No IFRS 13, uma medição de valor justo é
   classificada **inteira** no nível da entrada significativa mais fraca. O mesmo vale aqui: o dado
   vale o que vale a sua dimensão significativa mais fraca.
3. **Confiança na fonte e credibilidade do dado são eixos diferentes.** O código do Almirantado
   (NATO, AJP-2.1) avalia separado a fonte (A–F) e a informação (1–6). Uma fonte excelente pode
   trazer um dado errado; uma fonte nova (sem histórico) pode trazer um dado confirmado por outras.
   Misturar os dois num número perde exatamente essa distinção.
4. **"Não medido" não é número.** Se uma dimensão não pôde ser medida, um zero baixa a média como
   se o dado fosse ruim; um valor neutro a sobe como se fosse bom. Os dois mentem (regras 1 e 7).
5. **Número que vira meta deixa de medir** (lei de Goodhart). Se o portão é um único número, a
   tentação é afrouxar a regra que mais reprova, ou deixar de consultar a fonte difícil. Componentes
   visíveis e todo "furo do portão" registrado reduzem isso.

**Consequência para o desenho:** o score é um **perfil** (uma nota por dimensão, cada uma com
estado), mais **vetos**, **pisos** e uma **classe**. O score ponderado (§5A) só é lido depois dessas
três camadas.

---

## §3 — As dimensões

Três níveis, porque mudam em velocidades diferentes: a **fonte** muda devagar, o **dado** muda a cada
coleta, e a **execução** prova que o estágio rodou.

Toda dimensão devolve um de três **estados**: `medido` (com valor e método), `nao_medido` (com
motivo) ou `nao_se_aplica`. **Nunca um padrão.**

### Nível A — a fonte (vale para todos os dados dela)

| # | Dimensão | O que pergunta | Como se mede no Oria | Base |
|---|---|---|---|---|
| A1 | **Origem** | Quem produz o dado? | Escala fixa: **produtor primário** (o IBGE produz o IPCA) > **espelho oficial** (o BCB republica o IPCA) > **parceiro contratado** que lê a origem > **agregador ou revendedor** > **raspagem** > **sem origem declarada** | ISA 500 (fonte externa independente; original > cópia); IFRS 13 (nível 1/2/3 pela observabilidade) |
| A2 | **Histórico de acerto** | Quando pudemos conferir, quanto ela acertou? | Acertos / conferências, sobre o gabarito e os cruzamentos resolvidos. **Usa o limite inferior** do intervalo (Wilson ou Jeffreys), não a taxa crua: 3 de 3 não é 100% | Knowledge-Based Trust (Google): confiança = P(valor certo \| a fonte deu um valor); D6 para o limite inferior |
| A3 | **Estabilidade** | Ela falha, muda de endereço ou de leiaute sem avisar? | Taxa de `falhou` por coleta; mudanças de esquema detectadas; dias fora do ar | Já aconteceu: endereço do CNPJ deu 404; Comex fora do ar; protestos da Infosimples descontinuados (Espec. 13, §8a) |
| A4 | **Independência** | Ela tem origem comum com outra fonte que usamos? | Catálogo declara a origem de cada fonte (`origem_compartilhada_com`). Duas fontes com a mesma origem contam **uma** confirmação | Dong, Berti-Equille e Srivastava (2009): sem detectar cópia, a fusão de fontes premia o erro repetido |
| A5 | **Base legal e contrato** | Podemos usar, e o fornecedor responde pelo dado? | Autorização (`autorizacao`, Espec. 13) e cláusulas de SLA e de origem | LGPD art. 6º, V; N-C7b. **É veto, não peso** (§4) |

### Nível B — o dado (cada observação)

| # | Dimensão | O que pergunta | Como se mede no Oria | Base |
|---|---|---|---|---|
| B1 | **Concordância** | Bate com o que já temos? | Diferença contra cada referência, em três tipos — ver a regra da divergência abaixo | ISA 520 (expectativa e diferença aceitável); régua B3b-1; `fn_divergencias_indice_macro` (`0025`) já faz isso para as séries macro |
| B2 | **Frescor** | Ainda vale? | Idade do dado ÷ cadência esperada da fonte. Certidão 90 dias (Espec. 13, R7); série diária; balanço anual | ISO/IEC 25012 (atualidade); BCBS 239 (tempestividade); item 1.C4 |
| B3 | **Completude** | Veio tudo o que devia? | Esperado × obtido: meses da série, CNPJs do perímetro consultados, tribunais cobertos | BCBS 239, princípio 4: exceção de completude identificada e documentada |
| B4 | **Validade** | Tem forma de dado certo? | Tipo, domínio, unidade, dígito do CNPJ, data possível. **No banco** (`check`), não em nó Code | ISO/IEC 25012 (conformidade); degrau 4 da escada |
| B5 | **Plausibilidade** | Faz sentido diante do histórico? | Salto fora da distribuição da própria série; número fora da faixa do setor | Pilar "distribuição" da observabilidade de dados |
| B6 | **Identidade** | O dado é mesmo desta empresa (ou pessoa)? | CNPJ exato = certo. Por nome (processos, notícias): probabilidade de correspondência com **dois limiares** — acima, aceita; entre, humano; abaixo, recusa | Fellegi–Sunter (ligação de registros, faixa de revisão manual) |
| B7 | **Custódia** | Dá para provar de onde veio e que não mudou? | Hash do conteúdo bruto, data e endpoint da coleta, versão do coletor, recibo ou assinatura em E2 | ISA 505 (A11, A12); W3C PROV; itens 1.B6 e 2.15 |

**A regra da divergência (B1) — a decisão mais importante do desenho.** A referência pode ser de três
tipos, e cada um conta diferente:

| Diverge de… | Efeito no score do dado externo | O que acontece |
|---|---|---|
| **Outra fonte externa independente** (A4) | **Baixa** a concordância | Um dos dois está errado; o par vai ao humano (N-C6a) |
| **Uma identidade aritmética** (soma, saldo inicial + movimento = saldo final) | **Baixa** a concordância | Erro de captura ou da fonte |
| **O documento do cliente** | **Não baixa** | É o **achado** (D3, D3-3). Baixar o score aqui esconderia exatamente o que a Oria é paga para encontrar |

E **concordar com o cliente** sobe pouco: se a fonte externa é derivada do próprio cliente (ex.: um
bureau que lê o balanço que o cliente publicou), a concordância é circular (A4).

### Nível C — a execução (regra 7)

| # | Dimensão | O que pergunta | Como se mede |
|---|---|---|---|
| C1 | **Sinal de execução** | A consulta rodou de fato? | Estado da `consulta_externa` (`encontrado`, `nada_encontrado`, `falhou`, `nao_consultado`), status HTTP, número de registros, hash. Sem esse sinal, o dado é **não medido** — nunca "limpo" |

---

## §4 — Como as dimensões viram decisão

Em quatro passos, nesta ordem. Os três primeiros decidem; o quarto só exibe.

1. **Vetos** (determinísticos, sem limiar a calibrar). Qualquer um deles → **BLOQUEADO**, seja qual
   for o resto:
   - sem autorização válida (A5) — já previsto no banco pelo item 1.B7;
   - sem sinal de execução, ou `falhou`/`nao_consultado` lido como dado (C1);
   - identidade abaixo do limiar inferior (B6);
   - custódia quebrada: hash diferente, recibo ausente em E2 (B7);
   - validade reprovada (B4);
   - vencido além do prazo crítico da fonte (B2).
2. **Piso por dimensão.** Cada par (tipo de dado × etapa) declara um mínimo para cada dimensão que
   importa a ele. Abaixo do piso → o desfecho que o par declarou (§5). Dimensão `nao_medido` numa
   dimensão com piso → trata como abaixo do piso, com o motivo.
3. **Classe** do dado, pelo elo mais fraco entre as dimensões significativas:

   | Classe | Quer dizer | Exemplo |
   |---|---|---|
   | **Confirmado** | Fonte primária, ou ≥ 2 fontes independentes concordando dentro da tolerância | IPCA do IBGE que bate com o espelho do BCB |
   | **Provável** | Uma fonte com bom histórico, sem contradição independente | Série do SGS sem segunda fonte |
   | **Possível** | Fonte sem histórico, ou identidade por nome na faixa de revisão aceita pelo humano | Processo achado por nome e confirmado pelo analista |
   | **Contestado** | Fontes externas independentes discordam acima da tolerância | Dois provedores de processos com contagens diferentes |
   | **Não julgável** | Falta dimensão significativa medida | Fonte nova, sem referência nenhuma |

   "Não julgável" é falta de conhecimento nosso, não defeito do dado — o código do Almirantado faz a
   mesma distinção no grau 6. Ele **aparece**, com o motivo.
4. **Score composto (0–100)**: média ponderada das notas, com os pesos **do agente ou da etapa que
   vai usar o dado** (§5A). Pedido do dono em 23/11: o portão lê o score **depois** dos vetos e dos
   pisos, nunca no lugar deles — é o que impede a média de esconder um zero.

**Fonte e dado saem lado a lado, como no código do Almirantado:** "fonte primária · Confirmado",
"agregador · Possível". Um rótulo de duas partes diz mais do que um número.

---

## §5 — Os portões, etapa por etapa

**Três desfechos, sempre:**

| Desfecho | O que acontece | Regra que já existe |
|---|---|---|
| **SEGUE** | A etapa usa o dado | — |
| **SEGUE COM RESSALVA** | Usa, e o book leva nota com o **motivo e o efeito** ("juros por modalidade de 4 meses atrás; o custo da dívida pode estar subestimado") | Regra 1; E3 (até 3 ressalvas altas) |
| **PARA** | Só as etapas que **dependem** desse dado esperam; as independentes seguem. Vai ao humano com o prazo da gravidade | "Diagnóstico não confiável não sai como definitivo" (v0.1.2 §5); E5 |

**Furar o portão** é possível, mas é decisão humana em campo estruturado (N-B5b): quem, por quê, com
qual evidência. Dado de gravidade crítica: só o Sócio (como na E3-1). Todo furo entra na revisão
semanal (E4) — é o antídoto contra Goodhart.

| Etapa (fragmento do processo) | O que o portão pergunta | Dimensões que mais pesam | Ao reprovar |
|---|---|---|---|
| **1. Captação** (coletor) | A consulta rodou, com autorização, e o conteúdo bruto foi guardado? | A5, C1, B7 | Vetos → PARA a coleta e marca `falhou`/`nao_consultado`. Nunca grava "sem dados" |
| **2. Normalização e identidade** | É desta empresa, no formato certo? | B4, B6 | Identidade na faixa do meio → humano. Abaixo → recusa |
| **3. Cruzamento** (Conferidor, 1.B5) | O dado serve de **referência** para conferir o cliente? | A1, A2, A4, B2 | Abaixo do piso → o dado ainda é mostrado, mas **não** dá veredito sozinho; o cruzamento fica "sem referência confiável" com o efeito |
| **4. Análise** (agentes, 1.E) | O agente pode apoiar uma conclusão nele? | Classe + B2 | "Possível" ou pior não sustenta conclusão sozinho; o agente registra a hipótese e encaminha (N-C6a) |
| **5. Book / Excel** | O número pode entrar numa célula? | Classe + gravidade do número | Por materialidade (G5): o dado que mexe > 5% do EBITDA ou da dívida pede classe mais alta que o que mexe < 1% **[A CALIBRAR]** |
| **6. Entrega** (cliente, credor) | Pode sair da Oria? | Classe de todos os dados citados | "Contestado" ou "Não julgável" sem ressalva aprovada → PARA. Segundo revisor (E1) vê a lista |
| **7. Monitoramento** (2.8) | Mudou algo desde a última vez? | B2, A3 | Fonte vencida ou instável vira alerta, não silêncio |

**O piso escala com o que está em jogo**, não é um só para tudo: um índice de inflação usado como
contexto pede menos do que a dívida bancária do Registrato que vai para o fluxo de caixa. Essa é a
régua de materialidade que a auditoria já usa (ISA 520: quanto mais precisa a expectativa, menor a
diferença aceitável).

**Ligação com o dial (reuso, não mecanismo novo).** Cada portão é um "estágio" do dial, e a classe
(ou a dimensão que o par declarou) é a "confiança" que `fn_dial_permite_auto` já compara com o
limiar. Assim o portão herda o que o dial já tem: nível N0–N3, teto por natureza do estágio,
promoção por gabarito e o registro de quem mudou o quê.

---

## §5A — Pesos, notas de corte e classificação por agente (proposta inicial, 23/11/2026)

Pedido do dono: um peso percentual para cada nota e um score mínimo, por agente de IA e por etapa,
para que **só o dado de alta confiabilidade passe sozinho** para a etapa seguinte.

**Status destes números: hipótese inicial, não medida** (D15.8). São escolhas de julgamento,
conferidas contra 12 casos realistas (tabela 5A.6), e não contra um gabarito. Eles entram em
**modo sombra** — calculam, gravam e mostram, sem barrar. Só passam a bloquear depois da etapa 4
(§12), quando a taxa de erro por classe tiver sido medida. Até lá, só os vetos bloqueiam (D15.4).

### 5A.1 — Como cada nota é dada (rubrica objetiva, 0 a 100)

Cada dimensão tem degraus fixos. "Sem histórico" e "sem referência" são **estados medidos**
(contamos zero conferências; procuramos e não há referência), não ausências, por isso têm degrau.

| Cód. | Dimensão | Degraus da nota |
|---|---|---|
| A1 | Origem | **100** produtor primário direto, ou documento oficial com recibo ou assinatura conferidos · **85** espelho oficial, ou canal regulado (Open Finance por integradora autorizada) · **70** parceiro contratado que declara a origem · **50** agregador ou revendedor sem origem por item · **30** raspagem · **0** sem origem declarada |
| A2 | Histórico de acerto | **Limite inferior de Wilson (95%)** de acertos ÷ conferências × 100, com ≥ 30 conferências (30 em 30 → 89; 300 em 300 → 99; a mesma régua da D6). **Com menos de 30:** 70 se A1 ≥ 85, senão 40 (a origem oficial vale como ponto de partida; o resto começa desconfiado) |
| A3 | Estabilidade | % de coletas com sucesso nas últimas 30, menos 20 por mudança de endereço ou de esquema não anunciada nos últimos 12 meses (mínimo 0). Fonte sem coleta anterior: 70 |
| A4 | Independência | **100** origem própria declarada · **50** origem compartilhada com outra fonte usada no mesmo cruzamento · **30** origem desconhecida |
| B1 | Concordância | **100** confirmado por ≥ 2 fontes externas independentes, ou a identidade aritmética fecha · **85** confirmado por 1 fonte independente · **50** sem referência independente disponível · **30** diverge até 2× a tolerância · **0** diverge acima de 2× a tolerância. **A comparação com o documento do cliente não entra** (D15.7) |
| B2 | Frescor | **100** idade ≤ 1× a cadência da fonte · **70** ≤ 2× · **40** ≤ 3× · acima do prazo crítico: **veto** |
| B3 | Completude | Obtidos ÷ esperados × 100 (meses da série, contas, CNPJs do perímetro, tribunais da UF) |
| B5 | Plausibilidade | **100** dentro de 3 desvios-padrão da própria série · **50** entre 3 e 5 (alerta) · **0** acima de 5 · série com menos de 12 pontos: **60** (não testável) |
| B6 | Identidade | **100** chave exata (CNPJ ou CPF) · **probabilidade × 100** quando acima do limiar superior (inicial 0,95) · **90** quando o humano confirmou · entre 0,60 e 0,95 sem revisão: não passa, vai ao humano · abaixo de 0,60: **veto** |

**Vetos, fora dos pesos** (são sim/não): A5 base legal · B4 validade · B7 custódia · C1 sinal de
execução · B6 abaixo do limiar inferior · B2 acima do prazo crítico.

**Dimensão com peso ≥ 10% que ficou `nao_medido`** (o cálculo não rodou) não vira zero nem média:
o dado é **Não julgável** e vai ao humano.

### 5A.2 — Pesos por agente (cada linha soma 100%)

| Agente / etapa | A1 Origem | A2 Histórico | A3 Estabil. | A4 Indep. | B1 Concord. | B2 Frescor | B3 Complet. | B5 Plausib. | B6 Identid. | Por que esse perfil |
|---|---|---|---|---|---|---|---|---|---|---|
| **Captador** (captação e identidade) | 10 | 5 | **20** | 5 | 5 | 15 | **20** | 5 | 15 | Na entrada importa a coleta ter rodado inteira e estável. Confiança fina é dos portões seguintes |
| **Conferidor** (cruzamento) | **25** | **20** | 0 | 15 | 10 | 15 | 5 | 5 | 5 | Para servir de **referência** contra o cliente, a fonte tem de ser de origem forte, com acerto comprovado e independente |
| **Mercado** | **25** | 10 | 10 | 5 | 15 | **20** | 10 | 5 | 0 | Séries oficiais: origem e frescor decidem; entidade não se aplica |
| **Caixa** | 15 | 10 | 5 | 5 | **25** | 15 | **20** | 5 | 0 | O extrato tem de fechar (saldo inicial + movimento = final) e cobrir todas as contas e meses |
| **Dívida** | **25** | 10 | 0 | 5 | 15 | **20** | 15 | 5 | 5 | Registrato e juros: origem oficial, data-base recente, todas as operações |
| **Risco** | 15 | 10 | 5 | 10 | 10 | 15 | 15 | 0 | **20** | Processos e protestos: o maior erro é o homônimo; depois, tribunal não coberto |
| **Estrategista** | 20 | 15 | 5 | 5 | 15 | **20** | 10 | 10 | 0 | Premissas de proposta aos credores: dado vencido ou implausível muda a proposta |
| **Entregas** (book e documento externo) | 20 | 15 | 0 | 10 | **20** | 15 | 10 | 5 | 5 | O que sai da Oria precisa ser confirmado e independente |

**Supervisor, Auditor e Autoaprimoramento não têm pesos**, porque não consomem dado externo
diretamente:
- **Supervisor:** só distribui a um especialista o dado APROVADO no portão daquele especialista. Só
  decide sozinho (B3b-1) quando todo dado do item tem score ≥ 90 no agente de origem.
- **Auditor:** confere 100% dos usos. Todo dado usado tem um registro em `portao_decisao` (regra 7) e
  o score recalculado bate com o gravado. Divergência é falha do portão, com gravidade crítica.
- **Autoaprimoramento:** lê as reprovações e os furos de portão para propor ajuste de peso ou piso.
  Quem decide é o Técnico.

### 5A.3 — Score mínimo, pisos e classe mínima

| Agente / etapa | Score mínimo | Pisos (nota mínima numa dimensão, valha o que valer a média) | Classe mínima |
|---|---|---|---|
| Captador | **70** | — (os vetos bastam na entrada) | Qualquer (guarda até o contestado, marcado) |
| Conferidor | **85** | A1 ≥ 70 · B2 ≥ 70 · **B6 = 100** (cruzamento só por chave exata) · B1 ≥ 50 | Provável |
| Mercado | **80** | A1 ≥ 70 · B2 ≥ 70 · B1 ≥ 50 | Provável |
| Caixa | **85** | **B1 ≥ 85** (o saldo fecha) · **B3 ≥ 95** | Provável |
| Dívida | **85** | A1 ≥ 85 · B2 ≥ 70 · B3 ≥ 95 · B1 ≥ 50 | Provável |
| Risco | **75** | **B6 ≥ 90** · B3 ≥ 80 · B1 ≥ 50 | Possível (o provedor **descobre**; a conclusão pede certidão) |
| Estrategista | **85** | B2 ≥ 70 · B1 ≥ 50 | Provável |
| Entregas, número no book | **85** | B1 ≥ 50 · B6 ≥ 95 | Provável. **Gravidade crítica** (> 5% do EBITDA ou da dívida): Confirmado, ou aceite do Sócio |
| Entregas, texto de contexto | **70** | B1 ≥ 50 | Possível |
| Monitoramento | O mínimo do agente que usou o dado | — | — | 

**Classe, por regra fixa:** **Contestado** se B1 ≤ 30 · **Confirmado** se B1 ≥ 85 · **Provável** se
B1 = 50 e A1 ≥ 85 · **Possível** se B1 = 50 e A1 < 85 · **Não julgável** se uma dimensão com peso
≥ 10% não foi medida.

### 5A.4 — A classificação do resultado (o que o portão devolve)

| Resultado | Critério objetivo | O que acontece |
|---|---|---|
| **APROVADO** | Nenhum veto **e** score ≥ mínimo **e** todos os pisos atendidos **e** classe ≥ classe mínima | Segue sozinho para a etapa seguinte |
| **EM REVISÃO** | Nenhum veto **e** score ≥ mínimo − 10 **e** no máximo 1 piso falho **e** não Contestado | **Não segue sozinho.** Segue só com aceite humano registrado (analista; Sócio na gravidade alta ou crítica) e leva ressalva com motivo e efeito |
| **REPROVADO** | Qualquer veto, **ou** score < mínimo − 10, **ou** 2 ou mais pisos falhos, **ou** Contestado (fora do Captador), **ou** Não julgável | Não segue. Param só as etapas que dependem do dado; vai ao humano com o prazo da gravidade |

O monitoramento reabre o portão quando o score de um dado em uso cai abaixo do mínimo do agente que o
usou (por exemplo, quando o dado vence).

### 5A.5 — O mesmo dado, julgado por agentes diferentes

O score **não é do dado sozinho**: é do dado **para um uso**. O Focus serve ao Mercado e não precisa
servir ao Caixa. Um processo achado pelo provedor serve ao Risco como pista e não entra no book.

### 5A.6 — Os 12 casos usados para conferir os números (piloto, sem histórico)

Calculados com as rubricas, os pesos e as regras acima. APRO = aprovado · REV = em revisão ·
REPR = reprovado.

| Caso | Captador | Conferidor | Mercado | Caixa | Dívida | Risco | Estrategista | Entregas |
|---|---|---|---|---|---|---|---|---|
| IPCA do IBGE, confirmado pelo BCB | 98,5 APRO | 94,0 APRO | 97,0 APRO | 97,0 APRO | 97,0 APRO | 97,0 APRO | 95,5 APRO | 95,5 APRO |
| Focus (BCB), sem segunda fonte | 96,0 APRO | 89,0 APRO | 89,5 APRO | 84,5 REV | 89,5 APRO | 92,0 APRO | 88,0 APRO | 85,5 APRO |
| Focus vencido (2× a cadência) | 91,5 APRO | 84,5 REV | 83,5 APRO | 80,0 REV | 83,5 REV | 87,5 APRO | 82,0 REV | 81,0 REV |
| Registrato com recibo conferido | 96,0 APRO | 89,0 APRO | 89,5 APRO | 84,5 REV | 89,5 APRO | 92,0 APRO | 88,0 APRO | 85,5 APRO |
| Open Finance, saldo fecha | 97,0 APRO | 90,2 APRO | 93,2 APRO | 94,8 APRO | 93,2 APRO | 94,8 APRO | 92,5 APRO | 92,5 APRO |
| Open Finance, faltando 1 de 10 contas | 95,0 APRO | 89,8 APRO | 92,2 APRO | 92,8 REV | 91,8 REV | 93,2 APRO | 91,5 APRO | 91,5 APRO |
| Processo por CNPJ, via API de parceiro | 86,0 APRO | 64,5 REPR | 74,5 REV | 71,5 REPR | 74,0 REPR | 76,0 APRO | 73,0 REPR | 67,0 REPR |
| Processo por nome, probabilidade 0,97 | 85,5 APRO | 64,3 REPR | 74,5 REV | 71,5 REPR | 73,8 REPR | 75,4 APRO | 73,0 REPR | 66,8 REPR |
| Processo na certidão do tribunal | 97,8 APRO | 92,5 APRO | 94,8 APRO | 93,2 APRO | 94,8 APRO | 95,5 APRO | 93,2 APRO | 92,5 APRO |
| Score de bureau | 86,0 APRO | 60,0 REPR | 70,5 REV | 70,5 REPR | 70,5 REPR | 74,5 REV | 70,0 REPR | 64,0 REPR |
| Notícia por nome, probabilidade 0,90 | 66,5 REV | 55,0 REPR | 60,5 REPR | 57,0 REPR | 60,5 REPR | 63,5 REPR | 59,5 REPR | 56,5 REPR |
| IPCA com IBGE e BCB divergentes | 93,5 APRO | 84,0 REPR | 82,0 REPR | 72,0 REPR | 82,0 REPR | 87,0 REPR | 80,5 REPR | 75,5 REPR |

**O que os casos mostram:**
1. Dado oficial confirmado passa em todos os agentes.
2. Dado contestado é guardado na captação e barrado em todo o resto.
3. Provedor de processos e bureau servem de pista ao Risco, mas não entram no book sem certidão
   (a regra da Espec. 13, agora como número).
4. Notícia nunca passa sozinha.
5. Dado vencido cai para revisão onde o frescor pesa, antes de virar reprovação.

### 5A.7 — Limites desta proposta

- **Os pesos são julgamento.** Não existe medida de "quanto a origem vale contra o frescor". O que
  a calibração pode medir é se o **resultado** (APROVADO, EM REVISÃO, REPROVADO) prevê o erro.
  Se não prever, os pesos mudam, por decisão registrada.
- **A prior de A2 (70 ou 40) decide muito no piloto**, porque nenhuma fonte terá 30 conferências tão
  cedo. Sem ela, nenhum dado de parceiro passaria no Conferidor; com ela, a origem oficial passa
  pela origem, não pelo acerto. A cada 30 conferências, a prior sai de cena.
- **Mínimo − 10 para EM REVISÃO** é uma faixa arbitrária. O tamanho dela deve sair da medição:
  quantos casos da faixa o humano aprovou, e quantos deles estavam errados.
- **A tolerância de B1 e os limiares de B6** (0,95 e 0,60) são os valores mais sensíveis. Eles
  são os primeiros a calibrar.

---

## §6 — O perfil por tipo de dado

O primeiro rascunho da matriz. Cada linha vira uma regra de portão depois da calibração.

| Tipo de dado | Origem típica | Referência para concordância (B1) | Dimensões críticas | Limitação principal |
|---|---|---|---|---|
| **Séries macro** (IPCA, IGP-M, Selic, CDI) | BCB SGS; IBGE SIDRA | IBGE × BCB (já em `fn_divergencias_indice_macro`) | A1, B2 | Revisão de série e código de série trocado por terceiro (SGS 7447 rotulada errado; Espec. 13, §8a) |
| **Focus e juros por modalidade** | BCB | Sem segunda fonte independente | B2, A3 | Concordância quase sempre "não julgável"; vive de origem e frescor |
| **Demonstrações de pares** | CVM (DFP/ITR) | Identidade contábil interna (ativo = passivo + PL) | B4, B1 aritmética | Comparabilidade entre empresas não é qualidade do dado; fica na Espec. 14 |
| **Emprego** | CAGED/RAIS | eSocial do cliente (quando houver) | B2, B3 | Defasagem longa e revisões |
| **Cadastro do CNPJ e QSA** | Dados abertos da Receita | Documento societário do cliente | B2, A3 | Endereço mudou sem aviso; base mensal |
| **Processos** | Tribunais, APIs processuais, Exato | **Certidão** (a prova); outro provedor | B6, A4, B3 | Homônimos; dois provedores podem ler o mesmo tribunal (não são duas confirmações); cobertura por tribunal desigual |
| **Protestos** | Bureau | Certidão de protesto | B6, B2, A1 | Fonte trocou de canal sem aviso (gov.br) |
| **Score e restritivos de bureau** | Serasa, Boa Vista, Quod | Outro bureau (independência parcial) | A1, A4 | Modelo do bureau é caixa-preta: concordância mede o bureau, não o devedor |
| **Indicadores Núclea** | Núclea | Extrato/OFX (só plausibilidade, R3) | B5 | **Agregado**: não concilia item a item; nunca muda número do book |
| **Extrato por Open Finance** | Integradora regulada | OFX/CNAB do cliente; saldo inicial + movimento = saldo final | B1 aritmética, B3, C1 | Consentimento expira em silêncio (R2); categoria do agregador é sugestão (R4) |
| **Registrato/SCR** (E2) | BCB, via cliente | Dívida do balanço; contratos | B7, B2 | Chega pelo cliente: custódia pesa; data-base mensal |
| **SPED** (E2) | Fisco, via cliente | Balanço e DRE extraídos | B7 (recibo), B1 | Versão retificada; SCP e livro auxiliar (ficha F2T) |
| **Notícias** | Busca e fornecedores | Nenhuma estruturada | B6, A1 | Quase sempre "Possível": serve de pista, não de número |

---

## §7 — O modelo de dados (conceitual; não é migration)

Seis peças. As três primeiras **já estão desenhadas** na Espec. 13 e no plano; as três últimas são o
que este score acrescenta.

| Peça | O que guarda | De onde vem |
|---|---|---|
| `fonte_externa` (catálogo) | Origem (A1), cadência esperada, prazo de validade, `origem_compartilhada_com` (A4), base legal típica, fornecedor | **Nova**, mas pequena. O `fornecedor` da `consulta_externa` aponta para ela |
| `consulta_externa` | Execução: quatro estados, custo, autorização, hash do bruto | Espec. 13, §3 |
| `autorizacao` | Escopo, pessoas, validade, revogação | Espec. 13, §3 |
| `avaliacao_dado` | Uma linha por (observação, dimensão, versão do método): estado, valor, motivo, referência usada | **Nova.** Só acréscimo: avaliação nova não apaga a anterior (versões preservadas, v0.1.2 §8) |
| `portao_regra` | (tipo de dado, etapa, dimensão) → piso e desfecho; decisão que o fixou; vigência | **Nova.** É o "estágio" do dial com limiar por dimensão |
| `portao_decisao` | Cada passagem pelo portão: dado, regra (com versão), desfecho, furo humano com justificativa | **Nova.** Prova que o portão rodou (regra 7) e alimenta a revisão semanal (E4) |

O formato segue o vocabulário de qualidade de dados do W3C (DQV: dimensão → métrica → medição) e a
proveniência do W3C PROV, sem adotar RDF: só a forma, para não inventarmos nomes.

**O que o score consome e não refaz:** proveniência por dado (1.B6), autorização (1.B7), cruzamento
(1.B5), painel de frescor (1.C4), estados "falhou" das fontes de mercado (1.C1–1.C3).

---

## §8 — Os limites a definir (e quem define)

| Limite | O que é | Como se define | Quem decide |
|---|---|---|---|
| Tolerância de concordância (B1) por tipo | Diferença que ainda é "bate" | Arredondamento de publicação (já é 0,011 p.p. nas séries macro) + régua B3b-1 para valores | Dono, com a medição |
| Limiares de identidade (B6) | Superior (aceita) e inferior (recusa) | Pela taxa de falso positivo e falso negativo aceitável, medida numa amostra rotulada (Fellegi–Sunter) | Dono |
| Prazo de validade (B2) por fonte | Até quando o dado vale; e o prazo crítico (veto) | Cadência publicada da fonte; R7 da Espec. 13 | Catálogo; dono aprova |
| Piso por (tipo × etapa × dimensão) | O mínimo para seguir | Pelo custo dos dois erros (§9, passo 4) | Dono, por decisão registrada |
| Histórico mínimo (A2) | Quantas conferências antes de a fonte sair de "sem histórico" | Limite inferior de Wilson/Jeffreys; a mesma lógica dos 300 da D6 | Dono |
| Quem fura o portão | Analista, Sócio | Pela gravidade (G5) | Dono (D15.3) |

---

## §9 — Como sair do papel sem inventar número

1. **Catálogo e vetos primeiro.** São determinísticos e não precisam de calibração: autorização,
   sinal de execução, custódia, validade. Cada veto nasce com o seu invariante **medido não-vazio**
   (regra 2): plantar a falha, ver o portão reprovar, contar os asserts.
2. **Modo sombra (N0).** Calcular todas as dimensões e a classe, gravar em `avaliacao_dado`, mostrar
   no painel — **sem barrar nada**. Durante o piloto inteiro.
3. **Gabarito do dado externo.** Uma amostra de observações rotuladas por humano (certa, errada, não
   é desta empresa), reusando o gabarito que já existe (`0126`). Parte cega, como na D6.
4. **Medir se a classe prevê o erro.** Para cada classe, a taxa de erro observada com o seu limite
   superior. Se "Confirmado" erra tanto quanto "Provável", a classe não separa nada e o desenho volta
   à mesa.
5. **Fixar pisos pelo custo dos dois erros.** Barrar um dado bom custa atraso e dinheiro (reconsulta
   paga, N-C6b). Deixar passar um dado ruim custa um diagnóstico errado. O piso é onde o dono aceita
   a troca — e fica escrito como decisão.
6. **Ligar em degraus, por portão:** alerta → ressalva → bloqueio. Com **rebaixamento automático**
   quando a taxa de erro medida piorar (D6).
7. **Revisar a cada semestre**, junto com o gabarito (D4). Fonte que mudou de metodologia ou de
   endereço **zera** o histórico (A2) a partir da quebra.

---

## §10 — Limitações (o que este score não resolve)

1. **Concordância não é verdade.** Duas fontes que leem a mesma origem concordam no erro. Os
   fornecedores raramente declaram de onde tiram o dado, então a independência (A4) muitas vezes é
   **desconhecida**, e deve aparecer assim.
2. **Divergir do cliente é o produto, não o defeito.** Se a divergência com o documento do cliente
   baixasse o score do externo, o sistema aprenderia a esconder o achado. Por isso ela não baixa
   (§3, B1). O custo: um externo errado que diverge do cliente só é pego pela concordância com
   **outra** fonte externa ou pelo humano.
3. **Muitos dados não têm referência.** Focus, notícias, score de bureau: a concordância fica "não
   julgável" e o dado vive só de origem e frescor. É um teto real, não um defeito a corrigir.
4. **Pouco volume, histórico fraco.** Com poucos mandatos, o limite inferior do acerto (A2) fica
   baixo por muito tempo. As fontes vão ficar "sem histórico" durante o piloto. Isso é honesto, mas
   significa que, no começo, o portão vai depender mais da origem (A1) do que do acerto medido.
5. **Calibrar exige rotular, e hoje quem rotula é uma pessoa só** (K3). O gabarito do dado externo
   compete com o gabarito da extração pelo mesmo tempo.
6. **As fontes mudam sem avisar** — endereço, leiaute, metodologia, revisão de série. O histórico de
   acerto de antes da mudança pode não valer depois. Sem detectar a quebra, o score fica alto sobre
   uma fonte que já piorou.
7. **Dado agregado não concilia.** Núclea e parte do bureau dão faixas e percentis: só servem de
   plausibilidade (R3). O score deles nunca libera um número do book.
8. **O modelo do fornecedor é caixa-preta.** Um score de bureau "bate" com outro bureau porque os dois
   modelam parecido, não porque o devedor é bom. Concordância entre modelos mede os modelos.
9. **Frescor custa dinheiro.** Em fonte paga, manter o dado fresco é reconsultar, contra o teto por
   mandato (N-C6b). O piso de frescor e o teto de custo precisam ser decididos juntos.
10. **Pesos não têm verdade de referência.** Não há como medir "quanto vale a origem contra o
    frescor". Os pesos do §5A são escolhidos à mão; os vetos e os pisos limitam o estrago de um peso
    errado, e a calibração mede o resultado, não o peso.
11. **Goodhart.** Um portão que reprova muito será afrouxado ou contornado. O registro de todo furo
    (§5) e a revisão semanal (E4) mitigam, não eliminam.
12. **Não é certificação.** O score é controle interno. Mostrá-lo ao cliente ou ao credor como "nota
    de qualidade" cria uma promessa que pede parecer jurídico (D15.5).
13. **LGPD.** Para dado de pessoa física, a qualidade (exatidão, clareza, relevância e atualização) é
    um princípio da lei (art. 6º, V). O score ajuda a mostrar que cuidamos dela, mas não substitui a
    base legal (A5 é veto, não peso).
14. **Não protege contra fraude no documento do cliente.** Ele mede o dado de fora. A fraude do
    cliente aparece como divergência (o achado), não como score baixo.

---

## §11 — Decisões do dono (abertas)

| Código | Pergunta | Recomendação |
|---|---|---|
| **D15.1** | O documento oficial trazido pelo cliente (SPED, Registrato, certidões, canal E2) entra no score? | **Sim**, com custódia (B7) como veto: sem recibo ou hash, não conta como externo |
| **D15.2** | O rótulo é classe (Confirmado… Não julgável) ou número de 0 a 100? | **Classe**, ao lado da origem da fonte. O número só no painel interno |
| **D15.3** | Quem pode furar o portão? | Analista para gravidade baixa e média; **Sócio** para alta e crítica (como a E3-1). Sempre com justificativa |
| **D15.4** | Algum portão bloqueia antes do modo sombra acabar? | **Só os vetos** (§4, passo 1). Pisos esperam a calibração |
| **D15.5** | O score aparece para o cliente ou o credor? | **Não o número.** A ressalva com motivo e efeito, sim (regra 1). Mostrar a classe depende de parecer |
| **D15.6** | Quem rotula a amostra de calibração? | O mesmo papel do gabarito (D4, ainda a indicar) |
| **D15.7** | Divergência com o documento do cliente baixa o score do externo? | **Não** (§3, B1; §10, item 2) |
| **D15.8** | Aprovar os pesos, mínimos, pisos e prioris iniciais do §5A como ponto de partida do modo sombra? | **Sim, como hipótese.** Eles rodam em sombra; só bloqueiam depois da etapa 4 (§12), e cada ajuste vira decisão registrada |

---

## §12 — O plano, em etapas (sem calendário, K2)

| Etapa | O que | Depende de | Pronto quando |
|---|---|---|---|
| **0** | Decisões D15.1–D15.8 | — | Registradas numa nova versão do registro de decisões |
| **1** | Catálogo `fonte_externa` com origem, cadência, validade e origem compartilhada | Espec. 13 etapa da `consulta_externa`; 1.C1–1.C3 | Toda fonte captada no catálogo; fonte sem origem declarada aparece como "sem origem" |
| **2** | Vetos no banco | 1.B7, 1.B6 | Cada veto com invariante medido não-vazio (regra 2) |
| **3** | Dimensões e classe em modo sombra (N0) + painel | 1.B5, 1.C4 | Toda observação externa tem avaliação por dimensão, com estado; nenhuma em branco sem motivo |
| **4** | Gabarito do dado externo e medição por classe | 1.J2, D15.6 | Taxa de erro por classe medida, com intervalo |
| **5** | Pisos fixados e portões ligados em degraus | Etapa 4; decisão do dono | Cada portão ligado tem a decisão que o fixou; teste que reprova sem o portão |
| **6** | Rebaixamento automático e revisão semanal dos furos | 2.10 (E4) | Piora medida rebaixa o portão (teste) |

No plano de execução, isto são os itens **2.18** (etapas 0–3) e **2.19** (etapas 4–6).

---

## §13 — Fontes consultadas em 23/11/2026

Pesquisa pública. Onde só um resumo secundário foi lido, está dito.

**Qualidade de dados — modelos e dimensões**
- ISO/IEC 25012:2008, modelo de qualidade de dados (15 características, visões inerente e dependente
  do sistema): [ISO](https://www.iso.org/standard/35736.html) · [resumo arc42](https://quality.arc42.org/standards/iso-iec-25012)
- Wang & Strong (1996), *Beyond Accuracy: What Data Quality Means to Data Consumers* — qualidade
  intrínseca, contextual, de representação e de acesso: [MIT TDQM](https://web.mit.edu/tdqm/www/tdqmpub/beyondaccuracy_files/beyondaccuracy.html)
- Pesquisa sobre dimensões na prática (2025): [arXiv 2507.17507](https://arxiv.org/pdf/2507.17507)
- W3C Data Quality Vocabulary (dimensão, métrica, medição): [W3C DQV](https://www.w3.org/TR/vocab-dqv/)
- Observabilidade de dados (frescor, volume, esquema, distribuição, linhagem): [Databricks](https://www.databricks.com/glossary/data-observability) · [TechTarget](https://www.techtarget.com/searchdatamanagement/tip/Pillars-of-data-observability-bolster-data-pipeline)
- Portão de validação com tolerância (`mostly`) e suítes de aviso × falha: [Great Expectations](https://legacy.017.docs.greatexpectations.io/docs/reference/expectations/standard_arguments) · [fórum GX](https://discourse.greatexpectations.io/t/can-i-use-an-evaluation-parameter-to-pass-in-a-dynamically-calculated-argument-to-the-mostly-parameter-in-expectations/722)

**Confiabilidade de fonte e fusão de fontes em conflito**
- Código do Almirantado / NATO (fonte A–F × informação 1–6, eixos independentes; resumo secundário,
  o texto da AJP-2.1 não é público): [Wikipedia](https://en.wikipedia.org/wiki/Admiralty_code) · [Pangea Research](https://pangearesearch.substack.com/p/the-admiralty-code-nato-6x6-system)
- Dong et al. (2015), *Knowledge-Based Trust* (confiança da fonte = probabilidade de o valor estar
  certo; erros de extração separados dos erros da fonte): [arXiv 1502.03519](https://arxiv.org/abs/1502.03519)
- Dong, Berti-Equille & Srivastava (2009), *Integrating Conflicting Data: The Role of Source
  Dependence* (detectar cópia entre fontes): [PDF](https://lunadong.com/publication/dependence_vldb.pdf)
- Data fusion, visão geral: [Google Research](https://research.google/pubs/data-fusion-resolving-conflicts-from-multiple-sources/)
- Dempster–Shafer e desconto por confiabilidade (e a crítica ao desconto fixo arbitrário): [PMC 7515099](https://www.ncbi.nlm.nih.gov/pmc/articles/PMC7515099/) · [Smarandache/Dezert](https://www.gallup.unm.edu/~smarandache/DSmT/ABeliefCombinationRule.pdf)
- Ligação de registros de Fellegi–Sunter (pesos m/u, dois limiares, revisão manual): [arXiv 2008.04443](https://arxiv.org/pdf/2008.04443) · [Winkler, FCSM 2013](https://apps.bea.gov/icsp/fcsm/assets/docs/J1_Winkler_2013FCSM.pdf)

**Auditoria e regulação financeira**
- ISA 500, evidência de auditoria (fonte externa independente; definição de fonte externa): [IAASA, ISA 500](https://iaasa.ie/wp-content/uploads/2023/10/ISA_500_UpdatedOct2023.pdf) · [ACCA](https://www.accaglobal.com/an/en/technical-activities/uk-tech/in-practice-ezine-archive/in-practice-archive-2024/April/Audit-evidence-when-is-enough-enough.html)
- ISA 505, confirmações externas (resposta indireta é duvidosa; A11, A12): [ICAEW](https://www.icaew.com/technical/audit-and-assurance/faculty-resources/implementing--isas-international/external-confirmations-in-an-isa-audit)
- ISA 520, procedimentos analíticos (expectativa e diferença aceitável; material didático, não o
  texto da norma): [Masaryk](https://is.muni.cz/el/econ/podzim2019/MPF_AAUD/um/60366333/By_phase_-_Testing.pdf?lang=cs)
- IFRS 13, hierarquia de valor justo (classificação pelo nível da entrada significativa mais fraca): [IAS Plus](https://www.iasplus.com/standard/ifrs13.htm) · [IFRS Community](https://ifrscommunity.com/knowledge-base/fair-value-hierarchy/)
- BCBS 239, princípios de agregação de dados de risco (exatidão, completude, tempestividade): [Wikipedia](https://en.wikipedia.org/wiki/BCBS_239) · [Risk.net](https://www.risk.net/bcbs-239/5475736/managing-data-quality-completeness-accuracy-and-timeliness)
- Resolução Conjunta BCB/CMN nº 18/2025, governança e qualidade dos dados das instituições
  financeiras (resumo secundário; o texto da norma não foi lido): [EY](https://www.ey.com/pt_br/newsroom/2026/08/nova-resolucao-bc-adocao-ia-exigem-gestao-eficiente-dados-instituicoes-financeiras)
- LGPD (Lei 13.709/2018), art. 6º, V — qualidade dos dados: [Planalto](https://www.planalto.gov.br/ccivil_03/_ato2015-2018/2018/lei/l13709.htm)

**Agregação, estatística e o risco da métrica**
- OCDE/JRC, *Handbook on Constructing Composite Indicators* (agregação compensatória × não
  compensatória): [OCDE](https://www.oecd.org/en/publications/handbook-on-constructing-composite-indicators-methodology-and-user-guide_9789264043466-en.html) · [PDF JRC](https://knowledge4policy.ec.europa.eu/sites/default/files/jrc47008_handbook_final.pdf)
- Intervalos para proporção com amostra pequena (Wilson, Jeffreys): [Brown, Cai & DasGupta 2001](https://projecteuclid.org/download/pdf_1/euclid.ss/1009213286) · [Agresti & Coull 1998](https://math.unm.edu/~james/Agresti1998.pdf)
- Lei de Goodhart e o desenho de métricas: [Manheim, MPRA 98288](https://mpra.ub.uni-muenchen.de/98288/1/MPRA_paper_98288.pdf)
