# Agentes do Oria Digital: estrutura, responsabilidades e status real

**Fonte oficial** do catálogo de agentes e do status real de cada um. O slide 9 do deck mostra o
catálogo **sem status** (J4); a [documentação do deck](../../Apresentações/Business%20Plan%20Oria%20Digital/DOCUMENTACAO.md)
aponta para cá. As regras que todos os agentes obedecem estão em
[`04_regras_de_negocio/REGRAS_E_DEFINICOES.md`](../04_regras_de_negocio/REGRAS_E_DEFINICOES.md).

## 1. O catálogo (B1)

**Onze agentes** — 8 especialistas + Supervisor/Orquestrador, Auditor Independente e Autoaprimoramento.
É uma **referência flexível**: pode crescer ou encolher, com justificativa, teste e versão (B1).

**Hoje nenhum agente existe como agente no produto** (conferido no código em 19/11/2026: não há
orquestração, nem chamada de agente, nem Supervisor ou Auditor-agente). O que existe são módulos do
sistema que a v1 transforma em agentes, começando pelo piloto (K6). Os 7 agentes em `.claude/agents/`
são do **ambiente de desenvolvimento** (quem constrói o sistema), não do produto.

| Agente | Texto do slide 9 (literal) | O que faz (decisões) | Base que existe hoje (evidência) | O que falta | Entrega |
|---|---|---|---|---|---|
| **Captador** | Lê os documentos e busca dados na Receita e nos bancos | Extração dos documentos e captação externa (D3-3) | Leitores determinísticos de SPED/EFD/CNAB/OFX/XML (`Leitor/ler.mjs`, `Leitor/lib/familia.mjs`); extração e classificação por IA (`N8N/lib/extract.mjs`, `N8N/lib/classifier.mjs`); duplicata por fingerprint; Kit pelo banco (`0300`, `0301`) | IA revisora em PDF/imagem; captação de Registrato, Open Finance e fontes públicas; volta da extração e da classificação a N1 (D6, D6-1) | Funções no piloto (trilhas B e C do plano); agente formal no restante da v1 |
| **Conferidor** | Cruza a contabilidade com fontes externas e aponta divergências | Cruza extração × captação externa e dá o veredito (D3-3) | Conferências de balanço, caixa e DRE (`0009`, `0015`, `0105`, `0133`); mútuos (`0117`, `0124`); reconciliação registrada (`fn_registrar_reconciliacao`, desde a `0023`) | Cruzamento com fonte externa guardando os dois valores; veredito; achado | **Piloto** |
| **Mercado** | Compara a empresa e os juros com o setor e o mercado | Compara a empresa e os juros com o setor e o mercado | Séries macro do BCB (IPCA, IGP-M, INPC, Selic, CDI) e expectativas do Focus (IPCA, Selic, IGP-M, PIB, câmbio), com agendamento diário: `0025`, `N8N/lib/macro.mjs`, `N8N/workflow.macro.json`; premissas do Focus no export; IPCA do IBGE (SIDRA) só como conferência | Juros por modalidade, CVM, CAGED/RAIS captados e atualizados; juro por contrato vs. mercado; despesa vs. setor | **Piloto** |
| **Caixa** | Mostra até onde o caixa aguenta, semana a semana | Até onde o caixa aguenta, semana a semana | Capital de giro (NCG e ciclo); aging conciliado com o balanço (`0274`) | Fluxo de 13 semanas; variação calendário × permanente | **Piloto** |
| **Dívida** | Mapeia a dívida e mede a capacidade de pagamento | Mapa da dívida e capacidade de pagamento | Mapa da dívida, operação a operação (`portal/src/lib/mapa-da-divida.ts`), e ND/EBITDA em fórmula no Excel; covenant rompido só como fato lido do texto do documento (`covenant_rompido`, crítico, `0148`) | Covenant calculado a partir dos contratos e índices; cronograma (waterfall); cruzamento com o Registrato | **Piloto** |
| **Risco** | Mapeia processos, protestos e dívida ativa antes da crise | Processos, protestos e dívida ativa antes da crise | Nenhuma captação de processos, protestos ou notícias. Existem só os fatos lidos do texto do documento `litigio_relevante` e `garantia_dada` (`0148_o_fato_que_o_documento_diz_em_texto.sql`); o scorecard de risco existe só como estrutura | Tudo; o dossiê de processos e notícias entra no piloto como entrega, não como agente | Restante da v1 |
| **Estrategista** | Propõe cortes, renegociação e propostas aos credores | Cortes, renegociação e propostas aos credores (B7) | Plano em 3 cenários (Base, Cliente, Stress) no export (`portal/src/lib/modelo-institucional.ts`) | Simulação de propostas (carência, desconto, dinheiro novo); motor de cenários | Restante da v1 |
| **Entregas** | Monta modelo, dossiê e apresentação, com a prova | Modelo, dossiê e apresentação, com a prova (G4) | Excel do comitê com 14 abas em fórmula e base de dados exportável; apresentação `.pptx` (suíte em `.github/workflows/suites.yml`) | Link número → documento e página **no Excel** (no portal já existe: `portal/src/lib/original-do-documento.ts`); relatório em PDF; apresentação a credores | Excel + PDF no piloto; agente no restante da v1 |
| **Supervisor / Orquestrador** | Coordena os agentes e media divergências | Distribui, coordena, media divergências; decide só baixo impacto (B3, B3b-1, L5) | Nada | Tudo | **Piloto** |
| **Auditor Independente** | Revisa o trabalho de todos os agentes | Revisa a execução dos outros agentes, evidências e coerência, usando o motor, sem recalcular (B4); valida os erros que o autoaprimoramento conta (F1-3) | O equivalente hoje são as conferências em SQL e o Portão 2 | Tudo | **Piloto** |
| **Autoaprimoramento** | Propõe melhorias a partir dos erros | Propõe melhorias a partir dos erros (F1–F6) | Nada | Tudo | Restante da v1 (fase A); código só depois do gatilho (fase B) |

## 2. Contrato comum a todos os agentes

1. **Entrada:** dados e evidências do mandato, por permissão; na 1ª rodada, nunca as conclusões dos
   outros agentes (v0.1.2 §2).
2. **Saída:** interpretação em formato estruturado, citando o número **do motor** e a evidência
   (documento, página, fonte). Nunca um número calculado pelo agente (B2).
3. **Incongruência:** devolve para revisão com a sua interpretação; não resolve sozinho (B2).
4. **Memória:** nenhum agente guarda memória própria por empresa; consulta a base central por
   permissão (v0.1.2 §4). Detalhe em [`05_governanca/`](../05_governanca/MEMORIA_AUTOAPRIMORAMENTO_E_GOVERNANCA.md).
5. **Acesso:** chave de mínimo privilégio, isolada por organização (H4).
6. **Medição:** custo, tempo e erros registrados por execução, por etapa e por agente (D5, J6).
7. **Cobertura das 31 frentes de diligência:** definida na construção de cada agente (B6). O mapa das
   frentes está nos anexos do deck (slides 11–14).

## 3. Fluxo entre os agentes

O fluxo completo, bloco a bloco e com selo de status, é o
[workflow v0.3.0](../02_workflow_e_arquitetura/oria_digital_workflow_v0.3.0.html). Em resumo:

```
Captador (extração + captação) → Conferidor (cruzamento e veredito)
  → Supervisor distribui a 1ª rodada independente → especialistas (Mercado, Caixa, Dívida, Risco, Estrategista)
  → Supervisor consolida e media divergências (decide só baixo impacto)
  → Auditor revisa a execução (motor recalcula) → até 3 tentativas
  → fila de decisão humana (segundo revisor quando vai para fora)
  → Entregas (Excel em fórmula + PDF)
Autoaprimoramento lê o histórico de todos e propõe; o Técnico decide.
```

## 4. Mantendo este arquivo

Quando um agente mudar de situação, atualize a linha dele aqui, com a evidência (arquivo, migration
ou suíte), e o item correspondente do plano de execução. O deck não muda: ele não mostra status.
