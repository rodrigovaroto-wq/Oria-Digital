---
name: ci-cancel-in-progress-esconde-o-run-antigo
description: o CI cancela o run anterior do mesmo branch a cada push — um commit antigo com jobs cancelados não está verde nem vermelho, e só o último commit tem a suíte completa
metadata:
  type: architecture
---

`.github/workflows/suites.yml` tem `concurrency` com `group` por workflow e ref e `cancel-in-progress:
true` (linhas 74–76). Um push novo cancela o run inteiro do commit anterior, com todos os jobs.

Na prática, o vermelho de um commit intermediário costuma ser job cancelado, não reprovação. Registrado
na pausa do redesenho (28/10/2026, `REDESENHO_DO_PORTAL.md`): as rodadas anteriores tiveram jobs
cancelados por envio seguido, e nenhum teste reprovou. `banco`, `portal`, `n8n-e-derivados` e `e2e`
passaram em `277b672`, `9339d71` e `81aca9c`. Para saber se um commit antigo passa, rode as suítes
localmente nele ou olhe o CI do último commit. Ler o CI de um commit anterior como "reprovou" é o erro
que esta entrada evita.
