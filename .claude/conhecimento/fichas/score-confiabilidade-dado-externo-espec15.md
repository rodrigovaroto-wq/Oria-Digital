---
id: score-confiabilidade-dado-externo-espec15
tipo: doutrina
toca:
  - Arquitetura do Sistema/2 Especificação/15_SCORE_DE_CONFIABILIDADE_DOS_DADOS_EXTERNOS.md
  - Business Plan/06_execucao/PLANO_DE_EXECUCAO.md
  - Business Plan/08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md
substitui: []
---

# Score de confiabilidade do dado externo e portões por etapa: Espec. 15

Termos de busca: score, nota, confiabilidade, confiança, qualidade de dados, dado externo, fonte
externa, portão, gate, barreira, piso, limiar, veto, classe, Confirmado, Contestado, Não julgável,
Admiralty, Almirantado, truth discovery, Fellegi-Sunter, Trilha K, 1.K1, 1.K3, 3.8, 3.9, D15.

**Estado (24/11/2026): decidido e no plano, nada construído.** Decisões no registro v0.1.6, seção 22
(D15, D15.1–D15.15). Duas respostas do dono **diferem da recomendação da Espec. 15**: pisos já
bloqueiam no piloto (D15.4; só o score ponderado fica em sombra até o 3.8) e qualquer analista libera
o dado em REVISÃO, em qualquer gravidade (D15.3). No plano: Trilha K da Fase 1 (1.K2 vetos e 1.K3
portões dos agentes são P1), 2.18 e 2.19 na Fase 2, 3.8 e 3.9 na Fase 3.

## O que surpreende quem chega sem ler a Espec. 15

- **O score sozinho nunca aprova.** Ordem: vetos → pisos por dimensão → classe → score ponderado
  com os pesos do agente que vai usar o dado (§5A). Média sem piso esconde o zero (regras 1 e 7).
- **O score é do dado PARA UM USO.** O Registrato passa na Dívida e trava nas Entregas sem
  autorização de envio. Pesos do §5A (v2) = mediana de três avaliações independentes; os 13 casos
  saem de `15_anexos/casos_do_score.py` — mude o número no script primeiro, depois cole a tabela.
- **A v1 errou e foi corrigida pela comparação cega (23/11):** contava A4 duas vezes, tratava o
  espelho do BCB como confirmação independente e deixava processo de provedor passar sozinho no Risco.
- **Nota ausente não tem valor fixo:** sai da conta (`na`/`nm`), a cobertura mínima freia, e a fonte
  em estreia tem teto (90 oficial, 80 demais) até 30 conferências.
- **Divergir do documento do cliente NÃO baixa o score do externo.** É o achado (D3). Só baixa a
  divergência com outra fonte externa **independente** ou com uma identidade aritmética.
- **Duas fontes que leem a mesma origem são uma confirmação, não duas** (dimensão A4).
- **O portão reusa o dial** (`fn_dial_permite_auto`, `0127`) e a `consulta_externa` da Espec. 13.
  Não criar mecanismo paralelo.
- **Nenhum piso tem número ainda.** Os [A CALIBRAR] só se fixam depois do modo sombra e do
  gabarito do dado externo. Só os vetos (autorização, execução, custódia, validade) podem nascer antes.
