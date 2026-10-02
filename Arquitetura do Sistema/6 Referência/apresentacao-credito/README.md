# Apresentação de crédito — de onde ela vem e o que ela ainda não faz

> **Hierarquia das fontes (decisão do dono, 02/10/2026):** `PROMPT_PADRAO_ORIA.md` (Teaser) é a
> verdade da FORMATAÇÃO — Verdana, pt, componentes 4.7, rodapé 8,5/7,5 pt. O deck Centro Oeste é a
> referência de CONSTRUÇÃO — todos os capítulos, tabelas e gráficos. Exceções pedidas pelo dono ao
> Teaser: divisórias e sumário ficam; o endividamento usa rosca. Lacuna: `n/d` em número de tabela,
> "[a preencher]" em texto. Assinatura da capa: "ORIA PARTNERS CAPITAL SERVIÇOS". O Prompt-Mestre v3
> vale só para o CONTEÚDO do módulo de crédito (capítulos, amarrações, múltiplo-alvo, scorecard).

**Fonte da especificação:** `PROMPT_MESTRE_ORIA_v3.md` (cópia literal do Prompt-Mestre Oria v3, out/2026).
A referência visual foi o deck `CentroOeste_-_Apresentacao_Inicial_-_Oria_v1.pptx` (mandato real
Krauspenhar). **O deck não está versionado aqui de propósito**: é documento confidencial de cliente.
O que se tirou dele — o logo oficial (`ppt/media/image1.png`) — está em
`portal/src/lib/apresentacao/logo-oria.ts`.

## Onde mora

| Peça | Arquivo | Papel no prompt |
|---|---|---|
| Biblioteca visual | `portal/src/lib/apresentacao/pptx-oria.ts` | `oria.py` — paleta, tipografia, grade, layouts A, A′, B, C, G, H, I, J |
| Base financeira | `portal/src/lib/apresentacao/base-credito.ts` | `data.py` — indicadores, tags (A)/(B), amarrações executáveis |
| Realizado | `historicoParaCredito` em `portal/src/lib/modelo-institucional.ts` | o MESMO realizado do modelo institucional (classificadores, âncoras, escala) |
| Gerador | `portal/src/lib/apresentacao/deck-credito.ts` | o módulo de crédito (FASE 4) |
| Rota | `GET /casos/[id]/export?modo=apresentacao` | mesmo Portão 2 e mesma leitura do export completo |
| Portão | `portal/scripts/verificar-apresentacao.mts` | FASE 5 (QA) automatizada, com controle positivo |

## Decisões que divergem do prompt, e por quê

- **OOXML via JSZip, não `python-pptx`.** O portal roda numa função da Vercel (sem Python) e o JSZip
  já está no lock. As três razões do prompt para `python-pptx` (EMU inteiro, sem sombra, controle de
  `bodyPr`/`endParaRPr`) viraram garantia por construção na biblioteca e varredura no portão.
- **Só exercícios fechados.** O histórico do modelo para no último exercício real; YTD/LTM do
  balancete corrente ainda não entra.
- **Natureza `(A)` só com `DF_AUDITADA`.** O sistema não lê o parecer; marcar auditado sem ele seria
  suposição apresentada como dado.

## O que esta versão gera

Capa · Sumário · Sumário executivo (4 KPIs + diagnóstico + implicação) · Divisória · IX Base de
informação · X.1 Resultado · X.2 Estrutura de capital e prazos · Divisória · XI.2 NCG e prazos ·
XII Comparativo · Notas e fontes (amarrações com veredito) · Escopo e motivos de n/d · Contracapa.

Manchetes e implicações são **regras sobre o número** (limiares do próprio prompt, ex.: 2,5x–3,5x de
DFL/EBITDA), não texto livre.

## O que falta (em ordem de valor, para as próximas rodadas)

1. **XIII Endividamento** por credor, roscas e muro de vencimentos — exige o `MAPA_DIVIDA` estruturado
   por operação; gráficos nativos (`c:barChart`, `c:doughnutChart`) no mesmo molde de `xlsx-graficos.ts`.
2. **YTD/LTM** a partir do balancete corrente (base de dias proporcional, amarração 6).
3. **X.3 Fluxo de caixa reconstruído** (22 linhas, 2 slides) e **XI.1** composição com AV%.
4. **XIV–XVIII** (normalização, dívida sustentável, garantias, scorecard, síntese): pedem entrada do
   analista — tela de ajustes com confiança (verificado/informado/estimado) e notas por eixo.
5. **FASES 1–3** (pesquisa, pitch, capítulos I–VIII): exigem pesquisa web e redação; candidato a um
   fluxo com IA à parte, que entregue os dados estruturados para esta mesma biblioteca desenhar.
