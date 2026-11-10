---
id: xlsx-de-varias-abas-so-a-primeira-era-lida
tipo: defeito
toca:
  - N8N/build-workflow.mjs
  - N8N/lib/formato.mjs
prova: N8N/test/*.test.mjs
---

**Defeito (S124, 10/11/2026):** o n8n lia só a primeira aba do `.xlsx`, porque o repositório não
fixava `sheetName`. As 4 planilhas do book-espelho perderam a 2ª aba. Real: Endividamento
Krauspenhar.xlsx gravou 0 linhas.

**Correção (`3075c8d`, `e5252d9`, na branch; ingestão NÃO republicada no momento da ficha):** 3 nós
novos, Copiar Como ZIP, Ler Abas do XLSX (Compression) e Expandir Abas, com `sheetName` por item.
Decisão do dono: ler no n8n, com o arquivo intacto. `.xls` fica de fora (shortcut declarado).
O teste fica em `N8N/test/abas-do-xlsx.test.mjs`.

**NÃO provado:** as premissas sobre os nós nativos (Compression, `sheetName`) foram lidas no FONTE de
n8n-nodes-base@2.46.6, não na instância. A suíte simula os dois nós nativos. Só a republicação, com
o reenvio das 4 planilhas e a conferência das abas no banco, prova.

**A lição:** o cabeçalho de aba contava como conta na régua (a pendência mentia "leu só a primeira"
sem a origem da linha, `55f2e88`). Quem muda a leitura de planilha confere a origem da linha de
cada aba, não só o total.
