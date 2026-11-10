---
id: chromium-posix-descarta-arquivo-com-acento
tipo: armadilha
toca:
  - Verificação/enviar-book.mts
---

**O que parecia (07/11/2026):** "8 de 11 arquivos com acento no nome somem entre o portal e o
n8n, sem rastro" — um ALTO da P4, que mandava investigar o portal e o Form do n8n.

**O que era (S124, 09/11):** o script de teste. O `setInputFiles` do Playwright, com o Chromium
em locale POSIX (o do container), descarta em silêncio todo caminho com caractere fora do ASCII.
O portal já dizia "3 arquivo(s) enviado(s)": a lista chegava com 3 ao formulário.

**Medido (book-espelho, 11 arquivos, 8 com acento ou cedilha):** POSIX, 3 de 11 no input;
`LC_ALL=C.UTF-8` no launch, 11 de 11. O encaminhamento do portal reproduzido à parte (fetch
multipart até o formidable): 11 de 11. Provado ao vivo: o reenvio dos 8 virou 8 de 8 documentos.

**A lição:** antes de investigar o produto por um arquivo que "sumiu", conte quantos o input do
navegador automatizado realmente recebeu. E rode `enviar-book.mts` sempre com locale UTF-8.

**Não provado:** navegador real de cliente em Windows ou macOS. Não há como reproduzir daqui.
Não há suíte que reprove esta lição (o script é a ferramenta de teste), por isso a ficha não tem `prova`.
