# Mapa de execução — daqui até o projeto fechado

**Data:** 09/09/2026, sessão 81 · **Base conferida:** `main` em `668b6fe`, CI verde (PR #203).
**Tocado em 13/10/2026:** só a linha B8 do quadro e a §13 (Espec. 12). O resto do corpo continua
conferido em 09/09.
**Última migration:** `0160` — ver `ESTADO.md`.

> **NOTA IMPORTANTE (18/09/2026):** Este arquivo é histórico. O roadmap detalhado e atual está em
> `Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md` (atualizado em 15/09).
> As seções B0–B7 abaixo refletem o estado anterior à F0 ser fechada. Ver `ESTADO.md` para o estado
> atual e `ARQUITETURA_ALVO_E_ROADMAP.md` para as fatias de F1 em dia.

> **O corpo deste arquivo é mais novo que este cabeçalho era.** Até 09/09 ele dizia "20/08, sessão
> 55, migration `0133`" enquanto as seções abaixo já registravam coisas de 02/09 — uma revisão
> pegou. É o mesmo defeito que separou o `ESTADO.md` do `HANDOFF.md`: a parte que muda toda rodada
> convivendo com a que quase nunca muda, e a que quase nunca muda não convidando a editar nada.
> **Quem tocar o corpo atualiza esta data na mesma passada** — cabeçalho que fica para trás manda a
> próxima sessão planejar contra um estado que não existe mais.

## Como ler este arquivo

Os três documentos de estado do repositório respondem perguntas diferentes, e é isso que os mantém
separados:

| Arquivo | Pergunta que ele responde |
|---|---|
| `ESTADO.md` | **Onde o projeto está** — o que cada rodada entregou, com o porquê |
| `HANDOFF.md` | **Como chegou aqui** — histórico sessão a sessão, arquivo morto |
| **este arquivo** | **O que falta, em que ordem, e como saber que acabou** |

**A regra deste arquivo:** nada aqui é "provavelmente feito". Cada item ou tem evidência conferida
nesta rodada, ou está marcado como **NÃO CONFERIDO** — que é uma informação, não uma omissão. A lista
de pendências do `ESTADO.md` já disse uma vez que o Modo A não existia depois de ele existir (PR
#150); a maneira de não repetir isso é separar o que foi olhado do que foi lembrado.

---

## 1. O quadro em uma página

| # | Frente | Estado | Quem destrava | Bloqueia |
|---|---|---|---|---|
| **B0** | ~~Instalação do banco~~ — `0126`–`0133` **aplicadas em 20/08** | 🟢 **fechado** | — | — |
| **B1** | **A rodada real do book** num mandato novo + aceite | 🟠 **a rodada ACONTECEU em 02/09** (lote `7377`, 38/38, cobertura 0,987, nenhum nó morto); falta o **aceite** | **dono** (~20 min) | B2 inteiro |
| **B2** | Recalibrar cobertura, conferir fatiamento e subtotais | ⚪ não começou | engenharia, **depois** de B1 | a confiança nos números |
| **B3** | **A autonomia sem rotulagem manual** — decisão em aberto | 🟠 contradição viva | **dono decide** | a F4 do `Arquitetura do Sistema/1 Visão e Doutrina/03` |
| **B4** | Dívidas do output (alavancas, três cenários completos, 25 perguntas; apresentação de crédito) | 🟠 apresentação implementada, 0205 não aplicada | dono (aplicar 0205) | o valor no comitê |
| **B5** | Eficiência — o que sobrou depois da passada da sessão 54 | 🟢 quase fechada | engenharia | nada crítico |
| **B6** | **Operação** — proteção do `main`, ~~observabilidade~~, ~~backup~~ | 🟠 **B6.2 e B6.3 fechadas em 21/08**; sobra o `main` | dono | a segurança do processo |
| **B7** | Bloqueados por dado que não temos | ⚫ espera | terceiros | nada — são espera |
| **B8** | **Fontes oficiais e captação** (SPED, eSocial, logística, CNAB, CNAE) — Espec. 12, fase **F2T** do roadmap | ⚪ só especificação | **dono** (D12.1–D12.11) e depois engenharia | o dado independente que confere o declarado (DATA GATE) |

**O caminho crítico encurtou: `B0` fechou em 20/08.** Sobra `B1 → B2` e, em paralelo, `B3` (decisão)
e `B6` (higiene). **A rodada real aconteceu em 02/09** (sessão 79 do `ESTADO.md`) e não deixou erro
de execução — o que sobra do `B1` é o **aceite**: `auditar-xlsx.mts` sobre o arquivo exportado e o
`ACEITE.md` preenchido. Enquanto ele não existir, nada de `B2` começa, porque `B2` é recalibração
sobre números que ninguém conferiu.

---

## 2. A verdade do momento (conferido em 20/08)

**O que está bom, e foi verificado:**

- **CI verde no `main`.** Execução 352 sobre `75abcee`, `conclusion: success`. As sete suítes, os
  quatro geradores de workflow, os três geradores de fixture, o espelho do `Supabase/schema.sql`, o `tsc`,
  o `eslint` e o `next build` — todos passaram.
- **Não há reimportação de workflow pendente.** `git log --since=2026-08-19 -- N8N/workflow.e1-ingestao.json
  N8N/build-workflow.mjs N8N/lib` vem **vazio**. O n8n que o dono importou em 19/08 é o mesmo que está
  no repositório hoje. Isso é o inverso do que aconteceu nas rodadas 50–52, e vale registrar.
- **Quatro itens do backlog do diagnóstico de 11/08 que a lista ainda dava como abertos estão
  FECHADOS**, conferidos no código nesta rodada: o bloco de necessidade de recursos (`NR_FURO`,
  `modelo-institucional.ts:4489`), os índices que a `Arquitetura do Sistema/2 Especificação/f0/08` faseou (liquidez seca `R_LIQ_SECA:4438`,
  ciclo de caixa `:4458`), o **papel de usuário** (`0107`: `fn_papel`, `fn_ressalvar_pendencia`,
  `fn_tratar_pendencia`) e os **estados de tratamento da pendência** com ação de tela
  (`portal/src/lib/pendencia.ts:56-77`, `Pendencia.tsx:162`).

**O que não está, e é o assunto deste mapa:**

- **A fila de migrations zerou em 21/08, e o caminho até isso é a lição.** Este arquivo dizia que
  ela já tinha zerado em 20/08; a sonda das 80 migrations mostrou que a **`0133`** havia ficado para
  trás enquanto a `0134` e a `0135`, posteriores, entraram. Sem ela a checagem de balanço fechava por
  construção e seção com buraco não abria pendência. O dono aplicou no mesmo dia e a conferência
  fechou. Ver "A `0133` QUE FALTOU" no `ESTADO.md`. (A TELA `/instalacao` e o aviso no painel saíram
  do portal em 21/08, por decisão do dono; o catálogo, as duas funções e a suíte ficaram inteiros no
  banco.)

- **Ninguém rodou o book.** É o mesmo bloqueio de três sessões atrás, e a cada sessão ele fica mais
  caro: agora são **três checagens novas, um conserto de motor e três estágios inteiros** que nunca
  viram dado real.
- **A rotulagem manual saiu (PR #153) e o portão que ela alimentava ficou.** Ver B3 — é a única
  contradição estrutural aberta hoje.

---

## 3. B0 — A instalação · **FECHADO em 20/08**

As oito migrations (`0126`–`0133`) foram aplicadas no Supabase. Nada de banco fica entre o
repositório e o sistema.

**A conferência que vale, e não é este arquivo:** rodar a sonda contra o banco —

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

— e não obter linha nenhuma: os **13 requisitos verdes**. Se a sonda e qualquer recado em prosa
deste repositório discordarem, **a sonda é que está certa**: ela responde sobre o banco em que você
está de fato conectado. (Até 21/08 a mesma resposta vinha pela tela `/instalacao` e por um aviso no
topo do painel; o dono tirou as duas do portal, e o motor no banco não mudou.)

> **A ressalva que a própria sonda publica, e que continua valendo:** "o objeto existe" não é "a
> migration foi aplicada corretamente" — `create or replace` sobre um corpo velho deixa a assinatura
> idêntica e nenhuma sonda de catálogo vê isso. Quem confere comportamento é a suíte, no CI. O que a
> sonda garante é o contrapositivo, que é a parte útil: **objeto ausente é migration ausente, sem
> dúvida.**

### O que este bloco deixa para trás (B6.4)

Aplicar migration à mão já custou uma rodada inteira (a `0101`, sessão 33). A `0131` fez a parte que
dá para fazer de dentro do produto — **declarar** o que falta. O que ela não faz é **aplicar**.
Enquanto o apply for manual, o intervalo volta a existir na próxima migration; a diferença é que
agora ele é visível em vez de silencioso.

---

## 4. B1 — A rodada real (dono, ~1 hora, e é o maior destravamento do projeto)

**Este é o bloqueio.** Não é engenharia: é uma hora de execução que nenhuma suíte substitui, porque
todas as suítes provam a ingestão sobre extração **fiel** — PDF gerado por `reportlab`, texto limpo,
layout conhecido. Todo defeito de leitura de documento *real* (scan torto, carimbo, coluna deslocada,
escala mista) está fora do alcance de todas elas, por construção.

### Os dois passos manuais · **FEITOS em 02/09** (dono)

Eles bloquearam o B1 e caíram no mesmo dia em que foram medidos:

1. **As `0151`–`0156` aplicadas no Supabase.** Conferido contra produção: as seis voltaram
   `APLICADA`, e o veredito das três chamadas do workflow voltou **`PODE RODAR`** — inclusive a
   assinatura nova de `fn_reconciliar_por_documento` (`p_escopo`), que é a que um teste por nome
   daria como presente estando ausente.
2. **O `workflow.e1-ingestao.json` reimportado no n8n.** O nó `Abrir Lote` é novo; sem a
   reimportação, `lote_execucao` só receberia linha ao fim da cadeia.

**Não há mais nada de infraestrutura entre o repositório e o sistema.** Confira em 30 segundos,
antes de subir documento, com `Supabase/test/conferir-chamadas.mjs` apontado ao banco da rodada —
a conferência que vale é a que se roda contra o banco em que se está conectado, nunca este arquivo.

### A ordem, e ela importa

1. **Rodar o book num mandato NOVO** (não reaproveitar mandato existente — a `0118` deduplica por
   fingerprint e o reenvio do mesmo PDF não chama mais a OpenAI).
2. **Exportar o completo.**
3. **Passar o `auditar-xlsx.mts`** (10 itens automáticos) **e o `Arquitetura do Sistema/6 Referência/ACEITE.md`** (10 itens humanos)
   por cima.

Foi a falta desse par que deixou sair, em 06/08, um arquivo com seis números errados e as suítes
verdes.

### As onze coisas que só a rodada prova

| | O que ela prova | De onde vem | Como saber que passou |
|---|---|---|---|
| 1 | **O fatiamento liga em produção** — estava DESLIGADO (0 de 38 documentos fatiados) | sessão 52 | o lote sai com **~44 chamadas**, não 38; o `17_Livro_Razao` vira **4 blocos** |
| 2 | Os **subtotais impressos** chegam | `0116` | "TOTAL DO ATIVO" aparece como **linha**, não só como `secao` |
| 3 | A **divergência de mútuos** aparece quando existe | `0123` | pendência `reconciliacao:mutuos_planilha_vs_balanco` |
| 4 | O **espelho intragrupo** não dá falso positivo | `0124` | `reconciliacao:intragrupo_espelho` só abre se um par realmente não fechar |
| 5 | A **proveniência** chega ao arquivo | `0125` | a nota da célula diz arquivo, página, confiança e aceite |
| 6 | `lote_integro` e `cobertura_do_lote` | sessão 50 | `cobertura_do_lote` **não pode vir `null`** |
| 7 | O **custo** bate com o previsto | sessões 50–52 | o guarda prevê ~US$ 1,42 contra US$ 1,29 medido (+10%) |

### E as três que a `0128`/`0129`/`0130` acrescentaram, e ninguém listou ainda

| | O que a rodada prova | De onde vem |
|---|---|---|
| 8 | A **classificação contábil em sombra** grava sugestão sem decidir — e a rubrica do documento real casa com `rubrica_classe` | `0128` |
| 9 | A **transcrição assistida** não contamina: linha transcrita entra como `origem_valor` humana e não vira insumo de medição da máquina | `0129` |
| 10 | O **dial obedecido** recusa auto-aceite em estágio interpretativo sem concordância medida — na prática, não só no teste | `0127` |
| 11 | A **árvore da seção** fecha sobre PDF sujo — e quantas seções ela não consegue conferir por unidade mista ou rótulo duplicado, que é o número que diz se a extração real tem forma | `0133` |

### O que a rodada de 02/09 já respondeu, das onze

Medido no lote `7377` pelo dono (detalhe e números na sessão 79 do `ESTADO.md`):

| prova | resultado |
|---|---|
| 1 — fatiamento LIGADO em produção | ✅ **4 documentos fatiados**, e o `17_Livro_Razao` em blocos com emenda (a costura descartou 3 linhas repetidas — funcionou) |
| 6 — `cobertura_do_lote` não vem `null` | ✅ **0,987** |
| 7 — o custo bate com o previsto | ❌ **US$ 0,4674 contra 0,3200 previstos: +46%**, e o mesmo desvio na rodada de 31/08 (0,4779 contra 0,3200). Desvio estável não é ruído — a previsão está calibrada baixo. Entra no `B2` |

As demais (2, 3, 4, 5, 8, 9, 10, 11) exigem olhar o `.xlsx` e as pendências item a item, e é
exatamente isso que o aceite é. **Elas continuam abertas.**

### Critério de pronto

O `Arquitetura do Sistema/6 Referência/ACEITE.md` preenchido e registrado, com os 10 itens do `auditar-xlsx.mts` verdes sobre o
arquivo **exportado da rodada real** — não sobre fixture.

---

## 5. B2 — O que só existe depois da rodada

Nenhum destes pode começar antes de B1. Estão aqui para que a sessão seguinte não precise
redescobri-los.

1. **Recalibrar o limiar de cobertura (0,85)** com pontos REAIS. Desde 31/08 a régua é medida
   sobre o TEXTO DE PRODUÇÃO capturado (execução 7276, 20 dos 38 documentos): erro mediano **+0%**,
   pior caso **95%** com extração perfeita, zero falso positivo. Os números anteriores (+3%, 96%)
   vinham do texto do GERADOR e não valiam — ver
   `.claude/memory/portao-mede-a-entrada-de-producao.md`. **O que falta:** capturar os 18
   documentos restantes (o portão os declara "NÃO MEDIDO CONTRA PRODUÇÃO") e um documento sujo de
   verdade — a folga de 11 pontos continua sem medição contra scan real.
2. **Conferir se o fatiamento cortou onde devia**, e se a emenda entre blocos não duplicou linha. A
   `juntarBlocos` limpa emenda repetida e **nunca viu bloco de verdade**.
3. **Conferir os subtotais impressos** (`0116`) — a única mudança daquela rodada que só a extração
   real prova.
4. **Ler o que a `0133` disse na rodada.** A taxa de seções que fecham, por tipo de documento, é a primeira medida de qualidade de extração que não custa hora humana — e é o insumo para calibrar o limiar do item 1 por evidência em vez de por chute.
5. **Medir o custo por caso REAL** e comparar com o teto de lote. Hoje o custo é medido *offline*
   (`medir-custo-book.mjs`, sem chamar a API); a `0115` grava o custo real em `lote_execucao` mas
   nenhuma execução real passou por lá ainda.

---

## 6. B3 — ~~A autonomia sem rotulagem manual~~ · **DECIDIDO em 21/08: saída B** (`0136`)

> **A decisão está escrita em `Arquitetura do Sistema/1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md`**, na seção "Como se mede a
> concordância quando não há rotulagem", que é o critério de pronto deste bloco. Em uma linha: o
> veredito que o trabalho normal já produz passa a contar, com `base_do_nivel = 'medida_por_veredito'`,
> declarado como PISO enviesado — quem julga na revisão vê o palpite da máquina antes de decidir. A
> rotulagem cega continua sendo o caminho para o número que sustenta o dial para fora da casa, e a
> saída C fica guardada para esse dia. O texto abaixo é o diagnóstico que levou à decisão.

### O diagnóstico, preservado

**Esta é a única pendência estrutural do projeto, e ela não é um bug — é uma decisão que ficou pela
metade.**

O que aconteceu, em três PRs de um mesmo dia:

- **PR #151 (`0130`)** construiu a estrada até o portão: `fn_golden_abrir_rodada`,
  `fn_golden_incluir_documento`, `fn_golden_linhas_para_rotular` (cega), `fn_golden_rotular_campos`,
  `fn_golden_congelar` — mais as quatro telas de `/autonomia/golden` e a suíte
  `verificar-tela-cega.mts`, 18 asserts contra o vazamento que não tem sintoma.
- **PR #153** removeu as telas, os cinco componentes, a suíte e o passo dela no CI. **Decisão do
  dono:** não haverá fluxo de rotulagem manual; o objetivo é o sistema operar sem triagem humana.
- **O que ficou:** o caminho de escrita no banco (`0130`) e `fn_golden_classe_a`, que mede
  falso-positivo de Classe A a partir de **veredito de produção**, sem rotulagem nenhuma.

**A consequência aritmética, e ela não se resolve sozinha.** `Arquitetura do Sistema/1 Visão e Doutrina/01` (regra de ouro) e `Arquitetura do Sistema/1 Visão e Doutrina/03`
(F4) dizem que estágio interpretativo só sobe de dial com **concordância medida**. A `0126` pôs essa
regra dentro de `fn_mudar_dial` — ela agora **recusa**, não é mais só doutrina. `fn_golden_suficiente`
pede N mínimo por tipo em rodada congelada. Sem rotulagem, nenhuma rodada congela. Logo:

> **Hoje, o dial de nenhum estágio interpretativo pode subir. A F4 do `Arquitetura do Sistema/1 Visão e Doutrina/03` não tem como
> começar.** Isso é *correto* — o sistema está se recusando a certificar a si mesmo — mas é um estado
> terminal, não um caminho.

### As três saídas, e é decisão do dono qual delas vale

| | Saída | O que custa | O que se perde |
|---|---|---|---|
| **A** | **Aceitar o teto.** Interpretativo fica em N0/N1 para sempre; a autonomia sobe só onde é determinístico | zero engenharia; escrever a decisão em `Arquitetura do Sistema/1 Visão e Doutrina/01` e `Arquitetura do Sistema/1 Visão e Doutrina/03` | o produto opera sempre com humano no loop no interpretativo — o custo por caso não cai |
| **B** | **Medir por veredito de produção.** Aproveitar `fn_golden_classe_a`: cada aceite/rejeição humana na tela de revisão **já é** um rótulo, gerado pelo trabalho normal | médio: estender de Classe A para campo extraído; um portão novo que exija N vereditos por tipo | o veredito de produção **vê o palpite da máquina** — é conferência, não ground truth. Mede um PISO, e o viés de confirmação puxa o número para cima |
| **C** | **Rotulagem sem tela de mesa.** A planilha da `0129` já faz ida-e-volta de formato com suíte própria: exportar o lote cego em `.xlsx`, o rotulador preenche onde estiver, importar | baixo-médio: reusar `verificar-transcricao.mts`; a cegueira passa a ser do gerador da planilha | continua exigindo tempo humano — mas assíncrono e fora do portal, que era a objeção |

**Minha recomendação:** **B como piso permanente, C sob demanda.** B não custa tempo de ninguém e
produz número todo dia; a honestidade se preserva publicando que é um piso enviesado, do mesmo jeito
que `fn_golden_congelar` já publica o aviso de rotulador único. C fica guardado para o dia em que
alguém precisar de um número que sustente subir dial de verdade.

**O que NÃO pode acontecer, e é o risco real deste bloco:** subir o dial "porque a rodada foi bem".
A `0127` foi escrita exatamente para impedir isso, e dois níveis declarados eram falsos quando ela
chegou. Se a saída A for a escolhida, ela precisa ser **escrita**, senão daqui a três sessões alguém
vai propor afrouxar `fn_mudar_dial` para destravar algo — e vai parecer razoável.

### Critério de pronto · **ATENDIDO em 21/08**

Uma seção nova em `Arquitetura do Sistema/1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md` dizendo qual saída foi tomada e por quê, mais a
migration que implementa o portão e a suíte que o trava. Entregue: a seção "Como se mede a
concordância quando não há rotulagem", a `0136` e `Supabase/test/veredito_producao.test.sql`, cujo assert
central é que o veredito de produção **nunca** vira `base_do_nivel = 'medida'`.

---

## 7. B4 — As dívidas do output (o que chega ao comitê)

Em ordem de (impacto no que o cliente lê) ÷ (esforço).

### B4.1 — As 25 perguntas ao cliente que faltam · **bloqueado por texto, não por código**

A `0120` entregou **11 das 36** perguntas do capítulo 10, com as 25 restantes nomeadas família a
família. A máquina inteira existe: `fn_sugerir_perguntas`, os marcadores, o registro de envio com
texto congelado, a aba `/casos/[id]/perguntas`. **Acrescentar pergunta é uma linha de `seed`.**

O que falta é o **texto**: a `0120` declara que o enunciado é *VERBATIM da entrega*, e o repositório
não tem os códigos `1.1`–`8.3` / `A1`–`A12`. Redigi-los "no espírito" produziria 25 perguntas que o
cliente recebe **em nome da casa** e que ninguém aprovou — e elas pareceriam aprovadas, porque saem
do sistema.

**Destrava com um arquivo:** o capítulo 10 da entrega, commitado em `docs/`. Depois disso é meia
sessão.

### B4.2 — Os três cenários · **PARCIALMENTE FECHADO em 21/08: sensibilidade declarada**

> **O que entrou:** ND/EBITDA e DSCR por cenário como SENSIBILIDADE — o EBITDA varia, a dívida é a
> do cenário ativo —, com o teste de rompimento em cada linha e um CHECK provando que a coluna do
> cenário ativo reproduz o bloco de RATIOS. A nota de rodapé declara que a leitura é um PISO da
> deterioração: no cenário pior o revolver saca mais. **"Rompe aqui" implica "rompe lá"; o contrário
> não vale.** O que continua fora é a réplica completa (três cascatas de dívida e três fluxos de
> caixa) e o pico de caixa por cenário. O texto abaixo é o diagnóstico que levou a isso.

A sessão 54 entregou a cascata paralela (receita líquida, crescimento, EBITDA, margem para os três
cenários simultâneos) e **declarou a fronteira na própria aba**: ficam fora **ND/EBITDA, DSCR e pico
de caixa**, porque exigiriam replicar a cascata de dívida e o fluxo de caixa por cenário.

A decisão de deixá-los fora está certa e o motivo está escrito: *"um bloco que mostrasse ND/EBITDA dos
três cenários lendo a dívida de UM seria pior que a ausência dele — o número existiria, pareceria
comparação, e não seria."*

**O que fica no mapa:** ND/EBITDA e DSCR por cenário são justamente as métricas que o credor olha.
Se o comitê pedir, o custo é **três modelos paralelos dentro do arquivo**, com um CHECK provando que
a sombra do cenário ativo é igual à linha ativa — o mesmo desenho que já provou valer na cascata de
receita (os dois religamentos da sessão 54 mostraram que os dois grupos de assert são
complementares). É uma sessão inteira, e só vale depois de alguém pedir.

### B4.3 — As alavancas de reestruturação · **PRIMEIRA ALAVANCA ENTREGUE em 21/08**

> **O que entrou:** carência por tranche (célula de entrada ao lado do prazo, que já era editável) e
> o bloco REPERFILAMENTO no `Output`, com serviço antes, serviço depois, alívio por exercício e o
> DSCR nos dois mundos. O veredito diz se ATRAVESSOU o corte do covenant e, quando não atravessa,
> nomeia os caminhos seguintes: prazo maior, haircut pela chave de efeito caixa, dinheiro novo. O
> alívio publicado é piso — o efeito de segunda ordem no revolver não entra no lado "antes". O que
> continua fora: conversão em equity com diluição calculada e new money com custo próprio.

§2.6 do diagnóstico. Quando o `Output` diz DSCR 0,3 e ND/EBITDA 10,8×, a próxima pergunta do mandato
é: **qual reestruturação resolve?** Alongamento, carência, haircut, conversão, new money — o modelo
não tem nenhuma alavanca disso. O `CAPEX FINANCING` foi deliberadamente excluído para o rombo
aparecer (decisão certa); o passo seguinte natural é a alavanca que **fecha o rombo
declaradamente**: uma linha de reperfilamento com prazo e carência editáveis, comparando o antes e o
depois.

Isto não é correção — é o produto seguinte dentro do mesmo arquivo. Fica registrado como a pergunta
que o primeiro comitê vai fazer.

### B4.4 — Os defeitos anotados e pequenos

| | Defeito | Estado |
|---|---|---|
| a | ~~**`fn_conferir_modelagem` conta premissa de sazonalidade como "sem valor".**~~ | **FECHADO pela `0134`** (sessão 55): premissa de `curva_mensal` deixou de contar como sem valor, porque a curva é derivada do documento mensal e não digitada. O caso ruim de verdade ganhou nome próprio, `sazonalidade_sem_curva`, que informa e não bloqueia |
| b | **Linha que sozinha passa do teto de saída** — sem corte mais fino possível | anotado; nenhum documento do book cai nesse caso |
| c | **Rateio de despesa intragrupo que não deixa saldo no balanço** — não há espelho para conferir | limite conhecido da `0124`, sem solução barata |
| d | **Mútuo com sócio** — o par é o contrato com o quotista, que ninguém cruza hoje | limite conhecido da `0123` |
| e | ~~**"Sugerir do realizado"**~~ | **FEITO em 21/08.** As oito saem do próprio balanço e DRE do caso, gravadas com `origem = 'historico'`. `portal/src/lib/premissas-do-realizado.ts`, 25 asserts em `verificar-premissas-do-realizado.mts`, no CI. Duas regras sustentam: **zero não é resposta** (sem a conta, sai o motivo e não um número) e **a base de cada razão é a que o modelo aplica ao projetar** — fornecedor contra custos, o resto contra receita líquida —, senão o dia sugerido não reproduz o saldo de onde saiu |

### B4.5 — A apresentação de crédito (.pptx) · **IMPLEMENTADA em 02–03/10, NÃO APLICADA EM PRODUÇÃO**

> **O que entrou:** terceira saída da rota de export (`?modo=apresentacao`); 120 campos estruturados em `caso_apresentacao_campo` (migration 0205); tela `/casos/[id]/apresentacao` no portal; deck Centro Oeste com todos os capítulos; formatação Prompt Padrão Oria (Teaser). Testada em 14 entidades de 3 mandatos locais (Vertentes, Canastra, v35): 12 geram com sucesso, 2 entidades tipo "GRUPO" recusadas com 409. Mandatos reais grandes não testados (Krauspenhar `33b58a89`). **O que falta:** aplicar migration 0205 em produção, testar com dados reais (casos não-GRUPO), resumo multi-entidade para grupos, merge do branch (sem PR aberto).

**Critério de pronto:** 0205 aplicada em produção e conferida pela sonda, apresentação gerada e endereçável a partir da tela de casos, casos reais grandes (Krauspenhar) com geração bem-sucedida, resumo multi-entidade testado.

---

## 8. B5 — Eficiência: o que a passada da sessão 54 fechou, e o que sobrou

**O valor daquela passada está no que ela NÃO mudou**, e isso poupa a próxima sessão de refazer a
caça. Quatro hipóteses medidas, **três descartadas pela medição**:

| Hipótese | Medição | Veredito |
|---|---|---|
| `fn_normalizar_texto` por (rótulo × termo) em `fn_exigencias_do_caso` | 243 ms → 254 ms | **5% PIOR** — não é o gargalo |
| `linhas_distintas` achatada pelo planejador | 228 ms → 232 ms | 2% pior — o `distinct` já valia |
| Índice ausente em caminho quente | os índices existem | nada faltando |
| Cache de prompt da OpenAI não acertado | sistema estático vem primeiro; `cached_tokens` já é lido | já está certo |

**O que era real virou a `0132`** (sonda de instalação 7,9 ms → 0,5 ms, e **constante** em vez de
crescer com `lote_execucao`).

### O único item de eficiência que sobrou, e por que ele não foi feito

**`fn_recomputar_completude` custa 237 ms e roda uma vez por documento** — trabalho quadrático no
tamanho do lote. Num lote de 38 documentos isso é **<5% do relógio**, porque onde o tempo realmente
vai é nas chamadas à OpenAI, não no Postgres.

Consertar exige **mudar o workflow do n8n e reimportar** — e reimportação é a operação que já
custou duas rodadas de "a correção está no repositório e não na produção". Risco desproporcional ao
ganho.

> **Quando isto passa a valer:** se um lote real passar de ~80 documentos, ou se a medição da rodada
> B1 mostrar o Postgres acima de 15% do relógio. Antes disso, não mexer é a decisão certa — e o
> motivo de estar escrito aqui é para ninguém "descobrir" de novo que é lento e mexer sem medir.

**Medido e saudável:** export de 28 documentos / 1.260 linhas em **450 ms**; `fn_conferir_modelagem`
em **347 ms** (era 9.344 ms antes da `0101`); a sonda quente em **0,5 ms**.

---

## 9. B6 — Operação e processo: aberto, barato, e o que mais assusta

Estes são os itens do §5 do diagnóstico de 11/08 que **ninguém atacou em nove dias**. Nenhum é caro.
Todos protegem contra a classe de falha que este projeto mais teme: a que não tem sintoma.

### B6.1 — O `main` sem proteção · **trivial, e é o de maior risco**

As *rules* foram removidas em 07/08 e o diagnóstico as pediu de volta (item #6, esforço "trivial").
**NÃO CONFERIDO nesta rodada** — os tokens desta sessão não leem configuração de proteção de branch.
O que eu *observei*, e é indício e não prova: PRs sendo mergeados **5 minutos** depois de abertos
(#150: 17:26 → 17:31), enquanto o CI leva ~3,5 minutos. Isso é compatível com "check obrigatório
ausente".

**O que fazer:** *Settings → Rules/Branches*, em `main`: exigir PR, exigir o check **`suítes`**
verde, aprovações em 0 (o projeto tem duas pessoas — exigir aprovação travaria o trabalho sem
adicionar controle).

**Por que importa mais aqui que em outro projeto:** o CI deste repositório não é decoração. Ele
regera os quatro workflows, as três fixtures e o `Supabase/schema.sql` e reprova por `git diff` se o
commitado divergir da fonte. Um merge vermelho não quebra a build — ele deixa o **JSON que o dono
importa no n8n** divergir da fonte que o gera. É exatamente a família de defeito que este projeto
inteiro foi construído para não ter.

### B6.2 — ~~Observabilidade zero~~ · **FECHADA em 21/08** (`0135`)

Item #14 do backlog. O portal tem **8 `console.error`** e nada mais: nenhuma métrica, nenhum alerta.
Existe o `workflow.erros.json` ligado como *Error Workflow* no Intake, que é a metade certa — falha
de execução tem para onde ir.

O que não existe: **documentos/dia, taxa de falha, custo por caso, tempo de lote**. A `0115` grava
tudo isso em `lote_execucao` desde a sessão 50 — o dado está no banco. Falta uma tela e um limite que
avise.

**Executado, e a proposta barata era a certa:** `fn_operacao_lotes` lê `lote_execucao` dos últimos 30
dias. O que mudou em relação à proposta é **onde o veredito mora**: os quatro alertas são decididos
por `fn_operacao_lotes` (`0135`), no banco, e não na tela — repetir a régua em TypeScript criaria
duas réguas sobre a mesma quantidade, e a segunda divergiria no dia em que existisse um segundo
leitor. Os alertas: **cobertura não medida** (o mais importante — não é cobertura baixa, é a guarda
não ter opinado), **documento com falha**, **documento sem medição** e **custo acima de 1,5× a
estimativa daquele lote** (razão contra a própria previsão, não teto em dólar). A cobertura publicada
é **mediana**, e o resumo diz **há quantos dias nada roda**, porque silêncio é estado. 13 asserts em
`Supabase/test/operacao.test.sql`, com contraprova de que 1,4× **não** acende.

### B6.3 — ~~Backup e retenção não declarados~~ · **ESCRITO em 21/08** (`Arquitetura do Sistema/2 Especificação/10`)

Dado de cliente no Supabase, **sem procedimento de recuperação escrito**. `Arquitetura do Sistema/4 Análises e Auditorias/08_RISCOS.md`
menciona o risco; não há runbook. O susto da sessão 36 ("o susto do Supabase, que não era perda de
dado") mostrou que a pergunta aparece sob pressão, que é o pior momento para descobrir a resposta.

**Critério de pronto — atendido pela parte que é de engenharia:** `Arquitetura do Sistema/2 Especificação/10_DADOS_RETENCAO_E_LGPD.md`
escreve onde o dado do cliente mora (inclusive o fato de que **o documento vai à OpenAI**), que hoje
**não há expurgo e isso é escolha por omissão**, que **o schema e o pipeline se remontam do
repositório sozinhos** — logo o que não se recupera de backup é o DADO — e que o acesso é **binário**
hoje. **O que sobra é do dono, e está marcado [A CONFIRMAR]**: região e plano do Supabase, PITR, e
— o único que transforma crença em controle — **executar o teste de restauração** e anotar o tempo.

### B6.4 — Migration aplicada à mão

Ver B0. A `0131` fez a parte que dá para fazer de dentro do produto (declarar o que falta). Automatizar
o apply é escopo de infra e depende de decisão do dono sobre credenciais — fica registrado, sem
proposta, porque propor sem saber a restrição produz plano que não se executa.

### B6.5 — Higiene do repositório · **20 minutos**

**20+ branches `claude/*`** no remoto, quase todas já mergeadas. Elas não fazem mal e fazem ruído:
`git branch -a` deixou de ser legível, e "qual é a branch viva?" passou a ser uma pergunta.

---

## 10. B7 — Bloqueados por dado que o kit básico não coleta

**Não são trabalho, são espera.** Estão aqui para que ninguém os confunda com pendência.

| | Item | O que falta |
|---|---|---|
| 1 | **Tranche em moeda estrangeira** | a MOEDA por tranche — aplicar câmbio sem saber erra ~5× |
| 2 | **Vida útil por classe de imobilizado** | laudo |
| 3 | **Goodwill** | os três blocos de espelho só valem quando houver ágio de verdade num caso |

---

## 11. O que é "projeto fechado"

Uma definição de pronto para o conjunto, para que "fechar o projeto" não seja uma sensação:

- [x] ~~**Os 13 requisitos de `fn_instalacao_conferir()` verdes** no banco de produção~~ (B0) — **20/08**
- [ ] **Uma rodada real completa**, exportada, com o `ACEITE.md` preenchido e os 10 asserts do
      `auditar-xlsx.mts` verdes sobre o arquivo de verdade (B1)
- [ ] **O limiar de cobertura recalibrado** com pontos reais, e o fatiamento conferido em produção (B2)
- [x] ~~**A saída da autonomia escrita em `Arquitetura do Sistema/1 Visão e Doutrina/01`** — A, B ou C — e, se B ou C, o portão
      implementado e travado por suíte~~ (B3) — **21/08**: saída **B**, escrita na seção "Como se
      mede a concordância quando não há rotulagem" de `01_DOUTRINA_DE_AUTONOMIA.md`, implementada
      na `0136` e travada por `Supabase/test/veredito_producao.test.sql`. (A caixa ficou desmarcada
      até 09/09 embora a §6 deste mesmo arquivo já registrasse o critério como atendido — a régua
      dizia que faltava o que o corpo dizia estar feito.)
- [ ] **O `main` protegido** com o check `suítes` obrigatório (B6.1)
- [x] ~~**Backup, retenção e LGPD** escritos em `docs/`~~ (B6.3) — **21/08**; sobram os [A CONFIRMAR] do dono e o teste de restauração
- [x] ~~**Um painel de operação** lendo `lote_execucao`~~ (B6.2) — **21/08**, `0135` (a tela saiu do portal no mesmo dia, por decisão do dono; a leitura é por SQL)
- [ ] As 25 perguntas **ou** a decisão escrita de que 11 bastam (B4.1)

O que fica **deliberadamente fora** desta lista, e a distinção é o ponto: B4.2 (ND/EBITDA por
cenário), B4.3 (alavancas de reestruturação) e B7 não são pendências do projeto — são o **próximo
produto** e a espera por dado de terceiro. Chamá-los de pendência faria a lista nunca acabar, que é
como um roadmap deixa de orientar.

---

## 12. Ordem sugerida de sessões

| Sessão | O quê | Quem | Pré-requisito |
|---|---|---|---|
| ~~agora~~ | ~~B0 (apply)~~ — **feito em 20/08** | dono | — |
| **agora** | **B1 — a rodada real e o aceite** · e, em paralelo, B6.1 (proteger `main`) + B6.5 (podar branches) | dono, ~1h40 | nada |
| **S1** | B2 inteiro: recalibrar cobertura, conferir fatiamento e subtotais, medir custo real | engenharia | B1 |
| ~~**S2**~~ | ~~B3 — implementar a saída escolhida da autonomia~~ — **feito em 21/08** (`0136` mede, `0137` promove sozinha até N2) | engenharia | — |
| ~~**S3**~~ | ~~B6.2 (painel de operação) + B6.3 (backup/LGPD) + B4.4a (a suspeita da sazonalidade)~~ — **feito em 20–21/08** | engenharia | — |
| **S4** | B4.1, se o capítulo 10 chegar ao repositório | engenharia | o arquivo |
| **sob demanda** | B4.2, B4.3 | — | pedido do comitê |

**A primeira linha não é de engenharia** — e é por isso que este mapa começa por ela. O sistema tem
**82 migrations aplicadas** (numeradas até a `0137`), seis suítes e CI verde. Com o B0 fechado, **o que falta para ele valer é
uma hora de execução**, não uma linha de código.

---

## 13. B8 — Fontes oficiais e captação · **PLANEJADO em 13/10/2026**

**O detalhe NÃO mora aqui.** Este arquivo é histórico desde 18/09 (nota do cabeçalho), e repetir as
etapas em dois lugares é o defeito que este mapa já descreve. Elas moram em:

- **o quê e por quê:** `Arquitetura do Sistema/2 Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md`
  (§1–§12 o escopo, §13 as 27 lacunas G1–G27);
- **em que ordem, com que dependência e quando acabou:** `ARQUITETURA_ALVO_E_ROADMAP.md`, fase
  **F2T**, tabela de etapas.

**O resumo, para quem só lê este mapa:**

| Etapa | Destrava | Quem |
|---|---|---|
| 0 — Decisões D12.1–D12.11 e as [A CONFIRMAR] | todo o resto | **dono** |
| 1 — Fundação sem cliente (roteador, leitor fora do n8n, leiautes, precedência, tolerância, duplicidade) | as ondas | engenharia, ∥ F1 |
| 2 — Jurídico e segurança | qualquer coleta automática | dono + jurídico |
| Ondas 1–5 | as 24 reconciliações (S, E, L, C) | engenharia, depois da F1 (e F4/F6 onde a tabela diz) |
| Captação 4–6 | o caso que se abastece sozinho | engenharia, depois da etapa 2 |

**Critério de pronto do B8:** as cinco ondas aceitas em 3 casos reais cada, e um mandato-piloto
abastecido sem envio manual das fontes do canal B. Até lá, B8 **não** entra na definição de "projeto
fechado" (§11): é o próximo produto, pelo mesmo critério que deixou B4.2, B4.3 e B7 fora dela.
