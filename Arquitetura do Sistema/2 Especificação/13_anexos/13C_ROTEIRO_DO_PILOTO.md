# 13C — Roteiro do piloto: medir os fornecedores no mandato AMO antes de contratar

**Data:** 27/10/2026 · **Decide:** D13.3 (processos) e D13.6 (agregador, bureau, provedor) da Espec. 13
· **Pré-requisitos:** 13A, itens 0.9, 2.2, 2.4, 2.5, 2.6 e as contas do nível 3.

## §1 Por que existe

Os percentuais da planilha verificada são estimativas. A regra 4 do `CLAUDE.md` proíbe provar
comportamento de produção com fixture inventada, e a regra 2 só aceita um número depois de medido.
O piloto troca a estimativa pelo número, no arranjo real: um grupo econômico assessorado, com os
documentos que a Oria já tem como gabarito.

## §2 As perguntas que ele responde

| # | Pergunta | Categoria | Decide |
|---|---|---|---|
| P1 | Que fração dos processos listados nas certidões o provedor encontra por CPF/CNPJ? | B | D13.3 |
| P2 | Dos processos que o provedor acha e as certidões não listam, quantos são reais (não homônimos)? | B | D13.3 |
| P3 | Que fração das certidões pedidas o agregador emite sozinho, com documento válido? | A | contratação do nível 3 |
| P4 | Alguma falha volta como resultado negativo? | A, B, C | eliminatório (RFP §3.1) |
| P5 | Os protestos do bureau batem com as certidões de protesto e com o que o cliente declarou? | C | D13.6 |
| P6 | O relatório de situação fiscal do Integra bate com o e-CAC consultado à mão? | Integra | contratação do nível 3 |
| P7 | Quanto custa um alvo completo (empresa ou pessoa), por fornecedor? | todas | 13B §7 |
| P8 | Quanto tempo leva, do pedido ao resultado gravado? | todas | operação |

Open Finance e Núclea ficam fora da primeira rodada: dependem de consentimento do cliente e de
contrato (níveis 4 e 5). Entram numa segunda rodada com as mesmas regras.

## §3 A amostra

| Grupo | Alvos | Por quê |
|---|---|---|
| Empresas do mandato AMO | as 8 empresas do perímetro | o arranjo real, com o gabarito mais completo |
| Sócios e administradores | os que constam dos contratos sociais legíveis | o pré-mandato consulta PF; precisa da autorização 2.2 |
| Controle positivo | 2 CNPJs com processo, protesto ou recuperação judicial **públicos e conhecidos** | garante que o fornecedor acha o que existe |
| Controle de falha | 1 CNPJ válido de empresa baixada e 1 identificador inválido | mede a pergunta P4 |
| Terceiros (opcional) | os 20 maiores clientes e fornecedores, se o aging do AMO existir | mede o uso em crédito de terceiros (L137, L145) |

**Sem a autorização dos sócios (2.2), o piloto roda só com empresas e controles.** A parte de PF
espera; ela não é feita "por enquanto" sem autorização.

## §4 O gabarito

| Fonte do gabarito | Mede | Quem providencia |
|---|---|---|
| Certidões de distribuição já emitidas (cível, falência, trabalhista, federal) | P1, P3 | analista do mandato |
| Relatório de contingências do jurídico do cliente | P1, P2 | cliente |
| Certidões de protesto e o que o cliente declarou | P5 | analista |
| e-CAC consultado à mão com a procuração (2.5) | P6 | analista |
| Mapa de dívida e Registrato dos sócios | P5 (histórico de pagamento) | cliente |

**Onde não há gabarito**, a referência é a concordância entre fornecedores. Toda divergência é
conferida à mão no tribunal ou no órgão, e a conferência entra no relatório.

**Validade do gabarito:** certidão tem 90 dias. Certidão vencida é reemitida antes do piloto, senão
um processo novo conta como "falso positivo" do fornecedor.

## §5 O ferramental (13A, item 0.9)

1. **Planilha de entrada**: um alvo por linha (tipo, CNPJ/CPF, nome, grupo do §3).
2. **Registro de cada chamada**, no esquema da `consulta_externa`: fornecedor, alvo, fonte, data e
   hora, resultado (`encontrado`, `nada_encontrado`, `falhou`, `nao_consultado`), retorno bruto,
   custo e tempo de resposta.
3. **Script de comparação**: por alvo, os processos, certidões e protestos de cada fornecedor contra
   o gabarito, com acertos, ausências e extras.
4. **Relatório**: as métricas do §7 por fornecedor, com a lista nominal de cada ausência.

**Onde o dado fica.** Se a T0 (13A, 0.1) ainda não estiver em produção, o dado de PF do piloto
**não entra no Supabase**. Fica em pasta criptografada com acesso só do time do piloto, e é apagado
ao fim, com o registro da destruição. Dado de empresa pode ir ao banco.

**Prova de que o script não nasceu vazio (regra 2):** antes do piloto, rodar o script sobre um
gabarito sintético, apagar um processo da saída de um "fornecedor" e confirmar que a métrica P1
cai.

## §6 O protocolo

| Passo | O que | Responsável |
|---|---|---|
| 1 | Congelar a planilha de entrada e o gabarito (data e versão) | analista |
| 2 | Rodar **todos os fornecedores de uma categoria no mesmo dia**, com a mesma entrada | engenharia |
| 3 | Gravar toda chamada, inclusive as que falharam; nenhuma é repetida sem registrar a primeira | engenharia |
| 4 | Repetir as chamadas que falharam **uma vez**, 24 horas depois, e registrar as duas | engenharia |
| 5 | Rodar o script de comparação | engenharia |
| 6 | Conferir à mão cada divergência (ausência ou extra) no tribunal ou no órgão | analista |
| 7 | Escrever o relatório (§8) | engenharia + analista |

## §7 Métricas e critérios de aprovação

| Métrica | Fórmula | Aprova se | Pergunta |
|---|---|---|---|
| Cobertura processual | processos do gabarito achados ÷ processos do gabarito | ≥ 95% | P1 |
| Precisão processual | extras confirmados como reais ÷ extras conferidos | ≥ 90% | P2 |
| Campos estruturados | processos com valor, polo, classe e fase ÷ processos achados | ≥ 80% | P1 |
| Emissão de certidões | certidões emitidas com documento válido ÷ certidões pedidas nas fontes cobertas | ≥ 85% | P3 |
| Falha mascarada | falhas devolvidas como resultado negativo | **0** (eliminatório) | P4 |
| Concordância de protestos | protestos do bureau que batem com a certidão ÷ protestos da certidão | ≥ 90% | P5 |
| Situação fiscal | débitos do SITFIS que batem com o e-CAC manual ÷ débitos do e-CAC | 100% | P6 |
| Custo por alvo | soma do custo ÷ alvos completos | menor, entre os aprovados | P7 |
| Tempo por alvo | mediana do pedido ao resultado gravado | ≤ 10 minutos para consultas; registrar o das certidões | P8 |

Os limiares são a proposta inicial e devem ser aprovados pelo dono **antes** da rodada, nunca
ajustados depois de ver o resultado.

**Desempate:** entre fornecedores aprovados, vence o menor custo por alvo no volume estimado do RFP.

## §8 O relatório e onde ele fica

O relatório vai para a Espec. 13 §7, na linha de cada decisão, com:

- as métricas do §7 por fornecedor;
- a lista nominal das ausências e dos extras, com a conferência manual de cada uma;
- as chamadas que falharam e o que o fornecedor devolveu nelas;
- o custo efetivo do piloto;
- **o limite do resultado:** 8 empresas de um grupo, num estado, num setor. O número vale para esse
  perfil. O segundo mandato repete o piloto em escala menor antes de a decisão virar definitiva.

## §9 Cronograma e orçamento

| Semana | Passo |
|---|---|
| 0 | gabarito pronto (2.6), autorização (2.2), contas do nível 3, script testado (0.9), limiares aprovados |
| 1 | rodada (§6, passos 1 a 4) |
| 2 | comparação, conferência manual e relatório (§6, passos 5 a 7) |
| 3 | decisão D13.3 e D13.6; contratos do nível 4 |

**Orçamento estimado da primeira rodada:** Infosimples, a franquia de R$ 100 mais as consultas
(cerca de 15 por alvo, R$ 0,20 cada); Escavador, um alvo por pessoa e por empresa a preço de painel;
Integra, centavos por transação; bureau e JUDIT, pelos créditos de teste pedidos no RFP. O total
esperado fica abaixo de R$ 1.000 sem os créditos de teste. **Não medido:** confirma-se com a tabela
de cada um na semana 0.
