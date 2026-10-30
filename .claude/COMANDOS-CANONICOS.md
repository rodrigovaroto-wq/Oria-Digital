# Comandos canônicos

> Saiu do `CLAUDE.md` em 30/10/2026: eram 9.100 dos 18.116 caracteres que TODA sessão carrega
> (~2,3k tokens), inclusive as de plano, documento e apresentação, que não rodam suíte nenhuma.
> **Antes de rodar qualquer suíte, abra este arquivo inteiro** — rodar parte das suítes por não
> tê-lo aberto é o defeito das sessões 82 e 86, descrito abaixo. O portão
> `node .claude/verificar-espelho-claude-md.mjs` continua exigindo o espelho, agora deste arquivo.

Use exatamente estes. O CI (`.github/workflows/suites.yml`) é a lista completa e a fonte.

```bash
# preparar o container (a sessão 14 perdeu tempo nos três)
cd portal && npm ci --ignore-scripts && cd ..   # --ignore-scripts: igual ao CI
cd "Dados de Teste"/book-vertentes && python3 -m pip install --quiet 'reportlab==5.0.1' \
  && PYTHONPATH=. python3 gerar.py && cd ../..   # PYTHONPATH=. é obrigatório
# O CANASTRA TAMBÉM, e ele faltava aqui: `medir-regua-cobertura.mjs` morre em
# "Falta .../book-canastra/pdf/METRICAS.json" sem este passo. O CI gera os DOIS.
cd "Dados de Teste"/book-canastra && PYTHONPATH=. python3 gerar.py && cd ../..
# O terceiro book (F2.4, distress): o gerador É o teste — 16 identidades por `assert`.
cd "Dados de Teste"/book-distress && PYTHONPATH=. python3 gerar.py && cd ../..
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf -k /tmp -p 5432" -l /tmp/pg.log start
# O `run.sh` roda COMO postgres e REESCREVE `Supabase/schema.sql`. Num container em que
# o repositório é do root, ele morre em "Permission denied" DEPOIS de aplicar as 101
# migrations — e nenhum `*.test.sql` chega a rodar. Custou uma passada na sessão 78.
chmod a+w Supabase Supabase/schema.sql

# suítes
node --test 'N8N/test/*.test.mjs'
node --test 'Leitor/test/*.test.mjs'          # o leitor de arquivos oficiais (F2T): SPED, XML fiscal, CNAB, OFX
node --test '.claude/hooks/test/*.test.mjs'   # os hooks do agente também têm suíte, e ela é portão
node --test 'Supabase/test/*.test.mjs'       # a tradução de "não perguntei a produção" em veredito
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-apresentacao.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-transcricao.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-mensagem-de-falha.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-premissas-do-realizado.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-kit-basico.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-modelagem-cobertura.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-limite-de-envio.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-envio-oficial.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-linhas-por-versao.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-exclusividade-ciclo.mts
./portal/node_modules/.bin/tsx portal/scripts/verificar-perimetro.mts
node --test '.claude/conhecimento/test/*.test.mjs'  # ANTES de indexar: o grafo COMMITADO não pode
                                                   # citar arquivo que o git ignora (depois do
                                                   # indexar essa pergunta é verdadeira por construção)
node .claude/conhecimento/indexar.mjs && git diff --exit-code -- .claude/conhecimento/grafo.jsonl \
  && node .claude/conhecimento/conferir.mjs   # o índice do conhecimento é derivado e tem portão
node .claude/verificar-comandos.mjs           # todo subagent_type citado por comando existe
node .claude/verificar-espelho-claude-md.mjs  # este bloco não ficou para trás do CI
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh
CONFERIR_PSQL="sudo -u postgres psql -h /tmp -p 5432" CONFERIR_DB=tdf_test \
  node Supabase/test/conferir-chamadas.mjs
SONDA_PSQL="sudo -u postgres psql -h /tmp -p 5432 -d tdf_test" \
  node Supabase/test/sonda-producao.mjs --so-buraco   # banco completo tem de dar ZERO buracos
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" ./portal/node_modules/.bin/tsx Verificação/run.mts
./portal/node_modules/.bin/tsx Verificação/variacoes.mts

# medidores — rodam no CI e reprovam: a régua contra o texto que produção produz,
# e o custo do book contra o modelo de estimativa. Precisam dos DOIS books gerados.
node N8N/medir-regua-cobertura.mjs
node N8N/medir-custo-book.mjs

# geradores — o gerado TEM de ficar igual ao commitado (`git diff --exit-code`)
node N8N/build-workflow.mjs && node N8N/build-workflow-macro.mjs \
  && node N8N/build-workflow-diagnostico.mjs && node N8N/build-workflow-erros.mjs
# e o conferidor em SQL que se cola no SQL Editor, gerado dos mesmos nós Postgres (24/09/2026)
node Supabase/conferir/gerar-conferir-chamadas.mjs > Supabase/conferir/conferir_chamadas.sql \
  && git diff --exit-code -- Supabase/conferir/conferir_chamadas.sql
# E AS FIXTURES DO BOOK, que faltavam aqui até 16/09 (F0, fatia 0.4): as TRÊS pontas se comparam
# entre si — o `.sql` do banco, o `.json` do export e o gabarito. Desincronizar uma faz as outras
# duas mentirem sobre a terceira, e foi o que aconteceu em 19/08.
cd "Dados de Teste"/book-vertentes \
  && PYTHONPATH=. python3 ../../Supabase/test/gerar_fixture.py > ../../Supabase/test/fixture_book_vertentes.sql \
  && PYTHONPATH=. python3 ../../Supabase/test/gerar_fixture.py --json > ../../portal/scripts/fixtures/book-vertentes.json \
  && cd ../book-canastra \
  && PYTHONPATH=. python3 ../../Supabase/test/gerar_fixture_canastra.py > ../../Supabase/test/fixture_book_canastra.sql \
  && cd ../.. && git diff --exit-code -- Supabase/test/fixture_book_vertentes.sql \
     portal/scripts/fixtures/book-vertentes.json Supabase/test/fixture_book_canastra.sql

# contra PRODUÇÃO — não roda no `suites.yml` (ele monta o próprio banco, sempre em dia).
# Quem roda é o workflow agendado `sonda-producao.yml`, e à mão é assim. Sem `SONDA_PSQL` o
# script sai com 2 = NÃO CONFERIDO, que é diferente de verde:
SONDA_PSQL="psql 'postgresql://usuario:SENHA@host:5432/postgres'" node Supabase/test/sonda-producao.mjs
# E a cobertura do lote real, que é o ACEITE FINANCEIRO da F0 (fatia 0.5): ≥95% dos documentos
# com linha, e a diferença explicada documento a documento. Somente leitura — e o percentual
# sozinho não cumpre o critério, por isso a consulta separa "não tinha número para dar" (`0111`)
# de "a extração voltou vazia e ninguém assumiu".
psql "$URL" -v caso_id="'<uuid do caso>'" -f Supabase/test/cobertura-do-lote.sql
# E o inventário do perímetro (F1, fatia 1.1): entidade por caso com CNPJ/papel, e a causa NOMEADA
# de cada `entidade_incorreta` aberta — 71 pendências não é diagnóstico, é contagem (regra 1).
CONFERIR_PSQL="psql 'postgresql://usuario:SENHA@host:5432/postgres'" node Supabase/test/perimetro-inventario.mjs
# E a republicação do n8n, que é o passo sem o qual a correção fica no repositório e não no ar.
# O caminho normal é Actions → "Republicar workflow no n8n"; o script que ela roda é:
N8N_URL=... N8N_API_KEY=... N8N_WORKFLOW_ID=... bash N8N/republicar.sh
# N8N_ARQUIVO_REPO escolhe QUAL dos quatro (padrão: a ingestão) — generalizado em 16/09/2026

# portal
cd portal && ./node_modules/.bin/tsc --noEmit && ./node_modules/.bin/eslint . \
  && ./node_modules/.bin/next build
```

> **E o espelho JÁ ficou para trás DUAS vezes — sessões 82 e 86.** Na 82 o CI rodava seis suítes
> de verificação e este bloco listava quatro (`verificar-kit-basico.mts` e
> `verificar-modelagem-cobertura.mts` faltavam): a "baseline completa" daquela sessão saiu sem 18
> asserts. Na 86 foram os dois MEDIDORES, que rodavam no CI e não estavam aqui — e um deles nem
> roda sem o `book-canastra`, cujo preparo também faltava acima. **Quem acrescenta suíte ou medidor
> ao CI acrescenta a linha aqui na mesma passada**, e desde 16/09/2026 isso não depende mais de
> ninguém lembrar: `node .claude/verificar-espelho-claude-md.mjs` roda no CI e reprova a
> divergência dos dois lados, inclusive arquivo citado que não existe mais.

**Conflito de merge em arquivo DERIVADO nunca se resolve à mão.** `grafo.jsonl`, os quatro
`N8N/workflow*.json`, `Supabase/conferir/conferir_chamadas.sql`, `Supabase/schema.sql` e as
fixtures do book conflitam em TODO par de PRs abertos juntos (medido em 05/10/2026: #252 × #253,
três conflitos, dois deles derivados). A regra é pegar qualquer um dos dois lados e REGERAR com os
comandos acima, nesta ordem: geradores do n8n → conferidor SQL → `run.sh` (reescreve o
`schema.sql`) → teste do conhecimento → `indexar.mjs` por último, porque ele indexa todos os
outros. E dois PRs com migration: o topo do `ESTADO.md` passa a citar a de número maior. Desde
05/10 o `run.sh` reprova a declaração velha, que antes passava se o nome aparecesse em qualquer
linha.

`npx` **não** serve no lugar de `./portal/node_modules/.bin/<bin>` — para o `tsx`, o `tsc`, o
`eslint` ou o `next`: sem o binário do lock, o npx baixa a última versão publicada no dia. Esta
regra existia aqui desde sempre e o CI a desobedecia em três linhas até 01/09 (era o que o Sonar
cobrava em `githubactions:S6505`/`S8543`). Agora os dois concordam — e é por isso que os comandos
acima têm de continuar concordando: **este bloco é espelho do CI, e espelho que fica para trás é
pior que espelho nenhum**, porque manda a próxima sessão instalar diferente do portão.
