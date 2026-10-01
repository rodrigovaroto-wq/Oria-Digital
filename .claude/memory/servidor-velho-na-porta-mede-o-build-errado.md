---
name: servidor-velho-na-porta-mede-o-build-errado
description: medir um conserto do portal servindo o build localmente — se a porta já estiver ocupada, o `next start` novo morre calado e o antigo responde; a medição "não mudou nada" é do build velho
metadata:
  type: environment
tipo: ambiente
toca:
  - portal/src/lib/export.ts
---

**MEDIDO em 30/09/2026 (sessão 104).** Para validar consertos do export contra o mandato real
(Krauspenhar, caso 33b58a89) a sessão compilou o portal do branch numa worktree e o serviu na porta
3100, apontado para o Supabase de produção (export é só leitura). O primeiro servidor subiu às 22:24.
Os dois `next start` seguintes, depois de recompilar, falharam com EADDRINUSE dentro do `nohup ... &`
— e o GET do export continuou respondendo 200, pelo servidor ANTIGO.

**O custo:** a sessão concluiu, duas vezes, que a correção da detecção de subtotal "não muda nada no
arquivo real", e quase descartou um conserto certo (receita bruta 77,19 → 113,38 mi) e mandou o
agente procurar outra causa. Só a checagem do processo (`ps -eo pid,lstart,cmd | grep next-server`,
hora de início 22:24) mostrou o engano.

**A regra:** antes de medir, confira que QUEM responde é o build que você acabou de compilar — PID e
hora de início do `next-server`, ou o "Ready" no log do start novo. É a regra 7 aplicada à própria
medição: um servidor que não subiu tem a cara de um servidor que subiu e não mudou nada. E `pkill` no
mesmo comando que você quer ver morre com exit 144 (armadilha da S103): mate por PID numa chamada
separada.
