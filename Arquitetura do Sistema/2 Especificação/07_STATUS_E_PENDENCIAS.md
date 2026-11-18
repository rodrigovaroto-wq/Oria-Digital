# 07 — Estrutura de Status e Pendências

## Máquina de status do CASO

```
intake → em_triagem → completude_ok (Portão 1) → em_revisão → aprovado (Portão 2) → pronto_para_base
```

Estados laterais: `bloqueado`, `aguardando_cliente`.

## Status do DOCUMENTO / ITEM

```
solicitado → recebido → em_validação → válido | inválido | recebido_não_válido | vencido
```

> **Completude ≠ validade.** Um item pode estar *recebido* (completude satisfeita) e ainda
> *não válido* (conteúdo/qualidade reprovados). São dois status separados de propósito, para
> evitar falsa sensação de completude.

## Severidade da pendência

| Severidade | Efeito | Exemplo |
|---|---|---|
| **BLOQUEANTE** | Impede o Portão 2 | Falta demonstração financeira obrigatória; arquivo ilegível de item essencial |
| **IMPORTANTE** | Não bloqueia sozinha; acumulada pode | Período desatualizado; divergência material sem explicação |
| **COMPLEMENTAR** | Não bloqueia | Documento de apoio ausente; metadado faltando |

## Estados de resolução da pendência

```
aberta → em_correção_interna | reenviada_ao_cliente → aceita_com_ressalva | rejeitada | resolvida
```

- **Reenviada ao cliente:** gera tarefa client-facing (relevante quando o portal existir; no
  MVP é ação do analista de "pedir de novo").
- **Aceita com ressalva:** liberação **consciente** de risco, não atalho — ver limites duros.

## Limites duros (fecha a "porta dos fundos" da ressalva)

- **Pendências bloqueantes NÃO-sobrepujáveis:** lista fechada (ex.: demonstração obrigatória
  ausente; documento essencial ilegível) que **nenhuma ressalva libera**.
- **Teto de ressalvas por caso.**
- Ressalva exige **sênior + motivo + data de expiração** (não é liberação permanente).

## Regra de portão determinística

> O caso é elegível ao **Portão 2 se e somente se** não há pendência **bloqueante** aberta
> **E** o teto de ressalvas não foi estourado.

Simples, auditável, sem interpretação.

## Motor de pendências (transversal)

Não é uma etapa — é um serviço que atravessa todos os estágios. Ele traduz erros e lacunas
detectadas em ações práticas: o que falta, o que está quebrado, o que está inconsistente, o
que precisa de correção interna, o que precisa ser solicitado de novo ao cliente, o que pode
ser aceito com ressalva, e o que bloqueia o avanço do caso.
