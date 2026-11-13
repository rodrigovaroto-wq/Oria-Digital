# S130 — P27 reescrita como VIEW: progresso (atualizado a cada parte)

> Branch `claude/eager-franklin-n4oxjd`, a partir do `8c1c6d1`. NADA comitado, NADA aplicado em produção, NADA enviado. Quem comita é a sessão principal. Tudo está na working tree.

## Feito
- [x] Contrato lido; Postgres local no ar; `run.sh` do HEAD verde ANTES da mudança (205 asserts do teste antigo, `TEST_DB=tdf_p27base`).
- [x] Achado de passagem: o `run.sh` do HEAD `8c1c6d1` reprovava no portão "o ESTADO.md aponta para a migration mais nova" (a linha 5 dizia `continua 0271` sem o nome do arquivo). Corrigido a linha 5 do `ESTADO.md` (só o nome do arquivo). Sem isso nenhuma suíte SQL rodava.
- [x] Nova 0243 (VIEW security_invoker sobre `fn_fato_resolver`; um gatilho só, o da pendência; `fn_registrar_campos_extraidos` e `fn_fundir_entidade` NÃO reemitidas) em `Supabase/migrations/0243_a_linha_que_nao_tinha_identidade.sql` (cabeçalho ainda provisório).
- [x] Teste novo `Supabase/test/fato_financeiro.test.sql` (fato escrito à mão por cenário) e `Supabase/test/fato_financeiro_corridas.test.sql` (duas sessões reais, dblink).
- [x] `run.sh` inteiro verde com a nova 0243 (`TEST_DB=tdf_p27v2`): fato_financeiro 182 asserts, 0 reprovados; corridas 14 asserts, 0 reprovados; "TODOS OS TESTES PASSARAM".
- [x] Ordem de produção x ordem do zero: `pg_dump` do schema `public` IDÊNTICO (25.877 linhas, diff vazio); catálogo da sonda idêntico (md5); `ln` gravado nas duas ordens (7 e 9) e a pendência abre nas duas.
- [x] Janela da aplicação, medida com duas sessões (migration segurando o lock por 8 s): o n8n ESPERA (não falha, não perde): a 1ª escrita em `evento_auditoria` levou 7,8 s; a extração da janela ficou com 2 fatos (a view) e 1 pendência; a extração de ANTES da migration ficou com 1 fato e 0 pendência (por decisão: só extração nova).
- [x] Achado de desempenho no resolver: a junção linha x papel era escolhida como laço aninhado e custava 1,8 a 2,1 s numa versão de 4.000 rótulos recém-extraída; trocada por busca em jsonb (0,4 a 0,54 s). Resultado idêntico conferido linha a linha (57.231 linhas, nos dois sentidos).
- [x] Achado de concorrência (R4): duas extrações concorrentes de duas versões do mesmo documento deixavam DUAS pendências abertas; corrigido com a trava `pg_advisory_xact_lock` por documento no gatilho.
- [x] `node --test 'Supabase/test/*.test.mjs'`: 48 passam, 0 falham, 4 saltam. `conferir-chamadas`: CHAMADAS OK. Sonda `--so-buraco`: sem buraco.

- [x] Achados de desempenho/plano no resolver, todos medidos: (1) junção linha x papel = laço aninhado, 1,8-2,1 s -> 0,4-0,54 s (jsonb); (2) JIT do servidor: 3,5 s para ler 684 fatos -> 0,68 s com `SET jit = off`; (3) `SET` na função a desinlina e o planejador passou a reexecutar o resolver por linha externa (teste 15 s -> >2 min): `COST 100000 ROWS 200` conserta (17 s). A sonda `recentes` custava 12,5 s (not exists correlacionado): junção + teto de 3 versões de até 1.500 linhas = 0,19 s.
- [x] Desempenho final (banco local, 82.634 linhas, 13/11): versão de 4.000 linhas 0,54-0,69 s; maior mandato das fixtures (684 fatos) 0,46 s; mandato 10 x 4.000 5,2-5,7 s; view inteira (81.831 fatos) 12,5 s; como authenticated o mesmo (5,4 s o mandato de 40.000; 0,59 s uma versão); sonda inteira 0,28 s; extração de 4.000 linhas 1,47-1,71 s com o gatilho e 0,92-1,00 s sem (era 3,2-3,4 s e 1,1 s na tabela); aplicação 0,065 s. Mandato grande passa de poucos segundos: P28 (view materializada) proposta, não implementada.
- [x] Sabotagem: security_invoker sozinho desligado NÃO vaza (o resolver invoker segura); resolver definer sozinho só vaza na chamada direta; as DUAS desligadas vazam (V07: 10 asserts de dado reprovam). A RLS está em duas camadas e a sonda exige as duas.
- [x] Corrida R4 (pendência, duas extrações concorrentes do mesmo documento): sem a trava `pg_advisory_xact_lock` por documento sobram 2 pendências abertas (1 assert reprova); com ela, 1.
- [x] N8N 814/814; 13 verificadores do portal exit 0.

## Estado final (13/11)
- TUDO feito e medido. `run.sh` final (`tdf_p27v3`): fato_financeiro 187 asserts, 0 reprovados; corridas 14, 0; TODOS OS TESTES PASSARAM. `node --test Supabase/test`: 48/0/4 saltados; conferir-chamadas OK; sonda --so-buraco sem buraco; indexar + conferir OK; N8N 814/814; 13 verificadores do portal, e2e (46 OK) e variacoes (0 achados) verdes.
- Sabotagens: tabela completa no cabeçalho da 0243 (41 medidas; M02 aborta o arquivo; controle 0 dos 187).
- Ficam para a sessão principal: comitar, 6ª revisão independente, CI, conferir `show server_version` e aplicar (nada foi aplicado). Scripts em `patches/s130-p27-view/`.
