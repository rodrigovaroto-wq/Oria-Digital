# Relatório de melhorias: Business Plan Oria Digital, v2 (14 slides) → v3 (13 slides)

**Resumo:** o deck passou de 14 para 13 slides. O slide das "nove análises" foi fundido no slide dos agentes, que virou um mapa mental. Os outros slides foram editados por partes, sem reconstrução. Paleta, tipografia, sextante, cartões e rodapé ficaram iguais.

Decisões do dono que guiaram o trabalho: [`00_BRIEFING.md`](00_BRIEFING.md).

## 1. Mapa de slides

| Original | Final | O que mudou |
|---|---|---|
| 1 Capa | 1 | Nada |
| 2 O problema | 2 | "recuperação (extra) judicial" → "recuperação judicial e extrajudicial" |
| 3 Consequências | 3 | "Meses perdidos" e um bloco **"COMO RESOLVEMOS"** em cada card. O problema já anuncia a resposta |
| 4 O negócio | 4 | **R$ 2,7 tri → R$ 2,8 tri de saldo em set/2026**, conferido no Banco Central |
| 5 Como funciona | 5 | Título novo e um bloco **"RESULTADO"** em cada etapa |
| 6 Dados | 6 | "principais fontes" (a lista é um resumo) e uma frase de fecho no card escuro |
| 7 Nove análises | — | **Removido.** O conteúdo foi para o slide 8 |
| 8 O que o cliente ganha | 7 | Tirei o texto solto sobreposto, revisei o exemplo (despesa de 15% para 10%), troquei os rótulos do gráfico e saiu a citação "McKinsey" |
| 9 Estratégia de IA | 8 | **Mapa mental:** Orquestrador → 8 agentes (1 a 4 à esquerda, 5 a 8 à direita) → 28 análises, cada uma com fonte no repositório |
| 10 Para levar adiante | 9 | O pedido ao sócio com os 4 pilares, o fim da contradição sobre o primeiro cliente e o prazo de 3 a 6 meses |
| 11 Anexo 1 | 10 | Uma palavra no rodapé |
| 12–14 Anexo 2 | 11–13 | Selos legíveis, painel "Onde os blocos pesam" nos slides 11 e 13 e uma palavra a menos no título do 11 |

## 2. Correções de fato (prioridade 1)

1. **Texto solto sobre os cards (final 7).** A frase "com um nível de excelência e exigência extremamente alto" cobria números. A checagem de render media 4 palavras sobrepostas, e agora mede zero.
2. **Ganho anual somado com ganho único (final 7).** O gráfico somava R$ 60 mi "por ano". Agora os rótulos são "R$ 10 mi / ano", "R$ 20 mi / ano" e "R$ 20 mi" (único, em verde).
3. **Despesa de 15% → 10% (final 7)**, por sua decisão. O exemplo agora é 10% de R$ 200 mi = R$ 20 mi por ano, com R$ 30 mi por ano de ganho recorrente. As notas acompanham.
4. **"Fonte: McKinsey."** saiu, por sua decisão. No lugar entrou a premissa do exemplo: empresa com R$ 500 mi de dívida e R$ 200 mi de custos operacionais por ano.
5. **Crédito a empresas (final 4).** Os R$ 2,7 tri eram de **agosto** (relatório do BC de 29/09/2026). O relatório de 29/10/2026 traz **R$ 2,8 trilhões em setembro**. O slide passou a dizer "R$ 2,8 tri · de saldo em set/2026", e a fonte virou "Banco Central (out/2026)".
6. **Prazo de 6 a 12 meses nas notas** contra 3 a 6 meses no slide: corrigido para 3 a 6.
7. **"O primeiro cliente já existe"** contradizia a linha do tempo. Agora o texto diz "O método já funciona na Oria Partners".
8. **Análises apresentadas como prontas que ainda não existem.** O antigo slide 7 listava como prontas Valuation, Recuperação por credor, Simulação de propostas e Comparativo setorial, que estão em 0% no `STATUS_POR_ETAPA_2026-11-11.md`. No mapa mental elas aparecem como "em construção".

## 3. Narrativa e estrutura

- **O motor era descrito três vezes sem ligação entre as descrições:** 5 etapas (slide 5), 9 análises (slide 7) e 8 agentes (slide 9). Agora fica assim:
  - O slide 5 mostra o fluxo, e cada etapa diz o que entrega ("RESULTADO").
  - O slide 8 mostra quem faz o quê: cada agente com as análises dele. Todo ramo é preenchido, e a bolinha diz o status: ● já existe, ○ em construção.
  - A mensagem do slide removido ("o especialista escolhe a saída que preserva mais valor") foi para a linha de supervisão.
- **O mapa mental mostra o que já existe e não aparecia antes:** reconciliações, mútuos e intragrupo, mapa da dívida, capacidade de pagamento, capital de giro, três cenários e o Excel em fórmula viva. As 28 análises vêm do código e do `STATUS_POR_ETAPA_2026-11-11.md` (14 já existem e 14 estão em construção). A fonte de cada ramo (arquivo ou etapa do plano) está comentada na lista `AGENTES` em `4_scripts/rodada5.py`. Exemplos: "3 cenários: Base, Cliente e Stress" (`modelo-institucional.ts:96`), "Waterfall de credores (Lei 11.101)" (etapas 12.1 a 12.3), "Motor: 7 fórmulas e 89 premissas" (etapas 6.1 e 6.2).
- **Pedido ao sócio (final 9):** "O QUE BUSCAMOS NO SÓCIO" traz os quatro pilares na sua ordem: Direção estratégica, Time, Infraestrutura segura para desenvolvimento e Banco de dados.
- **Títulos que viraram conclusão:** slides 5, 7, 8 e 9. "direto" saiu do título do slide 11.

## 4. Direção de arte

Os elementos novos são cópias de elementos que já existiam no deck: o divisor do slide 4, os rótulos laranja, os números grandes, as elipses e badges do slide dos agentes e as curvas cinza.

- **Cards preenchidos com conteúdo que tem função:**
  - "COMO RESOLVEMOS" no slide 3;
  - "RESULTADO" no slide 5;
  - "principais fontes" e a frase de fecho no slide 6;
  - "Onde os blocos pesam" nos slides 11 e 13. O painel é contado direto dos selos de cada slide (5/4/5/5 e 2/3/2/6, conferidos pelo revisor).
- **Mapa mental com dois lados:**
  - O Orquestrador fica no centro, os agentes 1 a 4 à direita e os 5 a 8 à esquerda, no sentido horário como no original.
  - Todas as análises aparecem como pílula branca. A bolinha diz o status: ● já existe, ○ em construção.
- **Acabamento:**
  - margem do antigo slide 7;
  - selos dos anexos de 7 para 8 pt, com o contraste do "RISCO" passando de 3,1:1 para 5,1:1;
  - rótulos do slide 9 com o espaçamento do deck;
  - títulos dos pilares com a mesma linha de base;
  - setas centradas;
  - rótulos do gráfico sem quebra de linha;
  - raio de canto dos painéis igual ao dos cards.

## 5. Para você validar

| # | Questão | Situação |
|---|---|---|
| 1 | **Status das 28 análises (final 8)** | Veio do código e do plano de execução. Confira se você quer incluir as funcionalidades novas que estão sendo adicionadas. É só ampliar a lista `AGENTES` em `4_scripts/rodada5.py` |
| 2 | **Slide de modelo de negócio** | Não entrou. A prévia com valores fictícios está em `2_renders/previas_rodada4/`, aguardando você e seu sócio |
| 3 | **"Mais de 30 fontes" (final 5)** | Mantido, por sua decisão. O slide 6 agora diz "principais fontes" |
| 4 | **Abrir no PowerPoint** | Conferir principalmente o gráfico do slide 7 e o mapa mental do slide 8 |

## 6. Apontado e não aplicado

| Ponto | Motivo |
|---|---|
| Barra "R$ 20 mi" (única) ao lado das barras "/ ano", no gráfico do slide 7 | Decisão sua. A diferença está no rótulo e na cor |
| Cards 1 e 6 do anexo 1 (final 10) com metade vazia | O card 3 tem 8 itens e não sobra espaço para um elemento comum aos seis |
| O painel de impacto não aparece no final 12 | Os 15 itens dos blocos 3 e 4 ocupam o slide inteiro. O título do 12 já traz as contagens |
| Cards escuros do final 4 com alturas de texto diferentes | Já era assim no original |
| Número da página na capa | Vem do layout do original |

## 7. Auditoria de valor do slide 8

Pedido do dono: tirar as métricas soltas e escrever cada ramo **como uma entrega**, com nome de etapa e nunca frase corrida (certo: "Capacidade de pagamento em fórmula"; errado: "Quanto de dívida a empresa aguenta"). A evidência de cada ramo está comentada em `4_scripts/rodada5.py`.

**Mantidos como estavam, por decisão do dono:**
- Duplicata barrada por fingerprint
- Capacidade de pagamento em fórmula
- Liquidez de 13 semanas
- Waterfall de credores (Lei 11.101)
- Capital de giro: NCG e ciclo

**Reescritos:**

| Agente | Antes | Depois | Por que mudou |
|---|---|---|---|
| Captador | Leitura de 4 formatos de arquivo | Leitura de documentos sem digitação | "4 formatos" não diz nada a quem decide |
| Captador | Kit do mandato: o que chegou e falta | Controle de documentos pendentes | Tirei o nome interno ("kit") |
| Captador | SPED, ECD, ECF, NF-e e eSocial | Coleta de SPED, ECD e NF-e na fonte | A lista de siglas virou uma entrega |
| Conferidor | Balanço, caixa e receita batidos | Conferência de balanço, caixa e DRE | Formato de entrega |
| Conferidor | Mútuos cruzados entre as empresas | Conciliação de mútuos do grupo | Formato de entrega |
| Conferidor | Pendência vira pergunta ao cliente | Perguntas ao cliente sobre lacunas | Era uma frase, virou uma entrega |
| Conferidor | Combinado do grupo sem intragrupo | Consolidação sem dupla contagem | Diz o risco que evita |
| Mercado | IPCA e índices do BC e do IBGE | Projeção com IPCA e Selic do Focus | Dado solto virou uso. Conferido: os índices alimentam as premissas de inflação e juro do modelo (`export/route.ts:200`) |
| Mercado | Juro de cada contrato vs. BC | Juro por contrato vs. Banco Central | Escrita completa |
| Risco | Índices, tendências e sinais | Sinais de deterioração financeira | "Índices" era vago |
| Risco | Processos, protestos e bureau | Mapeamento de processos e bureau | Formato de entrega |
| Risco | Scorecard de risco Oria | Nota de risco para o comitê | O nome interno virou o uso |
| Dívida | Mapa da dívida lido do cliente | Mapa da dívida por vencimento | Diz como a dívida fica organizada |
| Estrategista | 3 cenários: Base, Cliente e Stress | Plano em 3 cenários, com stress | Os nomes dos cenários são internos |
| Estrategista | Motor: 7 fórmulas e 89 premissas | Recálculo automático das premissas | **Métrica solta, removida.** "7 e 89" não significam nada para quem decide |
| Estrategista | Carência, haircut e new money | Simulação de propostas aos credores | Jargão virou entrega |
| Entregas | Excel do comitê: 14 abas em fórmula | Modelo do comitê auditável em Excel | **Métrica solta, removida.** "14 abas" não é valor; ser auditável é |
| Entregas | Excel de dados desde a ingestão | Base de dados conferível no 1º dia | Diz o ganho de tempo |
| Entregas | Apresentação de crédito em .pptx | Apresentação de crédito pronta | O formato do arquivo não importa |

Os números técnicos (4 formatos, 14 abas, 89 premissas) continuam nas **notas do apresentador**, para responder se o sócio perguntar.
