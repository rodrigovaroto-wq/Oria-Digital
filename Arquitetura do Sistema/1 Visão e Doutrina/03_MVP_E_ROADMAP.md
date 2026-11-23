# 03 — MVP e Roadmap

> **SUPERADO em 23/11/2026** pelo plano de execução único [`Business Plan/06_execucao/PLANO_DE_EXECUCAO.md`](../../Business%20Plan/06_execucao/PLANO_DE_EXECUCAO.md) (decisão K1 do registro v0.1.3).
> Este arquivo fica como histórico, sem outra alteração. O que dele seguia aberto, e para onde foi, está na
> seção 11 daquele plano (por bloco, não item a item).

## MVP = workflow completo em Modo Conservador

**Definição:** o MVP contém **todos os estágios e todas as camadas**, conectados ponta a
ponta, operando em **Modo Conservador** — determinístico autônomo; tudo interpretativo em
N0/N1 (humano no loop). O sistema faz o caminho inteiro do documento até o Portão 2 desde o
dia 1. O que evolui depois é o **nível de autonomia**, não a existência dos estágios.

### Dentro do MVP (tudo isto existe na v1 de produção)

- Modelo de caso/entidade/período/documento/versão (Supabase).
- Ingestão + **gate de captura** (legibilidade/integridade) + **transcrição humana assistida**.
  Na F1, ingestão por **upload manual em lote** no portal (integração SharePoint = fase futura);
  ver `Arquitetura do Sistema/2 Especificação/f0/02_build_vs_buy.md`.
- Classificação documento→checklist (N1: sugestão + confirmação).
- Validação formal (período/entidade/tipo/assinatura/integridade), com pré-condições.
- Completude (Portão 1) determinístico.
- **Extração** — identificadores em N1; linhas financeiras em **N0 (sombra)**, para começar a
  medir desde já sem influenciar decisão.
- **Reconciliação** — Classe A em N1; Classe B/C em N0/aproximação-para-humano.
- **Classificação contábil** — presente em **N0 (sombra)**: registra sugestão, não decide.
- Motor de pendências determinístico (transversal).
- Portão 2 (aprovação) com **limites duros** e trilha append-only.
- **Base para modelagem (export)** — só de dados com aceite humano.
- Dashboard de status + fila de revisão + **painel de autonomia**.

### Fora do MVP (explícito)

M&A (produto seguinte); portal do cliente (fase seguinte); apoio analítico de leitura de case
(fase futura). **Nenhum estágio do core fica de fora** — só o segundo produto, o lado cliente
e o apoio analítico.

### Por que isto é "profissional e à prova de erro"

Todo estágio interpretativo nasce sem poder de decidir (N0/N1); toda incerteza vira revisão
humana; nada interpretativo faz auto-commit; a base de modelagem só recebe dado com aceite
explícito. O sistema é completo, mas **não confia em si mesmo até medir que pode**.

## Roadmap (build-tudo-primeiro, depois calibrar) — sem waterfall de features

A abordagem original tinha fases de feature (waterfall disfarçado). A v2 tem **duas grandes
fases**: **Construção** (o workflow inteiro) e **Calibração** (subir o dial), com uma ordem de
*build* que de-risca integração cedo.

| Fase | Objetivo | Como termina |
|---|---|---|
| **F0 — Fundação** | Taxonomia+checklist (Reestruturação), schema, status/pendências, **baseline quantitativo**, **golden set dimensionado**, decisão build-vs-buy, política LGPD | Artefatos assinados; golden set com N/tipo suficiente |
| **F1 — Walking Skeleton** | O workflow **inteiro** conectado ponta a ponta, **todo estágio em N0/N1**; 1 caso real atravessa tudo | Integração e modelo de estado provados |
| **F2 — Encorpar** | Cada estágio levado à versão completa, **ainda em Modo Conservador** | Todos os estágios funcionais; pendências e portões completos |
| **F3 — Go-live Conservador** | Operação real; humano no loop em tudo interpretativo | Casos reais processados; dados de concordância acumulando |
| **F4 — Calibração (contínua)** | **Subir o dial por estágio** conforme concordância medida; corrigir os mal calibrados | Loop permanente; autonomia sobe onde os dados provam |
| **F5 — Expansão** | M&A; portal do cliente; apoio analítico | Fora do escopo atual |

### Risco desta abordagem (nomeado explicitamente)

Construir estágios interpretativos antes de ter dado de calibração significa construir sobre
premissas, e há a tentação de ligar autonomia antes da hora. **O Modo Conservador é o que
torna isso seguro** — enquanto ninguém subir o dial sem golden set, "construir tudo primeiro"
não escala erro.
