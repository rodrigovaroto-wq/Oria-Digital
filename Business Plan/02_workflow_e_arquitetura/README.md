# Workflow e arquitetura (visão de produto)

**Fonte oficial do fluxo do produto:**
[`oria_digital_workflow_v0.3.0.html`](oria_digital_workflow_v0.3.0.html) (abrir no navegador;
autocontido). Cada bloco tem um selo:

| Selo | Quer dizer |
|---|---|
| **EXISTE** | Está no código hoje |
| **EXISTE · EVOLUIR** | Existe e será alterado |
| **PILOTO** | Primeira entrega da v1, com a Oria Partners (K6) |
| **V1** | Entregas seguintes da v1 |
| **FUTURO** | Depois da v1, ou condicionado a parecer ou parceria |
| **EM ESTUDO** | Plataforma sujeita ao estudo comparativo (R2) |

O diagrama registra decisões; **não comprova implementação**. A situação de cada item, com a
evidência, está no plano de execução ([`../06_execucao/PLANO_DE_EXECUCAO.md`](../06_execucao/PLANO_DE_EXECUCAO.md)).
Divergências conhecidas entre o workflow e o código estão na
[validação de consistência](../08_pendencias_e_riscos/VALIDACAO_DE_CONSISTENCIA.md), seção 3.

## Regerar ou fazer uma versão nova

O gerador lê só o caminho de saída. Regerado na Fase 4, sai idêntico byte a byte ao versionado.

```bash
python3 -I "Business Plan/02_workflow_e_arquitetura/gerar_workflow_v030.py" /tmp/workflow_v030.html
```

Para uma versão nova: copie o gerador para `gerar_workflow_v031.py`, altere, gere o `.html` nesta pasta
e mova a versão anterior para [`../99_historico/workflow/`](../99_historico/workflow/).

## Arquitetura técnica (fonte oficial: `Arquitetura do Sistema/`)

Pela decisão K5, o **porquê de negócio** mora nesta pasta e o **como técnico** mora em
[`Arquitetura do Sistema/`](../../Arquitetura%20do%20Sistema/README.md). Os pontos de entrada:

| Documento | O que responde |
|---|---|
| [`COMO_O_SISTEMA_FUNCIONA.md`](../../Arquitetura%20do%20Sistema/3%20Estado%20e%20Execução/COMO_O_SISTEMA_FUNCIONA.md) | O fluxo de hoje, em linguagem simples |
| [`02_ARQUITETURA_FUNCIONAL.md`](../../Arquitetura%20do%20Sistema/1%20Visão%20e%20Doutrina/02_ARQUITETURA_FUNCIONAL.md) | Estágios, portões e componentes |
| [`01_DOUTRINA_DE_AUTONOMIA.md`](../../Arquitetura%20do%20Sistema/1%20Visão%20e%20Doutrina/01_DOUTRINA_DE_AUTONOMIA.md) | Os níveis N0–N3 |
| [`04_ADR_01_EVIDENCIA_IMUTAVEL.md`](../../Arquitetura%20do%20Sistema/1%20Visão%20e%20Doutrina/04_ADR_01_EVIDENCIA_IMUTAVEL.md) e [`05_ADR_02_ARITMETICA_NO_MOTOR.md`](../../Arquitetura%20do%20Sistema/1%20Visão%20e%20Doutrina/05_ADR_02_ARITMETICA_NO_MOTOR.md) | O original nunca muda; toda conta é do motor |
| [`ARQUITETURA_ALVO_E_ROADMAP.md`](../../Arquitetura%20do%20Sistema/3%20Estado%20e%20Execução/ARQUITETURA_ALVO_E_ROADMAP.md) | Decisão por componente existente (o roadmap dele foi superado pelo plano novo) |
| [`12_FONTES_OFICIAIS_E_CAPTACAO.md`](../../Arquitetura%20do%20Sistema/2%20Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md) e [`13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md`](../../Arquitetura%20do%20Sistema/2%20Especificação/13_PARCEIROS_DE_DADOS_E_PRE_MANDATO.md) | Fontes oficiais, captação e parceiros de dados |
