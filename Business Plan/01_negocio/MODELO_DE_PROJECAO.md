# Modelo de projeção (premissas em branco)

Pedido pela decisão J2: a documentação interna ganha um modelo de projeção com **premissas em
branco**, preenchidas pelo piloto. **Nenhum valor abaixo é estimado.** Célula em branco quer dizer
"ainda não medido", e o efeito de cada lacuna está escrito ao lado (regra 1 do `CLAUDE.md`: ausência
não é dado).

Quem preenche: o dono, a partir das medidas automáticas por mandato do piloto (J6). Cada valor
preenchido leva a fonte (mandato, período, medida) e a data.

## 1. Custo por mandato (medido no piloto)

| Premissa | Unidade | Valor | Fonte | Efeito enquanto em branco |
|---|---|---|---|---|
| Dias do envio ao diagnóstico aprovado | dias | | J6 | Sem prazo de entrega para propor ao cliente |
| Horas de analista por mandato | h | | J6 | Sem custo de pessoal por mandato |
| Horas do segundo revisor por mandato | h | | E1, R1 | Idem |
| Custo de IA por diagnóstico | US$ | | D5 (alerta acima de US$ 5) | Sem teto de IA (D5) |
| Custo de dados pagos por mandato | R$ | | C2, N-C6b | Sem teto de dados pagos (N-C6b) |
| Custo de infraestrutura por mês | R$ | | Estudo de infraestrutura (R2) | Sem custo fixo mensal |
| Erros por etapa e agente por mandato | nº | | J6 | Sem curva de qualidade |
| Achados em R$ por mandato | R$ | | J6 | Sem argumento de valor medido |

## 2. Receita (definida depois do piloto, J1)

| Premissa | Unidade | Valor | Efeito enquanto em branco |
|---|---|---|---|
| Preço do diagnóstico por mandato | R$ | | Sem receita de entrada |
| Assinatura de acompanhamento | R$ / mês | | Sem receita recorrente |
| Licença por usuário (mais adiante) | R$ / usuário / mês | | Sem receita por usuário |
| Bônus por resultado (opcional) | % ou R$ | | Sem receita variável |

## 3. Volume

| Premissa | Unidade | Valor | Efeito enquanto em branco |
|---|---|---|---|
| Mandatos por mês com a equipe atual | nº | | Sem capacidade |
| Mandatos que viram acompanhamento | % | | Sem base recorrente |
| Duração média do acompanhamento | meses | | Idem (G1: definida em contrato) |

## 4. Contas que o modelo fará quando houver dados

Margem por mandato = preço − (horas × custo-hora + IA + dados + parte da infraestrutura). Ponto de
equilíbrio = custo fixo ÷ margem por mandato. As contas ficam **em fórmula**, numa planilha que lê esta
tabela; elas não são feitas à mão neste arquivo. **No Excel, célula vazia vale zero:** cada fórmula
devolve vazio, com a nota do motivo, quando qualquer entrada dela estiver em branco. Sem isso, custo em
branco vira margem igual ao preço (regra 1).
