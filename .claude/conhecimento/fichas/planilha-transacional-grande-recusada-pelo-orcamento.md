---
id: planilha-transacional-grande-recusada-pelo-orcamento
tipo: defeito
toca:
  - N8N/lib/custo.mjs
  - Arquitetura do Sistema/3 Estado e Execução/DESENHO_LEITOR_TRANSACIONAL.md
---

**O que surpreende:** planilha de contas a pagar/receber linha a linha NÃO passa pela extração
por IA, e não é defeito do orçamento — é o orçamento funcionando. Em 11/11/2026 o 2º lote da AMO
("Amobeleza teste 2", n8n 9653, 68 docs) foi recusado antes de gastar: 1.828 chamadas, ~US$ 160,89
contra o teto de US$ 3, por 6 .xlsx de CP/CR com ~389 mil linhas (o maior, ~US$ 61,75 sozinho).
Nada foi enviado à IA nem gravado, e os originais NÃO subiram ao bucket.

**O caminho previsto é o leitor transacional por código** (IA só mapeia colunas; DuckDB lê todas
as linhas; COPY no Postgres; worker fora do n8n). Desenho e pesquisa com fontes em
`DESENHO_LEITOR_TRANSACIONAL.md`. **Status: guardado, não aprovado pelo dono.** Não começar sem ele.

**Junto, no mesmo dia:** um lote de 80 MB derrubou o n8n de 2 GB (9650 `crashed`, nada gravado);
o dono subiu o pod para 4 GB. Mandar um lote por vez (limite de chamadas da OpenAI é da conta).
