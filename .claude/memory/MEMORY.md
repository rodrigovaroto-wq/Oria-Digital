# Memória — o que já custou caro neste projeto

Índice sempre carregado. Regras de uso e política de crescimento em `INSTRUCTIONS.md`.
Uma linha por entrada; teto mole de 130 linhas não vazias.

> **Antes de procurar aqui, rode o briefing:** `node .claude/conhecimento/buscar.mjs "<assunto>"`.
> Ele indexa ESTAS fichas e as de `.claude/conhecimento/fichas/`, mais migrations, funções, nós do
> n8n, portões e sessões do HANDOFF — e devolve `arquivo:linha` em um comando. As fichas novas
> nascem em `fichas/`; estas continuam aqui porque dezenas de comentários de código as citam por
> este caminho. Ver `.claude/conhecimento/INSTRUCOES.md`.

## O padrão de erro central

- [Estágio desligado parece estágio limpo](estagio-desligado-parece-limpo.md) — o modo de falha
  que mais custou aqui: nada de erro, nada de pendência, e o estágio simplesmente não rodou
- [Verificador sem controle positivo](verificador-sem-controle-positivo.md) — a mesma regra na
  verificação à mão: um "nenhum encontrado" só vale se a checagem PROVADAMENTE acha o que procura.
  Cinco do PR #238 responderam outra pergunta, três dizendo "tudo certo"

## Doutrina (viola isto e o defeito chega ao cliente)

- [Nunca apresentar ausência como dado](nunca-apresentar-ausencia-como-dado.md) — zero fabricado
  é indistinguível de zero medido; branco + nota com o EFEITO
- [Teto de autonomia por natureza do estágio](teto-de-autonomia-por-natureza.md) — nenhum volume
  de veredito sobe Classe B/C ou classificação contábil acima de N1
- [A sonda responde pelo banco, o documento não](sonda-responde-pelo-banco.md) — a `0133` ficou
  para trás enquanto a `0134` entrou, e o repositório dizia que estava tudo aplicado
- [E a sonda só conhece o catálogo que o banco tem](sonda-so-conhece-o-catalogo-que-o-banco-tem.md)
  — verde nela não é "a rodada vai rodar": num banco na `0150`, três nós do workflow não resolviam
  e ela não acusava nenhum. `Supabase/test/conferir-chamadas.mjs` faz a outra ponta
- [Nunca corrigir função por `replace` de texto](nunca-corrigir-funcao-por-replace.md) —
  passa em toda suíte local e reprova em produção; reemita a função inteira
- [Nó Postgres novo vai como ramo TERMINAL](no-postgres-novo-vai-como-ramo-terminal.md) —
  inline no fluxo por documento ele apaga o contexto de todos os seguintes (v47: 11 dias; 0156: 0 de 38)

## Armadilhas de teste e de portão

- [Em relatório itemizado o conceito não está no rótulo](conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md)
  — o rótulo é o ITEM (nome do fornecedor, do banco, do processo) e o conceito é o TIPO do
  documento; exigência lexical reprova 17 documentos que TÊM o dado e passa 22 por linha residual
- [E `secao` não é estável entre versões da extração](../conhecimento/fichas/f2-localizador-chave-pendencia-falsa.md)
  — o mesmo book canastra tem `secao` nula nas ingestões antigas e preenchida nas novas, e a
  fixture do repositório tem: teste verde contra ela, falso em produção (`0166`, depois `0185`)
- [Fixture nasce vazia com mais frequência do que parece](fixture-nasce-vazia.md) — duas da
  sessão 18 passavam com o bug LIGADO
- [Derivado versionado precisa de `git diff --exit-code`](derivado-versionado-precisa-de-git-diff.md)
  — quem roda é o commitado, não a fonte que o gera
- [A medição reescreve o derivado](medicao-reescreve-derivado.md) — o `cp` do protocolo
  protege o arquivo alterado, não o `Supabase/schema.sql` que o `run.sh` regrava por baixo
- [Um portão pode reprovar por ruído](portao-pode-reprovar-por-ruido.md) — `FOR ROLE root` contra
  `FOR ROLE postgres`: schema idêntico, CI vermelho
- [Portão calibra sobre a entrada de PRODUÇÃO](portao-mede-a-entrada-de-producao.md) — o texto
  que o n8n extrai não é o de nenhum extrator local: +3% no portão, 161% de erro em produção
- [`item_sem_conteudo` só cobre tipo OBRIGATÓRIO](item-sem-conteudo-so-cobre-obrigatorio.md) —
  documento COMPLEMENTAR vazio só aparece via `extracao_falhou` por documento (`0111`); a `0185`
  teria assumido cobertura que não existe se tivesse ido adiante

- [Agente interrompido deixa a correção DESLIGADA](agente-morto-deixa-a-correcao-desligada.md) —
  um `false and` no meio da expressão, o arquivo com cara de pronto; e não rode a suíte enquanto
  um agente tem a árvore (medi um arquivo e li outro, 43 segundos de diferença)

- [O teto da hospedagem recusa ANTES de o código rodar](teto-da-borda-recusa-antes-do-codigo.md) —
  413 da borda da Vercel com 48 arquivos: a rota nunca rodou, e nenhuma mensagem nossa podia
  aparecer. Erro com número HTTP e sem frase nossa: pergunte se a rota chegou a rodar

## Armadilhas de ferramenta (custaram tempo real)
- [A credencial do n8n quebra sem deixar rastro](credencial-do-n8n-quebra-sem-deixar-rastro.md) — de 17/09 a 30/09
  nenhum mandato gravava no banco, e sonda, conferidor e `execucao_falha` estavam limpos: o workflow
  de erros usa a MESMA credencial. Verde neles não diz que o n8n alcança o banco
- [Baixar execução grande derruba o n8n](n8n-nao-aguenta-baixar-execucao-grande.md) — `includeData=true`
  numa execução de planilha grande deu 502 na instância; diagnostique pelo banco


- [Âncora de texto quebra com CRLF](ancora-de-texto-quebra-com-crlf.md) — o corpo que
  `pg_get_functiondef` devolve em produção pode estar em CRLF, e âncora multi-linha sem `\r?`
  acha ZERO — passa em toda suíte local, onde o corpo nasce LF
- [`git checkout <arquivo>` apaga trabalho não commitado](git-checkout-apaga-trabalho.md) — copie
  para o scratchpad e restaure com `cp`
- [Backtick em comentário de nó Code quebra o `jsCode`](backtick-quebra-jscode.md) — aconteceu
  duas vezes; só o teste pega
- [`spliceRows` na aba Macro desloca endereços em silêncio](splicerows-desloca-enderecos.md)
- [`avaliarCelula` não segue referência entre abas](avaliarcelula-nao-cruza-abas.md)
- [A ordem dos parâmetros dos dois classificadores é diferente](ordem-dos-classificadores.md)
- ["TODO" em português vira achado do Sonar](todo-em-portugues-vira-achado-do-sonar.md) — a `S1135`
  casa o texto, não o idioma; cinco ocorrências até 13/09. Use `CADA`/`TODOS OS`

## Produção (não está em nenhum arquivo do repositório)

- [Aplicar migration em produção é pela API de gerenciamento](aplicar-migration-em-producao-pela-api.md)
  — `psql` não alcança a porta; e a API envolve tudo numa transação, então `alter type … add
  value` exige DUAS chamadas. Backfill: meça o alcance do `where` em produção ANTES (365 × 7) —
  e a 0183 REPETIU o erro com esta linha escrita, porque quem escreve migration é o agente
- [Sessões paralelas aplicam fora de ordem](sessoes-paralelas-aplicam-fora-de-ordem.md) — a
  numeração reservada segurou; o marcador de cobertura regrediu (0188→0182) e a sonda não viu o
  buraco. Antes de aplicar: compare com produção o corpo de toda função que você reemite
- [O auto mode recusa aplicar migration em produção mesmo autorizado no chat](auto-mode-recusa-migration-producao.md)
  — o classificador de permissão decide por categoria de ação, não por instrução lida na hora;
  e recusa o agente escrever a própria regra ("Self-Modification"). Funciona: o dono passa a
  sessão para modo manual e aprova cada chamada (0186–0188 aplicadas assim, 22/09)
- [O mandato real não tem holding](grupo-por-controle-comum-sem-holding.md) — as 8 empresas são
  irmãs sob controle comum de PESSOAS FÍSICAS, medido nos contratos sociais; `controladora_id`
  (0181) fica NULL por estar certo, não por faltar cadastro, e é por isso que o COMBINADO do
  cliente provavelmente nunca existiu. Com o dado real, o modelo da 1.7 dá DOIS grupos de dois —
  "as 8 como um grupo" exige decidir se controle familiar conta, e isso é juízo, não medição

- [A republicação do n8n perde toggles](republicacao-do-n8n-perde-toggles.md) — `multipleFiles`,
  `onError` em 23 nós, `retryOnFail` em 11
- [A cota RPD 500 é o limite que aperta](cota-rpd-e-o-limite-do-dia.md) — 440/500 para 190
  documentos: um book por dia
- [`MATERIALIZED` não é enfeite](materialized-nao-e-enfeite.md) — sem ele o Postgres inlina a CTE
  e o agrupamento que matava o cartesiano vira o cartesiano
