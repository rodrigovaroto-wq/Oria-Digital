---
name: n8n-http-com-texto-cru-entrega-em-outputpropertyname
description: no nó HTTP do n8n com responseFormat text + fullResponse o corpo vai para outputPropertyName (default "data"), não "body"; fixture inventada escondeu isso
metadata:
  type: reference
---

No nó HTTP Request do n8n (HttpRequestV3), com `responseFormat: 'text'` e `fullResponse: true`, o corpo
da resposta vem no campo `outputPropertyName`, cujo padrão é `data`, e NÃO em `body`
(`HttpRequestV3.node.ts`, ramo text). Quem lê `body` recebe `null` em toda chamada, sem erro.

O gerador do repositório fixa o campo explicitamente (`corpo_cru`) e o passa ao nó Ler. A fixture
inventada `{statusCode, body}` deixava o defeito passar: com o leitor antigo, 11 de 34 testes
reprovam quando a fixture tem a forma real. Detalhes e portão em
`.claude/conhecimento/fichas/n8n-http-corpo-no-campo-da-opcao.md`.
