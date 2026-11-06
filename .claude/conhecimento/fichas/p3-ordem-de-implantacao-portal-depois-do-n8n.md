---
id: p3-ordem-de-implantacao-portal-depois-do-n8n
tipo: armadilha
toca:
  - Arquitetura do Sistema/3 Estado e Execução/DESENHO_P3_ROTEAR_POR_CASO_ID.md
  - Supabase/migrations/0222_o_envio_que_criava_o_mandato_novo_quando_o_nome_mudava.sql
  - N8N/conferir-publicado.mjs
---

**Armadilha (S117, P3):** uma mudança que atravessa banco, n8n e portal tem uma ordem de
implantação rígida. Cada ordem errada falha de um jeito diferente, e uma delas não falha:

| Ordem errada | O que acontece |
|---|---|
| Portal novo antes da 0222 | Todo envio recusado como `malformado`. Erro explícito |
| n8n novo antes da 0222 | Todo envio falha: `fn_caso_do_envio` não existe. Erro explícito |
| **Portal novo com o n8n ANTIGO** | **Silencioso.** A 0222 ignora o nome no v2 e o `Upsert` antigo grava pelo nome do Form. Um Analista alocado só em A posta `Mandato=B` e os documentos caem em B, com execução verde e sem auditoria |

**A ordem certa:** 0222 com a sonda conferida → n8n republicado **e o publicado conferido**
(`N8N/conferir-publicado.mjs`) → deploy do portal → 30+ min sem nenhum v1 aceito no histórico do
n8n → 0223.

**Por que conferir o publicado, e não o JSON do repositório:** a sonda do banco não vê a versão
do n8n. O JSON certo no repositório não prova nada sobre o que está no ar.

**Generalização:** antes de implantar mudança em mais de uma camada, monte a tabela "camada X
nova com Y antiga" e procure a linha que não dá erro. Essa linha decide a ordem.
