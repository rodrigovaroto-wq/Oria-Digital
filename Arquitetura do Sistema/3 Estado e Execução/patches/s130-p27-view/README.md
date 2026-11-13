# s130 — scripts de medição da 0243 (view)

Tudo aqui foi escrito para a S130 e rodado como `root` contra um Postgres 16 local (`/tmp:5432`), com `sudo -u postgres`. Os caminhos apontam para `/tmp/p27/...` (o diretório de trabalho da rodada): copie os arquivos para lá ou ajuste.

- `sab.py <banco> [prefixo ...]` — o protocolo de NÃO-VAZIO (regra 2): desliga uma parte por vez e conta os asserts de `Supabase/test/fato_financeiro.test.sql` que reprovam (S = resolver, V = view/segurança, P = pendência, N = sondas, M = migration). Precisa de um banco montado pelo `run.sh`.
- `scripts/build_db.sh <banco> <modo>` (+ `prelude.sh`, `pos.sh`, copiados do `run.sh`) — monta um banco: `normal` (0001..0271 em ordem), `sem243`, `prod` (a 0243 DEPOIS da 0270/0271) ou `fixtures` (normal + as fixtures).
- `scripts/ordem.sql` — o que se confere nos dois bancos (ordem do zero x ordem de produção): requisitos, cobertura, `ln` gravado, pendência.
- `scripts/janela/` — a janela da aplicação: a migration segurando o lock (uma cópia com `pg_sleep(8)` depois do `create trigger`) enquanto o n8n extrai.
- `scripts/perf/` — `gen.sql` (gera balancetes de 4.000 rótulos distintos), `gen_all.sql` (dois mandatos 10 x 4.000 e uma Analista), `final.sql` (as leituras), `ext.sql` (a extração com e sem o gatilho), `small.sql` (documentos de 100 linhas), `jit.sql` (o efeito do JIT).
