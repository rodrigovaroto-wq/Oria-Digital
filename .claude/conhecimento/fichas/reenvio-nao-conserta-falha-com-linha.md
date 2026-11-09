---
id: reenvio-nao-conserta-falha-com-linha
tipo: defeito
toca:
  - Supabase/migrations/0230_o_documento_sem_dado_financeiro_pago_a_cada_reenvio.sql
  - Supabase/test/reextracao.test.sql
  - portal/src/lib/rotulos.ts
prova: Supabase/test/reextracao.test.sql
---

**O que parecia óbvio e estava errado (P7, S123, 09/11/2026):** "falha de extração que deixou
linha gravada é pulada para sempre pelo reenvio, então o reenvio deve tentar de novo". A primeira
versão da `0230` fazia isso e foi reprovada na revisão independente, antes do commit.

**A medição que desmentiu (produção, última versão de cada documento):** das cerca de 75 falhas
com linha, só 3 são do serviço (2 de limite de cadência, 1 de resposta sem conteúdo). As outras
se repetem com o mesmo arquivo e o mesmo prompt: 36 de extração incompleta, 11 de desalinhamento,
cerca de 17 de total ou identidade que não fecha, 5 de emenda entre blocos. O próprio portal já
diz isso por motivo, em `portal/src/lib/rotulos.ts` (`reenvio: false`).

**O dano de reextrair assim mesmo:** cada reenvio paga de novo sem consertar, e a versão nova vira
a vigente. A linha que o analista já aceitou sai da Modelagem e do book sem evento nenhum
(reproduzido pelo revisor no banco de teste: v1 aceita com 100, v2 pendente com 90).

**O que ficou:** `fn_versao_extracao_concluida` é o critério da `0118` (tem linha) mais um caso
só: o último evento `extracao_sombra` declara `tem_dado_financeiro = false` sem falha. Falha com
linha continua reaproveitada até o prompt mudar (o fingerprint cuida disso).

**A lição:** antes de mandar o reenvio reextrair uma classe de falha, agrupe os motivos reais
dela em produção. Reextrair só vale para motivo transitório, e isso pede a classe do motivo
gravada no evento. É a fatia P8 do plano.
