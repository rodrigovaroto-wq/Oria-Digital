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
- **Pesos e mínimos por agente (§5A, v2):** mediana de três avaliações independentes, com 7 regras
  aprovadas pelo dono e 13 casos recalculáveis por script. Roda em modo sombra até a calibração.
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
| B6 | **Identidade** | O dado é mesmo desta empresa (ou pessoa)? | **Veto em três níveis, sem peso:** chave exata (CNPJ/CPF) passa; por nome (processos, notícias) **nunca passa sozinho** — vai ao humano; chave divergente reprova. A probabilidade de correspondência só decide qual candidato por nome nem chega ao humano | Fellegi–Sunter (ligação de registros, faixa de revisão manual) |
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

A ordem é fixa. Cada camada só é lida se a anterior passou. As regras completas, com os números,
estão no §5A.

1. **Vetos** (sim ou não, fora da média). Qualquer um → **REPROVADO**:
   - **A5 base legal, por destino:** o mesmo dado pode servir ao uso interno e não poder ir a um
     terceiro (cliente, credor). Proibição contratual expressa reprova; autorização de envio ainda
     não registrada leva a REVISÃO.
   - **C1 execução:** sem prova de que a consulta rodou, não há dado — há "não consultado".
   - **B4 validade:** por registro. O registro inválido sai, e a perda aparece na completude (B3).
   - **B6 identidade, em três níveis:** chave exata (CNPJ/CPF) passa; correspondência por nome
     **nunca passa sozinha** (REVISÃO); chave divergente reprova.
   - **A1 "sem origem declarada".**
   - **B7 em documento oficial trazido pelo cliente** (SPED, Registrato, certidão) sem recibo ou
     autenticidade conferidos: deixa de contar como dado externo (pode ser adulteração).
   - **B2 acima do prazo crítico** da fonte, medido contra a **data de referência do uso**.
   - **"Nada consta"** sem execução provada (C1) e sem cobertura declarada (B3): não vale como
     resposta negativa.
2. **Travas** (levam a REVISÃO em todo agente; no Captador, à quarentena):
   - conflito entre fontes externas independentes, ou identidade aritmética que não fecha (B1 = 0);
   - identidade por nome (B6);
   - dado **opinativo** (score de bureau, rating, notícia) fora do Risco: o score mede se a
     transmissão é confiável, não se a opinião é verdadeira;
   - frescor abaixo de 60 (fora do Captador).
3. **Cobertura**: a parte do peso que de fato foi medida. Abaixo do mínimo do agente → REVISÃO.
4. **Pisos por dimensão** do agente.
5. **Score ponderado** com os pesos do agente que vai usar o dado, comparado com o mínimo dele.

**A classe é rótulo, não portão** (com uma exceção, nas Entregas: §5A.4):

| Classe | Quer dizer | Exemplo |
|---|---|---|
| **Confirmado** | Confirmado por fonte independente, ou a identidade aritmética fecha | Extrato cujo saldo fecha |
| **Provável** | Origem oficial sem segunda fonte possível, ou confirmado só por espelho da mesma origem | Focus; IPCA do IBGE com o espelho do BCB |
| **Possível** | Parceiro ou agregador sem confirmação | Processo achado pela API do provedor |
| **Opinião** | Saída de modelo de terceiro | Score de bureau |
| **Contestado** | Fontes externas independentes discordam | IPCA do IBGE ≠ BCB |
| **Não julgável** | Cobertura abaixo do mínimo | Fonte nova sem nenhuma referência |

"Não julgável" é falta de conhecimento nosso, não defeito do dado — o código do Almirantado faz a
mesma distinção no grau 6. Ele **aparece**, com o motivo.

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
qual evidência. **Qualquer analista libera, em qualquer gravidade** (D15.3, decisão do dono em
24/11/2026): liberar o **dado** não é aprovar o **diagnóstico**, que continua pela E3 e pela E3-1. Todo
furo entra na revisão semanal (E4, D15.13) — é o antídoto contra Goodhart.

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

## §5A — Pesos, notas de corte e classificação por agente (v2, 23/11/2026)

Pedido do dono: um peso percentual para cada nota e um score mínimo, por agente de IA e por etapa,
para que **só o dado de alta confiabilidade passe sozinho** para a etapa seguinte.

**Como esta versão nasceu.** A v1 (a minha proposta) foi comparada com **três avaliações
independentes** que não viram os números dela. Os três concordaram muito entre si: o mesmo peso
variou no máximo 5 pontos, e 10 no Captador. Comigo concordaram menos: de 10 a 32 pontos de peso
deslocados por agente. Nos 8 casos comuns, a v1 concordou com a maioria em 53 de 64 julgamentos.
Das 11 divergências, em 6 a v1 deixava passar o que a maioria segurava. A v2 adota:
1. a **estrutura** dos três;
2. os **pesos na mediana** dos três;
3. as **7 regras** que eles trouxeram, aprovadas pelo dono em 23/11/2026.

O que mudou, item a item, está no §5A.8.

**Status: hipótese inicial, não medida** (D15.8). **No piloto, os vetos e os pisos já bloqueiam**
(D15.4, decisão do dono em 24/11/2026): veto reprova, piso falho manda para REVISÃO. As travas do §4
(conflito, identidade por nome, opinião fora do Risco, frescor < 60) contam como pisos globais e
bloqueiam junto. **O score ponderado e a cobertura rodam em modo sombra** (calculam, gravam e
mostram, sem barrar) até a calibração (etapa 4 do §12; item 3.8 do plano).

### 5A.1 — Como cada nota é dada (rubrica objetiva, 0 a 100)

Cada nota tem três estados possíveis, e nenhum vira zero nem média:
- **medida**, com o valor;
- **não se aplica** (`na`): sai da conta e da cobertura;
- **não medida** (`nm`): podia ter sido medida e não foi; sai da conta, mas **reduz a cobertura**.

| Cód. | Dimensão | Degraus da nota |
|---|---|---|
| A1 | Origem | **100** produtor primário, ou documento oficial com autenticidade conferida · **90** espelho oficial · **85** canal regulado (Open Finance por integradora autorizada) · **70** parceiro que declara a origem · **45** agregador ou provedor sem origem declarada · **25** raspagem · **sem origem: veto** |
| A2 | Histórico de acerto | **Fonte em estreia** (< 10 conferências): `na`, com **teto no score** (5A.3). Depois, limite inferior de Wilson (95%) de acertos ÷ conferências × 100. **Só conta a conferência feita contra uma referência de origem independente conhecida**; senão, o histórico fica circular |
| A3 | Estabilidade | % de coletas com sucesso nas últimas 30, menos 20 por mudança de endereço ou de esquema não anunciada nos últimos 12 meses. Sem coleta anterior: `nm` |
| B1 | Concordância | **100** confirmado por fonte externa independente · **90** a identidade aritmética fecha (saldo inicial + movimento = final) · **70** confirmado só por espelho da mesma origem · **0** conflito acima da tolerância (**trava**) · `na` quando não existe segunda fonte possível · `nm` quando podia ter sido cruzado e não foi, ou quando a origem da outra fonte é desconhecida (a confirmação não conta). **A comparação com o documento do cliente não entra** (D15.7) |
| B2 | Frescor | Medido contra a **data de referência do uso**, não contra hoje. **100** até 1× a periodicidade da fonte · **50** com 2× · **0** com 3× (linear entre os pontos) · acima do prazo crítico: **veto** |
| B3 | Completude | Obtidos ÷ esperados × 100 (meses, contas, CNPJs do perímetro, tribunais). Cobertura de tribunais não declarada: `nm` |
| B5 | Plausibilidade | **100** dentro de 3 desvios-padrão da própria série · **50** entre 3 e 5 · **0** acima de 5 · menos de 12 pontos: `nm` · dado sem série numérica (processo): `na` |
| B7 | Custódia | **100** assinatura ou recibo conferido · **80** API oficial com hash gravado na captura · **75** canal regulado com hash na captura · **50** parceiro de origem declarada com hash na captura · **30** provedor sem origem declarada (o nosso hash só prova que nada mudou depois de chegar) · **20** nenhuma prova |

**A4 (independência) e B6 (identidade) não têm peso.** A4 decide quanto uma confirmação vale em B1;
dar peso a ela também contaria a mesma coisa duas vezes. B6 é veto em três níveis (§4).

### 5A.2 — Pesos por agente (% ; cada linha soma 100)

Mediana das três avaliações. No Mercado a mediana somava 95, e os 5 pontos foram para o Frescor:
é onde a v1 errava, deixando passar Focus vencida.

| Agente / etapa | A1 Origem | A2 Histórico | A3 Estabil. | B1 Concord. | B2 Frescor | B3 Complet. | B5 Plausib. | B7 Custódia | Por que esse perfil |
|---|---|---|---|---|---|---|---|---|---|
| **Captador** | **20** | 10 | 15 | 5 | 10 | **20** | 10 | 10 | Na entrada importa saber de onde veio e se veio tudo; instabilidade aparece aqui primeiro. Julgar o valor é de quem vem depois |
| **Conferidor** | **25** | 15 | 5 | **20** | 10 | 10 | 5 | 10 | O dado externo é a **régua**: régua torta gera achado falso contra o cliente. Plausibilidade baixa de propósito (o implausível pode ser o achado) |
| **Mercado** | **25** | 10 | 5 | 15 | **25** | 10 | 10 | 0 | Série oficial, mas que envelhece em semanas. Custódia 0: série pública se busca de novo |
| **Caixa** | 15 | 5 | 5 | **25** | 20 | **20** | 5 | 5 | O saldo que fecha é a prova mais forte de extrato; conta ou dia faltando muda o caixa |
| **Dívida** | 20 | 5 | 0 | 15 | 10 | **25** | 5 | **20** | Credor omitido é o erro mais caro do mapa da dívida; Registrato chega pelo cliente, então o recibo pesa |
| **Risco** | **20** | 15 | 5 | 15 | 15 | **20** | 5 | 5 | O perigo é o falso "nada consta" (tribunal não coberto) e o provedor sem origem declarada |
| **Estrategista** | 20 | 15 | 0 | **25** | 15 | 15 | 10 | 0 | Proposta a credor sobre número não corroborado é o erro de maior consequência; recebe dado já filtrado |
| **Entregas** | 20 | 10 | 0 | 15 | 15 | 10 | 5 | **25** | O que sai da Oria precisa provar origem e integridade diante de terceiros |

**Supervisor, Auditor e Autoaprimoramento não têm pesos (4 de 4 avaliações):**
- **Supervisor:** só roteia e aplica o portão do agente de destino. Um segundo portão poderia
  divergir do primeiro.
- **Auditor:** vê tudo, inclusive os reprovados, com a decomposição por dimensão. Ele confere:
  - que todo dado usado tem registro em `portao_decisao` (regra 7);
  - que o score recalculado bate com o gravado (se não bater, é falha crítica);
  - uma **amostra de 5% dos aprovados, mais todos os que passaram com até 5 pontos de folga**.
  Essa amostra é o que alimenta o histórico de acerto (A2).
- **Autoaprimoramento:** propõe pesos novos a partir das reprovações, com teste retroativo. Quem
  aplica é sempre um humano.

### 5A.3 — Score mínimo, cobertura mínima, pisos e teto da fonte em estreia

**Score** = Σ(peso × nota) ÷ Σ(pesos das notas medidas). **Cobertura** = pesos medidos ÷ pesos
aplicáveis. As duas aparecem sempre juntas.

| Agente / etapa | Score mínimo | Cobertura mínima | Pisos (nota mínima, valha o que valer a média) |
|---|---|---|---|
| Captador | **60** | 60% | — (vetos e travas bastam na entrada) |
| Conferidor | **80** | 75% | A1 ≥ 65 (agregador nunca é régua) · B2 ≥ 50 · B7 ≥ 60 |
| Mercado | **75** | 75% | A1 ≥ 70 · B2 ≥ 70 |
| Caixa | **75** | 75% | Em extrato: B1 ≥ 90 (o saldo fecha) e B3 ≥ 80 |
| Dívida | **80** | 80% | A1 ≥ 60 · B3 ≥ 80 · B7 ≥ 80 em documento trazido pelo cliente |
| Risco | **70** | 75% | A1 ≥ 45 · para afirmar "nada consta": C1 provado e B3 ≥ 80 |
| Estrategista | **85** | 80% | B2 ≥ 60 |
| Entregas | **85** | 85% | A1 ≥ 70 · B7 ≥ 70. Gravidade crítica (> 5% do EBITDA ou da dívida): classe Confirmado, ou aceite do Sócio |

**Teto da fonte em estreia** (menos de 30 conferências): score máximo de **90** se A1 ≥ 85, ou
**80** nos demais casos. Ele evita que tirar o histórico da conta infle a fonte nova, risco que as
três avaliações apontaram. O teto sai quando a fonte tem 30 conferências.

### 5A.4 — A classificação do resultado

| Resultado | Critério objetivo | O que acontece |
|---|---|---|
| **APROVADO** | Nenhum veto, nenhuma trava, cobertura ≥ mínimo, todos os pisos, score ≥ mínimo | Segue sozinho |
| **REVISÃO** | Nenhum veto e score ≥ 50, mas alguma trava, cobertura, piso ou score abaixo do exigido | **Não segue sozinho.** Fila humana com o motivo e o efeito. Só segue liberado por humano — qualquer analista, com justificativa (D15.3) —, com ressalva no book |
| **REPROVADO** | Qualquer veto; score < 50; nas Entregas, custódia < 50; "nada consta" sem cobertura | Não segue. Nova captura na fonte primária, ou a ausência registrada com motivo — nunca zero |
| **QUARENTENA** (só no Captador) | O que seria REVISÃO na entrada | Gravado com score e motivo, sem sair para ninguém. Conflito entre fontes: **guarda as duas versões** |

### 5A.5 — As 7 regras aprovadas pelo dono (23/11/2026; D15.9–D15.15)

| # | Regra | Efeito objetivo |
|---|---|---|
| 1 | **Base legal por destino** | O mesmo dado serve ao uso interno e pode travar na saída. Sigilo bancário (Open Finance, SCR) e licença de bureau exigem autorização registrada para enviar a terceiros. Sem ela: REVISÃO; com proibição expressa: REPROVADO |
| 2 | **"Nada consta" só vale com execução provada e cobertura medida** | Resposta negativa sem C1 e sem B3 declarado é REPROVADO em todo agente: vira "não consultado" ou "cobertura insuficiente", com o efeito |
| 3 | **Propagação pelo menor score** | Número calculado herda o **menor** score e o **pior** resultado dos insumos. Um dado em REVISÃO numa soma deixa a soma em REVISÃO |
| 4 | **Frescor contra a data de referência do uso** | Uma Focus de março é a versão certa para uma análise datada de março. Frescor mede a distância até a data que o uso pede |
| 5 | **Alerta de carimbo** | Se, num portão, o humano libera sem alterar mais de 95% dos casos de REVISÃO, o alerta é de **calibração do portão**, não do humano |
| 6 | **Amostra do Auditor** | 5% dos aprovados, mais todos os aprovados com até 5 pontos de folga; o resultado alimenta A2 |
| 7 | **Teto e promoção da fonte em estreia** | Teto de 90 ou 80 até 30 conferências (5A.3); A2 entra na conta a partir de 10 conferências |

### 5A.6 — O mesmo dado, julgado por agentes diferentes

O score **não é do dado sozinho**: é do dado **para um uso**. O Registrato passa na Dívida e trava
nas Entregas enquanto não houver autorização para mostrá-lo ao credor. O score de bureau passa no
Risco, rotulado "opinião do bureau X", e em nenhum outro agente.

### 5A.7 — Os 13 casos (piloto, fontes em estreia)

Gerados por [`15_anexos/casos_do_score.py`](15_anexos/casos_do_score.py), que é a fonte desta
tabela. A proposta em página (com impressão em PDF) está em
[`15_anexos/Portoes_de_Confiabilidade_Oria_v2.html`](15_anexos/Portoes_de_Confiabilidade_Oria_v2.html):
é um **retrato derivado** do §5A em 24/11/2026 (com as decisões da v0.1.6), não uma fonte; se o §5A mudar, a página fica velha
até ser refeita. Se um número do §5A mudar, ele muda primeiro no script, e a tabela é colada de novo. APRO =
aprovado · REV = revisão · REPR = reprovado · QUAR = quarentena.

| Caso | Captador | Conferidor | Mercado | Caixa | Dívida | Risco | Estrategista | Entregas |
|---|---|---|---|---|---|---|---|---|
| IPCA do IBGE, espelho do BCB confere | 90 APRO | 89,7 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 89,2 APRO |
| Focus (BCB), sem segunda fonte possível | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO |
| Focus com o dobro da idade | 89,4 APRO | 88,1 REV | 82 REV | 83,2 REV | 88,4 REV | 86,8 REV | 86,7 REV | 83 REV |
| Registrato com recibo; envio a credor não autorizado | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 REV |
| Open Finance, saldo fecha, todas as contas | 90 APRO | 89,1 APRO | 90 APRO | 90 APRO | 89,5 APRO | 90 APRO | 90 APRO | 87,5 REV |
| Open Finance, falta 1 de 10 contas | 88 APRO | 87,8 APRO | 90 APRO | 90 APRO | 86,8 APRO | 89,7 APRO | 90 APRO | 86,4 REV |
| Processo por CNPJ, API sem origem declarada | 55 QUAR | 53,9 REV | 72,5 REV | 70,6 REV | 50 REV | 63,8 REV | 68,6 REV | 52,5 REPR |
| Processo por nome (homônimo possível) | 55 QUAR | 53,9 REV | 72,5 REV | 70,6 REV | 50 REV | 63,8 REV | 68,6 REV | 52,5 REPR |
| Processo na certidão do tribunal | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO | 90 APRO |
| Score de bureau | 80 APRO | 78,1 REV | 80 REV | 80 REV | 78,8 REV | 80 APRO | 80 REV | 74 REV |
| Notícia, por nome | 59,1 QUAR | 55,5 REV | 72,3 REV | 70,6 REV | 50 REV | 64,4 REV | 68,6 REV | 52,5 REPR |
| IPCA: IBGE e BCB divergem | 90 QUAR | 73,2 REV | 82,2 REV | 71,8 REV | 79,7 REV | 80,3 REV | 70 REV | 77,5 REV |
| 'Nada consta' de processos via provedor | 55 REPR | 53,9 REPR | 72,5 REPR | 70,6 REPR | 50 REPR | 63,8 REPR | 68,6 REPR | 52,5 REPR |

**O que os casos mostram:**
1. **Dado oficial confirmado** (IPCA, Focus, certidão) passa em todos os agentes, com o score no
   teto de 90 enquanto a fonte estreia.
2. **A Focus vencida cai em revisão** em todos os agentes, menos na entrada. Na v1, ela passava no
   Mercado.
3. **Registrato e Open Finance** passam em todo uso interno e travam só na saída, até a autorização
   de envio (regra 1).
4. **O processo achado pelo provedor nunca passa sozinho.** Na v1, ele passava no Risco. A certidão
   do mesmo processo passa em todos os agentes.
5. **O score de bureau** passa só no Risco, como opinião.
6. **O conflito IBGE × BCB** fica em revisão em todos os agentes, com as duas versões guardadas.
7. **O "nada consta" sem cobertura** é reprovado em todos os agentes.

### 5A.8 — O que mudou da v1 para a v2

| Ponto | v1 | v2 | Por quê |
|---|---|---|---|
| A4 independência | Peso de 5% a 15% | Sem peso; regula B1 | Contava duas vezes (3 de 3 avaliações) |
| B6 identidade | Peso de até 20%; nome com p ≥ 0,95 passava sozinho | Veto em três níveis; nome nunca passa sozinho | 3 de 3 avaliações; o dono quer que só a alta confiança passe |
| B7 custódia | Só veto | Ponderada (até 25%); veto só em documento oficial do cliente | Custódia tem graus; é o que o credor cobra (3 de 3) |
| Espelho BCB do IPCA | Concordância 100 | 70 | Espelho confirma a captura, não a medição. Era um erro da v1 (3 de 3) |
| Nota ausente | Valores fixos (histórico 70/40; "sem referência" 50) | Sai da conta, com cobertura mínima e teto | O valor fixo era um número inventado (regra 1) |
| Frescor com o dobro da idade | 70 | 50 | Na v1, a Focus vencida passava no Mercado |
| Conflito entre fontes | REPROVADO | REVISÃO, com as duas versões guardadas | A causa costuma ser revisão de série ou erro de captura, que se resolve recapturando (3 de 3) |
| Dado opinativo | Sem regra (barrado por acaso, pela nota de origem) | Trava fora do Risco | A transmissão confiável não torna a opinião verdadeira |
| Pesos | Julgamento meu | Mediana das três avaliações | Os três concordaram entre si (variação ≤ 5 pontos) |
| Mínimos | 70 / 85 / 80 / 85 / 85 / 75 / 85 / 85 | 60 / 80 / 75 / 75 / 80 / 70 / 85 / 85 | Mediana das três avaliações. Comparar com a v1 engana: o score da v2 sai mais alto, porque tira da conta o que não se mediu, e o freio passa a ser a cobertura |

### 5A.9 — Limites desta proposta

- **Os pesos são julgamento**, agora de quatro avaliadores em vez de um. A calibração mede se o
  **resultado** prevê o erro, não se o peso está "certo".
- **Concordância entre avaliadores não é medida.** Os três vêm da mesma família de modelos e podem
  compartilhar vieses. Por isso o modo sombra e o gabarito continuam obrigatórios.
- **O teto (90 ou 80) decide muito no piloto**, porque toda fonte estreia. Ele é o primeiro número
  a revisar quando houver 30 conferências.
- **A cobertura mínima depende da lista do que é `na` e do que é `nm`.** Classificar errado (um
  `nm` como `na`) infla a cobertura em silêncio. É o defeito da regra 7 do projeto, um nível acima,
  e pede um invariante próprio quando for construído.

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
| Limiar de identidade por nome (B6) | Abaixo dele, o candidato por nome nem vai ao humano (acima, vai sempre; nunca passa sozinho) | Pela taxa de falso negativo aceitável, medida numa amostra rotulada (Fellegi–Sunter) | Dono |
| Prazo de validade (B2) por fonte | Até quando o dado vale; e o prazo crítico (veto) | Cadência publicada da fonte; R7 da Espec. 13 | Catálogo; dono aprova |
| Piso por (tipo × etapa × dimensão) | O mínimo para seguir | Pelo custo dos dois erros (§9, passo 4) | Dono, por decisão registrada |
| Histórico mínimo (A2) | Quantas conferências antes de a fonte sair de "sem histórico" | Limite inferior de Wilson/Jeffreys; a mesma lógica dos 300 da D6 | Dono |
| Quem fura o portão | Qualquer analista, em qualquer gravidade, com justificativa | Decidido | Dono (D15.3, 24/11/2026) |

---

## §9 — Como sair do papel sem inventar número

1. **Catálogo e vetos primeiro.** São determinísticos e não precisam de calibração: autorização,
   sinal de execução, custódia, validade. Cada veto nasce com o seu invariante **medido não-vazio**
   (regra 2): plantar a falha, ver o portão reprovar, contar os asserts.
2. **Piloto: vetos e pisos bloqueando, score em sombra** (D15.4). Calcular todas as dimensões, a
   classe, a cobertura e o score, gravar em `avaliacao_dado`, mostrar no painel. Vetos reprovam e
   pisos (com as travas) mandam para REVISÃO desde o primeiro mandato; o score e a cobertura **não
   barram** até a calibração.
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

## §11 — Decisões do dono (respondidas em 24/11/2026; registro v0.1.6, seção 22)

Todas fechadas. O texto oficial e a fala do dono estão no
[registro v0.1.6](../../Business%20Plan/07_decisoes/oria_digital_decisoes_e_pendencias_v0.1.6.html);
aqui fica o resumo e o que mudou em relação à recomendação desta especificação.

| Código | Pergunta | Decisão do dono | Igual à recomendação? |
|---|---|---|---|
| **D15.1** | O documento oficial trazido pelo cliente (SPED, Registrato, certidões) entra no score? | Sim, só com recibo, hash ou autenticidade conferidos | Sim |
| **D15.2** | O que o analista vê no portal interno? | Resultado + classe + score, com cobertura e motivo | Sim (a classe virou rótulo na v2) |
| **D15.3** | Quem pode furar o portão? | **Qualquer analista, em qualquer gravidade**, com justificativa | **Não** (recomendação: Sócio na alta e crítica). A E3 e a E3-1 continuam valendo para o diagnóstico |
| **D15.4** | O que bloqueia antes da calibração? | **Vetos e pisos** (as travas contam como pisos globais); score e cobertura em sombra | **Não** (recomendação: só os vetos) |
| **D15.5** | O cliente ou o credor vê o score? | Só a ressalva, com motivo e efeito | Sim |
| **D15.6** | Quem rotula a amostra de calibração? | O dono, no piloto (como na D4-1) | Recomendação era "o papel do gabarito"; o dono assumiu os dois |
| **D15.7** | Divergência com o cliente baixa o score do externo? | Não, é o achado | Sim |
| **D15.8** | Os números do §5A (v2) são o ponto de partida? | Sim, como hipótese a calibrar | Sim |
| **D15.9–D15.15** | As 7 regras do §5A.5 | Aprovadas | — |

---

## §12 — O plano, em etapas (sem calendário, K2)

| Etapa | O que | Depende de | Pronto quando |
|---|---|---|---|
| **0** | Decisões D15.1–D15.15 | — | **Feito em 24/11/2026:** registro v0.1.6, seção 22 |
| **1** | Catálogo `fonte_externa` com origem, cadência, validade e origem compartilhada | Espec. 13 etapa da `consulta_externa`; 1.C1–1.C3 | Toda fonte captada no catálogo; fonte sem origem declarada aparece como "sem origem" |
| **2** | Vetos no banco | 1.B7, 1.B6 | Cada veto com invariante medido não-vazio (regra 2) |
| **3** | Dimensões e classe em modo sombra (N0) + painel | 1.B5, 1.C4 | Toda observação externa tem avaliação por dimensão, com estado; nenhuma em branco sem motivo |
| **4** | Gabarito do dado externo e medição por classe (rotulado pelo dono no piloto, D15.6) | 1.J2, D15.6 | Taxa de erro por classe medida, com intervalo |
| **5** | Pisos fixados e portões ligados em degraus | Etapa 4; decisão do dono | Cada portão ligado tem a decisão que o fixou; teste que reprova sem o portão |
| **6** | Rebaixamento automático e revisão semanal dos furos | 2.10 (E4) | Piora medida rebaixa o portão (teste) |

**No plano de execução (24/11/2026), por fase:**

| Etapa | Item do plano | Fase |
|---|---|---|
| 0 | 0.13 (registro v0.1.6) | 0 — Fundação |
| 1 | 1.K1 | 1 — Piloto |
| 2 | 1.K2 (P1) | 1 — Piloto |
| 3 | 1.K3 (portões dos agentes do piloto), 1.K4 (propagação e frescor pela data do uso), 1.K5 (painel) | 1 — Piloto |
| 3, agentes da Fase 2 | 2.18 (Risco, Estrategista, Entregas, Captador formal, monitoramento) | 2 — Restante da v1 |
| 6, revisão dos furos | 2.19 (alerta de carimbo) | 2 — Restante da v1 |
| 4 | 3.8 (calibração) | 3 — Evolução operacional |
| 5 e 6 | 3.9 (bloqueio em degraus, rebaixamento automático) | 3 — Evolução operacional |

A tabela "Em que fase nasce o portão de cada agente", na Trilha K do plano, diz qual portão do §5A.2
nasce com qual agente.

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
