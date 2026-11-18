# 0.4 — Modelo de Status + Pendências + Regra do Portão  ·  [APROVADO]

**Objetivo:** especificação executável das máquinas de estado e do motor de pendências.
Proposta pronta (decorre da arquitetura aprovada em `Arquitetura do Sistema/2 Especificação/07_STATUS_E_PENDENCIAS.md`).

> **Aprovado em 2026-07-14 (Rodrigo Varoto):** máquinas de estado, catálogo de pendências,
> severidades e regra do Portão 2 aceitos como estão. Teto de ressalvas confirmado em **3**
> (default parametrizável). O conjunto obrigatório verificado no Portão 1 é o **Kit Básico**
> definido em `03_taxonomia_reestruturacao.md`. É o que o schema (0.5) materializa.

## Máquina de estado do CASO

| Estado | Significado | Transições permitidas |
|---|---|---|
| `intake` | Recebendo documentos | → `em_triagem` |
| `em_triagem` | Classificação/validação/extração rodando | → `completude_ok`, `bloqueado`, `aguardando_cliente` |
| `completude_ok` | Portão 1 satisfeito | → `em_revisao`, `aguardando_cliente` |
| `em_revisao` | Analista/sênior revisando pendências | → `aprovado`, `bloqueado`, `aguardando_cliente` |
| `aprovado` | Portão 2 fechado (avanço autorizado) | → `pronto_para_base` |
| `pronto_para_base` | Export disponível para análise | (terminal do escopo) |
| `bloqueado` | Pendência bloqueante aberta | → estado anterior quando resolvida |
| `aguardando_cliente` | Reenvio solicitado | → `em_triagem` |

**Invariante:** o caso só entra em `aprovado` pela regra do Portão 2 (abaixo). Toda transição
gera evento de auditoria.

## Máquina de estado do DOCUMENTO/ITEM

```
solicitado → recebido → em_validação → { válido | inválido | recebido_não_válido | vencido }
```

- `recebido_não_válido`: chegou, mas falhou validação formal (fecha completude, não validade).
- `vencido`: passou da janela de vigência da taxonomia (0.3).
- **Completude ≠ validade** — status separados de propósito.

## Motor de pendências

Toda pendência: `{ id, caso_id, origem_estágio, tipo, severidade, estado, descrição,
documento/entidade/período alvo, criada_em, resolvida_em, resolvida_por, motivo }`.

### Tipos de pendência (catálogo inicial)
| Tipo | Origem | Exemplo |
|---|---|---|
| `item_faltante` | Completude | Documento obrigatório não recebido |
| `periodo_faltante` | Completude | Falta um mês da série |
| `item_vencido` | Completude | Documento fora da janela de vigência |
| `arquivo_ilegivel` | Gate de captura | Scan/foto ilegível |
| `arquivo_corrompido` | Intake | Arquivo não abre |
| `entidade_incorreta` | Validação formal | Documento de outra entidade |
| `periodo_incorreto` | Validação formal | Documento de outro período |
| `tipo_incorreto` | Validação formal | Classificação não bate |
| `divergencia_reconciliacao` | Reconciliação | Classe A/B acima da tolerância |
| `precondicao_nao_satisfeita` | Reconciliação/Extração | Período/escopo/moeda não batem |
| `extracao_baixa_confianca` | Extração | Campo abaixo do threshold |

### Severidade
- `BLOQUEANTE` — impede Portão 2.
- `IMPORTANTE` — não bloqueia sozinha; acúmulo acima de um teto pode bloquear (parametrizável).
- `COMPLEMENTAR` — não bloqueia.

### Estados de resolução
```
aberta → { em_correção_interna | reenviada_ao_cliente } → { aceita_com_ressalva | rejeitada | resolvida }
```

## Regra do Portão 2 (determinística)

> O caso é elegível a `aprovado` **se e somente se**:
> 1. **nenhuma** pendência `BLOQUEANTE` está `aberta`/`em_correção`/`reenviada`; **e**
> 2. o número de pendências `aceita_com_ressalva` ativas ≤ **teto por caso** (parâmetro,
>    sugestão inicial: 3); **e**
> 3. **nenhuma** pendência da **lista de bloqueantes não-sobrepujáveis** existe aberta.

### Bloqueantes NÃO-sobrepujáveis (lista fechada — nenhuma ressalva libera)
Definida a partir do **Kit Básico** (0.3): ausência de `DRE`, `BALANCO`, `COMBINADO`, `MUTUOS`
ou `CONTRATO_SOCIAL`; `arquivo_ilegivel` de qualquer item do Kit Básico. *(Revisar quando a
taxonomia evoluir para v2.)*

### "Aceitar com ressalva" (controlado)
- Exige papel **sênior** + `motivo` obrigatório + **data de expiração**.
- Ao expirar, a pendência **reabre** automaticamente e o caso pode voltar a `bloqueado`.

## Dial de autonomia por estágio (estado inicial da F1)

| Estágio | Nível inicial | Teto |
|---|---|---|
| Classificação doc→checklist | N1 | N2 |
| Validação formal (determinística) | N2 | N3 |
| Completude (Portão 1) | N2 | N3 |
| Extração de identificadores | N1 | N2 |
| Extração de linhas financeiras | N0 | N2 |
| Reconciliação Classe A | N1 | N2 |
| Reconciliação Classe B/C | N0 | N1 |
| Classificação contábil | N0 | N1 |

**Critério de pronto (DoD):** máquinas de estado aprovadas; catálogo de pendências e
severidades fechado; regra do Portão 2 sem ambiguidade; teto de ressalvas e lista de
não-sobrepujáveis definidos; dial inicial confirmado.
