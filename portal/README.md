# Portal (Vercel) — Fatia 1

Next.js (App Router) + Supabase Auth. Telas cobrem a F1 do plano (`f0` /
`Arquitetura do Sistema/1 Visão e Doutrina/03`): **dashboard do caso** (checklist do Kit Básico, lista de
documentos, pendências de reconciliação/qualidade), **fila de revisão**
(humano confirma/corrige classificação/entidade/tipo/período — o N1 da
Doutrina de Autonomia, `Arquitetura do Sistema/1 Visão e Doutrina/01`), **planilha por documento** (linhas
extraídas + aceite humano — Portão 2 mínimo, `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`) e
**export Excel** do caso inteiro.

> **Upload em lote continua fora do portal por decisão explícita** (ver
> `N8N/README.md`): a ingestão roda pelo Form Trigger do N8N. O portal aqui é
> só o lado de **leitura + revisão humana**.

## O que tem

- `src/proxy.ts` + `src/lib/supabase/proxy.ts` — renova a sessão a cada
  requisição e redireciona quem não está autenticado para `/login` (Next.js
  16 renomeou `middleware.ts` → `proxy.ts`, ver
  [nextjs.org/docs/messages/middleware-to-proxy](https://nextjs.org/docs/messages/middleware-to-proxy)).
- `src/app/login` — login por email/senha (Supabase Auth). Contas são criadas
  pelo administrador direto no painel do Supabase (Authentication → Users) —
  não há tela de cadastro (ferramenta interna, um time).
- `src/app/casos` — lista de casos.
- `src/app/casos/[id]` — dashboard: status do caso, checklist do Kit Básico
  (verde = presente, calculado da mesma forma que `fn_recomputar_completude`
  no banco: existe algum `documento` desse `tipo_taxonomia` no caso), a lista
  de documentos com tipo/entidade/período/confiança/fonte/resumo/legibilidade
  (link "ver linhas →" por documento), pendências de **Reconciliação (Classe
  A)** e de **Qualidade dos arquivos**, e o botão **Exportar para Excel**.
- `src/app/casos/[id]/revisao` — fila de revisão: uma pendência de
  classificação/entidade/tipo/período por card (`classificacao_pendente`,
  `tipo_incorreto`, `entidade_incorreta`, `periodo_incorreto` — as três
  últimas vêm do diagnóstico de conteúdo do N8N, `Supabase/migrations/0010`),
  formulário pré-preenchido com a sugestão atual. Confirmar (sem editar) ou
  corrigir e salvar chama a RPC `fn_revisar_documento`
  (`Supabase/migrations/0008_portal_revisao.sql`) — toda a lógica (resolver
  pendência, `decisao`+`evento_auditoria`, checklist, recomputar completude)
  roda no Postgres, não no Next.js.
- `src/app/casos/[id]/documentos/[docId]` — a "planilha" de um documento:
  linhas extraídas agrupadas por `secao`, resumo, aviso de legibilidade, e o
  botão **"Aceitar estes dados para a base"** — chama `fn_aceitar_extracao`
  (`Supabase/migrations/0011_aceite_export_e4.sql`), o Portão 2 mínimo: sem esse
  aceite, a linha nunca entra no export como fato (fica "pendente").
- `src/app/casos/[id]/export` — **route handler** (não página) que gera o
  Excel do caso (`src/lib/export.ts` + `src/lib/statement-templates.ts`,
  função pura testável isoladamente, `exceljs`).
  - **Balanço / Balancete / DRE / Fluxo de Caixa / Combinado** saem no
    **layout padrão de mercado** dessas demonstrações — colunas = entidade ×
    período; linhas = contas, organizadas por SEÇÃO (Ativo Circulante, Ativo
    Não Circulante, Passivo Circulante/Não Circulante, Patrimônio Líquido no
    Balanço; Receita/Custos/Despesas/Resultado Financeiro/Impostos na cascata
    da DRE; Atividades Operacionais/Investimento/Financiamento no Fluxo de
    Caixa — método indireto, CPC 03).
    **Não é um template de ~15 nomes de conta fixos** (isso quebra na
    primeira empresa que nomeia a conta diferente) — `statement-templates.ts`
    **classifica cada conta extraída na seção certa** por sinais amplos (a
    `secao` que a IA já anota + palavras-chave no rótulo, com casamento por
    PALAVRA tolerante a plural/singular e a conectivos diferentes — "Provisão
    PARA Férias" bate com a regra "provisão DE férias", "Duplicatas a
    Receber" bate com "duplicata a receber") e mantém o **rótulo original**
    de cada empresa dentro da seção — não força um nome canônico. Nenhum
    subtotal/total é calculado por soma — só aparece se o próprio documento
    já trouxer aquela linha extraída (mesmo princípio de `fn_valor_conceito`,
    `Supabase/migrations/0009`: casamento determinístico, nunca um cálculo novo).
    Contas que não são classificáveis com segurança vão para um bloco
    explícito "Contas Não Classificadas (revisar manualmente)" ao final da
    aba — nada desaparece nem é forçado pro lugar errado. Proveniência
    (arquivo/página/confiança/status/versão da taxonomia) vai em
    **comentário da célula** (não em colunas auxiliares, já que as colunas
    são entidade×período).
  - **Faturamento / Dívida / Fluxo Projetado** continuam em listagem simples
    (já são, por natureza, uma série/tabela — não uma demonstração de blocos).
  - Aba `Resumo` com metadados do snapshot (data-base, contagem aceitas/
    pendentes, versões de taxonomia). Linhas pendentes de aceite aparecem
    junto (nunca somem), mas com preenchimento âmbar + itálico — "sugestão
    pendente de revisão", nunca fato silencioso (princípio inegociável de
    `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`).

## Configuração

```bash
cp .env.example .env.local
```

Preencher com os valores do projeto Supabase (Settings → API):
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` — a chave **anon/publishable** (pública por
  design, é o que o browser usa). **Nunca** a `service_role` aqui — ela
  ignora RLS (ver `Supabase/README.md` "Notas de segurança (LGPD)"). O acesso do
  portal respeita RLS porque o usuário chega autenticado (`authenticated`
  role) via Supabase Auth.

Para habilitar o **upload pelo portal** (páginas "Novo mandato" e "Adicionar
arquivos" — ver abaixo):
- `N8N_INTAKE_FORM_URL` — a **URL de produção do Form do N8N** (o mesmo
  formulário de intake; em N8N: abra o node "Intake (Form)" → aba do webhook →
  copie a *Production URL*). O portal encaminha os arquivos para essa URL
  servidor-a-servidor, então o pipeline (classificação/extração/reconciliação)
  continua 100% no N8N — o portal é só um front-end de intake mais amigável.
  Sem essa env, as páginas de upload mostram um aviso de "não configurado" (o
  resto do portal funciona normalmente).
- `N8N_INTAKE_SEGREDO` — **obrigatório para enviar**: o segredo do HMAC que autoriza cada envio
  a UM mandato (`src/lib/assinatura-do-envio.ts`). O Form do N8N é público; sem o token assinado
  o nó `Conferir Envio` recusa o lote antes de gravar. Tem de ser o **mesmo valor** na variável
  `N8N_INTAKE_SEGREDO` do N8N. Ausente, o portal recusa o envio ("envio desligado").
- `N8N_INTAKE_FIELD_MANDATO` / `N8N_INTAKE_FIELD_ARQUIVOS` (opcionais) — nomes
  dos campos do Form. **Normalmente não precisa configurar**: o portal
  DESCOBRE os nomes reais dos campos sozinho, lendo o HTML do próprio Form
  antes de enviar (`src/lib/n8n-form.ts`) — não adivinha/fixa `"Mandato (nome
  do caso)"`/`"Arquivos"` como antes. Isso existe porque o N8N pode aceitar o
  POST com HTTP 200 mesmo quando o nome do campo está errado (o formulário
  "aceita a submissão" antes de saber se o workflow vai processar), e nesse
  caso o workflow falha silenciosamente SEM gastar nenhum token — sintoma:
  portal mostra sucesso, mas nada aparece no mandato e nenhum custo de IA é
  gerado (achado em produção, sessão 7 cont.¹²). Só defina essas envs se quiser
  **forçar** um nome específico (override manual).

### Upload pelo portal e o conceito de "mandato"

O **mandato é o caso** (`caso`): reenviar arquivos com o MESMO nome de mandato
os acumula no mesmo caso — mesmo checklist, mesma exportação para Excel e mesma
checagem de dados (reconciliação). Isso vale tanto para o upload pelo portal
quanto para o Form do N8N: `fn_upsert_caso(nome)` reusa por nome
(`Supabase/migrations/0006`). Fluxo no portal: **"+ Novo mandato"** (lista de
mandatos) para começar um; **"+ Adicionar arquivos"** (dentro de um mandato)
para enviar mais em outro momento.

> **Tamanho do lote — resolvido em 13/09/2026, e o que mudou.** A Serverless
> Function da Vercel recusa corpo acima de ~4,5 MB **na borda**, antes de
> invocar `/api/intake`: um lote de 48 arquivos (~50 MB) morria em HTTP 413 sem
> que nenhuma mensagem do portal pudesse aparecer. O conselho antigo era
> "mande em levas" — e automatizá-lo seria pior, porque cada submissão abre UMA
> execução no n8n e a cadência da IA é por execução (treze levas = treze
> execuções concorrentes contra o mesmo rate limit da conta).
>
> Hoje a decisão é da própria tela e não pede nada do analista: até o teto, o
> envio segue pelo encaminhamento de sempre (`POST /api/intake`), que devolve o
> status real do n8n; acima dele, o navegador manda o `multipart` **direto para
> o Form do n8n**, sem intermediário — uma execução só, sem limite de tamanho da
> Vercel. A tela mostra o total do lote antes de enviar. A conta que decide o
> caminho mora em `src/lib/limite-de-envio.ts` e é travada por
> `scripts/verificar-limite-de-envio.mts` (no CI).
>
> O que o caminho direto custa, dito onde importa: a resposta do Form vem opaca
> (outra origem, sem CORS), então "enviado" ali significa "a requisição partiu".
> Quem confirma a chegada é o acompanhamento pelo banco — que sempre foi a única
> prova real neste sistema, já que o webhook responde 200 antes de saber se o
> workflow terá o que processar.

### Depois do envio: acompanhamento e aviso de conclusão

O upload não tem retorno síncrono do processamento (classificação + extração
rodam depois, fora do portal) — em vez de mostrar termos técnicos, o portal
acompanha silenciosamente em segundo plano (`GET /api/intake/status`, polling
a cada ~8s por até ~12 min) e, quando os arquivos enviados terminam de passar
pelo pipeline, mostra um aviso ("Tudo pronto") sem precisar recarregar a
página. "Pronto" aqui significa "terminou de tentar" (`documento` criado +
evento de extração gravado para cada arquivo), não "sem pendências" —
divergências/revisões continuam visíveis no dashboard do mandato como sempre.

Depois de rodar as migrations do `Supabase/` (até a `0011` inclusive):

```bash
npm install
npm run dev     # http://localhost:3000
```

Criar um usuário de teste em Authentication → Users no painel do Supabase
para logar.

## Deploy (Vercel)

1. Importar este diretório (`portal/`) como o **Root Directory** do projeto
   Vercel (o repo tem outras pastas — `N8N/`, `Supabase/`, `Arquitetura do Sistema/` — que não fazem
   parte do app Next.js).
2. Configurar as env vars acima em Project Settings → Environment Variables
   (`NEXT_PUBLIC_SUPABASE_*` obrigatórias; `N8N_INTAKE_FORM_URL` para habilitar
   o upload pelo portal).
3. Deploy. Sem passos de build customizados — `next build` padrão.

## Verificado localmente antes de entregar

- `npx tsc --noEmit` — sem erros.
- `npm run lint` — sem erros.
- `npm run build` — build de produção completo, todas as rotas compilam
  (com env vars de teste; `/casos`, `/casos/[id]`, `/casos/[id]/revisao`,
  `/casos/[id]/documentos/[docId]`, `/casos/[id]/export`, `/casos/novo`,
  `/casos/[id]/adicionar`, `/api/intake`, `/api/intake/status` e `/login`
  corretamente dinâmicas, `/` estática).
- `src/lib/export.ts` + `src/lib/statement-templates.ts` (classificação +
  montagem do workbook) testados isoladamente com dados sintéticos via `tsx`
  + `exceljs`, incluindo o cenário que motivou a reformulação: **duas
  empresas com nomenclatura de plano de contas totalmente diferente para as
  mesmas contas** (ex.: "Caixa e equivalentes de caixa" vs. "Disponibilidades";
  "Imobilizado líquido" vs. "Bens do Ativo Imobilizado") — ambas classificadas
  corretamente na mesma seção, cada uma com o rótulo original preservado.
  Casos de plural/conectivo cobertos e confirmados ("Duplicatas a Receber"
  batendo com a regra "duplicata a receber"; "Provisão PARA Férias" batendo
  com "provisão DE férias"). Disambiguação entre "Total do Ativo" e "Total do
  Ativo Circulante"/"Não Circulante" (achou e corrigiu um bug real de
  sobreposição: "Total do Patrimônio Líquido" casando com a linha combinada
  "Total do Passivo e do Patrimônio Líquido"). Balancete testado reaproveitando
  o classificador do Balanço. Contas genuinamente não-classificáveis (nota
  explicativa, dado sem sentido) caindo em "Contas Não Classificadas" —
  nunca desaparecem, nunca são forçadas pro lugar errado. Nota de proveniência
  na célula, preenchimento âmbar + itálico em pendente, negrito + borda dupla
  em total, aba Resumo com as contagens certas.

## O que NÃO foi possível verificar aqui (precisa do Supabase real)

Sem um projeto Supabase/PostgREST real rodando neste ambiente, as queries
com **embed de foreign key** (`entidade:entidade_id(razao_social)`,
`periodo:periodo_id(tipo, referencia)`, `documento_versao(nome_original)`,
os embeds em `revisao/page.tsx`, `documentos/[docId]/page.tsx` e
`export/route.ts`) foram escritas conforme a sintaxe documentada do
PostgREST/Supabase-js, mas **não foram exercitadas contra um banco real**
(a lógica de montagem do Excel em si — `src/lib/export.ts` — foi testada
isoladamente com dados sintéticos, só a busca via Supabase não). Ao testar a
primeira vez com Supabase real, conferir especialmente:
- Que os embeds trazem os dados esperados (não `null` por ambiguidade de FK
  ou nome errado de relação).
- Que as RPCs `fn_revisar_documento` e `fn_aceitar_extracao` estão com
  `EXECUTE` liberado para `authenticated` (as migrations já fazem o `grant`,
  mas confirmar no painel).
- Login/logout e o redirect do `proxy.ts` funcionando ponta a ponta.
- O botão "Exportar para Excel" baixando um `.xlsx` que abre corretamente no
  Excel/LibreOffice (o teste local só reabriu com `exceljs`, não com um
  programa de planilha de verdade).

## Egresso do Supabase — a cota é dividida com o clipping

A cota de egresso do plano Free é da **organização**, não do projeto. Este portal
divide 5 GB/mês com o *news-clipping*, e em agosto/2026 a organização chegou a
**4,54 GB** — causa quase inteira do outro lado (uma consulta que lia uma tabela
inteira de hora em hora). Se a cota estourar, os dois projetos passam a responder
**HTTP 402 juntos**, e a restrição só cai no ciclo seguinte: no Free não existe
pagar excedente.

Este portal não era o problema — as consultas aqui já nomeiam colunas, e o
`proxy.ts` usa `getClaims()` (verificação local do JWT) em vez de `getUser()`, que
faria um round-trip de rede a cada requisição. As regras abaixo existem para que
continue assim:

- **Nomeie as colunas, nunca `select("*")`.** Se há um `as { ... }` logo abaixo da
  consulta, essa é a lista autoritativa — o `*` só traz o que ninguém lê.
- **Filtre e agregue no Postgres**, não em TypeScript. Linha que chega para ser
  descartada foi paga em egresso à toa. É por isso que as telas pesadas chamam
  RPC (`fn_linhas_para_modelagem`, `fn_conferir_modelagem`) em vez de montar o
  resultado no Next.
- **Toda tela que pergunta em laço precisa desacelerar.** O acompanhamento
  pós-upload (`upload-form.tsx`) mantém a cadência de 8 s nos primeiros 2 minutos
  — onde o analista está olhando — e afrouxa até 30 s depois disso, preservando a
  janela total. Cadência de tela multiplica por centenas.

Para saber quem está consumindo, dentro deste banco:

```sql
select calls, rows, round(rows::numeric / greatest(calls,1), 1) as linhas_por_chamada,
       left(regexp_replace(query, '\s+', ' ', 'g'), 200) as consulta
from pg_stat_statements
order by rows desc limit 20;
```

`linhas_por_chamada` alto é o sinal — não tempo de execução. A consulta que causou
o incidente era rápida; ela só devolvia a tabela toda. O clipping tem isso
empacotado em views (`sql/12_egresso_watch.sql`, naquele repositório), e o número
autoritativo é sempre o painel do Supabase em *Usage → Egress*.

## Estrutura

```
src/
  lib/
    supabase/{client,server,proxy,env}.ts   # clientes Supabase (browser/server/proxy)
    types.ts                                 # tipos das linhas do Postgres
    status.ts                                # rótulos/cores de caso_status
    statement-templates.ts                   # layout padrão de mercado (Balanço/DRE/Fluxo)
    export.ts                                # monta o workbook (função pura, sem Supabase)
  app/
    login/{page.tsx,actions.ts}
    casos/
      layout.tsx                             # header + logout (rotas autenticadas)
      page.tsx                               # lista de casos
      [id]/page.tsx                          # dashboard do caso
      [id]/revisao/{page.tsx,actions.ts}      # fila de revisão
      [id]/documentos/[docId]/{page.tsx,actions.ts}  # planilha + aceite
      [id]/export/route.ts                    # gera o .xlsx (usa lib/export.ts)
  proxy.ts                                    # sessão + redirect (Next.js 16)
```

## Próximas fatias (fora deste escopo)

- Upload em lote pelo portal (hoje é N8N Form) — se algum dia migrar, via SDK
  oficial do Supabase JS (evita o bug de plataforma do HTTP Request do N8N,
  ver `N8N/README.md`).
- Aceite por linha/célula (hoje é por documento_versao inteiro, v0 —
  `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md` permite refinar o "layout fino" depois).
- Portão 2 formal do caso inteiro (bloqueantes não-sobrepujáveis, teto de
  ressalva, `Arquitetura do Sistema/3 Estado e Execução/07_STATUS_E_PENDENCIAS.md`) — hoje só existe o aceite
  mínimo por linha extraída (`fn_aceitar_extracao`).
- RLS por caso (membership) — hoje é "qualquer autenticado vê tudo" (decisão
  explícita da F1, `Supabase/migrations/0003_rls_e_storage.sql`).
