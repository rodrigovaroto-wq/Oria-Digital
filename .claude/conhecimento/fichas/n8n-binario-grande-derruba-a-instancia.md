---
id: n8n-binario-grande-derruba-a-instancia
tipo: numero
toca:
  - N8N/build-workflow.mjs
  - Leitor/medicao-n8n/README.md
  - Leitor/medicao-n8n/no-ler-fatia.js
  - Leitor/medicao-n8n/navegador-leitor.js
ancora: N8N/build-workflow.mjs#getBinaryDataBuffer
ancora_sha: 4a9a052af262
substitui: []
---

# Arquivo grande no nó Code: `getBinaryDataBuffer` derruba o n8n; fatia de Range não

Termos de busca: SPED grande, milhões de linhas, 10 milhões, n8n memória, heap out of memory,
task runner, getBinaryDataBuffer, Range, fatia, sub-workflow, leitor no n8n, P5, D12.9, PikaPods,
leitor no navegador, File.stream, resumo, agregado, guardar no banco, Storage.

**Medido em 13/10/2026 (sessão 108), n8n 2.30.7 local.** O detalhe e a tabela estão em
`Leitor/medicao-n8n/README.md`.

- **`this.helpers.getBinaryDataBuffer` num arquivo grande derruba o processo PRINCIPAL do n8n.**
  - Para chegar ao task runner, o binário vira um objeto JS byte a byte: 117 MB viraram 3,9 GB.
  - Com 3M de linhas de SPED (355 MB) e heap padrão, deu `FATAL ERROR ... JavaScript heap out of memory`.
  - Com 1M (117 MB) e heap de 384 MB, deu o mesmo erro.
  - Cai a instância inteira, e não só a execução.
- **O que passa: Range HTTP em fatias, como bytes, e gravação por sub-workflow.**
  - Fatia de 4 MB por pedido, porque o corpo também é serializado no caminho até o runner.
  - Fatia de 32 MB por execução filha.
  - 10.000.010 linhas foram gravadas no Postgres em 222 s, com pico de 563 + 386 MB e o heap limitado a 384/192.
  - É o mesmo pico do 1M.
  - O sub-workflow importa: num laço na mesma execução, o `runData` de cada volta fica na memória.
- **Fatia baixada com `encoding: 'text'` perde o acento.** O SPED é latin1, então tem de ser `arraybuffer` e `toString('latin1')`.

- **A alternativa que não passa pelo n8n nem pelo Storage é ler no navegador.** Medido com
  `navegador-leitor.js` num Chromium real, sobre uma ECD de 10M de linhas com composição realista:
  - 22,9 s, com 59 MB de pico no JS;
  - o SHA-256 incremental é igual ao `sha256sum`;
  - os registros-chave vão na íntegra e os 7,48M de `I250` são somados por conta e mês;
  - o resumo tem 3,4 MB (745 KB comprimido), contra 1,95 GB da carga bruta.
  - O custo: o lançamento individual não fica no banco.

**Quem desmente isto:** rodar de novo `Leitor/medicao-n8n/` em outra versão do n8n. O
comportamento do runner muda entre versões, e a âncora acima marca SUSPEITA quando o
`Preparar Conteudo` mexer na leitura do binário.
