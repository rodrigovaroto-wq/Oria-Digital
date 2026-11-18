# 02 — Arquitetura Funcional e Stack

## Arquitetura funcional (5 estágios + 2 portões + 2 transversais + o dial)

As 10 camadas originais colapsam em **5 estágios sequenciais**, **2 portões reais** e **2
serviços transversais** (pendências e status/auditoria) que atravessam tudo.

```
             ┌──────────── TRANSVERSAIS (atravessam tudo) ────────────┐
             │  Motor de Pendências  |  Status + Trilha de Auditoria   │
             └──────────────────────────────────────────────────────────┘
   [E1] INTAKE        [E2] EXTRAÇÃO      [E3] RECONCILIAÇÃO    [E4] BASE
   ingestão+captura   identificadores    A: aritmética         export
   +classificação     +linhas fin.       B/C: aproxima p/      estruturado
   +validação formal  (+confiança)       humano                (só pós-aceite)
        │                  │                   │                    │
        ▼                  ▼                   ▼                    ▼
   ══ PORTÃO 1 ══     (sem portão;       (sem portão;        ══ PORTÃO 2 ══
   COMPLETUDE          gera pendências)   gera pendências)    APROVAÇÃO HUMANA
   (determinístico,                                          (obrigatório, sênior,
    com pré-condições)                                        auditado, com limites)

   Cada estágio tem um DIAL de autonomia (N0–N3) independente. Ver 01_DOUTRINA_DE_AUTONOMIA.
```

### Mapeamento das 10 camadas originais → arquitetura nova

| Camada original | Vai para |
|---|---|
| 1 Intake documental | E1 |
| 2 Classificação/extração | E1 (classificação) + E2 (extração) |
| 3 Completude | **Portão 1** |
| 4 Validação formal | E1 |
| 5 Reconciliação | E3 (fatiada: aritmética vs interpretativa) |
| 6 Classificação contábil | E3-adjacente, nasce em sombra (N0) |
| 7 Motor de pendências | **Serviço transversal** |
| 8 Aprovação humana | **Portão 2** |
| 9 Base p/ modelagem | E4 (export, não "modelagem") |
| 10 Apoio analítico | Fase futura (suporte, nunca decisão) |

### Estágios

- **E1 — Intake:** ingestão de arquivos; **gate de captura** (legibilidade/integridade) com
  caminho de **transcrição humana assistida**; classificação documento→item de checklist;
  reconhecimento de período/entidade/tipo; duplicidade; versionamento; validação formal
  (período/entidade/tipo/assinatura/integridade).
  > **Ingestão na F1 (decisão `Arquitetura do Sistema/2 Especificação/f0/02`):** a porta de entrada começa por **upload manual em
  > lote** no portal — o operador sobe todos os arquivos brutos de uma vez e o sistema os
  > organiza automaticamente em **Mandato × Empresa × Tipo × Período** (classificação híbrida:
  > nome do arquivo + conteúdo). A integração automática de busca no SharePoint é fase futura;
  > não altera o resto do pipeline.
- **E2 — Extração:** identificadores (tipo/período/entidade) e linhas/tabelas financeiras,
  cada campo com **score de confiança** e separação alto vs revisar.
- **E3 — Reconciliação:** comparação cruzada entre fontes (ver `04_RECONCILIACAO.md`).
- **E4 — Base:** export estruturado, apenas de dados com aceite humano.

### Portões

- **Portão 1 (Completude):** determinístico, mas **honesto sobre suas premissas**. "Recebemos
  o mínimo para trabalhar?" Pode ser leve/assíncrono, humano só nas exceções.
- **Portão 2 (Aprovação humana):** o **único portão que trava avanço** para análise. Sempre
  humano, sempre auditado, com limites duros (`../2 Especificação/07_STATUS_E_PENDENCIAS.md`).

> **Não crie um portão entre cada camada.** Extração e reconciliação produzem *pendências*,
> não portões. Portões demais matam a operação.

### Fix do vazamento de gates (fronteiras "objetivas" que dependem de etapas subjetivas)

Cada estágio objetivo só produz resultado "limpo" se suas **pré-condições** forem satisfeitas.
Exemplos: completude só é confiável se a classificação daquele documento foi confirmada (ou
está em N2+ calibrado); reconciliação aritmética só roda se período/entidade/escopo/moeda
batem. **Pré-condição não satisfeita → pendência tipada, nunca um "OK" falso.**

## Arquitetura da stack

| Ferramenta | Papel | Fronteira dura (o que NÃO faz) |
|---|---|---|
| **Supabase** | **Fonte única da verdade do estado.** Postgres (caso/entidade/período/documento/versão/campo/pendência/decisão/evento/**nível de autonomia por estágio**). Storage. Auth+RLS. Realtime p/ a fila. | Não orquestra lógica de negócio multi-passo. |
| **N8N** | **Orquestrador STATELESS.** Triggers, OCR/parsing, chamadas LLM/API, criação de pendências *gravando no Supabase*, notificações. Cada passo lê estado do Postgres e escreve de volta. | **Não é dono de estado.** Nada "vivo" entre passos. |
| **Vercel** | Portal interno, dashboard de status, **fila de revisão humana**, interface de aprovação, **painel de autonomia** (subir/descer o dial por estágio). | Não roda reconciliação pesada (chama Supabase/Edge Functions). |
| **Claude Code** | Apoio à arquitetura/implementação em etapas pequenas. | **Não é runtime.** Fora do caminho de produção. |
| **Obsidian** | Playbooks, decisões, rationale, prompts, **espelho legível** da taxonomia. | **NÃO é fonte da verdade** operacional da taxonomia. |

### Três travas de stack que evitam desastre

1. **Supabase é dono do estado; N8N é stateless.** O fluxo aqui é event-driven, com humano no
   loop e casos de longa duração. Se o estado viver dentro de execuções do N8N, perde-se
   auditoria e retomada. N8N nunca "segura" estado entre passos — sempre persiste no Postgres.
2. **Taxonomia canônica vive no Supabase, não no Obsidian.** Regras de runtime só em markdown
   → *drift* garantido. Fonte da verdade = tabelas versionadas no Postgres; Obsidian espelha.
3. **Herdar pegadinhas do `clipping-news`:** Session Pooler IPv4 + SSL "ignore issues"; user
   do pooler com sufixo `.projectref`; RLS ligado exige policy (conexão direta do N8N ignora —
   cuidado ao expor ao portal); cast inline `$N::vector` se voltar a usar embeddings.
   (Ver `clipping-news/docs/DECISOES_E_APRENDIZADOS.md`.)

### Honestidade sobre o N8N

O `clipping-news` usa N8N em modo batch/cron, sem humano no meio — tolerável. Aqui o fluxo é
event-driven, com humano no loop e casos longos. N8N funciona **se e somente se** for
stateless e cada passo for um trigger independente sobre o estado do Postgres. Se isso começar
a doer, o plano B é DB triggers + Edge Functions — mas não se troca de stack por antecipação.
