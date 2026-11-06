---
id: falha-de-envio-perdida-pela-fk-do-caso
tipo: defeito
toca:
  - Supabase/migrations/0222_o_envio_que_criava_o_mandato_novo_quando_o_nome_mudava.sql
  - Supabase/test/run.sh
prova: Supabase/test/run.sh
---

**Defeito (S117, 04/11/2026):** `execucao_falha.caso_id` é FK de `caso(id)`. Uma recusa de envio
para um mandato que não existe, ou que foi apagado no caminho, chamava
`fn_registrar_falha_execucao` com o id dele. O resultado era o erro `23503` e **a falha nunca
era gravada**. A tela não via nada, e a execução no n8n parecia só "erro de banco".

**Por que demorou três rodadas:** a revisão independente achou duas vezes um ALTO de FK
(`caso_inexistente` e `expirado`), e as duas primeiras correções foram pontuais, uma em cada
chamador. Só a terceira foi na raiz: `fn_registrar_falha_execucao` anula o id que não existe e
guarda o original no detalhe (`caso_id_anulado`). É o ponto por onde todo chamador passa.

**A lição:** quando o mesmo defeito volta por outro caminho, a correção está no lugar errado.
Liste os chamadores (`grep -rn fn_registrar_falha_execucao Supabase/ N8N/ portal/src/`) e corrija
no ponto comum, como manda o `CLAUDE.md`.

**Onde está o detalhe:** seção 2a da 0222; requisito da sonda `envio_falha_com_id_inexistente`.
Regra 2 medida no cabeçalho da 0222: sem a anulação, 3 asserts reprovam.
