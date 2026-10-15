---
name: rls-so-select-passa-no-superusuario
description: RLS com só policy de SELECT faz a escrita passar em todo teste (superusuário ignora RLS) e falhar no primeiro clique — teste a escrita como authenticated
metadata:
  type: architecture
---

As suítes de banco rodam como superusuário, que ignora RLS. Uma tabela com policy só de SELECT
(caso perimetro, controlador e entidade_controlador, S109) faz toda função de escrita passar nos
testes e dar 42501 na tela. Medido: `set local role authenticated` deu 42501 em
`fn_perimetro_definir_escopo` e `fn_controlador_registrar`; o UPDATE de `fn_fundir_entidade` afetava
0 linhas sem erro. Para escrita nova, o teste roda com `set local role authenticated`. Detalhe:
`.claude/conhecimento/fichas/f1-perimetro-0208-0211-caminho-de-escrita.md`.
