---
id: reenvio-nao-conserta-falha-com-linha
tipo: defeito
toca:
  - Supabase/migrations/0230_o_documento_sem_dado_financeiro_pago_a_cada_reenvio.sql
  - Supabase/test/reextracao.test.sql
  - portal/src/lib/rotulos.ts
prova: Supabase/test/run.sh
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

**A segunda versão também foi reprovada, antes de aplicar:** pular todo documento de zero linha
cujo último evento declara `tem_dado_financeiro = false`. Dos 71 que ela pularia em produção, 41
eram de tipo financeiro (DF_AUDITADA 16, NOTAS_EXPL 12, DRE 5, BALANCO 3 e outros). Quando a IA diz
"sem dado", a guarda de cobertura e o Sinal 3 se calam: não há `falha_motivo` nem pendência. A
declaração da IA não prova nada sozinha.

**O que ficou (0230, aplicada em 09/11/2026):** `fn_versao_extracao_concluida` é o critério da
`0118` (tem linha) mais um caso só: último evento sem falha e com `tem_dado_financeiro = false`,
tipo da categoria Societário/Legal menos CONTINGENCIAS, medição sem conta contada e nenhuma
`extracao_falhou` aberta. São 29 documentos em produção. Falha com linha continua reaproveitada
até o prompt mudar (o fingerprint cuida disso).

**A lição:** antes de mudar o que o reenvio pula ou paga, agrupe em produção, por motivo e por
tipo de documento, os casos que a regra nova alcança. As duas versões reprovadas pareciam certas
até essa tabela existir. Reextrair só vale para motivo transitório, e isso pede a classe do motivo
gravada no evento. É a fatia P8 do plano.
