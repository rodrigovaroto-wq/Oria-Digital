# Andamento — checkpoint para retomada

Atualizado em 02/10/2026, ~22h40 UTC. Retomada agendada para 03/10 00:42 UTC (`trig_01Jzm1i5XUuxKVPY8truHdGL`).

## Feito (commitado no branch `claude/eloquent-wozniak-jgyo95`)

- Deck no padrão do Teaser com todos os capítulos do Centro Oeste; contracapa toda "[a preencher]".
- Testado em 14 entidades (Vertentes, Canastra, captura real v35) num banco local `tdf_ap`
  montado pelas migrations + fixtures; 12 geram, os 2 "GRUPO" são recusados com 409.
- Corrigidos: DRE sem totais (cascata), sem estoque, consolidado vazio, divergência no sumário.
- `verificar-apresentacao.mts` 49/49; `verificar-export` 845/0.
- `ARQUITETURA.md` desta pasta: encaixe no pipeline, fonte de cada capítulo, próximo passo.

## Bloqueio

- Leitura do Supabase de **produção** negada pelo controle de permissões da sessão (classificador
  "Production Reads"). Os mandatos reais maiores do portal (ex.: Krauspenhar `33b58a89`) não foram
  testados. Para destravar: permitir a leitura, ou rodar à mão
  `DB=<banco> APRESENTACAO=saida.pptx ./portal/node_modules/.bin/tsx portal/scripts/gerar-export-do-banco.mts <caso_id>`
  contra uma cópia local do banco.

## Próximo (em ordem)

1. `caso_apresentacao_campo` (migration + leitura na rota + uso no gerador) — ver ARQUITETURA.md.
2. Esconder capítulos de resultado quando a entidade não tem DRE em exercício algum.
3. Resumo multi-entidade para grupos com avais cruzados.
4. Atualizar ESTADO.md e MAPA_DE_EXECUCAO.md (agente `estado-e-handoff`).

## Como recriar o banco local de teste

Ver o bloco de comandos no histórico do commit `e491263`: bootstrap de roles/storage, todas as
migrations, `Supabase/test/fixture_book_{vertentes,canastra}.sql` e `fixture_modelagem_v35.sql`,
e `caso_modelagem` com a entidade e `ultimo_exercicio_real = 2025`.
