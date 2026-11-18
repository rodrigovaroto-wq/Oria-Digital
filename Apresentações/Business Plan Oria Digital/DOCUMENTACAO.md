# Business Plan Oria Digital: documentação da versão final

Este documento reúne tudo o que é preciso para entender, apresentar, manter ou refazer o deck `Business_Plan_Oria_Digital.pptx` (13 slides, 16:9, 13,33" × 7,5"). **Esta é a única versão.** Qualquer mudança futura parte dela.

## 1. Para quem e para quê

| Item | Definição |
|---|---|
| Público | Um potencial **sócio investidor** |
| Formato | **Ao vivo**, conduzido pelo dono. As notas do apresentador sustentam a fala |
| O que pedimos | Mecanismos para desenvolver o projeto, e não principalmente dinheiro. Na ordem: **direção estratégica, time de especialistas, infraestrutura segura para desenvolvimento, banco de dados** |
| Prazo | Primeiro cliente fora da Oria Partners em **3 a 6 meses** |
| Mensagem central | O método já funciona na Oria Partners. Metade das análises já existe; a outra metade é o que construímos com o sócio |

## 2. Estrutura (13 slides)

| # | Seção | Título | Função na narrativa |
|---|---|---|---|
| 1 | Capa | Oria Digital: visão 360° da empresa em poucos dias, não em meses | Promessa |
| 2 | 1 · O problema | Decisões de milhões são tomadas com números que ninguém conferiu | Dor e tamanho do que está em jogo |
| 3 | 2 · As consequências | O trabalho manual custa tempo, credibilidade e dinheiro | 4 dores, com a dor resolvida em cada uma |
| 4 | 3 · O negócio e para quem | Do caos de documentos à decisão em poucos dias | Solução, diferencial, 4 clientes e o tamanho de cada mercado |
| 5 | 4 · Como funciona | Do documento ao diagnóstico, com a prova de cada número | 5 etapas e o que cada uma muda para o cliente |
| 6 | 5 · Os dados que ele captura | Dados da empresa e do mercado, cruzados em uma base única | Fontes micro e macro, e o que o cruzamento revela |
| 7 | 6 · O que o cliente ganha | Menos custo desnecessário, mais dívida amortizada | Exemplo ilustrativo em R$ |
| 8 | 7 · A estratégia de IA | Oito agentes de IA dividem o diagnóstico, e o Especialista Oria decide | Mapa mental: Orquestrador → 8 agentes → 28 ramos, com o status de cada um |
| 9 | 8 · Para levar adiante | Quatro pilares levam o Oria Digital do método validado ao mercado | Linha do tempo e "O QUE BUSCAMOS" |
| 10 | Anexo 1 | 6 blocos e 31 frentes de diligência | Mapa da diligência |
| 11–13 | Anexo 2 (1/3 a 3/3) | Blocos 1–2, 3–4 e 5–6 | Cada frente com a área de impacto e a alavanca de valor |

## 3. Dados e fontes

| Slide | Dado | Fonte e período | Situação |
|---|---|---|---|
| 2 | R$ 18,9 bi em dívidas renegociadas nas recuperações extrajudiciais de 2025 | OBRE (out/2026) | Confirmado pelo dono |
| 2, 4 | "3 meses" para montar os números à mão | Experiência da Oria Partners | Sem fonte externa |
| 4 | 2.466 empresas em recuperação em 2025 | Serasa Experian (abr/2026) | Confirmado pelo dono |
| 4 | 1.581 transações de M&A em 2025 | KPMG 4T25 | Confirmado pelo dono |
| 4 | **R$ 2,8 tri de crédito PJ em set/2026** | Banco Central, Estatísticas Monetárias e de Crédito publicadas em 29/10/2026: *"O estoque total das operações de crédito do SFN somou R$7,4 trilhões em setembro […] somando R$2,8 trilhões e R$4,7 trilhões"* (pessoas jurídicas e físicas). Em agosto eram R$ 2,7 tri | **Conferido na fonte** |
| 4 | R$ 56 bi captados por FIDCs em 2026 | Anbima (out/2026) | Confirmado pelo dono |
| 5 | "mais de 30 fontes" | O slide 6 mostra só as principais | Mantido por decisão do dono |

**Exemplo do slide 7.** É ilustrativo, e o slide diz isso duas vezes. A empresa tem R$ 500 mi de dívida e R$ 200 mi de custos operacionais por ano.

| Alavanca | Conta | Natureza |
|---|---|---|
| Juro acima do mercado | 2 p.p. × R$ 500 mi = **R$ 10 mi / ano** | Recorrente |
| Despesa acima do setor | 10% × R$ 200 mi = **R$ 20 mi / ano** | Recorrente |
| Crédito tributário | **R$ 20 mi**, recuperados uma vez e usados para amortizar dívida | Único (barra verde, sem "/ ano") |

O total é de R$ 30 mi por ano recorrentes, mais R$ 20 mi uma vez. Nenhuma fonte externa é citada: a citação "McKinsey" foi retirada por decisão do dono.

**Anexos.** As contagens dos títulos batem com os selos de cada frente:
- slide 10: 3 + 6 + 8 + 7 + 4 + 3 = 31 frentes;
- slide 11: 5 com efeito no EBITDA;
- slide 12: 10 em risco e 10 em caixa;
- slide 13: 6 em risco.

## 4. Slide 8: os 28 ramos e a evidência de cada um

A bolinha cheia (●) quer dizer que o ramo já existe no sistema hoje, e a vazada (○) que está em construção. O badge do agente segue a mesma regra: cheio indica agente em operação. Hoje há **14 ramos que já existem e 14 em construção**. O status vem do código deste repositório e do retrato de 11/11/2026 (`STATUS_POR_ETAPA_2026-11-11.md`, hoje só no histórico do git). Ao atualizar, use o plano em vigor: `Arquitetura do Sistema/3 Estado e Execução/PLANO_MVP_2026-11.md`.

Lado esquerdo do mapa:

| Agente | Ramo | Status | Evidência |
|---|---|---|---|
| 1 Captador (opera) | Leitura de documentos sem digitação | ● | ARQUITETURA_ALVO_E_ROADMAP.md:122 (4 formatos, extração) |
| | Duplicata barrada por fingerprint | ● | ARQUITETURA_ALVO_E_ROADMAP.md:122 |
| | Controle de documentos pendentes | ● | Kit do mandato, migrations 0300/0301 |
| | Coleta de SPED, ECD e NF-e na fonte | ○ | STATUS fase 16 (ondas 1 e 3) |
| 2 Conferidor (opera) | Conferência de balanço, caixa e DRE | ● | Migrations 0009, 0015, 0105, 0133 |
| | Conciliação de mútuos do grupo | ● | Migrations 0117, 0124 |
| | Perguntas ao cliente sobre lacunas | ● | portal/src/lib/perguntas.ts |
| | Consolidação sem dupla contagem | ○ | STATUS 5.3/5.4 |
| 3 Mercado | Projeção com IPCA e Selic do Focus | ● | portal/src/app/casos/[id]/export/route.ts:200 (premissas de inflação e juro) |
| | Juro por contrato vs. Banco Central | ○ | STATUS 18.6 |
| | Despesas vs. setor e região | ○ | STATUS 18.3/18.5 |
| 4 Risco | Sinais de deterioração financeira | ○ | STATUS 10.1–10.3 |
| | Mapeamento de processos e bureau | ○ | STATUS 17.3/17.4 |
| | Nota de risco para o comitê | ○ | Scorecard em portal/src/lib/apresentacao/deck-credito.ts (só a estrutura) |

Lado direito do mapa:

| Agente | Ramo | Status | Evidência |
|---|---|---|---|
| 5 Caixa | Capital de giro: NCG e ciclo | ● | portal/src/lib/modelo-institucional.ts (aba Capital de Giro) |
| | Aging conciliado com o balanço | ● | Migration 0274 |
| | Liquidez de 13 semanas | ○ | STATUS 9.1–9.3 |
| 6 Dívida | Mapa da dívida por vencimento | ● | portal/src/lib/mapa-da-divida.ts |
| | Capacidade de pagamento em fórmula | ● | modelo-institucional.ts:6062 (ND/EBITDA) |
| | Garantias e covenants por credor | ○ | STATUS 8.1–8.3 |
| | Waterfall de credores | ○ | STATUS 12.1–12.3 (Lei 11.101) |
| 7 Estrategista | Plano em 3 cenários, com stress | ● | modelo-institucional.ts:96 (Base, Cliente, Stress) |
| | Recálculo automático das premissas | ○ | STATUS 6.1/6.2 (motor: 7 fórmulas, 89 premissas) |
| | Valuation por DCF e múltiplos | ○ | STATUS 11.1/11.2 |
| | Simulação de propostas aos credores | ○ | STATUS 13.1–13.4 (carência, haircut, new money) |
| 8 Entregas (opera) | Modelo do comitê auditável em Excel | ● | modelo-institucional.ts:73–78 (14 abas em fórmula) |
| | Base de dados conferível no 1º dia | ● | export/route.ts, `?modo=dados` ("desde a ingestão") |
| | Apresentação de crédito pronta | ○ | STATUS 14.3 (80%) / 14.4 |

Os detalhes técnicos (4 formatos, 14 abas, 13 semanas, Lei 11.101, 89 premissas) ficam **fora** dos ramos e **dentro** das notas do apresentador.

## 5. Identidade visual

| Elemento | Valor |
|---|---|
| Navy (títulos, cartões escuros) | `16263B` |
| Laranja (rótulos, números, badges) | `F04600` |
| Verde (faixas de conclusão, "amortiza dívida", valor único no gráfico) | `2E5B45` |
| Fundo | `EEF3EE` · faixa tingida `E3EBE4` |
| Bordas de cartão e pílula | `D6DED6` · curvas do mapa `B7C4BA` (1,75 pt agente, 1 pt ramo) |
| Texto corrido | `404040` · secundário `707070` · selo RISCO `66716C` (contraste 5,1:1 com branco) |
| Tipografia | Calibri (fonte do tema). Rótulo de seção 11 pt, caixa alta, espaçamento 300, laranja. Título 28 pt navy |
| Margens | 0,60" nas laterais (conteúdo de 0,60" a 12,73") |
| Elementos de marca | Sextante na capa; rodapé "CONFIDENCIAL · uso exclusivo do destinatário" + "ORIA DIGITAL" espaçado |

## 6. Regras de escrita

1. **Os títulos são conclusões curtas**, sem ponto final.
2. **Os ramos do slide 8 são entregas**, com nome de etapa e nunca frase corrida. Certo: "Capacidade de pagamento em fórmula". Errado: "Quanto de dívida a empresa aguenta".
3. **Os blocos "COMO RESOLVEMOS" (slide 3) e "RESULTADO" (slide 5)** dizem a dor resolvida do cliente e não repetem o texto de cima. Textos definidos pelo dono:
   - Slide 3:
     - Time focado na tomada de decisão
     - Erro achado antes do credor
     - Rastreabilidade de cada valor
     - Empresa vs. seus benchmarks
   - Slide 5:
     - Maior confiabilidade nos dados
     - Nenhuma surpresa em cima da hora
     - Até onde o caixa aguenta
     - Sugestões estruturadas e bem embasadas
     - A prova que o banco precisava para renegociar
4. **Número e unidade não se separam** (usar espaço que não quebra). Valor anual se escreve "R$ 10 mi / ano".
5. **Nada é afirmado no presente se estiver "em construção" no slide 8.** Exemplos: o slide 6 diz "cruzados em uma base única", e não "automaticamente"; o slide 8 diz "dividem", e não "cobrem".
6. **O que ainda não tem dado não entra.** O slide de modelo de negócio e concorrência foi desenhado com valores fictícios e **não faz parte do deck**. Ele fica para depois da validação dos números com o sócio.

## 7. Como conferir e comparar

Os comandos abaixo rodam a partir desta pasta. Pré-requisitos: LibreOffice (`soffice` ou `libreoffice` no `PATH`), Poppler (`pdftoppm`, `pdftotext`) e Python com `python-pptx` e `Pillow`. **Por segurança, as ferramentas só aceitam arquivos `.pptx`/`.pdf` que existem dentro da pasta de trabalho.** Para comparar com uma versão nova, copie-a para esta pasta antes.

```bash
soffice --headless --convert-to pdf Business_Plan_Oria_Digital.pptx
python3 ferramentas/qa_geometria.py Business_Plan_Oria_Digital.pptx Business_Plan_Oria_Digital.pdf
python3 ferramentas/comparativo.py Business_Plan_Oria_Digital.pptx nova_versao.pptx comparativo.pdf --rotulos "ATUAL" "NOVA"
```

- **`qa_geometria.py`** aponta:
  - shape fora do slide;
  - caixas de texto sobrepostas;
  - fonte abaixo de 9 pt;
  - **palavras que colidem no render**, que é o defeito que importa. Hoje são **0**.

  Os outros achados da lista são do próprio desenho: o sextante que sangra para fora da capa, os badges presos às elipses e os títulos empilhados nos anexos.
- **`comparativo.py`** compara duas versões quaisquer, lado a lado, e marca IGUAL ou ALTERADO pela contagem de pixels.
  - Testado em 18/11/2026: a mesma versão contra ela mesma dá 0 slides alterados. Trocar um único número ("R$ 56 bi" → "R$ 99 bi") marca só aquele slide, com 519 pixels diferentes.

**Limitação.** A conferência visual foi feita no LibreOffice, em que a Calibri é substituída pela Carlito, de métricas iguais. Abra no Microsoft PowerPoint antes de apresentar. Os pontos mais sensíveis são os conectores curvos do slide 8 e os rótulos do gráfico do slide 7.
