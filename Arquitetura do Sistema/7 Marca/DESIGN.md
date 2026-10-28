---
name: Portal Oria — Tratamento de Dados Financeiros
description: O mundo visual da Oria Partners traduzido de página de marketing para mesa de conferência.
colors:
  papel: "#f6f4ef"
  folha: "#fcfbf8"
  tinta: "#11161d"
  tinta-secundaria: "#6e6a62"
  linha: "#d2cdc1"
  acento: "#b6482f"
  risco: "#78223a"
  alerta: "#805a1e"
  ok: "#3a643c"
  info: "#2f5b6f"
  serie: "#563965"
typography:
  documento:
    fontFamily: "Fraunces, ui-serif, Georgia, serif"
    fontSize: "1.5rem"
    fontWeight: 500
    lineHeight: 1.2
    letterSpacing: "-0.025em"
  corpo:
    fontFamily: "Inter Tight, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.875rem"
    fontWeight: 400
    lineHeight: 1.5
    letterSpacing: "normal"
  rotulo-secao:
    fontFamily: "Inter Tight, ui-sans-serif, system-ui, sans-serif"
    fontSize: "0.8125rem"
    fontWeight: 600
    lineHeight: 1.3
    letterSpacing: "0.025em"
  dado:
    fontFamily: "JetBrains Mono, ui-monospace, monospace"
    fontSize: "1.5rem"
    fontWeight: 600
    lineHeight: 1.2
    letterSpacing: "-0.025em"
rounded:
  sm: "4px"
  md: "6px"
  lg: "8px"
  full: "9999px"
spacing:
  xs: "6px"
  sm: "8px"
  md: "16px"
  lg: "32px"
components:
  button-primary:
    backgroundColor: "{colors.tinta}"
    textColor: "{colors.papel}"
    rounded: "{rounded.md}"
    padding: "6px 12px"
  button-primary-hover:
    backgroundColor: "#1e242c"
    textColor: "{colors.papel}"
  button-secondary:
    backgroundColor: "{colors.folha}"
    textColor: "#1e242c"
    rounded: "{rounded.md}"
    padding: "6px 12px"
  button-approve:
    backgroundColor: "{colors.ok}"
    textColor: "{colors.papel}"
    rounded: "{rounded.md}"
    padding: "6px 12px"
  chip:
    backgroundColor: "#efe4d2"
    textColor: "#6b4c19"
    rounded: "{rounded.full}"
    padding: "2px 8px"
  card:
    backgroundColor: "{colors.folha}"
    textColor: "{colors.tinta}"
    rounded: "{rounded.lg}"
    padding: "16px"
  input:
    backgroundColor: "{colors.folha}"
    textColor: "{colors.tinta}"
    rounded: "{rounded.md}"
    padding: "8px 12px"
---

# Design System: Portal Oria — Tratamento de Dados Financeiros

Este arquivo governa `portal/`. Ele **não** governa o entregável em Excel
(`portal/src/lib/oria-marca.ts` + `export-estilo.ts`), que segue grafite/ciano
por decisão registrada — ver *Do's and Don'ts*.

## Overview

O mundo é o da própria Oria Partners, medido no site em produção e trazido
para dentro da ferramenta: **papel creme, tinta quase-preta, um acento
terracota**. O que muda da página de marketing para cá não é a paleta — é o
regime. No site, o design é o produto e pode falar alto. Aqui o usuário está
numa tarefa: conferir linha por linha se a máquina leu o balanço direito, por
horas. Expressão que atrapalha a tarefa é defeito.

Disso saem as três decisões que estruturam tudo:

**A tinta é a ação, o terracota é a identidade.** No site, `--accent` e
`--destructive` são a mesma cor, e `--primary` é a tinta. Copiar isso para um
portal com "excluir mandato" pintaria a marca com a cor do perigo. Então o
botão primário é tinta (como no site), o terracota fica com seleção, foco,
item ativo e link, e o risco ganhou um oxblood próprio.

**Nenhuma superfície é branca.** Mesa (`papel`), folha (`folha`) e faixa de
navegação (`tinta-50`) são três temperaturas do mesmo creme. Branco puro ao
lado de creme lê como papel de outro lote.

**Cor nunca carrega significado sozinha.** Todo estado é cor **mais** palavra.
A regra veio do entregável impresso e vale mais na tela: cerca de 8% dos homens
que abrem este portal não distinguem verde de vermelho.

## Colors

Estratégia: **Restrained** — neutros quentes mais um acento, que é o piso para
superfície de trabalho. O terracota nunca decora: ele marca onde você está e o
que está selecionado.

### Primary

`acento` **#b6482f** — terracota. Seleção corrente, anel de foco, item ativo da
navegação, link. Medido em `hsl(11 59% 45%)` no site.
Rampa: `700 #93381f` · `600 #b6482f` · `100 #f2ddd6` · `50 #f9eeea`.

### Secondary

`tinta` **#11161d** — a ação primária e todo o texto forte. É o `--primary` do
site, não uma invenção nossa. Rampa completa de 900 a 50, descendo em direção
ao papel e não ao cinza: os degraus claros carregam o amarelo da mesa.

### Tertiary

Cinco famílias de estado, geradas com saturação alta nas faixas claras porque
sobre creme um tom claro lavado vira o próprio papel:

| Família | 700 | Significa |
|---|---|---|
| `risco` | #78223a | divergência, bloqueio, erro, ação destrutiva |
| `alerta` | #805a1e | pendente, faltante, aguardando |
| `ok` | #3a643c | conferido, aceito, completo |
| `info` | #2f5b6f | nota do sistema, subtotal — nem bom nem ruim |
| `serie` | #563965 | categoria de linha derivada (taxonomia, não estado) |

### Neutral

`papel #f6f4ef` (mesa) · `folha #fcfbf8` (superfície de dado) ·
`tinta-50 #f1eee6` (faixa de navegação) · `linha #d2cdc1` (fio).

### Named Rules

- **A regra do acento reservado.** Terracota só aparece em foco, seleção, item
  ativo e link. Nunca em botão de salvar, nunca em preenchimento decorativo.
- **A regra dos 28 graus.** O risco vive a pelo menos 28° de matiz do acento e
  mais escuro que ele. Sem essa distância, "excluir" e "a marca" viram a mesma
  mancha vermelha na periferia da visão.
- **A regra do par medido.** Nenhum par texto/preenchimento entra sem ser
  medido. Todos os que o código usa passam AA; o pior é 5,39:1.
- **`tinta-400` é o piso do texto** (3,62:1). Abaixo dele só fio, ícone
  desativado e marca-d'água. Placeholder é `tinta-500`.

## Typography

Três famílias, todas do site, todas auto-hospedadas por `next/font`.

### Hierarchy

| Papel | Família | Onde |
|---|---|---|
| `documento` | Fraunces 500, -0.025em | Nome do mandato; título da tela de abrir mandato |
| `corpo` | Inter Tight 400/500/600 | **Toda** a interface: rótulo, botão, chip, célula, prosa |
| `rotulo-secao` | Inter Tight 600, versalete, +0.025em | Título de seção (`.titulo-secao`) |
| `dado` | JetBrains Mono 400/600, tabular | Valor monetário, contagem, indicador, nome de arquivo |

Escala em rem fixa, nunca fluida: o analista lê em DPI constante e um `h1` que
encolhe dentro de um painel piora, não melhora.

### Named Rules

- **Fraunces nomeia documento, não interface.** Serifa de display em rótulo,
  botão, chip ou célula é o erro clássico de UI de produto. Ela toca em dois
  lugares no portal inteiro.
- **Mono só onde há medição.** Número, contagem, identificador, proveniência.
  Mono em texto corrido para parecer técnico é fantasia, não tipografia.
- **`tabular-nums` é global** (`html`), porque coluna de dinheiro que dança
  entre linhas custa tempo de conferência.

## Layout

Densidade a serviço da conferência. Tabela pode passar de 120ch; prosa fica em
65–75ch. Comportamento responsivo é **estrutural** — a barra lateral recolhe, a
tabela vira lista —, nunca tipografia fluida.

Regra de navegação herdada e mantida: **nenhuma função da barra lateral se
repete no conteúdo.**

## Elevation & Depth

Elevação mínima (o vidro do casco e da folha leva `--vidro-sombra`, difusa, só para
destacar a superfície da imagem; dentro da folha vale a regra abaixo). O produto é dado; sombra demais compete com o número.

### Shadow Vocabulary

- `--sombra-carta` `0 1px 2px 0 rgb(17 22 29 / .05), 0 1px 3px 0 rgb(17 22 29 / .07)`
- `--sombra-topo` `0 1px 0 0 rgb(17 22 29 / .07)`

Ambas tingidas da tinta. Sombra cinza-neutro sobre creme lê como sujeira.

### Named Rules

- **Separação vem de fio e espaço, não de sombra.** A sombra só distingue a
  folha da mesa; hierarquia dentro da folha é espaçamento.

## Shapes

`4px` campo compacto · `6px` botão e input · `8px` carta e bloco de pendência ·
`full` chip. Sem cantos vivos, sem raio grande: raio grande infantiliza tabela
de dado.

## Components

### Buttons

Um primário por tela. `btn-primario` (tinta), `btn-secundario` (folha com fio),
`btn-aprovar` (`ok-700` — reservado ao aceite que leva dado para a base),
`btn-discreto` (sem preenchimento). Todos com `disabled:opacity-50` e
`cursor-not-allowed`.

### Chips

`.chip` é pílula de `text-xs font-medium`, sempre `bg-<família>-100` com
`text-<família>-800/900`. **Todo chip carrega a palavra do estado.**

### Linha pendente de aceite

O componente assinatura do produto. Linha extraída que ainda não foi aceita
**nunca some e nunca vira fato**: âmbar + itálico + a palavra — princípio de
`Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`. A linha inteira
em itálico e `alerta-900` (`#573d14`); o valor continua em JetBrains Mono,
alinhado à direita e com `tabular-nums`; o chip "pendente de aceite"
(`alerta-100` / `alerta-800`) volta a `font-style: normal`, para a palavra do
estado não ficar em itálico com o resto. A linha já aceita é tipografia
normal com o chip "aceita" (`ok-100` / `ok-800`).

(Esta especificação morava só no `.impeccable/design.json`, removido em
24/09/2026 com a skill impeccable; foi trazida para cá para não se perder. O
portal a implementa EM PARTE: a tabela de linhas da tela do documento
(`portal/src/app/casos/[id]/documentos/[docId]/page.tsx`) já mostra o chip
"pendente"/"aceito", mas com `alerta-700`/`ok-700` em vez de `-800`, sem a linha
em itálico e com a palavra "pendente" em vez de "pendente de aceite". Quem for
alinhar ajusta esse chip; não cria um segundo. No Excel a linha pendente sai em
itálico âmbar, em `portal/src/lib/export.ts`, na aba de linhas extraídas.)

### Cards / Containers

`.carta` — `folha`, fio `tinta-200`, raio 8px, `--sombra-carta`. Carta dentro
de carta é proibido.

### Inputs / Fields

Fio `tinta-200` (ou `tinta-300` em campo compacto), fundo `folha`, raio 6px.
Foco: contorno terracota de 2px com deslocamento de 2px — nunca só mudança de
cor de borda.

### Navigation

Barra lateral retrátil e **flutuante** (decisão do dono, 28/10/2026): solta a
12px das bordas, `rounded-2xl`, `sticky top-3`, altura `100dvh - 24px`, em vidro
escuro (ver *Vidro e imagem de fundo*). A marca mora no topo dela — o sextante
original (sem recolorir; só um `drop-shadow` azul) e "ORIA / DIGITAL" em
versalete. Item em `vidro-texto` (#ece8df), item ativo com preenchimento claro a
10% e uma barra de 2px à esquerda em terracota claro (#e8937c); "Novo mandato" é
o único botão claro (creme, texto escuro). Recolhida, vira trilho de ícones com o
mesmo vidro. No lugar do cabeçalho de 57px há uma barra de topo flutuante, do
mesmo vidro, com a trilha e o menu da conta. Estado (recolhida, seção aberta)
mora no navegador.

Desde o redesenho (27/10/2026, `REDESENHO_DO_PORTAL.md`): ícones de traço
próprios no lugar de caracteres soltos; recolhida, a barra vira trilho de
ícones com o nome em `aria-label`; os mandatos da barra são só os recentes.
Dentro do mandato, abas fixas sublinhadas pelo acento, com régua de etapas
(Recebimento → Conferência → Modelagem → Entrega) no cabeçalho.

**Celular (< 640px, Fase 4):** a barra lateral e o trilho somem e entram cinco
destinos numa **barra inferior** fixa e flutuante, no mesmo vidro do casco: Início ·
Mandatos · Busca · Novo · Mais (`barra-inferior.tsx`). "Mais" abre uma folha por
portal com os recentes e a Administração. Rótulos em `vidro-texto` (9,6:1), nunca
`vidro-suave`, porque texto de 11px não tem folga em 4,71:1; o destino ativo leva
barra de 2px terracota claro no topo, fundo +10% e `aria-current`. A barra respeita
`env(safe-area-inset-bottom)` (`max` com 12px), e o conteúdo ganha o padding
equivalente. As abas do mandato rolam na horizontal e centralizam a ativa.

**Modo discrição:** botão com `aria-pressed` ao lado da busca; liga `data-discricao`
no `<html>` (script inline no `<head>`, sem flash) e o CSS aplica `blur(6px)` em
`.valor-sensivel`. Hover e foco **não** revelam — o objetivo é sigilo. O aviso
"Modo discrição ligado" é texto no botão. Marca valor financeiro (colunas de valor,
Modelagem, Custos), não contagens. **Limite:** é proteção visual; o texto segue no
DOM (leitor de tela, Ctrl+F, copiar-tudo, Excel exportado não são cobertos — leitor
de tela não é silenciado de propósito).

### Vidro e imagem de fundo

**Esta seção substitui a regra anterior "a imagem nunca fica atrás de tabela ou
de número"** (decisão do dono, 28/10/2026). A regra nova:

- **A imagem da marca cobre a tela inteira, fixa**, em toda tela autenticada e no
  login (`FundoDaMarca`: `next/image` `fill`, `priority`, `fixed inset-0 -z-10`).
  Nunca `background-attachment: fixed` (quebra no iOS). Dois arquivos estáticos
  em `public/marca/` (960px, 94 KB; 1678px, 230 KB) escolhidos por um `loader`
  próprio: celular baixa 59% menos. O `body` é `#0d0f13` até a imagem chegar.
- **Véu sobre a imagem**: nas telas do app, `rgba(10,12,16,.62)` no topo a `.78`
  embaixo; no login, `.15` à esquerda (a placa "ORIA DIGITAL" tem de ser lida) a
  `.70` à direita.
- **Casco (vidro escuro)** — barra lateral, barra de topo, cartão do login:
  `rgba(18,21,27,.64)`, `blur(18px) saturate(140%)`, borda `rgba(255,255,255,.09)`,
  texto `#ece8df`, secundário `#a39d92`. O cartão do login sobe para `.80`.
- **Folha (vidro creme)** — **todo o conteúdo** de todas as telas, numa única
  folha: `rgba(252,251,248,.94)`, **sem** `backdrop-filter` (ver abaixo), borda `rgba(255,255,255,.55)`.
  As 13 telas usam texto escuro desenhado para superfície creme; a folha mantém
  todo número sobre >= 94% de creme e a imagem aparece ao redor e só de leve por
  baixo. **Número nunca fica diretamente sobre a imagem nem sobre o casco.**
  A folha **não** leva `backdrop-filter`: pela especificação ele vira bloco de
  contenção dos descendentes `fixed`, e os diálogos de Fechar/Excluir e o "Tudo
  pronto" moram dentro dela (revisão do PR #265). Os diálogos de Fechar/Excluir
  também vão para o `<body>` por portal, contra qualquer outro contêiner.
- **Fallbacks**: `prefers-reduced-transparency: reduce` → superfícies sólidas
  (casco `#161a20`, folha `#fcfbf8`, sem filtro); sem `backdrop-filter` → casco
  `.94` e folha `.98`. Os valores moram em `globals.css` (`--vidro-*`,
  `.vidro-casco`, `.vidro-folha`), nunca repetidos em `.tsx`.
- **Foco sobre o casco** é terracota claro `#e8937c` (o `#b6482f` dá ~2,6:1 ali);
  o menu da conta continua creme e usa o anel escuro.

**Medições (28/10/2026)**, contra o pior fundo possível — o pixel mais claro da
foto (255,255,236) sob o véu de `.62` — e contra o mais escuro (preto):

| Par | Razão |
|---|---|
| `#ece8df` sobre o casco, pior caso | 9,6:1 |
| `#a39d92` sobre o casco, pior caso | 4,71:1 (com `.58` eram 4,38 — por isso `.64`) |
| `#a39d92` sobre o casco, véu `.78` | 5,5:1 |
| terracota `#e8937c` sobre o casco, pior caso | 5,4:1 |
| `#ece8df` sobre o item ativo (+10% branco), pior caso | 7,1:1 |
| `#a39d92` sobre o cartão do login (`.80`, véu `.45`, pixel mais claro) | 4,89:1 |
| borda de campo `white/40` sobre o cartão do login | 3,47:1 |
| `tinta-900` sobre a folha, pior caso | 14,8:1 |
| `tinta-500` sobre a folha `.92`: sobre pixel claro / sobre preto | 4,69:1 / **4,37:1** |
| `tinta-500` sobre a folha `.94`, sobre preto | 4,57:1 |

Por isso a folha é `.94` e não `.92`: `tinta-500` valia 5,20:1 sobre a `folha`
sólida e, a `.92`, caía abaixo de 4,5:1 onde a foto é preta — o caso comum, porque
a foto é escura na maior parte.

**O sextante sobre o casco** leva `.marca-neon` (três sombras azuis: núcleo, halo e
aura). A arte original é azul-marinho de traço escuro, como a placa da foto, e
quase sumia no vidro escuro com um brilho só; as sombras reproduzem a luz de
fundo da placa sem tocar no arquivo.

### Superfícies do navegador

Seleção em `acento-100`, cursor em `acento-600`, marcador de lista em
`tinta-400`, barra de rolagem `thin` em `tinta-200`, sublinhado com
`text-underline-offset: 0.2em`. Nenhum comportamento é reinventado — só
recolorido.

## Motion

Uma curva: `cubic-bezier(0.22, 1, 0.36, 1)` (ease-out-quint). Transições de
estado em `transition-colors`. A abertura do painel toca **uma vez por sessão**
do navegador, qualquer gesto corta, e `prefers-reduced-motion` desliga tudo sem
versão reduzida de consolo. Nada anima `width`, `top` ou `left`.

## Do's and Don'ts

### Do:

- Escreva estado como cor **mais** palavra, sempre.
- Meça o par texto/fundo antes de adicionar um tom.
- Use `folha` para superfície de dado e `papel` para a mesa.
- Deixe Fraunces nomear documento e Mono medir número.
- Prefira fio e espaço a sombra para separar.

### Don't:

- Não pinte ação primária de terracota. Ação primária é tinta.
- Não use branco puro em superfície nenhuma.
- Não ponha serifa de display em rótulo, botão, chip ou célula.
- Não aninhe cartas.
- Não mexa em `oria-marca.ts` ao mudar cor de tela. **O Excel diverge de
  propósito:** modelo de crédito é lido em impressão preto e branco por comitê,
  e a gramática de cor de fonte de lá (azul = digitado, preto = calculado,
  verde = outra aba) é convenção de mercado.
