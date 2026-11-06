---
id: token-v2-etiqueta-contra-colisao-com-v1
tipo: armadilha
toca:
  - Supabase/migrations/0222_o_envio_que_criava_o_mandato_novo_quando_o_nome_mudava.sql
  - Supabase/migrations/0223_o_token_v1_que_ainda_entrava_por_nome.sql
  - N8N/lib/assinatura-do-envio.mjs
prova: Supabase/test/run.sh
---

**Armadilha (S117, P3):** dois formatos de token assinados com o MESMO segredo colidem quando
o campo livre de um pode imitar o outro. O v1 assinava `<nome do mandato>|exp|usuario`; o v2
assina `<caso_id>|exp|usuario`. Um mandato chamado com o uuid de outro caso faria o v1 assinar
exatamente a mensagem v2 daquele caso, e o token valeria para o mandato alheio.

**O fechamento, em duas camadas:**
1. A mensagem v2 leva a etiqueta `v2|` na frente: `v2|<caso_id>|<exp>|<usuario>`.
2. A etiqueta só fecha o nome que é o uuid puro. Um mandato chamado literalmente `v2|<uuid>`
   ainda colidiria. Por isso o ramo v1 recusa como `malformado`, ANTES do HMAC, todo mandato
   normalizado que comece com `v2|` (e a lib do n8n repete a recusa).

**Desde a 0223 (aplicada em 04/11/2026) todo v1 é recusado com `versao_antiga`**, e a colisão
deixou de ser alcançável. A lição continua valendo para a próxima versão de token: **etiqueta de
versão na mensagem assinada, e recusa, no formato velho, do texto que comece com a etiqueta nova.**

**Medido (cabeçalho da 0222):** sem a etiqueta, 21 asserts reprovam; sem a guarda do v1 contra
`v2|...`, 2 reprovam.
