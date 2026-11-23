# Prontidão por estágio — o que falta para o objetivo estar 100% cumprido

> **SUPERADO em 23/11/2026** pelo plano de execução único [`Business Plan/06_execucao/PLANO_DE_EXECUCAO.md`](../../Business%20Plan/06_execucao/PLANO_DE_EXECUCAO.md) (decisão K1 do registro v0.1.3).
> Este arquivo fica como histórico, sem outra alteração. O que dele seguia aberto, e para onde foi, está na
> seção 11 daquele plano (por bloco, não item a item).

**Data:** 20/08/2026, sessão 55 · **Base:** `dbc5eec` · suítes: banco 884 · export 618 · n8n 298 ·
transcrição 35 · e2e 46.

---

## 1. O objetivo, na fonte

O `Arquitetura do Sistema/1 Visão e Doutrina/00` define o produto em uma frase, e ela é o critério contra o qual tudo abaixo é medido:

> Um sistema de **intake governado e prontidão de dados** que recebe submissões de clientes e produz
> um **dataset estruturado, completo, formalmente válido, reconciliado e auditável**, com um
> **portão explícito de go/no-go** para análise. O produto é **confiança no dado + redução de
> retrabalho + trilha de auditoria** — não análise automática, não modelagem automática.

E o escopo negativo é tão importante quanto: **não é ferramenta de modelagem financeira, não é motor
de decisão contábil, não substitui o julgamento do analista — o habilita com dado confiável.**

### A essência, destilada

Se o produto é *confiança no dado*, então o sistema cumpre 100% do objetivo quando, em cada estágio,
**duas coisas são verdade ao mesmo tempo**:

| | A promessa | A falha que a nega |
|---|---|---|
| **1** | Nada se perde em silêncio | uma conta some e o placar não muda |
| **2** | Nada chega errado em silêncio | um número troca de coluna e nada acusa |

Toda a arquitetura é consequência disso: os portões, o dial de autonomia, as linhas de
reconciliação, a proveniência por célula. **Um sistema que erra e avisa cumpre o objetivo; um que
acerta 97% e cala nos 3% não cumpre** — porque o produto vendido é a confiança, não a taxa de acerto.

E há uma terceira promessa, que o dono acrescentou nesta rodada e que governa como as duas primeiras
são perseguidas:

> **A razão entre autonomia e (qualidade × eficiência) é o que manda.** Autonomia que custa qualidade
> é regressão. Toque humano que não compra qualidade também é. E a medição não pode custar hora
> humana, senão medir destrói a razão que se mede.

---

## 2. O pipeline, e os dois exports

```
E1 INGESTÃO ──► E2 EXTRAÇÃO ──► P1 COMPLETUDE ──► E3 RECONCILIAÇÃO ──► 1º EXPORT (dados)
                                                                             │
                                                       MODELAGEM ◄───────────┘
                                                            │
                                                    P2 APROVAÇÃO ──► 2º EXPORT (comitê)
```

- **1º export** (`?modo=dados`): as abas linha a linha, com proveniência. Insumo de **conferência**,
  disponível desde a ingestão. É o que prova que o dado é rastreável.
- **2º export** (completo): as 14 abas do modelo institucional. É o **arquivo que vai ao comitê**.

---

## 3. Inventário — tudo que não está 100%

Legenda: 🔴 bloqueia o objetivo · 🟠 degrada · ⚪ decisão pendente · ⚫ espera por terceiro

### E1 — INGESTÃO

| | Item | Estado |
|---|---|---|
| 🔴 | **A rodada real nunca aconteceu.** O fatiamento nunca ligou em produção (0 de 38 documentos fatiados); a `juntarBlocos` nunca viu bloco de verdade; a dedup por fingerprint (`0118`) nunca viu reenvio real | só o dono destrava |
| 🔴 | **O limiar de cobertura (0,85) está calibrado contra 38 documentos SINTÉTICOS.** A folga de 11 pontos existe para o documento sujo, e ninguém mediu se basta | depende da rodada |
| 🟠 | **`classificacao_doc_checklist` opera em N2 `declarada`** — auto-clear a 0,70 **sem concordância medida**. Documento com confiança 0,71 entra classificado sem humano olhar | ver E-AUTONOMIA |
| ✅ | ~~O espelho lib ↔ workflow só tinha guarda para 2 funções~~ — **fechado em 21/08**: `N8N/test/espelho-inline.test.mjs` roda os mesmos casos nas **26** funções embutidas e na lib, e o penúltimo assert exige que toda função duplicada esteja coberta ou declarada com motivo | |
| ✅ | ~~A confiança da classificação era a maior das duas~~ — corrigido; documento que a IA declarou ilegível não entra mais sem revisão | |
| ✅ | ~~`parseCsv` não tratava aspas~~ — corrigido; `"Silva, João"` não desloca mais as colunas | |

### E2 / P1 / E3 — TRATAMENTO

| | Item | Estado |
|---|---|---|
| 🔴 | **`extracao_linhas_financeiras` opera em N2 `declarada`** — auto-aceite sem concordância medida. É o coração da promessa "não confia em si mesmo até medir que pode", e hoje ele confia sem ter medido | ver E-AUTONOMIA |
| 🟠 | **`fn_conferir_modelagem` conta premissa de sazonalidade como "sem valor"** e segura o "pronto" da tela. Suspeita da sessão 39, **nunca reconferida contra dado real** — 10 minutos de trabalho | engenharia |
| 🟠 | **Linha que sozinha passa do teto de saída** — não há corte mais fino possível. Nenhum documento do book cai nesse caso; um razão real pode | engenharia |
| 🟠 | **Rateio de despesa intragrupo que não deixa saldo no balanço** não tem espelho para conferir | limite conhecido da `0124` |
| 🟠 | **Mútuo com sócio** — o par é o contrato com o quotista, que ninguém cruza | limite conhecido da `0123` |
| ✅ | ~~A seção não era conferida contra as próprias linhas~~ — `0133`: linha perdida, valor errado, sinal invertido e total declarado duas vezes passam a ser pegos, localizados na seção | |

### 1º EXPORT — dados / conferência

| | Item | Estado |
|---|---|---|
| 🟢 | Sem defeito aberto conhecido. As 618 verificações cobrem os invariantes do arquivo, e a correção de detecção de subtotal desta rodada beneficia as duas saídas — elas compartilham o mesmo veredito, por construção | |

### MODELAGEM

| | Item | Estado |
|---|---|---|
| 🟠 | **Nada guarda contra "a mesma premissa de giro vinculada a N contas".** Vinte contas × 60 dias = **1.200 dias de receita em giro**, e o balanço continua fechando porque o PL absorve. A fixture de demonstração faz exatamente isso, e por isso o arquivo de demonstração mostra passivo circulante indo de 71 mil a **5,7 milhões** em cinco anos | engenharia |
| ⚪ | **`pct_de_linha` e `dias_de_giro` incidem sobre a RECEITA TOTAL do caso, não sobre a linha** — decisão de produto registrada. Se o Modelo Base usa outra base, é divergência de mecanismo e a regra da casa manda perguntar, não consertar | dono |

### P2 + 2º EXPORT — o arquivo de comitê

| | Item | Estado |
|---|---|---|
| ✅ | ~~O ativo circulante não fechava~~ — **fecha em ZERO** agora. Eram dois defeitos de sinais opostos que se mascaravam (−9.200 contra +12.400): uma coincidência aritmética de 2024 apagava uma conta em 2025 e em todo o grupo, e o `Math.abs` do giro somava as contas redutoras | |
| ✅ | ~~Dívida bancária projetada por dias de giro~~ — corrigido; 6.827 (9,6% do PC) saíram do giro | |
| ⚪ | **−15.149 no passivo circulante:** o mapa de dívida diz 43.542 de curto prazo e o balanço diz 28.393. **Decisão tomada: o mapa manda**, o balanço é reconciliado, o arquivo declara a diferença. Fica como decisão registrada, não como defeito | resolvido |
| 🟠 | **ND/EBITDA, DSCR e pico de caixa não estão nos três cenários.** A fronteira está DITA na aba, e o motivo é bom: mostrá-los lendo a dívida de um cenário só seria pior que a ausência | dono prioriza |
| 🟠 | **INSS e FGTS a recolher vão para a aba de Tributos**, com cronograma decrescente, quando são encargos mensais recorrentes. Classificação deliberada e documentada — mas discutível, e muda número | dono |
| ⚫ | **25 das 36 perguntas ao cliente** — a máquina existe; falta o TEXTO do capítulo 10, que é verbatim da entrega e ninguém pode inventar | destrava com um arquivo |
| ⚫ | **Alavancas de reestruturação** (alongamento, carência, haircut, new money) — escopo novo, e é a pergunta que o primeiro comitê vai fazer | produto seguinte |

### E-AUTONOMIA — a contradição estrutural

| | Item | Estado |
|---|---|---|
| 🔴 | **Dois estágios operam em N2 `declarada`** (extração de linhas e classificação documento→checklist): auto-clear **sem concordância medida**. A `0126` pôs a regra de ouro dentro de `fn_mudar_dial`, que agora **recusa** subir — mas os dois já estavam lá antes dela | |
| 🔴 | **E não há caminho para medir.** A rotulagem manual saiu do produto por decisão do dono; sem rotulagem nenhuma rodada de golden set congela; sem rodada congelada `fn_golden_suficiente` recusa. **O dial não pode subir, e os dois que já estão em cima não podem ser confirmados** | decisão do dono |

> **É a única contradição estrutural aberta do projeto.** As três saídas estão dimensionadas no
> `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` (B3). A recomendação registrada: medir por **veredito de produção**
> como piso permanente — cada aceite ou rejeição na tela de revisão já é um rótulo, produzido pelo
> trabalho normal, e portanto não custa hora humana — publicando que é um piso enviesado.

### PROCESSO — atravessa todos os estágios

| | Item | Estado |
|---|---|---|
| 🔴 | **`main` sem proteção — NÃO CONFERIDO.** Esta sessão não lê configuração de branch. O indício, que não é prova: PRs mergeados 5 minutos depois de abertos, com o CI levando ~3,5 | dono, trivial |
| ✅ | ~~Observabilidade zero~~ — **fechado em 21/08** (`0135`): `fn_operacao_lotes` decide quatro alertas no banco (cobertura não medida, documento com falha, documento sem medição, custo acima de 1,5× o previsto) e `fn_operacao_resumo` publica o cabeçalho, inclusive há quantos dias nada roda | |
| 🟠 | **Backup, retenção e LGPD** — **escritos em 21/08** (`Arquitetura do Sistema/2 Especificação/10`): onde o dado mora, o que se remonta do repositório sozinho, o teste de restauração que falta e quem vê o quê. Continua laranja porque as linhas **[A CONFIRMAR]** dependem do console do Supabase, e o teste de restauração **nunca foi executado** | dono |
| 🟠 | **Migration aplicada à mão.** A `0131` declara o que falta; aplicar continua manual, e o intervalo entre "mergeado" e "no ar" volta a existir na próxima | infra |

---

## 4. O caminho até 100%, em ordem

1. **A rodada real do book** — destrava E1 e E2 inteiros, e é uma hora do dono. Nada de engenharia
   substitui: toda suíte prova a ingestão sobre extração fiel, por construção.
2. **A decisão da autonomia (B3)** — sem ela, dois estágios ficam permanentemente em autonomia não
   medida e a F4 não começa. Não depende da rodada; pode ser hoje.
3. **Processo** — a observabilidade e o documento de dados fecharam em 21/08; sobra a **proteção do `main`** (dono, trivial) e o **teste de restauração** do `Arquitetura do Sistema/2 Especificação/10`, que é o único que transforma a crença de backup em controle.
4. **Pós-rodada:** recalibrar cobertura, conferir fatiamento, medir custo real.
5. **Guarda de giro agregado** na modelagem, e a suspeita da sazonalidade.
6. **Sob demanda:** ND/EBITDA por cenário, as 25 perguntas, alavancas.

---

## 5. O que este inventário NÃO cobre — dito, não omitido

Revisei com profundidade a **triagem** (as 12 libs do n8n, exercitadas contra casos-limite) e o
**output** (modelo institucional e export, gerando o arquivo e auditando célula a célula). **Não**
revisei linha a linha: as 78 migrations, as ~7.400 linhas de telas do portal, os geradores dos books
sintéticos, nem o `export-modelagem.ts` (a aba Modelagem mensal, 2.400 linhas).

**Um inventário que se declara completo sem ter olhado tudo é a mesma família de defeito que este
projeto passa o tempo corrigindo** — a ausência com cara de normalidade. O que está acima é o que foi
medido; o que não foi, está nesta seção.
