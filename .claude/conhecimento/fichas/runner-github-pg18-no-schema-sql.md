---
id: runner-github-pg18-no-schema-sql
tipo: armadilha
toca:
  - Supabase/test/run.sh
  - .github/workflows/suites.yml
prova: Supabase/test/run.sh
---

**Armadilha (S117, 04/11/2026):** o runner `ubuntu-latest` do GitHub passou para o Ubuntu 26.04,
que não tem `postgresql-client-16`. O CI caiu no cliente 18, e o `pg_dump` 17+ escreve
`SET transaction_timeout = 0;` no topo do dump. O 16 não escreve essa linha.

**Efeito:** o job `banco` reprovava o portão "o schema materializado bate com as migrations",
com o `schema.sql` gerado no container (cliente 16) diferente do gerado no CI (cliente 18). O
schema era idêntico; só essa linha de sessão divergia. Medido nos jobs de `cfe4e4f` e `6f3d023`.

**Correção (`ee74f16`):** o `run.sh` filtra a linha no `grep -vE` do `pg_dump`, ao lado dos
outros ajustes de cabeçalho do dump.

**A lição:** quando o portão do `schema.sql` reprova com o código igual, olhe primeiro a versão
do cliente que gerou cada lado (`pg_dump --version` no log do CI). A próxima versão do
`pg_dump` pode trazer outra linha de sessão nova, e o filtro tem de crescer junto.
