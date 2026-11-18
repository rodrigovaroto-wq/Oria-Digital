# Verificação — ponta a ponta e vistorias

As suítes de cada camada (`N8N/test`, `Supabase/test`, `portal/scripts`) testam o seu pedaço
contra fixtures. Os scripts daqui testam a **costura** entre as camadas e o sistema no ar.

| Script | Onde roda | O que prova |
|---|---|---|
| [`run.mts`](run.mts) | CI (job `e2e`) | a cadeia real extração → banco → export sobre o book Vertentes: o que o produtor de campos emite é o que o SQL grava e o que o export lê |
| [`variacoes.mts`](variacoes.mts) | CI (job `variacoes`) | a mesma cadeia sobre documentos "sujos" (escala trocada, locale anglo, negativo entre parênteses, subtotal ausente, moeda misturada…), injetados no ponto em que a IA responde |
| [`vistoria-por-papel.mts`](vistoria-por-papel.mts) | manual, contra produção | quem vê e quem altera o quê: anônimo, Sócio, Analista e Leitura em todas as rotas, no desktop e no celular, e tentativas de escalada pela API |
| [`varredura-dos-mandatos.mts`](varredura-dos-mandatos.mts) | manual, contra um portal no ar | abre todos os mandatos, aba por aba, e os três arquivos entregues ao cliente |
| [`enviar-book.mts`](enviar-book.mts) | manual, contra produção | envia um book de teste inteiro pelo portal, como o Sócio faria |
| [`linha-de-base.mts`](linha-de-base.mts) | manual, contra produção | completude da leitura documento a documento, contra a verdade do gerador do book |

Os scripts manuais **escrevem em produção** (dado sintético) ou gastam chamadas de IA: só rodam
com autorização do dono. O cabeçalho de cada um traz as variáveis de ambiente e o comando exato.

Sempre pelo binário do lock, nunca `npx`:

```bash
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" ./portal/node_modules/.bin/tsx Verificação/run.mts
```

A saída das rodadas vai para `Verificação/saida/`, que o git ignora.
