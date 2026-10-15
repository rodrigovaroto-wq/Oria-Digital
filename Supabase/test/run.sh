#!/usr/bin/env bash
# Aplica as migrations num Postgres local, carrega os fixtures dos DOIS books
# (Vertentes, o fácil; Canastra, o difícil) e roda os testes de reconciliação.
#
#   Supabase/test/run.sh                     # usa um Postgres já rodando (PGHOST/PGPORT/PGUSER)
#   PGPORT=5599 Supabase/test/run.sh         # porta alternativa
#
# Precisa de um Postgres 16 acessível e de permissão para criar banco. Não toca
# em Supabase — é tudo local e descartável (o banco é recriado a cada execução).
set -euo pipefail

DB="${TEST_DB:-tdf_test}"
RAIZ="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$RAIZ"

psql -q -c "drop database if exists $DB" -c "create database $DB"

# Papéis e schema que o Supabase provê por padrão e as migrations assumem.
for r in anon authenticated service_role; do
  psql -tAc "select 1 from pg_roles where rolname='$r'" | grep -q 1 \
    || psql -q -c "create role $r nologin"
done
psql -q -d "$DB" -c "
  create schema if not exists storage;
  create table if not exists storage.buckets(id text primary key, name text, public boolean default false);
  create table if not exists storage.objects(id uuid default gen_random_uuid() primary key,
    bucket_id text, name text, owner uuid);
  alter table storage.objects enable row level security;" >/dev/null

# Supabase configura isto UMA VEZ, na criação do projeto — e nenhuma migration
# deste repositório faz GRANT de tabela (nem precisa) porque conta com isso.
# É por isso que um defeito de AUTORIZAÇÃO nunca tinha sido pego por teste
# nenhum aqui: sem replicar este passo, `set role authenticated` falharia para
# QUALQUER tabela, não só a que tem o bug — o teste acusaria falso positivo em
# geral, então ninguém testava como authenticated. Achado real:
# Supabase/migrations/0028 (índices macro sem RLS nem grant).
#
# Função é DIFERENTE de tabela, e não replicamos o lado de função aqui — de
# propósito, depois de medir. Em produção o Supabase impede EXECUTE público em
# função nova (é por isso que este projeto já tem, desde a sessão 8, `grant
# execute ... to authenticated` explícito em toda função chamada PELO PORTAL:
# 0008 `fn_revisar_documento`, 0011 `fn_aceitar_extracao`, 0028
# `fn_indice_macro_anual`). Tentei replicar isso aqui com `alter default
# privileges ... revoke execute on functions from public` e MEDI que não
# funciona neste Postgres: a revoke não grava linha em `pg_default_acl` (objtype
# 'f') e função criada depois continua executável por PUBLIC — plain Postgres
# não tem como REVOGAR um default que nunca foi GRANTado por default privilege
# (o hardcoded "PUBLIC pode executar" não passa por ali). O mecanismo real do
# Supabase para isso não é `ALTER DEFAULT PRIVILEGES` puro. Por isso os `grant
# execute` em migration continuam sendo o único jeito CORRETO de garantir o
# acesso em produção — só não dá para provar aqui, com teste local, que a
# ausência deles quebraria (o teste da 0028 exercita a chamada como smoke test,
# não como negativo).
psql -q -d "$DB" -c "
  grant usage on schema public to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;"

# Duas migrations com o MESMO prefixo não geram conflito de merge — o git aceita
# `0035_a.sql` e `0035_b.sql` de branches diferentes sem uma palavra, e o laço
# abaixo aplica as duas na ordem alfabética do SUFIXO. A ordem oficial de
# aplicação (`Supabase/README.md`) passa a mentir em silêncio, e nada acusa. É por isso
# que a checagem existe, e é por isso que ela vem ANTES de aplicar qualquer coisa:
# com duas pessoas no repositório (faixas em `CLAUDE.md`), colisão é questão de
# tempo, e o lugar de morrer é o PR, não o banco de produção.
#
# BURACO na sequência é LEGÍTIMO e não reprova: as faixas reservam 0035-0099 ao
# dono, então 0034 → 0100 é o estado esperado, não um erro.
echo "== numeração das migrations"
dup=$(for f in Supabase/migrations/*.sql; do basename "$f" | cut -c1-4; done | sort | uniq -d)
if [ -n "$dup" ]; then
  echo "FALHOU: prefixo de migration duplicado — cada número tem de ser único."
  for n in $dup; do
    echo "   $n:"
    for f in Supabase/migrations/"$n"*.sql; do echo "     - $f"; done
  done
  echo "   Renumere a mais nova respeitando as faixas de CLAUDE.md (dono 0035-0099, estagiário 0100+)."
  exit 1
fi
echo "   sem prefixo duplicado"

# A LISTA DE COMANDOS DO Supabase/README.md É O QUE O DONO COPIA PARA APLICAR.
#
# O CLAUDE.md chama esse arquivo de "ordem oficial de aplicação", e o próprio
# README já narra o estrago de ele ficar atrás: treze migrations (0032→0044)
# nunca entraram na lista, e quem aplicasse seguindo-a pararia na 0031 com um
# banco "sem Portão 2, sem catálogo de premissas, sem papel da linha — sem nenhum
# erro, só faltando".
#
# ACONTECEU DE NOVO, e desta vez custou uma rodada de produção: a `0101` entrou na
# TABELA do README e **não** na lista de comandos. O dono mergeou o PR, aplicou o
# que a lista mandava, e a tela de Modelagem continuou mostrando o mesmo defeito —
# porque a correção nunca chegou ao banco. Da tela, "aplicada" e "não aplicada"
# têm exatamente a mesma aparência.
#
# Escrever migration e esquecer de listá-la é um erro silencioso de UMA linha, e é
# o único passo entre "corrigido no git" e "corrigido em produção". Aqui ele para
# de ser silencioso.
echo "== o Supabase/README.md lista todas as migrations"
faltando=""
for f in Supabase/migrations/*.sql; do
  grep -qF "$f" Supabase/README.md || faltando="$faltando $f"
done
if [ -n "$faltando" ]; then
  echo "FALHOU: migration que existe e o Supabase/README.md não manda aplicar:"
  for f in $faltando; do echo "     - $f"; done
  echo "   Acrescente 'supabase db execute --file <arquivo>' na lista de comandos do Supabase/README.md."
  echo "   Sem isso o dono aplica o que a lista diz, a correção não chega ao banco, e a tela"
  echo "   mostra o defeito antigo como se o PR não tivesse funcionado."
  exit 1
fi
echo "   as $(ls Supabase/migrations/*.sql | wc -l) migrations estão na lista de aplicação"

# TODO *.test.sql É CHAMADO POR ESTE ARQUIVO — a mesma guarda de cima, para os testes.
#
# Até 24/09/2026 um teste novo que alguém esquecesse de acrescentar abaixo passava com o CI verde
# SEM NUNCA RODAR — estágio que não rodou com a aparência de estágio que rodou e não achou nada
# (regra 7). Os 67 de hoje estão todos aqui; o que esta guarda impede é o 68º. O critério é o
# arquivo aparecer num `-f` deste script (o teste de escala da 0164 conta: ele é chamado, só que
# condicionado a ESCALA_0164=1, e o motivo está escrito junto).
echo "== todo Supabase/test/*.test.sql é executado por este run.sh"
este="${BASH_SOURCE[0]}"
sem_chamada=""
for f in Supabase/test/*.test.sql; do
  # Linha COMENTADA não conta: `# DESLIGADO: psql … -f <teste>` é exatamente o estágio desligado
  # com cara de limpo que esta guarda existe para barrar (achado da 3ª revisão do PR #244).
  grep -F -- "-f $f" "$este" | grep -qv '^[[:space:]]*#' || sem_chamada="$sem_chamada $f"
done
if [ -n "$sem_chamada" ]; then
  echo "FALHOU: teste que existe e que este run.sh nunca executa:"
  for f in $sem_chamada; do echo "     - $f"; done
  echo "   Acrescente a linha 'psql -v ON_ERROR_STOP=1 -d \"\$DB\" -f <arquivo>' no ponto certo da ordem."
  echo "   Sem isso o teste fica no repositório com cara de portão e o CI fica verde sem rodá-lo."
  exit 1
fi
echo "   os $(ls Supabase/test/*.test.sql | wc -l) testes .sql estão na lista de execução"

# O ESTADO.md CITA A MIGRATION MAIS NOVA — e é assim que ele não envelhece.
#
# O cabeçalho do HANDOFF.md passou 17 PRs congelado em "migrations até 0034",
# mandando quem chegava começar errado. Documento de estado não envelhece por
# descuido: envelhece porque nada acusa. Aqui acusa — e a checagem é sobre o
# fato que mais se move (a última migration), não sobre o texto inteiro, que
# viraria um portão irritante e sem valor.
echo "== o ESTADO.md aponta para a migration mais nova"
ultima=$(ls Supabase/migrations/*.sql | sort | tail -1 | xargs basename)
if ! grep -qF "$ultima" ESTADO.md; then
  echo "FALHOU: a migration mais nova é $ultima e o ESTADO.md não a cita."
  echo "   Atualize o ESTADO.md — ele é o que alguém lê para saber onde o projeto está."
  exit 1
fi
# E A DECLARAÇÃO NÃO PODE MENTIR. O `grep` acima passa com o nome em QUALQUER lugar do arquivo — e
# dois PRs com migration abertos ao mesmo tempo produzem exatamente o caso que ele não vê: medido no
# merge simulado do #252 (0199–0204) com o #253 (0205) em 05/10/2026, o topo dizia "Migration mais
# nova: 0204" e o portão passava porque a seção do #253, mais abaixo, citava a 0205. Toda linha que
# DECLARA a mais nova tem de citar a de verdade; arquivo sem declaração fica só com o grep acima.
declaradas=$(grep -n "Migration mais nova" ESTADO.md | grep -vF "$ultima" || true)
if [ -n "$declaradas" ]; then
  echo "FALHOU: o ESTADO.md declara como mais nova uma migration que não é a $ultima:"
  echo "$declaradas" | cut -c1-160 | sed 's/^/   /'
  echo "   Depois de um merge de dois PRs com migration, o topo tem de passar a citar a $ultima."
  exit 1
fi
echo "   $ultima"

# A 0163 nasceu porque a 0161/0162 patchavam fn_registrar_diagnostico por
# ÂNCORA sobre pg_get_functiondef() sem tolerância a CRLF (a 0160, mesma
# técnica, já sabia — usava `\r?\n`), e produção guarda o corpo com `\r\n`
# desde que passou por um editor/colagem do Windows uma vez. Este portão
# varre TODA migration nova em busca da mesma forma frágil, ANTES de aplicar
# migration nenhuma — estático, não precisa do banco de pé.
echo "== nenhuma migration patcheia corpo de função com âncora multi-linha sem \\r?"
if ! python3 Supabase/test/guarda_ancora_crlf.py; then
  exit 1
fi

echo "== migrations"
for f in Supabase/migrations/*.sql; do
  if ! out=$(psql -q -v ON_ERROR_STOP=1 -d "$DB" -f "$f" 2>&1); then
    echo "FALHOU $f"; echo "$out" | head -20; exit 1
  fi
done
echo "   $(ls Supabase/migrations/*.sql | wc -l) migrations aplicadas"

# -----------------------------------------------------------------------------
# O CATALOGO DE INSTALACAO DECLARA ATE ONDE FOI REVISADO — e este portao existe
# porque ele passou 16 migrations sem que nada acusasse.
#
# A sonda `fn_instalacao_conferir` responde "o que precisa existir no banco de
# PRODUCAO esta la". Ela so responde sobre o que o catalogo LISTA — e o catalogo
# parou na 0130 enquanto o banco chegava na 0146. Ninguem errou: nada acusa um
# catalogo que fica para tras, exatamente como nada acusava o cabecalho do
# HANDOFF.md congelado em "migrations ate 0034".
#
# O portao e o MESMO do ESTADO.md logo acima, e por isso e barato: compara a
# migration mais nova do diretorio com a cobertura declarada pelo banco recem
# montado. Quem escreve a proxima migration e obrigado a decidir uma das duas
# coisas — "acrescento um requisito" ou "revisei e nao ha o que acrescentar" —
# e as duas passam por um `update instalacao_cobertura`. Nenhuma delas e "nao
# pensei nisso".
echo "== o catálogo de instalação foi revisado até a migration mais nova"
num_ultima="${ultima%%_*}"
cobertura=$(psql -qAt -d "$DB" -c "select ate_migration from instalacao_cobertura" 2>/dev/null | tr -d '[:space:]')
if [ -z "$cobertura" ]; then
  echo "FALHOU: instalacao_cobertura está vazia ou não existe — a 0147 não foi aplicada."
  exit 1
fi
if [ "$cobertura" != "$num_ultima" ]; then
  echo "FALHOU: a migration mais nova é $num_ultima e o catálogo de instalação"
  echo "   declara revisão só até $cobertura."
  echo "   Ou a migration nova precisa de um requisito em instalacao_requisito"
  echo "   (o painel de produção não vê o que o catálogo não lista), ou ela não"
  echo "   precisa — e nesse caso diga isso, com o motivo:"
  echo "     update instalacao_cobertura set ate_migration = '$num_ultima',"
  echo "            revisado_em = current_date, observacao = '<por que nada a acrescentar>';"
  exit 1
fi
echo "   revisado até $cobertura"

# -----------------------------------------------------------------------------
# O SCHEMA ATUAL, MATERIALIZADO — porque ler 51 migrations não é uma resposta.
#
# O PROBLEMA. Uma função deste banco pode ter sido republicada três vezes:
# `fn_recomputar_completude` existe na 0004, na 0006 e na 0036, e a que vale é a
# última. Para saber o que o banco faz HOJE é preciso saber qual migration tocou
# aquela função por último — e o único jeito de descobrir isso, olhando o
# repositório, é ler todas em ordem. Numa revisão de PR ninguém faz isso, então o
# efeito de uma migration nova sobre o estado final não é revisável.
#
# A SOLUÇÃO É A MESMA DO ESPELHO DO n8n: gerar e conferir. Este passo aplica as
# migrations do zero (é o que o laço acima acabou de fazer) e escreve o resultado
# em `Supabase/schema.sql`; o CI roda `git diff --exit-code` em cima. Passa a existir um
# arquivo que responde "como está o banco depois de tudo", que aparece no diff do
# PR, e onde o efeito real de uma migration nova é UMA seção alterada em vez de
# 300 linhas de SQL imperativo.
#
# `--no-owner` porque o dono do objeto é o usuário de quem rodou (root aqui,
# postgres no CI) e isso não é informação do schema. As PRIVILÉGIOS ficam: os
# `grant execute ... to authenticated` são o que separa uma função que o portal
# chama de uma que devolve "permission denied" em produção (0028), e a ausência
# de um deles é exatamente o tipo de coisa que este arquivo tem de denunciar.
echo "== schema materializado (Supabase/schema.sql)"
# As duas linhas filtradas mudam A CADA EXECUÇÃO e nada têm a ver com o schema:
# a versão do pg_dump/servidor (que difere entre a máquina de quem roda e o CI) e
# o par `\restrict`/`\unrestrict`, que o pg_dump 16.10+ emite com um TOKEN
# ALEATÓRIO. Sem tirá-las, o `git diff --exit-code` do CI ficaria vermelho toda
# vez, por ruído — e um portão que acusa sempre é um portão que se aprende a
# ignorar, que é pior do que não ter portão.
#
# E O `--no-owner` NÃO COBRE O DEFAULT ACL — foi o que reprovou o CI em 21/08.
# `ALTER DEFAULT PRIVILEGES FOR ROLE <alguem>` carrega o nome do superusuário que
# aplicou as migrations: `postgres` no CI e no Supabase, mas o que estiver logado
# na máquina de quem roda (num container que só tem `root`, sai `FOR ROLE root`).
# Isso é a MESMA informação que o `--no-owner` já decidiu que não é do schema, só
# num lugar onde a flag não chega. Normalizar para `postgres` deixa o portão
# medir o schema em vez de medir quem digitou o comando — e `postgres` é o nome
# verdadeiro em produção, então o arquivo publicado continua sendo o que o
# Supabase tem. O GRANT em si (a anon/authenticated/service_role) não é tocado:
# é ele que carrega a informação, e é ele que o arquivo existe para denunciar.
pg_dump --schema-only --no-owner --schema=public -d "$DB" \
  | grep -vE '^(-- (Dumped (from|by)|PostgreSQL database dump)|\\(un)?restrict )' \
  | sed -E 's/^ALTER DEFAULT PRIVILEGES FOR ROLE [^ ]+ /ALTER DEFAULT PRIVILEGES FOR ROLE postgres /' \
  | sed -E '/^$/N;/^\n$/D' > Supabase/schema.sql
echo "   $(grep -c '^CREATE ' Supabase/schema.sql) objetos criados · $(wc -l < Supabase/schema.sql) linhas"

echo "== fixture (book Vertentes, extração fiel dos 14 documentos)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fixture_book_vertentes.sql

echo "== fixture (book CANASTRA, extração fiel dos documentos DIFÍCEIS)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fixture_book_canastra.sql

# O ACEITE FINANCEIRO DA F0 (`cobertura-do-lote.sql`) RODA AQUI — e antes de 24/09/2026 não rodava
# em lugar nenhum. É consulta manual contra produção (CLAUDE.md, bloco "contra PRODUÇÃO"), mas nada
# a executava nem contra o schema do banco de teste: uma coluna renomeada numa migration só seria
# descoberta no dia do aceite, com o dono diante do SQL Editor. Aqui ela roda sobre o caso da
# fixture do Vertentes com `default_transaction_read_only=on` — o que prova também a frase
# "somente leitura" do cabeçalho dela: qualquer escrita aborta a sessão — e o resumo tem de dar os
# 14 documentos da fixture, todos com linha.
echo "== o aceite da F0 (cobertura-do-lote.sql) roda no schema atual, somente leitura"
resumo_lote="$(PGOPTIONS='-c default_transaction_read_only=on' psql -X -q -At -F'|' -v ON_ERROR_STOP=1 -d "$DB" \
  -v caso_id="'11111111-1111-1111-1111-111111111111'" -f Supabase/test/cobertura-do-lote.sql)"
if ! grep -qx '14|14|0|0|0|100.0' <<< "$resumo_lote"; then
  echo "FALHOU: o resumo do cobertura-do-lote.sql sobre a fixture do Vertentes não é 14 documentos, 14 com linha:"
  echo "$resumo_lote" | sed 's/^/     /'
  exit 1
fi
echo "   14 documentos, 14 com linha, 0 sem linha, 0 nunca extraídos — a consulta do aceite está viva"

# E AS TRÊS SITUAÇÕES QUE SÃO A RAZÃO DE SER DO ACEITE. Sobre a fixture pura só o ramo `com_linha`
# era exercitado (achado da 3ª revisão do PR #244): se a chave `tem_dado_financeiro` ou a ação
# `extracao_sombra` fossem renomeadas no produtor, o portão ficaria verde e, em produção, todo
# documento sem linha cairia em `sem_linha_silencioso`. Aqui três documentos sem linha entram
# numa transação que VOLTA, e os eventos saem da função de PRODUÇÃO que os grava
# (`fn_registrar_campos_extraidos`), não de um insert feito à mão: um declara que não tinha dado,
# outro volta vazio sem declarar, o terceiro nunca é extraído.
echo "== o aceite da F0 separa as três situações de documento sem linha"
situacoes="$(psql -X -q -At -F'|' -v ON_ERROR_STOP=1 -d "$DB" \
  -v caso_id="'11111111-1111-1111-1111-111111111111'" <<'SQL'
begin;
insert into documento (id, caso_id, entidade_id, periodo_id, tipo_taxonomia, status, confianca, fonte)
select v.id, d.caso_id, d.entidade_id, d.periodo_id, 'CERTIDOES', 'valido', 0.9, 'fixture'
  from (values ('aaaaaaaa-0000-0000-0000-000000000001'::uuid), ('aaaaaaaa-0000-0000-0000-000000000002'::uuid),
               ('aaaaaaaa-0000-0000-0000-000000000003'::uuid)) v(id),
       (select * from documento where caso_id = '11111111-1111-1111-1111-111111111111' limit 1) d;
insert into documento_versao (id, documento_id, n_versao, arquivo_ref, nome_original, hash)
select ('bbbbbbbb-0000-0000-0000-00000000000' || n)::uuid, ('aaaaaaaa-0000-0000-0000-00000000000' || n)::uuid, 1,
       'fixture/sem-linha-' || n || '.pdf', 'sem-linha-' || n || '.pdf', md5(n::text)
  from generate_series(1, 3) n;
select fn_registrar_campos_extraidos('bbbbbbbb-0000-0000-0000-000000000001', '[]'::jsonb, p_falha_motivo => null, p_tem_dado_financeiro => false);
select fn_registrar_campos_extraidos('bbbbbbbb-0000-0000-0000-000000000002', '[]'::jsonb, p_falha_motivo => 'resposta vazia', p_tem_dado_financeiro => true);
\i Supabase/test/cobertura-do-lote.sql
rollback;
SQL
)"
for esperado in 'sem_linha_declarado|CERTIDOES|sem-linha-1.pdf|' 'sem_linha_silencioso|CERTIDOES|sem-linha-2.pdf|' \
                'extracao_nunca_chamada|CERTIDOES|sem-linha-3.pdf|' '17|14|1|1|1|82.4'; do
  if ! grep -qF -- "$esperado" <<< "$situacoes"; then
    echo "FALHOU: o cobertura-do-lote.sql não classificou como esperado — faltou: $esperado"
    echo "$situacoes" | sed 's/^/     /'
    exit 1
  fi
done
echo "   declarado, silencioso e nunca extraído: cada um na sua situação (17 documentos, 82,4% com linha)"

# O TESTE DA 0188 VEM ANTES DE QUALQUER OUTRA RECONCILIAÇÃO, E A ORDEM É
# OBRIGATÓRIA: os blocos 1 e 2 comparam o que as checagens produzem sobre as
# fixtures (perturbadas dentro de uma transação que volta) contra o retrato
# MEDIDO com os corpos da 0187 — e isso só vale com os dois casos de fixture sem
# nenhuma linha de reconciliação ainda. O bloco 0 reprova dizendo isto se
# alguém o mover para baixo. Termina em rollback: não deixa nada para os
# testes seguintes.
echo "== motivo específico (0188): a checagem diz o motivo que ela sabe, e nada mais muda"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/motivo_especifico.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o mapa de um ano contra a DRE de dois (0191): só compara o ano que o mapa cobre"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/despfin_ano_par_do_mapa.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de reconciliação"
# A ÁRVORE DA SEÇÃO VEM ANTES DA RECONCILIAÇÃO, E A ORDEM É OBRIGATÓRIA.
# O bloco 6 do reconciliacao.test.sql renomeia TODA chave da versão ...0001 para
# "XPTO <uuid>" e toda seção para "BLOCO SEM NOME" (é o teste de rótulo
# irreconhecível) e não desfaz — nada depois dele dependia daquela versão. O
# teste da 0133 depende: ele precisa da árvore de verdade para religar defeito
# nela. Se alguém reordenar, o primeiro assert do arquivo falha dizendo isto.
echo "== a árvore da seção (0133): o documento conferindo a si mesmo"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/secao_fecha.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/reconciliacao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== motivo_precondicao (0186): o motivo verdadeiro que o achatamento engolia"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/reconciliacao_motivo_precondicao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

# O CASO POSITIVO das duas correções da v48 — e ele não cabia nos books.
# Os dois books trazem extração fiel, então provam só o lado "não grita à toa":
# com eles, a 0144 poderia ter matado a checagem de duplicidade inteira e todo
# teste do repositório continuaria verde. Este arquivo monta um caso próprio e
# exercita os DOIS sentidos de cada correção.
echo
echo "== os três eixos (0144/0145/0146): documento, coluna e a capa que não responde por oito"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/eixo_documento_e_coluna.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o ok que matava a divergência irmã (0192): a ordem da mesma rodada deixa de decidir o desfecho"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/divergencia_prevalece_na_rodada.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o estado vigente entre rodadas (0192, revisão S102): secao_fecha por documento, ok do irmão, descricao"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/divergencia_vigente_entre_rodadas.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a tolerância que crescia com a escala (0193): absoluta na base em caixa_bp_fluxo e receita_dre_vs_faturamento"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/tolerancia_na_base.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a planilha de mútuos que nunca foi lida (0194): retrato de uma data, conceito na coluna"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/mutuos_retrato_de_uma_data.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o espelho intragrupo que lia o balanço de outro ano (0195)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/intragrupo_le_o_ano_certo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o espelho, grupo A da revisão da 0195: face+nota, empate de criado_em, linha sem contraparte"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/espelho_grupo_a.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o caixa que lia a DFC de outro ano (0196): documento de um exercício só, faturamento pela coluna"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/caixa_dfc_de_um_ano.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o faturamento que não via o mês na coluna (0197): mês/ano na coluna; ticket médio fora da soma"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/faturamento_mes_na_coluna.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a faixa de anos que perdia o ano do meio (0198): multi 2024-2026"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/faixa_de_anos_do_periodo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a série por ano que lia movimento e abertura como saldo (0199): Débito, Saldo Inicial, balancete, contrato social"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/serie_por_ano_movimento_e_abertura.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o balancete semestral que entrava por cima do balanço anual (0200): parcial só no ano sem anual da família"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/serie_por_ano_balancete_sob_balanco_anual.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o realizado que não lia Saldo Final nem Saldo atual (0201): BALANCO/DRE anuais entram, mesma conta da série"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/realizado_le_saldo_final_e_atual.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o total com código contábil que virava conta (0202): o papel é o do nome, não o do código do ERP"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/papel_total_com_codigo_contabil.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a seção que a IA não deu e a linha que sumia do realizado (0203): inferida da seção bruta, marcada, sem sobrescrever"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/secao_inferida_da_secao_bruta.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a seção que o documento já dizia pela árvore (0204): herdada do pai e das irmãs, sem topo/total, conflito fica NULL"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/secao_herdada_pela_arvore.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== ingestão sobre o book CANASTRA (o difícil: 15 armadilhas, 3 exercícios, 6 empresas)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/canastra.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

# DEPOIS do canastra.test.sql de propósito: o bloco 8 é uma GUARDA DE FIXTURE —
# ele exige que o book real continue devolvendo ZERO conflito, e para isso o
# book precisa estar carregado e reconciliado.
echo
echo "== desempate entre documentos do mesmo período (0151: quem vence, por quê, e o empate)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/desempate.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

# DEPOIS do desempate, pela mesma razão: o bloco 7 exige que o book real
# continue devolvendo ZERO conflito, agora contra a implementação da 0152 — e a
# equivalência com a 0151 é medida sobre a extração real dos 28 documentos, que
# é diferente de medir sobre um caso montado à mão.
echo
echo "== a reconciliação do LOTE (0152: equivalência com a 0151 e dedução por chave sem perda)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/reconciliacao_do_lote.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o lote EXISTE antes de terminar (0156: fechado_em nulo distingue morta de nunca rodada)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/lote_abre_antes_de_fechar.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a autoridade do COMBINADO (0155: quinze empresas nas colunas, qualquer que seja o rótulo)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/autoridade_combinado.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o rótulo que a própria estrutura desmente (0159: COMBINADO com zero empresas não decide sozinho)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/rotulo_contraditorio.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o Kit Básico aceita o COMBINADO por estrutura (0157: o rótulo BALANCO não trava mais o item)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/kit_basico_combinado_estrutural.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a entidade AMBÍGUA (0153: o nome que casa com duas empresas não identifica nenhuma)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/entidade_ambigua.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== proveniência POR CÉLULA (0125: arquivo, página, confiança e aceite, por ano)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/proveniencia.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de índices macro"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/macro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de reextração (idempotência por hash)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/reextracao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de canonicalização (entidade e período no caminho de escrita)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/canonico.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de moeda por linha (0035: o último fator multiplicativo invisível)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/moeda.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de completude vs conteúdo (0036: chegou vazio não cumpre item)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/completude_conteudo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de linha exigida por tipo (0113: a exigência vira dado e o Portão 1 cobra pelo nome)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/linha_exigida.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de linha exigida POR ENTIDADE (0119: o grupo de oito balanços, e a guarda seed×código)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/linha_exigida_entidade.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== cobertura de tipos (0187, portão D6): todo tipo ativo tem exigência viva ou declaração"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/cobertura_de_tipos.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do banco de perguntas ao cliente (0120: a pergunta pronta vira dado)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/perguntas.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do Portão 2 por caso (0037: a regra de Arquitetura do Sistema/2 Especificação/f0/04 virou código)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/portao2.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes dos TRÊS BOTÕES da pendência (0109: decidir sem formulário, sem teto)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/pendencia_decisao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do catálogo de premissas e da modelagem por caso (0038)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/premissas.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
# DEPOIS do premissas.test.sql de propósito: é ele que deixa um caso com
# `caso_modelagem` configurado, e sem um caso configurado não há "pronto" a
# conferir. O primeiro assert do arquivo falha alto se essa ordem mudar.
echo "== o painel de operação (0135)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/operacao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== a sazonalidade no \"pronto\" da Modelagem (0134)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/sazonalidade_pronto.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de REMOVER premissa (0104: desativar limpa o vínculo que ela dirigia)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/desativar_premissa.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes dos campos da apresentação (0205: valor em branco não é valor)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/apresentacao_campo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do arquivo oficial (0206: trilha desligável, lido sempre contado, versão vigente)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/arquivo_oficial.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do resumo do arquivo oficial (0207: carga em partes, reconferência do servidor, recusa que apaga)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/resumo_oficial.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do papel da linha (0042: subtotal/serie mensal/derivado não se projetam)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/papel_da_linha.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do papel POR SEÇÃO (0100: guarda e tela concordam; lote não cai inteiro)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/papel_por_secao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de ESCALA da modelagem (0101: cabe no statement_timeout do Supabase)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/modelagem_escala.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo
echo "== o marcador da sonda tem de ser CÓDIGO, não comentário (a lista histórica não cresce)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/sonda_marcador_e_codigo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

# O TESTE DE ESCALA DA 0164 NAO RODA NO CI, e a razao e medida, nao preguica.
#
# Ele afere o `statement_timeout` de 8s -- o teto REAL do Supabase -- sobre uma
# fixture de 190 documentos e 1.000 rotulos. Medido em 11/09/2026:
#   . com a 0164:  2,6 s neste container
#   . sem a 0164: 10,9 s neste container   (razao de 4,2x)
# No runner compartilhado do GitHub a versao CORRIGIDA passou de 8 s e reprovou.
#
# Ou seja: para o teto de 8s pegar o defeito AQUI ele tem de ser <= 10 s; para a
# correcao passar NO CI ele tem de ser >= 15 s. Nao existe numero que satisfaca
# os dois, porque a razao entre defeito e correcao (4,2x) e MENOR que a razao de
# velocidade entre as duas maquinas. Num runner compartilhado este teste mede o
# RUNNER, nao o codigo -- e portao que reprova por ruido e pior que portao
# nenhum (.claude/memory/portao-pode-reprovar-por-ruido.md).
#
# TENTEI DUAS SAIDAS E AS DUAS ESTAVAM ERRADAS, e ficam registradas para ninguem
# repetir: (a) afrouxar o teto para 30 s -- MEDIDO: passa COM E SEM a 0164, ou
# seja vira portao que nao mede nada; (b) afirmar o PLANO em vez do tempo -- o
# plano correto tambem tem `Nested Loop` (varios, baratos), e o contador
# `Rows Removed by Join Filter: 9000000` aparece nas DUAS versoes.
#
# O QUE FICA DESCOBERTO, dito em vez de escondido: nenhum portao automatico
# impede a 0164 de regredir. A prova dela e a medicao no cabecalho da migration,
# mais este teste rodado A MAO:  ESCALA_0164=1 Supabase/test/run.sh
if [ "${ESCALA_0164:-0}" = "1" ]; then
echo
echo "== testes de ESCALA da versao vigente (0164: >250 rotulos, teto real de 8s)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/modelagem_versao_vigente_escala.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'
else
echo
echo "== escala da 0164: PULADO (mede o relogio da maquina; rode com ESCALA_0164=1)"
fi

echo
echo "== testes da Modelagem contra o caso REAL de produção (0102: versão vigente; rótulo real)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/modelagem_v35.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o pronto da Modelagem exige cobertura, não só parâmetro (0158)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/modelagem_pronto_exige_cobertura.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes de reconferir (0043: reaplicar as regras de hoje sobre o dado gravado)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/reconferir.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== documento sem dado financeiro (0111) + conferência de lote (0112: documento pulado)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/documento_sem_dado_financeiro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== fechar mandato sem excluir (0114)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fechar_mandato.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== o custo do lote passa a durar, sem dobrar (0115)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/custo_do_lote.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do dial de autonomia (0041: o dial passa a mandar no auto-aceite)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/dial.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes da transcrição humana assistida (0129: o fechamento #2 do Arquitetura do Sistema/1 Visão e Doutrina/01)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/transcricao_humana.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes da classificação contábil em sombra (0128: o oitavo estágio do MVP)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/classificacao_contabil.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do dial OBEDECIDO (0127: o nível passa a ser lido, não só declarado)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/dial_obedecido.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do golden set e do portão da regra de ouro (0126)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/golden.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do caminho de ESCRITA do golden set: rotulagem cega (0130)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/golden_rotulagem.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do veredito de produção (0136) — a terceira porta do dial"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/veredito_producao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes da promoção automática do dial (0137) — sobe sozinha, e o freio gruda"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/auto_promocao_dial.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes da sonda de instalação (0131) — o catálogo conferido contra a realidade"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/instalacao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do tipo gatilho da sonda (0189) — a função sobrevive ao drop trigger, o vínculo não"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/sonda_ve_gatilho.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== testes do fato material (0148) — o que o documento diz em TEXTO"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fato_material.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0165 — \"PASSIVO\" sozinho já inclui o PL (números do balanço real da AMOBELEZA)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/passivo_bare_e_o_grupo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0167 — o faturamento é UM valor por mês (a coluna Total não soma junto)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/faturamento_por_mes.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0168 — o nome truncado que casa com os outros não vira empresa nova (os 4 nomes reais)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/alias_truncado.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0169 — o CNPJ é a identidade que o nome não é (os 4 nomes reais + o CNPJ real)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/cnpj_identidade.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0171 — o CNPJ também renomeia, não só funde (os 4 nomes reais, nas duas ordens)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/cnpj_renomeia.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0175 — dentro do balcão ambíguo, o CNPJ decide antes do nome"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/balcao_ambiguo_e_cnpj.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0176 — o balcão ambíguo parou de absorver quem é confirmado"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/balcao_nao_absorve_confirmada.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0178 — título de coluna/aba/arquivo não vira pessoa jurídica"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/entidade_titulo_suspeito.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0179 — papel no grupo tipado e preenchido (fatia 1.3 do plano F1)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/entidade_papel_no_grupo.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0180 — o perímetro do combinado (fatia 1.4 do plano F1)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/perimetro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0181 — participação societária: controladora_id e a guarda contra ciclo (fatia 1.5 do plano F1)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/entidade_participacao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0182 — grupo por controle comum: controlador/entidade_controlador, sem holding (fatia 1.7a do plano F1)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/entidade_controlador.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0183 — forma_de_controle: o vazio de controladora_id distinguível de não preenchido (fatia 1.7b, fecha a 1.7)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/entidade_forma_de_controle.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0183 — o marcador de cobertura da sonda não regride (a 0182 aplicada depois da 0188 o rebaixou em produção)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/instalacao_cobertura_nao_regride.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0183 — a fusão de entidades não apaga o controle declarado (o on delete cascade da 0182 o levava junto)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fusao_preserva_controle.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0208 — situação e veredito do perímetro (o que falta, em qual entidade; zero entidades não é fechado; aceite nunca ok por omissão)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/perimetro_situacao.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0209 — o escopo do perímetro: confirmar de novo é idempotente, encerrar tira a entidade do escopo"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/perimetro_encerrar.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0210 — a escrita da F1 COMO authenticated (RLS: policies de insert/update, sem delete) e a sonda que vê policy"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/f1_escrita_authenticated.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0211 — a fusão de entidades leva o perímetro da absorvida (e o que não leva fica no evento)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fusao_perimetro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0212 — o bloco familiar conta como controle comum, só se declarado (CPC 05 / IAS 24)"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/controlador_familia.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== 0213 — a fusão leva a pergunta já agida e caso_pergunta segue append-only"
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/fusao_pergunta.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "== carga inicial dos índices macro (dado real, versionado)"
psql -q -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/seed/macro_carga_inicial.sql >/dev/null
psql -v ON_ERROR_STOP=1 -d "$DB" -f Supabase/test/seed_macro.test.sql 2>&1 \
  | grep -E '^(NOTICE|ERROR|psql)' | sed -E 's/^NOTICE:  //'

echo
echo "TODOS OS TESTES PASSARAM"
