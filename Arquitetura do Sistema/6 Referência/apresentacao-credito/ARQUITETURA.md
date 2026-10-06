# A apresentação de crédito como última etapa do pipeline

## Onde ela entra

```
documentos → n8n (extração IA) → Postgres (campo_extraido + proveniência)
   → Portão 1 (kit básico) → revisão/pendências → Portão 2 (base aprovada)
   → Modelagem (entidade, último exercício real, premissas)
   → export .xlsx (dados | modelagem)          ← já existia
   → apresentação .pptx (?modo=apresentacao)   ← esta etapa
```

A apresentação **não tem leitura própria do banco**. Ela é uma terceira saída da rota
`GET /casos/[id]/export`, depois do mesmo Portão 2 e da mesma montagem do modelo institucional.
Esta decisão é a que mais protege o número: duas leituras do mesmo caso podem discordar em
silêncio, e uma leitura só não tem com quem discordar.

| Camada | Arquivo | Responsabilidade |
|---|---|---|
| Realizado | `historicoParaCredito` (`portal/src/lib/modelo-institucional.ts`) | Grandezas por exercício com os classificadores do modelo; âncora do documento, senão a cascata marcada "calculado" |
| Base | `portal/src/lib/apresentacao/base-credito.ts` | Indicadores, `n/d` × `n.s.`, natureza (A)/(B), amarrações com veredito, faixa de alavancagem |
| Costura | `portal/src/lib/apresentacao/montar-base.ts` | Entrada do modelo + documentos → `BaseCredito` |
| Conteúdo | `portal/src/lib/apresentacao/deck-credito.ts` | Os capítulos do Centro Oeste, títulos por regra sobre o número, recusa sem dado (`SemDadoParaApresentar`) |
| Forma | `portal/src/lib/apresentacao/pptx-oria.ts` | Padrão do Teaser (Prompt Padrão Oria) em OOXML; gráficos nativos |
| Rota | `portal/src/app/casos/[id]/export/route.ts` | `?modo=apresentacao`; 409 com motivo quando não há modelo ou dado |
| Tela | `portal/src/app/casos/[id]/modelagem/page.tsx` | Botão "Gerar apresentação de crédito", só com o Portão 2 aberto |
| Portão | `portal/scripts/verificar-apresentacao.mts` (CI) | Números contra o gabarito, ausência, padrão visual com controle positivo, setores |
| Teste com banco | `portal/scripts/gerar-export-do-banco.mts` com `APRESENTACAO=` | O mesmo caminho da rota, contra qualquer caso de um banco local |

## De onde vem cada capítulo

| Capítulo | Fonte hoje | O que falta para sair do "[a preencher]" |
|---|---|---|
| IX a XIII (base, resultado, estrutura, prazos, giro, comparativo, dívida do balanço) | **sistema** | YTD/LTM do balancete corrente |
| XIII por credor, muro de vencimentos | sistema (parcial) | `MAPA_DIVIDA` estruturado por operação (credor, saldo, vencimento, indexador, garantia) |
| XIV normalização | EBITDA reportado (sistema) | ajustes com confiança, digitados pelo analista |
| XV dívida sustentável | DFL, ΔNCG e dívida suportada ilustrativa (sistema) | capex de manutenção, IR caixa, cenário de estresse |
| XVI garantias | saldos contábeis (sistema) | realização (%) por ativo; imobilizado; laudo |
| XVII scorecard, XVIII síntese, SWOT, VIII | estrutura | notas por eixo e textos do analista |
| I a VIII (setor, societário, empresa, cadeia, concorrência) | estrutura | pesquisa das FASES 1–3 do Prompt-Mestre (fontes públicas) |

## O próximo encaixe estrutural: os campos "[a preencher]" com dono

Hoje toda lacuna é texto fixo `[a preencher]` gerado no código. O passo que transforma a
apresentação em produto é dar a cada lacuna uma **chave estável** e um lugar no banco:

1. Tabela `caso_apresentacao_campo (caso_id, chave, valor, fonte, preenchido_por, preenchido_em)`,
   com RLS igual à de `caso_premissa`, e uma chave por campo (ex.: `xiv.ajuste.nao_recorrentes`,
   `xvii.nota.rentabilidade`, `i.kpi.tamanho_setor`).
2. O gerador lê esses valores pela mesma rota e só escreve `[a preencher]` quando a chave não tem
   valor — a fonte do valor vai para a nota de fonte do slide (regra: número sem fonte não entra).
3. Uma tela "Apresentação" no caso, irmã da Modelagem, para o analista preencher por capítulo.
4. Os capítulos de pesquisa (I–VIII) ganham um fluxo próprio no n8n, que grava nas mesmas chaves
   com `fonte` = URL consultada; o analista revisa antes do export.

Ordem sugerida: (1)+(2) primeiro — sem tela, já permite preencher por SQL e testar; depois (3);
(4) por último, porque depende de pesquisa web com custo e revisão.

## Limitações conhecidas (medidas em 02/10/2026, 14 entidades de 3 mandatos)

- **Uma entidade por deck.** Grupo com avais cruzados exige a série por entidade avalizada
  (Prompt-Mestre, Cap. X); hoje é preciso trocar a entidade na Modelagem e gerar de novo.
- **Holding e SPE só com balanço** saem com resultado `n/d` — correto, mas o deck é longo para pouco
  dado. Candidato: esconder capítulos de resultado quando não há DRE em exercício algum.
- **Setores sem CMV/receita líquida no vocabulário** (banco, seguradora, cooperativa de crédito):
  as âncoras são de empresa comercial/industrial; esses casos saem majoritariamente `n/d`.
- **Rótulos de gráfico** usam o separador decimal do PowerPoint de quem abre (vírgula em pt-BR).
- **Gráficos sem planilha embutida**: exibem certo, mas editar os números exige recriar o gráfico.
