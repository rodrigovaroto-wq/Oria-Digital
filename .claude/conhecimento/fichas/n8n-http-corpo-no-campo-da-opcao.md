---
id: n8n-http-corpo-no-campo-da-opcao
tipo: defeito
toca:
  - N8N/lib/macro.mjs
  - N8N/build-workflow-macro.mjs
  - N8N/test/workflow-macro-sim.test.mjs
prova: N8N/test/*.test.mjs
ancora: N8N/lib/macro.mjs#lerRespostaHttp
ancora_sha: 58e4efa01d7e
substitui: []
---

# O corpo da resposta HTTP do n8n vai para o campo que a opção nomeia, não para "body"

Termos de busca: HTTP Request, responseFormat, fullResponse, outputPropertyName, corpo, body, data,
corpo_cru, lerRespostaHttp, macro, SGS, Focus, falhou, encontrado, teste sem captura real.

## O que surpreende quem chega aqui

- Com `responseFormat: 'text'` + `fullResponse: true`, o nó HTTP do n8n NÃO põe o corpo em `body`.
  Ele põe em `outputPropertyName`, cujo padrão é `data` (`HttpRequestV3.node.ts`, ramo text).
  Quem lê `body` recebe `null` em toda chamada.
- O gerador fixa o campo EXPLÍCITO (`corpo_cru`, em `build-workflow-macro.mjs`) e o passa aos cinco
  nós Ler. Um lado sem o outro falha na hora, que é o que se quer: o leitor errado não passa calado.
- Um teste com fixture inventada (`{statusCode, body}`) passa com o defeito ligado. Medido em
  25/11/2026: com o leitor antigo e a fixture derivada do código do n8n, 11 de 34 testes do arquivo
  reprovam (30 de 447 asserts). A fixture não é captura real: não há resposta real no repositório.

## Por que importa em produção

Sem o campo certo, cada consulta vira `falhou` com motivo falso, os nós Ler entregam `__corpo` nulo,
o Normalizar lança "zero observação" e `indice_macro_obs` e `expectativa` param de receber dado sem
aviso. A aba Macro do Excel congelaria.

## Como saber que a correção está viva

MEDIDO em produção em 25/11/2026, depois da republicação do #315: na execução real 10048 (cópia
do macro publicado com webhook; ver `republicar-macro-credencial-e-teste-por-copia`), a saída de
"BCB SGS" trouxe exatamente `corpo_cru`, `headers`, `statusCode` (200) e `statusMessage` — a forma
que a fixture deriva do código do n8n — e as 37 consultas saíram `encontrado`. A versão do n8n em
produção é a do `N8N/README.md`; se ela mudar, repita essa leitura antes de confiar na fixture.
