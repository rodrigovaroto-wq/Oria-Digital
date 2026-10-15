---
id: f1-perimetro-0208-0211-caminho-de-escrita
tipo: defeito
toca:
  - Supabase/migrations/0208_a_situacao_do_perimetro_que_so_o_teste_lia.sql
  - Supabase/migrations/0209_o_escopo_que_nao_se_confirmava_nem_se_encerrava.sql
  - Supabase/migrations/0210_a_escrita_do_perimetro_que_so_o_superusuario_fazia.sql
  - Supabase/migrations/0211_a_fusao_que_apagava_o_perimetro_da_absorvida.sql
  - Supabase/test/perimetro_situacao.test.sql
  - Supabase/test/perimetro_encerrar.test.sql
  - Supabase/test/f1_escrita_authenticated.test.sql
  - Supabase/test/fusao_perimetro.test.sql
  - portal/src/app/casos/[id]/perimetro/actions.ts
  - portal/src/lib/perimetro.ts
  - portal/scripts/verificar-perimetro.mts
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0211_a_fusao_que_apagava_o_perimetro_da_absorvida.sql#fn_fundir_entidade
ancora_sha: c6c5e3cd35d2
substitui: []
---

# F1: o caminho de escrita do perímetro que ninguém chamava (0208–0211 + a tela)

**Escrita em:** 15/10/2026 · PR #259 (draft) · **Nada aplicado em produção.** As 0208–0211 estão
no repositório; a sonda não as conferiu.

**O defeito que a originou:** as funções da F1 (0178–0183) não tinham NENHUM chamador fora de
`Supabase/test` (grep em `portal/src`, `N8N` e `Leitor`: zero). O perímetro só se declarava por
SQL, e os testes que o exercitavam rodam como superusuário — o que esconde a RLS. Isso é a regra 7:
o estágio existia e nunca rodou fora do teste.

## O que cada peça entrega

- **0208** — `fn_perimetro_situacao` (o que falta, por entidade) e `fn_perimetro_veredito` (o
  veredito do caso). O aceite financeiro nunca aparece como "ok" enquanto não houver combinado.
  Um motivo novo sem frase na tela reprova (`verificar-perimetro.mts` lê o vocabulário da própria
  0208).
- **0209** — `fn_perimetro_definir_escopo` idempotente (repetir o mesmo escopo devolve o vigente,
  sem linha nova) e `fn_perimetro_encerrar_escopo`, para tirar uma entidade de um escopo.
- **0210** — policies de INSERT/UPDATE para `authenticated` em `perimetro`, `controlador` e
  `entidade_controlador`; DELETE revogado nas três. Sem security definer.
- **0211** — `fn_fundir_entidade` reemitida: leva o perímetro da absorvida para a sobrevivente
  (antes o `ON DELETE CASCADE` o apagava em silêncio) e repõe as controladas.
- **Tela** `/casos/[id]/perimetro`: lê o veredito e a situação, e grava pelas funções. Não
  recalcula regra: só traduz a chave que o banco devolve.

## Medido (regra 2) — números das mensagens de commit

| Migration | Suíte | Asserts | Reprovam no estado anterior |
|---|---|---|---|
| 0208 | `perimetro_situacao.test.sql` | 52 | 9 (com pronta sempre verdadeira) |
| 0209 | `perimetro_encerrar.test.sql` | 28 | idempotência 2, sem vigente 5, outras 1 a 6 cada |
| 0210 | `f1_escrita_authenticated.test.sql` | 20 | **14 de 20** (aborta no bloco da sonda) |
| 0211 | `fusao_perimetro.test.sql` | 20 | **17 de 20** (com o corpo da 0183) |
| tela | `verificar-perimetro.mts` | 48 | 7 em 5 mutações; `next build`, `tsc`, `eslint` limpos |

Reconferido nesta rodada: `verificar-perimetro.mts` 48/0. Não aberta em navegador nem contra Postgres.

## A lição que cabe nesta ficha

**RLS com só `SELECT` faz o caminho de escrita passar em todo teste e falhar no primeiro clique.**
Os testes rodam como superusuário, que ignora RLS. Medido com `set local role authenticated` (em
transação desfeita): `fn_perimetro_definir_escopo` → 42501; `fn_controlador_registrar` → 42501.
Em cascata, `fn_fundir_entidade` perdia o vínculo de controle da absorvida **sem erro**, porque o
UPDATE afetava 0 linhas. Escreva o teste de escrita como `authenticated`; é o único que vê RLS.
(`.claude/memory/rls-so-select-passa-no-superusuario.md`.)

## Efeitos NÃO corrigidos (ditos, não escondidos)

- `caso_pergunta` tem FK `NO ACTION` para `entidade`: a fusão **falha alto** quando a entidade
  absorvida é citada numa pergunta. Decisão pendente do dono (decisão 5c do ESTADO).
- `caso_modelagem` e `caso_linha_premissa` guardam o **nome** da entidade: após a fusão, o nome
  fica órfão.
- A policy de escrita vale também para escrita direta na tabela (um UPDATE em `perimetro` sem
  evento passa). Restringir às funções exigiria security definer, que a casa não usa.

## Não verificado

- Deploy do portal e a aba de envio do zip (fora desta ficha: ver ESTADO, SESSÃO 109).
- A sonda contra produção sobre 0208–0211: **NÃO CONFERIDO**.
