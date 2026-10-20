---
id: grant-de-tabela-nao-vem-mais-do-supabase
tipo: defeito
toca:
  - Supabase/migrations/0214_o_grant_que_o_supabase_deixou_de_dar.sql
  - Supabase/migrations/0028_rls_e_grant_indices_macro.sql
  - Supabase/test/run.sh
  - Supabase/test/grant_de_tabela.test.sql
  - Supabase/README.md
  - Verificação/run.mts
  - Verificação/variacoes.mts
prova: Supabase/test/run.sh
ancora: Supabase/migrations/0214_o_grant_que_o_supabase_deixou_de_dar.sql#revoke delete on arquivo_oficial
ancora_sha: 42942fe3822f
substitui: []
---

# O GRANT de tabela deixa de vir do Supabase em 30/10/2026 (0214)

**Defeito (medido 20/10/2026):** a partir de 30/10/2026 tabela criada em `public` não recebe GRANT automático para
anon/authenticated/service_role. Vale para projeto novo, preview branch e `supabase db reset`; tabela existente mantém.
51 `create table` nas migrations, 39 sem GRANT. O `run.sh` e os dois harnesses E2E (`Verificação/run.mts`,
`variacoes.mts`) SIMULAVAM o default antigo, então o CI ficaria verde com produção quebrando na primeira tabela nova.

**O que mudou:** a simulação saiu dos três; a `0214` concede (authenticated e service_role, nada a anon) nas tabelas,
views e sequences existentes e REPETE os revokes intencionais depois do grant geral; a sonda ganhou o tipo `privilegio`
(6 requisitos). A `0028` ganhou uma linha de grant (único caso de migration já aplicada editada: o replay abortava nela).

**Armadilhas:**
- Revoke intencional (delete do authenticated em arquivo_oficial, perimetro, controlador, entidade_controlador,
  controlador_vinculo, caso_pergunta; update em caso_pergunta fora de entidade_id): quem cria outro o põe na 0214-style
  DEPOIS do grant e no `grant_de_tabela.test.sql`. Exigir DML completo do authenticated na sonda acusaria o revoke:
  só SELECT é exigido de toda tabela.
- `sonda-producao.mjs --so-buraco` NÃO vê requisito ausente (só migration declarada sem rastro). Quem reprova no CI o
  grant esquecido é `instalacao.test.sql` dentro do `run.sh`.
- Convenção: toda migration que cria tabela/view/sequence concede na mesma migration (`Supabase/README.md`).
