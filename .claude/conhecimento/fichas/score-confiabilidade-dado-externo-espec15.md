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
Admiralty, Almirantado, truth discovery, Fellegi-Sunter, itens 2.18 e 2.19, D15.

**Estado (23/11/2026): só desenho e pesquisa. Nada construído, por pedido do dono.** Itens 2.18
(catálogo, vetos, modo sombra) e 2.19 (calibração e portões) do plano; decisões D15.1–D15.7 abertas.

## O que surpreende quem chega sem ler a Espec. 15

- **O portão não lê um número.** Decide por vetos + piso por dimensão + classe pelo elo mais fraco.
  O número de 0 a 100 só ordena o painel. Média esconde o zero de uma dimensão (regras 1 e 7).
- **Divergir do documento do cliente NÃO baixa o score do externo.** É o achado (D3). Só baixa a
  divergência com outra fonte externa **independente** ou com uma identidade aritmética.
- **Duas fontes que leem a mesma origem são uma confirmação, não duas** (dimensão A4).
- **O portão reusa o dial** (`fn_dial_permite_auto`, `0127`) e a `consulta_externa` da Espec. 13.
  Não criar mecanismo paralelo.
- **Nenhum piso tem número ainda.** Os [A CALIBRAR] só se fixam depois do modo sombra e do
  gabarito do dado externo. Só os vetos (autorização, execução, custódia, validade) podem nascer antes.
