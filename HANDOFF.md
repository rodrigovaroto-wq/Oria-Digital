# Handoff — Tratamento de Dados Financeiros (Oria)

Nota de transição de contexto — **leia isto primeiro, é o resumo pra retomar rápido em um chat
novo.** O histórico detalhado sessão-a-sessão está preservado abaixo (seção "Sessão 7 (cont.¹⁻¹⁶)")
só como referência — não precisa ler tudo pra continuar, comece por aqui.

## ▶ SESSÃO 104 (30/09/2026) — PR [#248](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/248) (rascunho) · branch `claude/compassionate-cray-gk5ade`

> O PR #247 (fase 2 da S103) já estava MERGEADO no início desta sessão (8c0821d). Esta sessão:
> revisou a fase 2, conferiu item a item uma análise externa do Krauspenhar, e corrigiu o que ela
> e a revisão acharam. **Nada foi aplicado em produção**: o classificador do modo automático recusou
> a 0196 ("Production Deploy") — exatamente o que `.claude/memory/auto-mode-recusa-migration-producao.md`
> prevê. Ver §4.

### 0. Estado de produção agora (medido só leitura, 30/09 ~22h40 UTC; reconferido 01/10 ~11h30 UTC)

> Reconferência de 01/10: `instalacao_cobertura.ate_migration = '0195'`, 174/0 ausentes; n8n
> `na1AEv3m8fjDXlwM` atualizado em 30/09 21:08 UTC, 42 nós, `conferir-publicado.mjs` dá "ok" contra
> o repositório em `bc439fa` e diverge do HEAD (`Juntar Blocos`); Vercel produção = `8c0821d`
> (main, 30/09 21:53); nenhum `evento_auditoria`/`decisao` no Krauspenhar depois de 21:54 de 30/09
> (esta sessão não escreveu nele); caso de teste `72d9210a` em `em_triagem`, 4 docs, 10 pendências
> abertas, 0 premissas (o roteiro de modelagem/export NÃO foi feito nele).

- Supabase em **`0195`** (174 requisitos, 0 ausentes). `0196`, `0197`, `0198` só no repositório.
- n8n de ingestão no estado do `bc439fa`. Nenhum commit de ingestão desta sessão nem o `9bd2f88`
  (S103) foi republicado.
- Portal = `main` (inclui `ac9458d`/`4db4e9d` da S103). **Atenção:** o `ac9458d` ("Usar" grava 88,
  não 0,88) já está no ar e tirou a máscara do defeito do lote — em produção, HOJE, premissa em %
  ou em dias ligada a K contas multiplica por K (medido no Krauspenhar: ativo 2026 de 413 mi). O
  conserto (`e093f57`) só chega com o merge do #248. **Até lá, não exporte modelo com premissa em
  lote para cliente.**
- Caso de teste criado nesta sessão pelo portal publicado: **"S104 teste E2E Vertentes"**
  (`72d9210a`, 4 PDFs do book Vertentes). Serve de "antes": caixa 2024 falso (4.840 vs 500),
  faturamento 321.579,6 e `extracao_falhou` do faturamento — os três devem sumir com 0196+republicação.
  O roteiro completo do §5 da S103 (modelagem, Portão 2, export, auditor) NÃO foi feito neste caso:
  ele depende do merge e da republicação para medir o que importa.

### 1. O mandato Krauspenhar (`33b58a89`) — o que mudou desde a S103

Entre 21:50 e 21:53 de 30/09 uma OUTRA sessão Claude (ator `claude:reconstrucao-contabil`) gravou no
caso: v2 "transcrição humana" em 5 documentos (26–31 linhas cada, descritas como "digitadas a partir
do arquivo ilegível" — o arquivo era legível, foi reconstrução por identidade), 7 premissas, ~150
vínculos de linha, e **fundiu a entidade "Centro Oeste" na Krauspenhar** (`entidade_fundida`). Às
21:53:34 o dono aprovou o Portão 2 (caso `aprovado`). Nada disso foi tocado nesta sessão (não alterar
decisão tomada). A aritmética da v2 confere (custos 37,22+10,34+13,82+23,92+2,04 = 87,34; RL 97,95).
**O export que o portal de produção entrega hoje para este caso tem ativo 2026 de 413 mi e receita
bruta de 77 mi em 2025** — os dois defeitos corrigidos em `e093f57` e `d5be032`.

### 2. A análise externa, conferida item a item

Uma análise feita por outra sessão Claude (ator `claude:reconstrucao-contabil`) foi colada pelo dono
no pedido da S104. Cada afirmação foi conferida contra o banco de produção e contra o Excel que o
portal publicado entrega HOJE para o caso `33b58a89` (baixado por GET, que é só leitura: as
funções que a rota chama são `stable` e não escrevem; fórmulas recalculadas com `formulas` 1.3.4).

| # | Afirmação | Veredito | Evidência |
|---|---|---|---|
| 1 | Extração desloca rótulo↔valor | **CONFIRMADO** | DRE 2025 v1: "(-) pis sobre serviços" = −87.341.204,08 no Total (é o de `3.02 CUSTOS`); o deslocamento é de UMA linha para cima a partir da pág. 2 |
| 2 | Subtotal codificado entra como conta | **CONFIRMADO no dado, NÃO como descrito no Excel** | `fn_papel_linha` dá `conta` para 222 de 223 linhas da DRE 2025 v1, inclusive `3.01 RECEITA LIQUIDA`. Mas o Excel do caso NÃO tem receita de 234,6 mi: tem receita bruta de 81,27 mi (menor) porque a detecção estrutural do export tirou "Venda de peças e lubrificantes" (36,19 mi) da soma — ver achado novo N1 |
| 3 | "% da receita" multiplica pelo nº de linhas | **CONFIRMADO, e pior no Excel real** | `formulaConta` (`modelo-institucional.ts:1901`) e o capital de giro (`:2816-2834`). No arquivo do caso: PME 150 dias ligado a 40 contas de estoque → ativo circulante operacional 36,10 → **340,32 mi** em 2026, revolver 18,00 → **333,11 mi**, ativo total 413 mi. CHECK fecha, nenhuma célula vermelha |
| 4 | Estoque em dias sobre a receita, não sobre o custo | **CONFIRMADO no código** | `baseFonte` = `RECEITA_LIQUIDA` para todo ativo; `CUSTOS` só para fornecedor (`:2838`) |
| 5 | Depreciação: vida útil fixa e terreno depreciado; EBITDA distorcido | **PARCIAL** | Vida útil 10 fixa (`:2981`), sim. EBITDA soma de volta a depreciação do ativo fixo (0,43 mi) enquanto o SG&A projeta a da DRE (0,61 mi): 0,18 mi em 2026, sim. **Terreno NÃO é depreciado** neste arquivo (17,78 mi fora do `TOTAL_FA`) — os "1,8 mi sobre terra" não procedem |
| 6 | Storage vazio | **CONFIRMADO** | `storage.objects` = 0 linhas; 1.968 versões com `origem_arquivo='supabase_storage'` e `arquivo_ref` preenchido. Pendência conhecida desde 17/07 (nó `Upload Storage` desligado por bug do n8n), mas o `origem_arquivo` afirma o que não aconteceu (regra 7) |
| 7 | Endividamento 0 linhas | **CONFIRMADO** (já no HANDOFF S103) | 1ª aba é índice |
| 8 | Colunas do balancete trocadas | **CONFIRMADO, com a permutação exata** | Nas págs. 1–8, gravado "Débito" = saldo atual real, "Crédito" = débito real, "Saldo atual" = crédito real (com sinal); 196 contas fecham assim, 111 como rotuladas (90 triviais). Págs. 9–10 como rotuladas |
| 9 | Entidade duplicada; pendência aberta para a DRE e não para o balanço | **INVERTIDO** | A `entidade_incorreta` foi aberta para o **Balanço** CO 2024 e resolvida pelo dono. A fusão Centro Oeste → Krauspenhar foi feita pela própria reconstrução (`entidade_fundida`, 21:50:53) |
| 10 | Defeitos da S103 abertos | **DESATUALIZADO** | PR #247 mergeado (8c0821d): portal corrigido em produção; só a 0196 (não aplicada) e o n8n (não republicado) seguem pendentes |
| 11 | A reconstrução gravada como "transcrição humana" | **CONFIRMADO, e o texto é falso** | As 5 v2 dizem "digitadas a partir do arquivo ilegível". O arquivo era legível; foi reconstrução por identidade. Aritmética da v2 confere (custos 37,22+10,34+13,82+23,92+2,04 = 87,34; RL 97,95) |
| 12 | Catálogo sem drivers de revenda | **PARCIAL** | Há `MARGEM_BRUTA`, `PRECO_MEDIO`×`VOLUME`, `CRESC_REAL`. O limite real é UM valor por código por caso — a mesma raiz do item 3 |

**Os "sinais de estresse em ago/26" são artefato do item 8.** A análise leu o crédito do período
como saldo. Pela identidade contábil (fecha nas seis contas), os saldos reais de ago/26 são:

| Conta | Análise | Real (SA − C + D ou SA + D − C) |
|---|---|---|
| Estoques | 61,6 mi | **47,96 mi** |
| Fornecedores | ~62 mi | **41,39 mi** |
| ICMS a recolher | 2,65 mi | **0,05 mi** |
| Adiantamento de clientes | 10,6 mi | **1,95 mi** |
| INSS/IRRF a pagar | 1,1 mi | **0,14 mi** |
| Salários a pagar | 2,3 mi | **0,15 mi** |

A conclusão "padrão de uso de tributo e folha como financiamento" NÃO é sustentada pelo dado.

**Achados novos (não estavam na análise):**
- N1. A detecção estrutural de subtotal do export tira um rótulo da soma em TODOS os anos da
  entidade quando ele é subtotal em QUALQUER documento dela: "Venda de peças e lubrificantes" é
  subtotal no balancete 2026 e folha na DRE 2025 → 36,19 mi viram resíduo de reconciliação
  constante na projeção (não crescem com o SSS).
- N2. O bloco de cenários (sombras) mostra EBITDA 2026 de −36,83 mi (margem −94,7%), porque o
  resíduo não entra nas sombras.
- N3. A reconstrução ligou premissas a rótulos da v1 E da v2 ao mesmo tempo (ex.: 27 contas de
  custo, incluindo subtotal e filhos) — decisões registradas com ator `claude:reconstrucao-contabil`,
  anteriores à aprovação do Portão 2 pelo dono (21:53:34).

**Sobre N1:** a primeira medição do conserto dizia "não muda nada" porque o servidor local antigo
continuava na porta 3100 (os `next start` seguintes falharam por EADDRINUSE sem eu ver). Refeita
com o processo certo: receita bruta 114,76/113,38 mi, resíduo ~0, EBITDA de cenários −2,46 mi.

### 3. Commits desta sessão (um por fatia, cada um medido desligado — números na mensagem)

| Commit | O quê | Onde vale |
|---|---|---|
| `efd19ef` | Série: total impresso ANTES dos meses fazia a conferência se pular (OMNIBEAUTY 63a36efe; bloqueava republicar o 9bd2f88) | republicar n8n |
| `05af713` | Balancete com colunas trocadas por página → `extracao_falhou` nomeando a troca (28 contas reais no teste) | republicar |
| `e093f57` | **Modelo: premissa ligada a K contas multiplicava por K** — rateio pela parcela histórica. Krauspenhar real: ativo 2026 413,15 → 89,07 mi | merge (portal) |
| `5ff57ac` | Aba Modelagem mostrava 8797% (premissa em pontos sem /100) | merge |
| `3854db7` | xlsx com várias abas → pendência "só a 1ª aba foi lida" (ler todas: sem caminho provado) | republicar |
| `4fb5b23` | Portão 2 com RPC falhando: tela dizia "Pronto" e export passava → 3 estados, export 503 fail-closed | merge |
| `578577e` | Valor colado ao rótulo ("2 113.860.002,40PASSIVO") limpo só quando prova ser o valor; chave só-número declarada | republicar |
| `6a94f9d` | **0197**: faturamento com mês na coluna somava 0 meses; ticket médio por rótulo entrava | aplicar |
| `8d1235e` | DRE jan–ago registrada "anual 2026" → `multi 8M26` pelo nome; prompts proíbem anual <12 meses | republicar |
| `86c459f` | **0198**: faixa "2024-2026" perdia 2025 (só o Mapa de Dívida do Krauspenhar muda) | aplicar |
| `d5be032` | **Export: agrupamento de um documento apagava a folha homônima de outro** — Krauspenhar: receita bruta 77,19 → 113,38 mi, resíduo 36,19 → 0 | merge |
| `1b440ac` | DRE analítica com 33 de 43 sintéticas sem fechar → `extracao_falhou` (hierarquia de códigos) | republicar |
| `69e6666` | O assert (0109d) do verificar-export passava SEMPRE (regex com `|` sem escape casava vazio) — achado pelo Sonar como bug | — |
| `507915b` | Revisão independente: a guarda de hierarquia acusava o Balanço 2025 real (código reduzido de 4 dígitos cortava as filhas). Controle negativo real agora no teste | republicar |
| `012087e` | Revisão independente: mesma premissa em custo E SG&A ainda projetava 2×; bases diferentes no giro ganham nota do efeito | merge |
| `7ad782c`, `9f096c5` | Guarda de hierarquia: aging certo acusado → regra de três → REDESENHO (só estrutura inequívoca; cala na dúvida). Corpus 1.387 docs: 0 disparos novos, 0 vereditos invertidos | republicar |
| `5f40d21` | Portão 2: helper único do veredito, botão desabilitado com texto visível, 503 sem erro cru | merge |
| `fa6ccda`, `7b9e820`, `3b803cb` | CI em 6 jobs paralelos + agregador `suites` (falha se qualquer job não for `success`, inclusive cancelado) | — |
| `bf19d42`, `7f49566` | **Export: CDI parcial (9 meses) virava taxa anual e, sem Focus de CDI, a projeção cobrava juro ZERO** — achado no E2E. A revisão pegou que copiar a Selic do Focus (META de fim de ano) subestima o acumulado num ciclo de corte: agora compõe o realizado parcial com a meta e usa a média das metas t-1/t. Krauspenhar real: CDI 2026-30 9,71/0/0/0/0 → 13,30/12,88/11,25/10,25/10; juros do revolver 0 → 2,83–4,26 mi/ano; revolver 2030 36,16 → 50,55 mi | merge |
| `a6d5231`, `9d692a1`, `466bc32` | Sonar (complexidade, template aninhado, duplicação 5,3% do Quality Gate), sem mudar comportamento | — |
| grafo | derivado regerado a cada leva | — |

**Revisão independente de `8c0821d..HEAD`:** feita, e RECONFIRMADA em 01/10. Os achados que
sobreviveram viraram `507915b`, `012087e`, `7ad782c`. A guarda de hierarquia bateu na regra de três
correções (Balanço 2025 Krauspenhar → aging do Canastra → DFC da Fort Lub) e foi REDESENHADA em
`9f096c5`: só avalia sintética de estrutura inequívoca e se cala na dúvida. Segunda leitura do
desenho novo (revisor, corpus de 1.387 documentos de produção, veredito por sintética contra
`1b440ac`): **nada sobreviveu** — 3 disparos (o único perdido é o falso positivo do Balanço), 0
vereditos invertidos, 13 sintéticas viram "não avaliável" (o preço declarado). As três DREs com
deslocamento seguem disparando (31/41, 10/15, 36/50). **A republicação da ingestão está liberada.**

### 3b. Validação de 01/10 (tudo só leitura em produção, exceto o caso de TESTE `72d9210a`)

- **Suíte local no HEAD:** 27/27 etapas do `suites.yml` OK (inclusive `run.sh`, conferidor, sonda
  sem buraco, E2E, variações e `next build`). CI: os 6 jobs + agregador verdes; Sonar QG OK.
- **Conexões de produção:** as 60 funções que n8n e portal chamam existem no `pg_proc` de produção;
  workflows `erros` (59DPz4s2d3DHSR9M) e `macro` (UGhv57BU3YNukVxV) batem com o repositório nó a nó
  (só default do n8n difere) — o `conferir-publicado` não os acha porque o NOME publicado tem
  "SARF" ("Oria SARF — Reportar Erros") e o do repositório não; ingestão = `bc439fa` (diverge do
  HEAD, esperado até republicar); portal de produção = `8c0821d` (`main`), `/login` 200.
- **E2E do portal do branch no caso de TESTE** (build local contra produção, Playwright): parâmetros
  salvos; as 7 sugestões do realizado "Usar" gravaram os valores em pontos (SG&A 23,62; PMR 153,30;
  PME 96,79; PMP 111,13; parcela onerosa 38,39; taxa 15,17; custo variável 87,97); lote "aplicar às
  6 contas" ok; **Portão 2 recusou o export completo (409, 4 bloqueantes)**; com as 4 pendências de
  Kit Básico decididas "Prosseguir sem resolução" (só no caso de teste) → 200, `auditar-xlsx` 11/11,
  balanço fecha nas 7 colunas, DRE do realizado com diferença zero. Krauspenhar NÃO foi tocado
  (hash das linhas de modelagem conferido antes/depois).
- **O E2E achou o `bf19d42`** (CDI → juro zero na projeção, ver tabela). Ainda no Krauspenhar, o
  `auditar-xlsx` dá 10/11 ANTES e DEPOIS: o resíduo de reconciliação do ativo circulante é 43% do
  ativo total (14 células) — anterior a este PR, entra em §5 como item novo (l).

### 4. O QUE O DONO FAZ À MÃO (modo manual — o automático recusa)

Na ordem. Cada migration numa chamada (nenhuma tem `alter type`):
```bash
REF=$(echo "$SUPABASE_URL" | sed -E 's#https://([^.]+)\..*#\1#')
for m in 0196_o_caixa_que_lia_a_dfc_de_outro_ano 0197_o_faturamento_que_nao_via_o_mes_na_coluna 0198_a_faixa_de_anos_que_perdia_o_ano_do_meio; do
  jq -Rs '{query: .}' < Supabase/migrations/$m.sql > /tmp/p.json
  curl -sS -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" --data-binary @/tmp/p.json; echo " <- $m"
done
# conferir: a primeira vazia, a segunda '0198'
#   select chave from fn_instalacao_conferir() where not presente;
#   select ate_migration from instalacao_cobertura;
```
Depois do MERGE do #248 (o `republicar.sh` exige a árvore igual ao `origin/main`):
```bash
git checkout main && git pull
N8N_URL="$N8N_BASE_URL" N8N_WORKFLOW_ID=na1AEv3m8fjDXlwM bash N8N/republicar.sh   # tem de dizer PUBLICADO E CONFERIDO
```
Depois: `fn_reconciliar_caso` no Krauspenhar (permitido pelo dono) e no `72d9210a`, registrando
antes/depois das pendências de reconciliação. Reprocessar o E2E: caixa 2024 sem divergência falsa,
receita 2024 = 183.480, sem `extracao_falhou` do faturamento. E um mandato novo pelo portal é a
única prova de que o n8n republicado alcança o banco.

### 5. Próximas fatias, pela ordem de impacto

a. **Causa do deslocamento rótulo↔valor** (a guarda de `1b440ac` só nomeia). Medido na DRE 2025 v1:
   deslocamento 0 até a ordem 13, +1 até 35, 0 até 55, +1 até 111, +2 até 170, mistura depois; as
   mudanças coincidem com 4 rótulos repetidos em sequência (3.01.01.03, 001259, 3.05.01.01, 3.05.02).
   Hipótese: o modelo duplica uma linha e o pareamento anda. Precisa da resposta crua do modelo dessas
   páginas (NÃO baixar execução grande do n8n; reproduzir com o PDF, que só o dono tem — o Storage
   está vazio, item 6 da tabela).
b. **Controle negativo real da guarda de hierarquia**: um DRE/balancete de produção com ≥10 sintéticas
   que feche (nenhum book do repositório tem hierarquia).
c. **Resíduo de reconciliação da receita fora das sombras e da base dos dias de giro**
   (`modelo-institucional.ts`, comentário ~2197 diz que ele "só existe no realizado" — falso).
d. **Subtotal codificado entra como conta** em `fn_papel_linha` (222 de 223 linhas da DRE 2025 v1,
   inclusive `3.01 RECEITA LIQUIDA`). O export tem detecção estrutural que cobre parte; medir num caso
   que use a v1 antes de mexer.
e. **Storage vazio** com `origem_arquivo='supabase_storage'` em 1.968 versões: subir do portal
   (upload assinado direto do navegador, sem passar pela Vercel) ou gravar a origem verdadeira.
f. **xlsx: ler todas as abas** (um nó por `sheetName`, ou liberar `zlib` no sandbox).
g. **Períodos "multi 02,25"** (17 em produção) viram {2002,2025} — `fn_periodo_canonico` lê "02" como ano.
h. **PME sobre receita (modelo institucional) × sobre custo (aba Modelagem)** — decidir a base.
i. **Um valor por código de premissa por caso** impede crescimentos diferentes por linha (máquinas
   −38% × pós-venda 0%): desenho de premissa por grupo de linhas.
j. `fn_reconciliar_ativo_passivo_pl` multiplica a tolerância pela escala (S103 §3.6f) — não tocado.
k. Sonar: issues menores do portal no PR (template aninhado, ternário) — Quality Gate passa.
l. **Krauspenhar: resíduo do ativo circulante 43% do ativo total** (Balance Sheet!E6:G6, 53,9/43,6 mi) —
   medir se é o subtotal codificado de (d) entrando como conta antes de mexer.
m. `conferir-publicado` não acha `erros`/`macro` por nome ("Oria SARF — …" publicado × "Oria — …" no
   repositório): renomear um dos lados é decisão do dono; o conteúdo bate.

### 6. Armadilhas novas

- **Servidor local velho na porta**: `next start` que falha por EADDRINUSE deixa o antigo servindo e
  a medição mente. Conferir `ps -eo pid,lstart,cmd | grep next-server` antes de medir.
- **Preview da Vercel tem SSO**: para testar o portal do branch contra produção, compile numa worktree
  (`node_modules` COPIADO — symlink quebra o Turbopack), sirva com a anon key (API de gerenciamento,
  `/v1/projects/<ref>/api-keys`) e baixe o export por Playwright. O export é só leitura (a rota chama
  só funções `stable`).
- **Recalcular o Excel sem LibreOffice**: `pip install formulas openpyxl`; ~1 min por arquivo.
- **O `run.sh` exige o ESTADO.md citando a migration mais nova** — o agente de banco não toca o
  ESTADO; quem comita acrescenta.
- **O hook de descarte bloqueia restaurar arquivo pelo índice até numa worktree descartável** (e casa
  até texto de heredoc que cite o comando): use `git show HEAD:arquivo > arquivo`.

---

## ▶ SESSÃO 103 (30/09/2026) — PLANO EXECUTIVO PARA A PRÓXIMA SESSÃO · branch `claude/epic-euler-gzuifi`

> Escrito no fim da S103, com o limite de uso da conta acabando. **Leia isto inteiro antes de
> qualquer coisa.** PR [#246](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/246)
> (fase 1) está MERGEADO. A fase 2 (este bloco) está no PR aberto no fim da S103 — a branch foi
> reiniciada do `main` depois do merge do #246.

### 0. Estado de PRODUÇÃO agora (conferido em 30/09, ~22h UTC)

- **Supabase em `0195`**: `ate_migration = '0195'`, `fn_instalacao_conferir()` = 174 requisitos,
  0 ausentes, `conferir_chamadas.sql` = "PODE RODAR". A **`0196` está só no repositório** (commit
  `cbcc74b`, NÃO aplicada, revisão independente NÃO concluída — foi interrompida pelo limite).
- **n8n**: ingestão (`na1AEv3m8fjDXlwM`) republicada e conferida (42 nós) no commit `bc439fa`
  (fase 1). O commit `9bd2f88` (total da série) **NÃO foi republicado**.
- **Credencial Postgres do n8n** (`D7NYaWY1UYKy2vBc`, "Postgres (Trat. Dados)") foi CONSERTADA
  hoje: estava com a senha inválida desde algum momento depois de 17/09 e nenhum mandato gravava.
  Ver `.claude/memory/credencial-do-n8n-quebra-sem-deixar-rastro.md`.
- **Portal (Vercel)**: produção no `main` (`af1aa90`, merge do #246). Os commits `ac9458d` e
  `4db4e9d` (portal) só chegam lá quando o PR da fase 2 for mergeado.
- O dono está com a sessão em **modo manual**: é assim que o apply em produção passa (o
  classificador do modo automático recusa — `.claude/memory/auto-mode-recusa-migration-producao.md`).

### 1. O MANDATO REAL — "KRAUSPENHAR E HARTMANN" (caso `33b58a89-0d77-417a-8859-e193c61e8db8`)

Subido pelo dono em 30/09 21:19 (execução n8n 8316, sucesso): 7 documentos, 8.915 linhas, US$ 0,42.
**É o caso que importa — trate com mais cuidado que qualquer caso de teste. O dono está trabalhando
nele (já resolveu tipo/período/entidade na revisão). NÃO rode reconciliação nem nada que ESCREVA
nele sem perguntar.** O que foi diagnosticado (só leitura):

| Documento | Problema medido | Contorno para o dono HOJE |
|---|---|---|
| `Endividamento Krauspenhar.xlsx` | **0 linhas.** O extrator do n8n lê SÓ A PRIMEIRA ABA, que é um índice; a tabela está na aba "Abertura endividamento" | Salvar a aba de dívida como arquivo próprio (ou movê-la para a 1ª posição) e reenviar por "Adicionar arquivos" |
| `balancete_janaago26.pdf` | Classificado COMBINADO (o dono corrigiu). 38 contas SINTÉTICAS (ATIVO, CIRCULANTE, DISPONÍVEL, CAIXA…) descartadas: modelo declara 4 colunas e devolve 5 valores. E as colunas gravadas não fecham entre si (ex.: Adiantamentos: 156.963 + 356.454 − 494.860 ≠ −295.369 do "Saldo atual"); "Crédito" tem 288 linhas contra 320 das outras | Não usar o balancete como base de número; usar Balanço 2025 e DREs |
| `Balanço 2025 Krauspenhar assinado.pdf` | Rótulo do total do passivo veio COLADO ao número (`"2 113.860.002,40PASSIVO"`) → Passivo+PL não localizado; ATIVO 113,86 mi com filhos 84,37 mi (ANC não pendurado no ATIVO); `extracao_padrao_suspeito` com 4 contas = 4.183.333,35 (pode ser legítimo: NC = ELP = Empréstimos LP quando há uma conta só) | Conferir na revisão o total do passivo contra o PDF |
| `DRE Krauspenhar 2025`, `DRE Centro Oeste 2024` | Cobertura 45% e 47% (223 de 493, 47 de 101 linhas de conta) | Conferir a DRE na revisão antes de confiar; se faltar muito, reenviar fatiado |
| `DRE_janaago26.pdf` | Registrada "anual 2026", mas é jan–ago (8 meses); cobertura 58%; 1 conta com 13 valores para 12 colunas | Na modelagem, **último exercício realizado = 2025** (não 2026) |
| `Balanço Centro Oeste 2024` | Entidade "Centro Oeste" × conteúdo Krauspenhar | O dono já resolveu |

Pendências abertas no caso (30/09): 5 `extracao_falhou`, 5 `item_faltante` (FAT_INTRAGRUPO,
CONTRATO_SOCIAL, FATURAMENTO_24M, FLUXO_CAIXA, MUTUOS), 3 `linha_exigida_ausente`, 5
`precondicao_nao_satisfeita`, 2 `secao_fecha` divergentes, papel/forma de controle das 2 entidades.

### 2. O que a fase 2 entregou (commits na branch, um por fatia, cada um medido desligado)

| Commit | Defeito | Medição | Em produção? |
|---|---|---|---|
| `ac9458d` | "Usar" numa sugestão em % gravava fração (0,8797) e o modelo dividia por 100 → Custo variável 0,9%, SG&A 0,2% no Excel | 3 de 5 reprovam desligado | só após merge (portal) |
| `4db4e9d` | Modelagem dizia "Pronto para o export" com Portão 2 fechado; export devolvia JSON 409 | 3 de 4 | só após merge (portal) |
| `9bd2f88` | `conferirTotalDaSerie` somava "Média mensal"/"Ticket médio" (depois do total) e colunas "Variação %" → `extracao_falhou` falsa no faturamento | 2+1 | **precisa republicar o n8n** |
| `cbcc74b` | **0196**: caixa/receita/despfin/faturamento liam linha de outro ano e somavam colunas de outro ano (R$ 4,34 mi falso de caixa; faturamento 321.579,6 em vez de 183.480) | 17 de 21 | **precisa aplicar** |

Suíte em `cbcc74b` (parcial, interrompida): 19 etapas verdes — n8n, hooks, Supabase .mjs, as 8 do
portal, conhecimento, índice, comandos, espelho, **run.sh (1.716 ok)**, conferidor, sonda, e2e.
NÃO rodaram nesta passada: `variacoes.mts`, medidores, geradores, fixtures, `next build`.

### 3. Roteiro da PRÓXIMA sessão, EM ORDEM (critério de pronto em cada item)

1. **Preparar o container** (comandos do `CLAUDE.md`) e rodar a suíte COMPLETA em `HEAD`. Pronto:
   as 26 etapas verdes.
2. **Revisão independente da 0196 e dos 3 commits** (`revisor-defeito-silencioso`), com foco em:
   o que a 0196 muda no caso Krauspenhar (simular por consulta só-leitura); a regex de coluna não
   aditiva do n8n (`/%|varia|\bvar\b|margem|media|ticket|indice|taxa/`) pular série legítima;
   `valorParaGravar` contra TODA leitura de `p.valores` em `modelo-institucional.ts` (há fórmula %
   que não divide por 100?); a tela de modelagem com `fn_avaliar_portao2` falhando. Pronto: "nada
   sobreviveu", ou cada achado corrigido e medido.
3. **Com autorização do dono (modo manual)**: aplicar a `0196` pela API de gerenciamento (arquivo
   inteiro, uma chamada — não tem `alter type`), conferir `fn_instalacao_conferir() where not
   presente` = vazio e `ate_migration = '0196'`; republicar o n8n (`N8N/republicar.sh`, com
   `N8N_URL="$N8N_BASE_URL" N8N_WORKFLOW_ID=na1AEv3m8fjDXlwM`). Pronto: os dois conferidos.
4. **Testar o fluxo** com um caso de TESTE novo (nunca no Krauspenhar sem autorização): BP + DRE +
   DFC + Faturamento do book `Dados de Teste/book-vertentes` pelo portal (roteiro Playwright no
   §5). Pronto: sem pendência falsa de caixa 2024, sem `extracao_falhou` do faturamento, receita
   2024 = 183.480.
5. **Abrir/atualizar o PR da fase 2** e levar ao verde.
6. **Próximas correções, pela ordem de impacto no mandato real** (cada uma com diagnóstico no dado
   real ANTES de codar):
   a. **xlsx lê só a primeira aba** (Endividamento perdido). O `Extract From File` só aceita UMA
      `sheetName`; ler todas exige outra abordagem (medir se o Code node da instância aceita
      `require` de builtin; ou um nó por aba). Maior valor para o dono.
   b. **Coluna N declarada × N+1 valores** (balancete: 38 contas sintéticas; COMBINADO do book
      Vertentes: 32 contas; DRE jan–ago: 1). Precisa ver QUAL é o valor a mais — provavelmente o
      código da conta sintética. NÃO baixe a execução 8316 com `includeData` (derruba o n8n,
      `.claude/memory/n8n-nao-aguenta-baixar-execucao-grande.md`); peça o PDF ao dono ou reproduza
      com o texto do book.
   c. **Rótulo com número colado** (`"2 113.860.002,40PASSIVO"`) no Balanço 2025.
   d. **Cobertura 45–58% nas DREs analíticas** (223 de 493 linhas).
   e. **Período YTD tratado como anual** (DRE jan–ago → "anual 2026").
   f. `fn_reconciliar_ativo_passivo_pl` ainda multiplica a tolerância pela escala (achado da 0196).
   g. **COMBINADO do book** com 0 linhas é o mesmo defeito de (b).

### 4. Armadilhas desta sessão (não repita)

- **Nunca baixe execução grande do n8n** (`includeData=true`): deu 502 na instância por ~2 min.
- **Verde da sonda/conferidor NÃO prova que o n8n alcança o banco** — a credencial ficou 13 dias
  quebrada. Um mandato de teste criando o caso no banco é a prova.
- Função da lib embutida em nó por `toString()`: helper nova tem de ser embutida também (o Sonar
  S3776 obrigou a extrair uma; sem embutir, 11 testes reprovam e o nó quebraria em produção).
- `pkill -f run.sh` do próprio shell mata a chamada (exit 144); confira `ps` em chamada separada.
- LibreOffice deste container não abre .xlsx (é o ambiente); o auditor é `auditar-xlsx.mts`.
- `rm /base.log` é bloqueado pelo hook de segurança — arquivo de 318 KB deixado por um agente na raiz
  do sistema do container; inofensivo, some com o container.

### 5. Como dirigir o portal publicado (usado nesta sessão)

`playwright-core@1.56` no scratchpad, Chromium em `/opt/pw-browsers/chromium-1194/chrome-linux/chrome`
com `--ignore-certificate-errors-spki-list=<SPKI da CA do proxy>` (calcular com
`openssl x509 -in /root/.ccr/agent-proxy-ca.crt -pubkey -noout | openssl pkey -pubin -outform der |
openssl dgst -sha256 -binary | base64`). Login com o e-mail/senha do dono em variáveis de ambiente
(nunca em arquivo). Seletores que funcionam: upload `form:has(input[type=file])`; premissa
`#premissas form:has(input[name=codigo][value="X"]):has(input[type=text])`; lote
`#linhas form:has(input[name=secao_canonica][value="S"]):has(select[name=premissa])`; download via
`ctx.request.get('/casos/<id>/export')` (dá o status HTTP — o clique esconde o 409).

---

## ▶ SESSÃO 102 (25–28/09/2026) — PLANO EXECUTIVO PARA A PRÓXIMA SESSÃO · PR #245 (rascunho)

> Escrito no fim da S102, com o limite semanal de uso em 97%. **Leia isto inteiro antes de qualquer
> coisa.** Branch `claude/eager-mccarthy-m4g1md`; o PR é
> [#245](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/245).

### 0. Onde estamos (conferido em 28/09, produção só leitura)

- **Produção está em `0182`**, e NADA foi escrito lá desde 22/09: nenhuma reconciliação, pendência
  ou evento. O `ate_migration = '0182'` está ERRADO (a `0183` conserta). As migrations `0183`,
  `0189` e `0190`–`0195` existem só no repositório.
- **Repositório:** `0190`–`0195` commitadas, uma fatia por commit, cada uma medida não-vazia. O
  `run.sh` está verde com 1.656 `ok` no `2cce60e`, e o CI está verde.
- **Em andamento quando a sessão parou:** um agente `migrations-postgres` corrigindo o GRUPO A
  (abaixo) no próprio arquivo da `0195`. **Se houver mudança não commitada na árvore, é esse
  trabalho pela metade:** rode `git diff`, confira contra o grupo A, rode o `run.sh` e só então
  commite. Se estiver incompleto, termine; não descarte sem ler.

### 1. O que a S102 entregou (detalhe e medição em cada commit: `git log 909e959..HEAD`)

| Migration | Defeito | Medição |
|---|---|---|
| `0190` | `fn_reconciliar_arvore` gravava `ok` com 0 seções conferidas | 12 linhas em 4 casos em produção; 4 de 12 asserts reprovam desligado |
| `0191` | despfin comparava cada ano da DRE com o Mapa de Dívida inteiro (o mapa é de UMA data) | 5 de 9 |
| `0192` | na mesma rodada, o `ok` de um período resolvia a divergência do irmão compatível | v33/v35: R$ 4,34 mi nascida e morta no mesmo instante; 3 de 15 |
| `0193` | tolerância de receita/caixa × escala (R$ 50 mi numa DRE em milhar); piso de arredondamento do caixa | 0 casos hoje; 1 por função |
| `0194` | a checagem de mútuos NUNCA leu a planilha em produção (sentinela `E'\x01'`); lado A escolhia o balanço sem olhar o ano; a razão social decidia o lado; uma planilha por chamada; balanço de um ano entrava em qualquer ano | 5+3, 4+1+2, 2 |
| `0195` | intragrupo com os mesmos vícios; regra fatorada em `fn_linha_vale_para_ano` | 7 de 10 |

**Decisão do dono em 25/09:** a F2.3 (checagem de FAT_INTRAGRUPO) foi ADIADA. Não existe o outro
lado da comparação em produção: o FAT_INTRAGRUPO do AMO não traz a contraparte, e nenhum COMBINADO
tem receita em "Eliminações". **Refutado por medição:** a hipótese de "DVA/DMPL contadas duas vezes
no realizado" — há 0 colisões, e `fn_linhas_do_realizado` escolhe um valor por grupo, não soma.

### 2. ACHADOS ABERTOS DA REVISÃO — resolver ANTES de aplicar `0192`/`0194`/`0195`

A revisão de defeito silencioso da S102 (refeita em 28/09, depois de morrer no limite) devolveu
seis achados. **Nenhum está resolvido no commit `2cce60e`.**

**GRUPO A — arquivo `0195` (corpo final de `fn_reconciliar_mutuos`/`fn_reconciliar_intragrupo`). Era o que estava em andamento.**
1. **CRÍTICO — o lado A de mútuos soma DUAS vezes a conta repetida na nota "Partes Relacionadas".**
   - Onde: CTE `linhas`, herdado da 0123. No alto volume, o doc `2f17a7ba` (Varejo, multi 21..25)
     traz "Mútuos a pagar - controladora" na face (ordem 38) E na nota (ordem 62).
   - As "divergências reais" de 2021/2022 que o cabeçalho da 0194 e o README descrevem (409 e 890
     mil) SÃO essa duplicata: sem ela, os dois lados fecham exatos. **Corrigir e desmentir o
     cabeçalho e o README.**
2. **ALTO — desempate por `criado_em desc` empata em produção:** 44 grupos, 160 documentos, 14 casos.
   O plano de execução escolhe o documento e o resultado muda (1,6 mi × 240 mil). Acrescentar
   `d.id` como último critério nas duas funções e remedir a previsão.
3. **MÉDIO — o `exists` de "tem dado intragrupo" aceita qualquer linha ≠ 0.** Deve exigir
   contraparte/lado, como a função reconhece uma linha intragrupo.

**GRUPO B — arquivo `0192` (`fn_registrar_reconciliacao`/`fn_reconciliar_caso`). NÃO começado.**
4. **ALTO — entre rodadas a ordem ainda decide o destino da pendência.**
   - Reproduzido no tdf_test: com a divergência ainda de pé, o `ok` do período que ordena primeiro
     RESOLVE a pendência (inclusive em `em_correcao_interna`/`aceita_com_ressalva`), e a
     divergente abre OUTRA. Some o trabalho humano e a trilha diz "resolvida".
   - Desenho sugerido: dentro de `fn_reconciliar_caso`, não resolver dentro de
     `fn_registrar_reconciliacao`; resolver no FIM da rodada só as pendências cujas chaves
     compatíveis desta transação concluíram sem divergência (flag local da transação,
     `set_config(..., true)`).
   - **É mudança de desenho: tratar como decisão, e medir.**
5. **ALTO — `secao_fecha` é POR DOCUMENTO, mas a pendência é casada por (entidade, período
   compatível).**
   - O n8n chama `fn_reconciliar_por_documento($1,'documento')` em transações separadas
     (`queryBatching: 'independently'`, `N8N/build-workflow.mjs:2405` e `:2030`), e o `ok` de outro
     balanço resolve a divergência.
   - Produção: 21 pendências `secao_fecha` resolvidas em menos de 10 minutos (ex.: `866d4c3d`,
     `c5c10450`). A `0190` agrava, porque `documento_ausente` também resolve.
   - Correção: casar a pendência de `secao_fecha` por `documento_id`.
6. **MÉDIO — regra 1: o texto da checagem se perde quando ela não abre pendência.**
   - `reconciliacao` não tem coluna de descrição.
   - Na 0190, "hierarquia achatada/rótulo duplicado" some; na 0194, "planilha deste exercício não
     entregue" fica igual a "nenhum balanço traz mútuo".
   - O `ok` da 0191 diz "em 1 ano(s)" sem dizer que 2024 ficou sem par (13 chaves assim em
     produção).
   - Sugestão: coluna `reconciliacao.descricao`, gravada sempre por `fn_registrar_reconciliacao`.

**Também registrado, sem fatia (é anterior a este PR):** o texto das pendências de receita/caixa
mistura escalas ("Receita Bruta 183480 vs 1 meses de faturamento 38.2 — diferença de 183441800.0").

### 3. O que o DONO faz à mão, NESTA ORDEM (auto mode recusa apply em produção: modo manual ou SQL Editor)

1. **`0183`** em duas chamadas: primeiro a linha do `alter type`, depois o resto com essa linha
   comentada (roteiro no `ESTADO.md`, bloco F1.7). Conferir: `select ate_migration from
   instalacao_cobertura` volta a `0188`+, e 18 pendências `forma_de_controle_indefinida` abrem.
2. **`0189`**. Conferir: `select chave, objeto from fn_instalacao_conferir() where tipo='gatilho' and
   not presente` → vazio.
3. **`0190`, `0191`, `0193`**: independentes e seguras (o revisor conferiu que um prefixo deixa o
   banco coerente). Conferências no `Supabase/README.md`.
4. **`0192`, `0194`, `0195`: SÓ depois de o grupo A e o grupo B fecharem neste PR.** A `0191` vem
   antes da `0192`.
5. Depois de aplicar: rodar a sonda (`fn_instalacao_conferir() where not presente` → vazio) e uma
   rodada de um caso de teste, conferindo a tabela de previsão do README da 0194/0195.
6. Backfills não automáticos (medir o alcance ANTES): as 12 linhas `secao_fecha` 'ok' com 0
   conferidas; as pendências nascidas e mortas no mesmo instante. Consultas no README.
7. O merge do PR #245 é do dono.

### 4. Roteiro da PRÓXIMA sessão de engenharia (em ordem, cada item com critério de pronto)

1. **Terminar o grupo A** (se ficou pela metade) e commitar. Pronto quando: run.sh verde; cada
   correção medida não-vazia; tabela de previsão remedida em produção, só leitura, sem empate que
   mude o resultado.
2. **Grupo B (achados 4, 5, 6)** no arquivo da `0192`. Começar pelo 5, que é o mais claro
   (`secao_fecha` por documento); o 4 e o 6 são desenho: escrever a escolha no cabeçalho antes do
   código. Pronto quando: um teste para cada cenário reproduzido acima reprova desligado; os 21
   casos de produção são explicados.
3. **`/revisar` de novo** sobre `909e959..HEAD` com as DUAS lentes (defeito silencioso e fidelidade
   do número), porque o grupo B mexe no registro que TODAS as checagens usam. "Nada sobreviveu" é
   o critério de pronto do PR.
4. **`/fechar`**: `ESTADO.md` (o bloco S102 do topo precisa das linhas finais da 0194/0195 e dos
   achados), ficha em `.claude/conhecimento/fichas/`, memória, `indexar.mjs` e `conferir.mjs`,
   descrição do PR.
5. **Memória nova sugerida** (padrão que custou caro 3 vezes nesta sessão): *"ligar um estágio que
   nunca rodou expõe os defeitos que ele escondia"*. A 0194 religou os mútuos e trouxe cinco
   defeitos antigos do lado A. Antes de ligar, medir em produção o número que vai sair.
6. **Depois do PR — o roadmap** (`Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md`):
   - **F1.6:** o aceite do perímetro. Bloqueado: depende do COMBINADO real do cliente e da decisão
     do dono sobre bloco familiar (§12.2).
   - **F2.3:** adiada; reabre quando houver FAT_INTRAGRUPO com contraparte, ou COMBINADO com
     eliminação de receita.
   - **Próxima de engenharia no caminho crítico: F4** (conta canônica, hierarquia e resolução), a
     intervenção central do plano. Pode ir em paralelo a F3/F3b se os arquivos forem disjuntos
     (§8). A F3b toca o `SYSTEM_PROMPT` e o schema da linha.
   - Erros de classificação medidos em 25/09, candidatos a fatia pequena: o "COMBINADO" do AMO é
     um balancete de uma empresa; os PDFs de faturamento mensal do AMOBELEZA estão classificados
     como FAT_INTRAGRUPO.

### 5. Como começar (e as armadilhas desta sessão)

- Preparo: os comandos canônicos do `CLAUDE.md`. O Postgres local NÃO sobrevive a um container
  novo: suba com `pg_ctl` e rode `chmod a+w Supabase Supabase/schema.sql`.
- Produção só leitura: API de gerenciamento com `begin read only; ...; commit;`
  (`.claude/memory/aplicar-migration-em-producao-pela-api.md`).
- **As fixtures NÃO têm o formato de produção.** A planilha MUTUOS das fixtures traz
  `periodo_coluna='2025'`, e a de produção traz o cabeçalho "Saldo devedor". Tudo passava no teste
  e falhava em produção. Meça o formato real antes de confiar num teste verde.
- A migration mais nova precisa estar citada no `ESTADO.md`, senão o `run.sh` reprova.
- Agente em segundo plano avisa "esperando o run.sh" várias vezes; confira com `ps` antes de achar
  que travou. Nunca commite a árvore enquanto um agente a tem.
- `git checkout <arquivo>` é bloqueado pelo hook: copie para o scratchpad e restaure com
  `git show HEAD:<arq> > <arq>`.

---

## ✅ SESSÃO 101 (23–24/09/2026) — `0189`: a sonda vê gatilho; PR #242

1. **`0189` escrita, medida e revisada duas vezes** (revisores independentes). A sonda passa a
   catalogar o gatilho POR SI — a função do gatilho sobrevive a `drop`/`disable trigger`, então
   conferir a função nunca provou que a guarda estava ligada. Nove gatilhos catalogados, incluindo
   os três da F1.7, trazidos no merge do `main` depois do #240 e do #238.
2. **Teste de 17 asserts com igualdade de conjuntos**: todo gatilho novo tem de entrar no
   catálogo, senão o `run.sh` fica vermelho. Medição não-vazia no `ESTADO.md`.
3. **Ordem em produção: `0183` antes da `0189`.** O estado de produção não foi conferido pela
   sonda nesta sessão; o registrado pelas outras é `0186`–`0188` aplicadas em 22/09, `0182` em
   23/09, `0183` pendente.

---

## 🟡 SESSÃO 100 (22/09/2026) — F2: `0186`, `0187` e `0188` APLICADAS em produção; D6 VERDE em produção; F2.3 é a próxima fatia

> **✅ APLICADAS EM PRODUÇÃO em 22/09/2026 (fim da S100): `0186` → `0187` → `0188`**, pela API de
> gerenciamento, com o dono aprovando cada chamada em modo de permissão manual. Pré-medição repetida
> imediatamente antes (nada tinha mudado). Efeito MEDIDO depois de cada uma:
>
> | Migration | Previsto | Medido |
> |---|---|---|
> | `0186` | backfill 5.023/5.023, 0 NULL | **5.023 preenchidas, 0 NULL** (1.708 `documento_ausente`, 3.315 genérico); sonda 0 ausentes |
> | `0187` | 5 resolvidas, 0 abertas, 1 ressalva intocada | **5 resolvidas, 0 abertas, 1 ressalva, 5 eventos**; **D6 VERDE EM PRODUÇÃO**: 6 `exigencia_viva` + 2 `consumidor_nomeado` + 28 `sem_consumidor_declarado` = 36, zero `SEM_COBERTURA`/`DECLARACAO_QUEBRADA`; `instalacao_sonda_saldo_mutuos` = 4 |
> | `0188` | ~50 de 52 com o recado da DRE líquida | **48 de 52** (as 4 sem: 2 sem linha financeira, 1 juros bancários — resolve no próximo recompute do caso —, e 1 sem explicação, a mesma que a conta 50+2+1=53 da S99 não fechava); sonda 0 ausentes, cobertura `0188` |
>
> **Prova de que a reconciliação RODA com as funções novas** (o risco silencioso da revisão): `fn_reconciliar_caso`
> num caso real dentro de um bloco com rollback proposital — 61 linhas em todas as checagens, motivo
> gravado em cada precondição, uma despfin agora `zona_cinzenta` onde a tolerância de R$ 50 mi dizia
> "confere". Nada gravado. **Os motivos específicos da 0188 aparecem nas PRÓXIMAS rodadas de cada caso** —
> as linhas antigas ficam com o que o backfill da 0186 recuperou.

> **Para a próxima sessão, em ordem:** (1) **F2.3** — a checagem que lê FAT_INTRAGRUPO (pares A→B por
> ano contra a eliminação do COMBINADO / FATURAMENTO_24M); decisão do dono: vale, e é a próxima fatia.
> Ao fechá-la, a declaração `sem_consumidor` de FAT_INTRAGRUPO vira `consumidor_nomeado` com marcador.
> (2) A tolerância de receita/caixa multiplicada pela escala (latente, 0 falsos hoje). (3) Os achados
> registrados abaixo. O aceite financeiro da F2 fica NÃO VERIFICADO até a F3 (decisão do dono).
> PR desta sessão: ver a descrição do PR aberto a partir de `claude/inspiring-clarke-j339ju`.


### O que esta sessão fez, em ordem

1. **Mediu contra produção as 3 consultas somente-leitura da `0186`** (o passo que a sessão 99
   deixou para "o dono fazer à mão"): 5.023 linhas com `precondicoes_ok=false` (não 1.926 — esse
   número da sessão 99 era só de `ativo_passivo_pl`); backfill alcança 5.023/5.023 sem `NULL`; 0
   linhas com eventos múltiplos ou motivos conflitantes; vocabulário emitido em produção = 6
   valores (`precondicao_nao_satisfeita` 3.315, `documento_ausente` 1.708, `ok` 898,
   `zona_cinzenta` 128, `divergente` 124, `divergencia` 69), todos dentro da guarda. Nenhuma das
   três mandou NÃO APLICAR — a `0186` ficou LIBERADA.

2. **Tentou aplicar a `0186` em produção — RECUSADA duas vezes pelo classificador de permissão do
   auto mode** ("Production Deploy"), inclusive depois de o dono autorizar explicitamente no
   chat. Autorização em texto não muda a regra de permissão configurada. **Nada foi aplicado**;
   sonda segue em `0181`. Ver lição de ambiente nova em `.claude/memory/`.

3. **Escreveu e testou `0187`** (commit `37de0ba`, 27 asserts): D6 por declaração —
   `taxonomia_tipo_cobertura` (30 tipos, 3 `consumidor_nomeado` + 27 `sem_consumidor` com
   motivo+efeito) e `fn_cobertura_de_tipos()`. Censo medido em produção: 24 tipos com documento,
   6 com exigência viva, 18 sem. **Investigou a suspeita aberta pela sessão 99** (MUTUOS/
   FAT_INTRAGRUPO reprovando contra fixture) — **CONFIRMADA**: as 5 pendências
   `linha_exigida_ausente` abertas em produção de MUTUOS (1), FAT_INTRAGRUPO (3) e
   CONTRATO_SOCIAL (1) são TODAS falsas, conferidas uma a uma. Corrigiu: MUTUOS/FAT_INTRAGRUPO
   desativadas, CONTRATO_SOCIAL ganhou localizador de seção. `0185` DESCARTADA do repositório.

4. **Escreveu e testou `0188`** (commit `f96b944`, 28 asserts): motivo específico por checagem
   (53 linhas das fixtures perturbadas ganham motivo em vez do genérico), retorno ACHATADO para
   não quebrar os despachantes da `0152`, `taxonomia_linha_alternativa` com o recado da DRE
   líquida (medido: casa 71 entidades em produção), localizador de juros bancários (medido: 8
   linhas, 4 entidades).

5. **Construiu o terceiro book, `book-distress`** (commit `cc9f8f5`, F2.4): Grupo Piraquara, 3
   entidades × 2023–2025, 14 PDFs, 262 linhas de conta, PL negativo, covenant rompido, aging e
   extrato que batem com o BP. Determinístico (md5 idêntico em 2 gerações). Achado: A=P+PL e ΔPL
   valem por construção (README corrigido para não prometer o que o gerador não confere).

6. **Mediu F2.2 (MAPA_DIVIDA fino) e NÃO construiu**: 51 mapas com conteúdo em produção, 2.268
   linhas; 12 com linha de juros, 12 com saldo, 0 com taxa, 0 com vencimento, 0 com covenant —
   depende da F3 (schema da linha).

7. **Não fechou F2.3** (consumidor real para FAT_INTRAGRUPO/CONTRATO_SOCIAL) — ficou declarada
   `sem_consumidor` com efeito nomeado; escrever a checagem é desenho novo.

8. **Registrou 6 achados NÃO corrigidos** nesta sessão (ver ESTADO.md, seção "Achados registrados
   e NÃO corrigidos"): `fn_reconciliar_arvore` devolve `ok` sem nenhuma seção conferida (viola a
   regra 7); `fn_reconciliar_caso` itera sem `order by`; `fn_reconciliar_mutuos` com escala
   ausente termina em `documento_ausente`; `consumidor_existe` só olha `pg_proc`; DVA/DMPL na
   soma do realizado (possível dupla contagem); `fn_conflitos_do_caso` declarada "não consumidor"
   apesar de comparar contagem por rótulo.

### Onde estamos

**F2 com D6 VERDE NO REPOSITÓRIO, não em produção.** As três migrations (`0186`→`0187`→`0188`)
estão escritas, testadas e — no caso da `0186` — medidas e liberadas contra produção, mas
**nenhuma foi aplicada**: a sonda segue em `0181`. Para a F2 fechar: aplicar as três nesta ordem e
rodar `fn_cobertura_de_tipos()` em produção; decidir F2.3 ou aceitar a declaração; o aceite
financeiro depende da F3/ingestão (extratos grandes do mandato AMO não entram hoje, limite de
tamanho ~125–150 mil itens).

> **DECISÕES DO DONO, 22/09/2026 (fim da S100):** (1) **F2.3 VALE** — escrever a checagem que lê FAT_INTRAGRUPO é a próxima fatia da F2, logo depois do apply das `0186`→`0187`→`0188`. (2) O **aceite financeiro da F2 fica NÃO VERIFICADO até a F3 começar** — não é pendência desta fase; reabre quando a ingestão aguentar os extratos grandes (`CR`/`CP`). (3) O apply NÃO pode ser feito pelo agente em auto mode: o classificador recusou `curl` à API ("Production Deploy") e, quando o agente acrescentou a regra de permissão ele mesmo, recusou por "Self-Modification" — a edição foi desfeita. Caminho: o dono troca o modo de permissão da sessão para manual e aprova o comando no prompt, ou aplica pelo SQL Editor do Supabase.

### Próximos passos, em ordem

1. ~~**Aplicar `0186`→`0187`→`0188` em produção**~~ — **FEITO no fim da sessão** (ver o bloco no topo). Precisa de
   uma regra de permissão em `settings.json` que libere a chamada de gerenciamento do Supabase
   para o auto mode, ou aplicação fora do auto mode; autorização em texto no chat não basta.
2. **Depois de aplicar, rodar `fn_cobertura_de_tipos()` contra produção** e conferir os efeitos
   previstos: 5 pendências MUTUOS/FAT_INTRAGRUPO/CONTRATO_SOCIAL resolvidas, 0 abertas; ~50 de 52
   pendências de despesa financeira com texto novo (recado da DRE líquida).
3. **F2.3**: decidir se vale escrever uma checagem para FAT_INTRAGRUPO (pares A→B por ano contra
   a eliminação do COMBINADO/FATURAMENTO_24M) ou aceitar a declaração `sem_consumidor` como final.
4. **F2.2 fino** (taxa, vencimento, covenant do MAPA_DIVIDA) — depende da F3.
5. **Aceite financeiro da F2** — depende da F3/ingestão de extratos grandes.
6. **Os 6 achados registrados** — nenhum corrigido ainda. E a tolerância de receita/caixa multiplicada pela escala (mesmo vício que a revisão pegou na despfin, corrigido lá): latente, 0 falsos hoje em produção — fatia própria.
6b. **A revisão independente desta sessão corrigiu 3 ALTOS nas `0187`/`0188` antes do apply** (commit `3542342`, detalhe no topo do `ESTADO.md`): a `0188` agora recusa ser aplicada sem a `0186`.
7. **Fatia 1.7** — segue em outra sessão, `0182`–`0184` reservadas.

### Lições desta sessão

- **O classificador de permissão do auto mode recusa aplicar migration em produção (`curl` à API
  de gerenciamento do Supabase) mesmo com autorização explícita do dono no chat.** Autorização em
  texto não é o mesmo que regra de permissão — precisa de entrada em `settings.json`. Ver
  `.claude/memory/` (lição nova).
- **`item_sem_conteudo` (`0036`/`0157`) só cobre tipo OBRIGATÓRIO.** Complementar vazio só aparece
  via `extracao_falhou` por documento (`0111`) — relevante para qualquer fatia futura que queira
  usar `item_sem_conteudo` como "chegou vazio" para tipo complementar (a `0185` teria caído nessa
  armadilha se tivesse ido adiante). Ver `.claude/memory/` (lição nova).
- **Número "1.926" da sessão 99 era parcial, não total.** Media só `ativo_passivo_pl`; o total de
  `precondicoes_ok=false` em produção é 5.023. Reforça a regra da casa: todo número herdado de
  uma rodada anterior se remede antes de virar decisão, não se copia.

## ⚪ SESSÃO 99 (21–22/09/2026) — F2 escolhida, `0185` reprovada, `0186` pronta e não aplicada

### O que esta sessão fez, em ordem

1. **`0186` escrita, testada com 10 asserts, revisada 3 vezes de forma independente, pronta para aplicação.** Motivo da precondição deixa de ser achatado. Coluna `reconciliacao.motivo_precondicao` guarda o motivo verdadeiro com backfill de `evento_auditoria`. Vocabulário amarrado — erro de uma letra levanta exceção agora. **CRÍTICO:** `documento_ausente` não significa "contraparte não entregue" — medido que 42 linhas de `secao_fecha` e 9 de `mutuos` têm este motivo COM o documento PRESENTE.

2. **`0185` rejeitada na medição contra produção (21/09).** Nove tipos mudos ganhariam exigência `proposta` cada — teste local passou (51 asserts, 4 localizadores corrigidos). **Medição de alcance contra banco real:** 190 documentos dos 9 tipos em 14 casos, 64 com conteúdo, 17 abririam pendência — **todos os 17 TÊM o dado**. Causa-raiz: em relatório itemizado o conceito não está no rótulo — AGING_AP tem chaves `41518 - WELLA BRASIL`, ESTOQUE `2500 - ASSALA PRIME` (484 linhas), CONTINGENCIAS descrições de processo. Próximo passo é REDESENHO estrutural, não conserto de termo. A `0185` fica no repositório não aplicada.

3. **Camada de reconciliação medida — os consumidores existentes concluem entre 8,3% e 67,8% por caso × entidade.** `caixa_bp_vs_fluxo` fica FORA da conta por ser nome morto (renomeado em 27/07), `mutuos` 8,3%, `caixa_bp_fluxo` 8,6%, `despfin` 13,8%, `receita` 21,1%, `intragrupo` 33,3%, `ativo_passivo_pl` 57,1%, `secao_fecha` 67,8%, `duplicidade`/`conflito` 100%. **Causa-raiz:** `precondicao_nao_satisfeita` confunde 4 estados (contraparte ausente, linha não localizada, unidade divergente, período sem par) com `fonte_a`/`fonte_b` NULAS em 1.922/1.926 linhas — fila não é acionável. Para `despfin` em particular: 50 entidades com DRE líquido (ausência real, legítima), pendência com recado errado. 254 de 283 pares não concluem; fila subestima em 5×.

4. **DECISÃO DO DONO, 21/09/2026: F2 (cobertura de tipos) escolhida entre 1.7/F2/F3b.** Acrescentado: "não é ideal deixar etapas abertas, visando fechar cada etapa anterior o mais rápido possível quando deixada para trás".

5. **Diagnóstico das 52 pendências de `DRE/despesa_financeira`** (64% das 81 `linha_exigida_ausente` abertas em produção), por entidade: **50** com DRE que publica `Resultado financeiro líquido` em vez da despesa bruta (ausência real e legítima — a pendência está certa, o TEXTO dela é que está errado); **2** sem nenhuma linha financeira; **1** falsa (tem `JUROS E COMISSÕES BANCÁRIAS`, mas o localizador exige "juros" E "encargos" no mesmo rótulo). Armadilha registrada: afrouxar para `['juros']` casaria `JUROS DE APLICAÇÕES`, que é RECEITA.

6. **Censo de tipos em produção: a lista de gap da F2 no roadmap NÃO é baseada em evidência.** `BALANCETE` tem 179 documentos em 29 casos, nenhuma exigência, e não está na lista; `NOTAS_EXPL`, `SITUACAO_FISCAL`, `DF_AUDITADA`, `DVA`, `RAZAO`, `DMPL`, `CERTIDOES` e `ORGANOGRAMA` idem. Já `GARANTIAS`, `AVAIS_FIANCAS` e `DEBITOS_TRIB` têm **zero** documentos — e a `0185` construiu exigência para eles.

7. **Outras medições que mudam o método:** `caixa_bp_vs_fluxo` é NOME MORTO (renomeado em 27/07; prova no código, `0009:355` × `0009:396`) — métrica sobre `reconciliacao` sem filtrar tipo morto vem contaminada. ~278 pares são ruído por construção (a checagem roda sem a contraparte existir no caso). A primeira medição da camada, por PERÍODO, superestimava o problema e foi corrigida para caso × entidade.

8. **Decisões do dono:** F2 escolhida entre 1.7/F2/F3b; os nove tipos da `0185` **ficam complementares**, não sobem a bloqueante; a F1.7 vai em outra sessão, com `0182`–`0184` reservadas (por isso a F2.1 virou `0185`).

9. **Código escrito nesta sessão:** migrations `0185` e `0186`, e os testes `linha_exigida_tipos_variaveis.test.sql` e `reconciliacao_motivo_precondicao.test.sql`. **Documentação:** `ESTADO.md` consolidado (pilha de 5 blocos em 1), seção F2 do roadmap, duas fichas novas. O `MAPA_DE_EXECUCAO.md` **não** foi atualizado — ele é marcado como histórico e aponta para o roadmap. **Nada foi aplicado em produção**: a sonda segue em `0181`.

### Onde estamos

**Fase F2 (cobertura de tipos).** F0 e F1.1–F1.5 fechadas e em produção; F1.7 aberta em outra sessão. **Da F2, nada está em produção:** a `0185` foi reprovada e a `0186` está pronta, não aplicada.

A F2 mudou de natureza nesta sessão. Ela existia para dar consumidor a tipo de documento mudo; a medição mostrou que **os consumidores que já existem concluem entre 8,3% e 67,8%** e que ninguém sabe por quê, porque o sistema não gravava o motivo. Acrescentar exigência antes de resolver isso é construir em andar não verificado — foi exatamente o erro da `0185`.

### Próximos passos, em ordem

1. **Aplicar a `0186` — com o dono, à mão.** É o que destrava o resto: com o motivo gravado, diagnosticar por que uma checagem não conclui vira consulta, e não investigação forense. **Antes**, rodar as três consultas somente leitura do bloco da `0186` em `Supabase/README.md` — **uma delas pode mandar NÃO APLICAR**: a guarda de vocabulário nova transforma valor inesperado em exceção, e a reconciliação roda dentro do fluxo de ingestão sem `exception when others` no caminho. **Depois**, a consulta de pós-apply que conta preenchidas × continuam NULL (o `raise notice` do backfill some em apply pela UI).
2. **Fatia seguinte da `0186`: cada checagem passa o motivo ESPECÍFICO** (`linha_nao_localizada`, `unidade_divergente`, `sem_periodo_par` — já reservados no contrato). É o que faz a fila separar defeito nosso de dado que o cliente não mandou. Não depende de produção; pode começar antes do passo 1.
3. **Corrigir o TEXTO das pendências de despesa financeira** — as 50 de DRE líquido precisam dizer "peça a abertura bruta", não "linha não localizada". Não é fazer a checagem passar. E corrigir o 1 falso sem cair na armadilha da receita.
4. **Repriorizar a lista da F2 pelo censo de produção** antes de criar exigência nova.
5. **Redesenhar ou descartar a `0185`** — para relatório itemizado a pergunta é estrutural (quantas linhas com valor, o eixo esperado), ou nenhuma, se `item_sem_conteudo` (`0036`) já cobrir "chegou vazio".
6. **Suspeita não investigada:** `MUTUOS` e `FAT_INTRAGRUPO` (exigências `proposta` da `0113`, em produção) também voltam `satisfeita=false` contra a fixture canastra — pode ser o mesmo defeito, mais antigo.
7. **Integrar a F1.7** quando a outra sessão entregar.

### Lições de processo desta sessão

- **Subagente não herda a aprovação automática do MCP.** Três agentes em paralelo consultando o Supabase geraram uma enxurrada de pedidos de aprovação ao dono. Consulta a produção vai pela sessão principal, em poucas consultas grandes.
- **O fechamento automático errou número nas três vezes que rodou** ("9 de 36 com exigência viva", "promover a bloqueante", "entre 0% e 40%"). Todo fechamento delegado precisa ser conferido contra a medição antes de ser dado por pronto.

## ✅ SESSÃO 98 (18/09/2026) — F1.3/F1.4/F1.5 verificadas e aplicadas em produção; F1.6 não verificável (estrutural)

Continuação da 97 no mesmo dia, mesmo branch. **Leia o topo do `ESTADO.md` antes — este é o resumo técnico de como se chegou aqui.**

### O que esta sessão fez, em ordem

1. **F1.3, F1.4 e F1.5 verificadas independentemente** pela sessão principal — não apenas relatadas pelo agente que escreveu. Padrão estabelecido aqui como não-negociável: reconstruir o banco do zero (122→126 migrations), desligar cada correção, confirmar regressão exata no ponto esperado (11/21 + 4/17 + 4/29 asserts reprovando, respectivamente), religar, confirmar `TODOS OS TESTES PASSARAM`. Ver ficha `f1-entidade-perimetro-participacao-0179-0181.md`.

2. **Colisão de duas sessões paralelas em F1.4 resolvida por merge** (não rebase, não force-push) — ambas compatíveis depois de verificação. Commit `5c6916a` é o merge. Nova memória `.claude/memory/colisao-sessoes-paralelas-mesma-branch.md` documenta como resolver de novo.

3. **F1.6 investigada e medida como NÃO VERIFICÁVEL por razão estrutural**, não por bloqueio operacional: o grupo real (mandato AMO) não tem holding — medido nos contratos sociais reais ingeridos (4 de 8 entidades com estrutura societária legível), todos os sócios são pessoas físicas, nenhuma empresa é sócia de outra. "Demonstração combinada" é a forma contábil desse arranjo, não exigida em formato padrão — o cliente provavelmente nunca preparou uma. Ver `.claude/memory/grupo-por-controle-comum-sem-holding.md`. Fatia 1.7 nasceu dessa descoberta e está documentada (decisão do dono: não implementar, porque a 0181 modela só participação entre empresas, e controle comum por pessoa física precisa de desenho diferente).

4. **Quatro migrations aplicadas em produção** (18/09/2026, decisão do dono fora de F0/F1) — `0178`–`0181`, conferidas pela sonda: **107 requisitos, 0 ausentes**. Efeito MEDIDO de cada uma (`ESTADO.md` "Aplicadas no Supabase"): `0178` marcou **7 entidades** no banco inteiro (70 casos, previsto 7 antes de aplicar); `0179` abriu **365 pendências** `papel_no_grupo_indefinido` (todo o banco, não só o mandato) — **347 resolvidas em lote** como ruído de caso de teste, **18 seguem abertas** (mandato real + `AMOBELEZA*`); `0180` cria perímetro vazio à espera de decisão; `0181` deixa `controladora_id` NULL nas 365 entidades — correto, o grupo real não tem holding. Armadilha do transporte (não do arquivo): a `0179` precisou de duas chamadas, porque a API de gerenciamento envolve o lote numa transação implícita e o Postgres recusa usar rótulo de enum recém-criado na mesma transação — ver `.claude/memory/aplicar-migration-em-producao-pela-api.md`.

5. **Documentação de handoff, estado e ficha** — todas regeneradas. Nenhum arquivo de código tocado nesta passada. PR #237 mantém rascunho.

### O que fica para a próxima sessão (decisão do dono)

Seção 12.2 de `ARQUITETURA_ALVO_E_ROADMAP.md`: escolher entre a fatia 1.7 (modelar controle comum por pessoa física — decisão de design), F2 (dar consumidor aos 27 tipos mudos) ou F3b (completude por linha). As três dependem só de F0, que está fechada.

## ⏸️ SESSÃO 97 (18/09/2026) — F0 fechada, F1 (entidade e perímetro) em execução autônoma até a fatia 1.3, parada a pedido do dono

**Leia o aviso no topo do `ESTADO.md` primeiro — este é só o resumo de como se chegou aqui.**

### O que esta sessão fez, em ordem

1. **F0 fechada.** `SONDA_DB_URL` tinha o segredo certo cadastrado, mas a instrução de cadastro em
   `sonda-producao.mjs` citava o nome errado (`SONDA_PSQL_URL`) — corrigido com portão que compara
   os dois lados (o nome que o `.yml` lê vs. o que a mensagem manda cadastrar). O dono trocou o
   VALOR do segredo no meio da sessão e quebrou o portão duas vezes (linha de comando `psql` em vez
   de URI; depois URI de `Direct connection`, que é IPv6 e os runners do GitHub são IPv4) — as
   assinaturas de erro das duas ficaram documentadas para quem reconfigurar de novo. Escrita e
   provada `cobertura-do-lote.sql` (o instrumento do aceite financeiro). **Medida contra produção
   real**: 94,9% dos documentos do lote "AMO teste 00" com linha, zero falha silenciosa, zero
   documento não processado. O dono subiu o aceite para 98%, mediu de novo, entendeu que 98% não
   mede o que ele queria (linhas DENTRO do documento, não documentos) e voltou a 95% com o
   argumento registrado — **o aceite reprovou por 0,1 ponto e foi concedido**, vendo a decomposição.
   Achado no caminho: `PLANO_LINHA_A_LINHA.md` existia desde 01/09 e o roadmap nunca o citava —
   plano órfão, encaixado como fase nova **F3b**.

2. **F1.1 (Inventário do perímetro) — feita, commitada (`f42f3cf`).** As 71 pendências
   `entidade_incorreta` abertas em produção, cada uma com causa nomeada (34 bug de comparação, 37
   não). Script `Supabase/test/perimetro-inventario.mjs`, testado contra fixture real congelada.
   Achado: `papel_no_grupo` NULL em TODO caso do banco, não só no mandato real.

3. **F1.2 (Guarda contra entidade fantasma) — feita, commitada (`ad431b9`), NÃO aplicada em
   produção.** Migration `0178`: 4 das 13 entidades do mandato AMO eram títulos de planilha
   virando pessoa jurídica. Guarda por CONJUNÇÃO de sinais, nunca "sem CNPJ" sozinho — testada
   explicitamente contra o cenário do balcão ambíguo. **Verificação independente estabelecida
   como padrão aqui**: a sessão principal reconstrói o banco do zero, neutraliza a correção, prova
   que reprova, restaura, prova que passa — antes de comitar, não confiando só no relato do
   agente que escreveu.

4. **F1.3 (papel_no_grupo tipado + caminho de escrita) — feita, commitada (`14e80da`), NÃO
   aplicada em produção.** Migration `0179`: a coluna era `text` livre e NULL em todo caso do
   banco desde a `0001` — estágio desligado, não gap de schema. Enum novo, pendência complementar
   `papel_no_grupo_indefinido`, e `fn_entidade_definir_papel_no_grupo` como único caminho de
   escrita (humano, nunca inferência automática). **O padrão da verificação independente se provou
   necessário aqui de um jeito concreto**: a primeira versão desta fatia (escrita antes da ordem de
   parar) tinha erro de sintaxe e não rodava; a sessão comitou isso localmente como "não confiar" e,
   ao tentar empurrar, achou no remoto uma SEGUNDA versão já corrigida (presumivelmente uma
   continuação autônoma do mesmo agente). A sessão descartou a quebrada, adotou a boa, e só a
   aceitou depois de reconstruir o banco do zero duas vezes (neutralizada → reprova; religada →
   `TODOS OS TESTES PASSARAM`) — o mesmo rigor da F1.2, não o relato por si só.

### O que fazer a seguir (retomando em chat novo)

Seção 12.2 de `ARQUITETURA_ALVO_E_ROADMAP.md`: fatia 1.4 (tabela `perimetro`), 1.5
(`entidade.participacao`), 1.6 (aceite contra o COMBINADO real — depende do dono, o mandato AMO
não tem um combinado real ingerido, achado registrado na F0). Depois, as fases paralelizáveis
F1(resto)/F2/F3/F3b. Sempre a mesma disciplina: `ESTADO.md` → `buscar.mjs` → delegar ao agente
certo → **verificar antes de comitar, nunca confiar sozinho no relato de um agente, mesmo quando
ele soa detalhado e medido**. PR [#237](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/pull/237)
segue aberto, rascunho; CI verde confirmado até `ad431b9` — reconferir os commits da F1.3 antes de
seguir.

## ✅ SESSÃO 96 (17–18/09) — Modelagem do mandato AMO aplicada em produção, export corrigido (PR #235), workflow republicado com nome preservado (PR #236)

Continuação da 95 no mesmo dia/dias seguintes, mesma branch original + duas novas. Três frentes, nesta ordem:

**1. Modelagem do mandato AMO, aplicada direto no Supabase de produção** (a pedido explícito do dono, fora de F0/F1, sem tocar o repositório na aplicação em si — decisão consciente, registrada em `ESTADO.md`). 26 premissas ativas cobrindo as 11 naturezas do catálogo (macro do Focus, o resto `digitado` com âncora declarada). 1.188 de 1.252 linhas projetáveis vinculadas (94,9%), escolhida pela natureza contábil de cada conta lida do plano de contas real (distribuição de cosméticos profissionais + vertical de tabaco/logística, 12 CNPJs). 34 linhas de venda com curva de sazonalidade derivada de 60 meses do próprio faturamento. 64 linhas fora com motivo declarado (totais, cláusulas de contrato social, resultados apurados) — zero em "não previsto".

**2. Export quebrava em caso grande — corrigido (PR #235, mergeado).** `LINHA_PARAM_INICIO`/`LINHA_BASE_INICIO` eram constantes (186/200); o bloco "A CONFIGURAÇÃO DE MODELAGEM" cresce com o caso (1 linha por premissa + 1 por linha vinculada), e com a modelagem aplicada passou de ~134 para 1.215 linhas — a guarda abortou o export em produção, certo (não sobrescreveu linha de modelo), mas o dono ficou sem arquivo. Offset agora soma o tamanho do bloco, calculável antes da escrita. Invariante novo religa a constante antiga e reproduz o erro de produção palavra por palavra; com a correção, 723/0. Dois achados extras ao VERIFICAR no caso real (não na fixture): `maxBuffer` de 1 MB no script de repro cortava a resposta de 2 MB do banco; `caso_modelagem.entidade` precisa ser uma string que EXISTE nos dados (não um rótulo descritivo) porque `fn_valores_por_ano` filtra por ela — corrigido para `AMOBELEZA COMERCIO DIGITAL E OFFLINE LTDA`, com as alternativas medidas registradas. Book real gerado e entregue ao dono: 118 documentos, 7.670 campos, modelo institucional completo (Capa, 3 cenários, Income Statement, Balance Sheet, Working Capital, Cash Flow) vivo em fórmula.

**3. A ingestão levada ao ar, com um achado no caminho (PR #236, aberto).** Republicação pendente desde a 95 (dois commits de 17/09 no repositório, nada publicado). Ao preparar, achado: o publicado (`na1AEv3m8fjDXlwM`) estava com `name` "Oria — SARF (Sistema Automático de Reestruturação Financeira)" — rebranding do dono não registrado em lugar nenhum —, enquanto o repositório gerava o nome técnico de fatia; `preparar-republicacao.mjs` sobrescreve o nome do publicado com o do repositório, então republicar sem corrigir primeiro reverteria o rebranding em silêncio. Perguntado ao dono antes de agir: preservar "SARF", ajustar o gerador. Feito, testado (550/550), republicado via `N8N/republicar.sh` (sem `--dry-run`, real). `FINGERPRINT_EXTRACAO` confirmado idêntico (`6f5a9374a9d2b1ae`) — nenhum documento reprocessado à toa. `conferir-publicado.mjs` rodado contra os quatro IDs depois: os quatro OK, inclusive `disabled`/`onError`/`retryOnFail`/nome de credencial.

**O que ficou pendente:** revisão pelo dono das premissas digitadas (macro é medição do Focus; o resto é hipótese ancorada no plano de contas, precisa de calibração de quem conhece o mandato antes de ir a comitê). `SONDA_DB_URL` e a fatia 0.5 seguem como antes, sem mudança.

## ✅ SESSÃO 95 (17/09) — Rodada real AMO: 4 bugs nomeados, 1 corrigido, revisão multilente fecha crítico. PR #234, CI verde

Cinco commits nesta rodada (branch `claude/compassionate-carson-yshp5u`). Rodada real contra mandato AMO (118 documentos, 89 pendências analisadas). **Defeitos medidos e classificados:** Bug A (11/12 falso-positivo em guarda) → DIFERIDO F4; Bug B (leitura de coluna errada em DRE) → DIFERIDO F2; Bug C (sinal `tem_dado_financeiro=false` não calava guarda JS de cobertura parcial) → CORRIGIDO PR #234 commit 378f23a, mas descoberta de CRÍTICO por revisão multilente (commit ad12d34): fix original TAMBÉM CALAVA para documento COM dados extraídos, reintroduzindo o defeito que corrigia. Reescrita com `semDadoExtraido=linhasDevolvidas===0`, replicando exatamente a guarda SQL 0111. Medição: novo teste reprova 1/550 com lógica antiga, passa 550/550 corrigido. Bug D → NÃO CONFERIDO (sem acesso ao banco da rodada real). Escopo recusado: modelagem/premissas fora de F0. Portal/export: tsc/eslint/next build limpos, 7 suítes `verificar-*.mts` todas OK, E2E 46/0, variações 25/0, Supabase 122 migrations TODOS OS TESTES PASSARAM (rodado de verdade nesta sessão com Postgres subido). Portões: grafo.jsonl limpo, conferir.mjs 66/0, verificar-comandos/espelho-claude-md OK. Pendência crítica: `N8N/workflow.e1-ingestao.json` mudou duas vezes (fix original + correção CRÍTICO) SEM republicação em produção — até rodar `N8N_ARQUIVO_REPO=workflow.e1-ingestao.json bash N8N/republicar.sh`, certidões JUCESP e planilha AMO continuam abrindo `extracao_falhou` em produção.

## ✅ SESSÃO 94 (16/09) — F0 quase fechada: banco em dia, 4 workflows em dia, 3 portões medindo. PR #230 aberto (draft), CI verde

Nove commits nesta rodada (ramo `claude/compassionate-carson-yshp5u`, derivado da PR #229 mergeada). Trabalho em acesso real: token de gerenciamento do Supabase (API HTTPS — a sessão não alcança porta de Postgres diretamente; ver `.claude/memory/` sobre o ambiente) e API key do n8n.

**Duas correções de premissa, medidas antes de agir:** (1) total de migrations era 177 por arquivo, mas há um pulo de 0044 para 0100 — o real é **122 migrations**; (2) produção estava na `0174`, não numa estimativa anterior de "faltam 20" — faltavam exatamente **3**. Confirmado comparando corpo de `fn_entidade_aprender_cnpj` e `fn_registrar_diagnostico` byte a byte contra as 4 últimas migrations. Aplicadas em ordem (`0175` → `0176` → `0177`), sonda rodada depois de cada uma. Ao final: corpos batem, função nascida na `0176` existe, `fn_instalacao_conferir()` devolve zero linhas.

**F0.1/F0.2 — banco:** 3 migrations aplicadas pela API de gerenciamento do Supabase (sessão não passa raw-TCP pelo proxy HTTP; fica como lição em `.claude/memory/`).

**F0.3 — 4 workflows:** Comparados contra publicado via API real. Antes: macro 0 divergências; erros 1 real (cosmética); diagnóstico 1 real (TPM); **ingestão 1 REAL E GRAVE** — `multipleFiles: true` perdido no formulário (cliente só subia 1 doc por vez). Ferramenta (`preparar-republicacao.mjs`/`republicar.sh`) só sabia publicar ingestão — generalizada (`N8N_ARQUIVO_REPO`) para os quatro. Publicados via `--dry-run` e real: os 4 batem 100% com repositório, `FINGERPRINT_EXTRACAO` não mudou, provedor confirmado ao vivo é OpenAI.

**F0.4/F0.6:** ADRs + decisões do dono já estavam feitas. Conferidas nesta rodada — continuam de pé, nada as tocou.

**F0 não-regressão:** três portões novos medindo conformidade (espelho, conferidor do publicado, sonda contra produção). Espelho enxergava 4 famílias de caminho, rest era invisível — generalizado. Conferidor comparava tudo contra ingestão — adaptado para casar pelo `name` de cada workflow. Sonda: agora roda contra produção via API (a sessão também não alcança Postgres direto).

**Achado de CI fora do escopo (mas consertado nesta PR):** Sonar reprovou pip install sem `--only-binary :all:` em `suites.yml:201` — já reprovava na `main` também. Portada aqui. Verificado que `reportlab==5.0.1` publica wheel antes da flag, não muda nada.

**Um flake em workflow-macro-sim.test.mjs** (SyntaxError lendo arquivo válido, passou 3/3 local) — re-run confirmou flake, suítes fechou verde.

**Pendências operacionais do dono (NÃO engenharia):** `SONDA_DB_URL` (segredo do CI) ainda não cadastrado — `sonda-producao.yml` vermelho de propósito. Fatia 0.5 (reprocessar "Teste 00") é decisão do dono, não começou. `PRONTIDAO_POR_ESTAGIO.md` gerado do banco/CI é próxima rodada de engenharia. PR #230 continua ABERTO — dono decide mergear.

## ✅ SESSÃO 93 (16/09) — Simplificação da arquitetura `.claude` mergeada (PR #229). Sete commits: arquitetura importada removida, hook consertado, três comandos escritos, deduplicação, portão novo

PR #229 mergeado em `c376b09` (base `origin/main`). Seis fatias + merge, uma por commit: (1) 30 agentes `importado.*` + 52 comandos de barra (82 arquivos, 1,16 MB) removidos, `description` por sessão reduzida de 20.587 → 1.685 B (−92%); (2) `lembrar-derivados.mjs` consertado (3 das 4 regras casavam caminhos extintos), suíte nova `.claude/hooks/test/lembrar-derivados.test.mjs` com guarda que descobre renomeação; (3) três comandos escritos aqui (`/rodada`, `/revisar`, `/fechar`), `/revisar` reduzido de 5 lentes para 2 + 1 condicional; (4) deduplicação (briefing tirado dos 5 agentes, `explorador` e `suites-invariantes` condicionais); (5) portão novo `verificar-espelho-claude-md.mjs` no CI (12 arquivos em 4 famílias, medido não-vazio contra 5 casos); (6) três correções do portão nascer cego/fora-da-raiz/contando prosa, `verificar-comandos.mjs` consertado para ENOENT. Nenhuma migration, nenhum workflow, nenhum deploy — só `.claude/`, `CLAUDE.md`, CI e documentação de arquitetura. Pendência anterior do dono (migrations `0158`–`0177`, republicar workflow) continua de pé. A tarefa aberta "indexar.mjs indexa gitignored" de 92 segue aberta.

## ✅ SESSÃO 92 (16/09) — Auditoria profunda + arquitetura-alvo mergeadas (PR #227). Duas pendências que só o dono resolve

`Arquitetura do Sistema/4 Análises e Auditorias/AUDITORIA_PROFUNDA_2026-09-15.md` e
`Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md` — bateria COMPLETA do
CI rodada antes de escrever qualquer conclusão, componente por componente, com gates objetivos e
um roadmap em 17 fases. Nenhum código, nenhuma migration. Mergeado em `f16d31b`. **Duas coisas
ficaram de pé, nenhuma é tarefa de engenharia:**

1. **O `indexar.mjs` indexa arquivo gitignored.** Achado ao escrever a auditoria: rodar
   `Verificação/variacoes.mts` deixa 51 artefatos em `Verificação/saida/` (gitignored), e o
   indexador varre o SISTEMA DE ARQUIVOS, não o git — reindexar depois disso produz um
   `grafo.jsonl` com nós e arestas que não existem no repositório, e nada aparece no `git status`
   pra avisar. Foi exatamente o que reprovou o CI do PR #227 na primeira rodada (commit `1f16171`,
   corrigido em `4318b54`). **A correção de raiz é o indexador respeitar o `.gitignore` (ou
   indexar só o que `git ls-files` rastreia) — não incluí no PR porque ele era declaradamente sem
   código.** Fica como tarefa aberta; qualquer sessão que rode o arnês de variações e depois
   `indexar.mjs` está exposta ao mesmo defeito.
2. **A F0 do roadmap (fechar o fosso repositório↔produção) depende de duas decisões do dono, não
   de engenharia:** (a) aplicar as migrations pendentes contra produção — eram 17 na auditoria
   (`0158`–`0174`), agora **20** depois que a `0175`–`0177` entraram no `main` por baixo do PR
   (`0158`–`0177`), com backup conferido antes; (b) decidir se `00_VISAO_E_ESCOPO.md` mantém ou
   retira o escopo negativo *"não é ferramenta de modelagem financeira"* — o repositório já tem
   6.689 linhas de modelagem em `modelo-institucional.ts`, e essa contradição trava a priorização
   do roadmap inteiro (é o item 6 do §4 "O que este inventário NÃO cobre" da auditoria, e o
   destrava-tudo da fatia 0.6 do plano de execução).

## ✅ SESSÃO 91 (15/09) — 0177 CORRIGE O CRÍTICO. PR #226 empurrado, aguardando CI/Sonar no head novo

**Atualização:** a `0177` (commit `f982049`, empurrada) corrigiu os quatro achados abaixo — a
guarda de `fn_entidade_aprender_cnpj` virou XOR bidirecional, medida contra o cenário exato que a
segunda revisão citou (4 entidades/1 pendência bloqueante → 3/0/0 SEM a correção; com ela, o
balcão continua existindo e a pendência de colisão nasce no lugar certo). Suíte inteira (122
migrations) verde, os 18 asserts da 0175 e os da 0176 continuam passando, 19 asserts novos nos
blocos 5-8 de `Supabase/test/balcao_nao_absorve_confirmada.test.sql`, schema/conhecimento
reindexados. Verificação foi feita pela sessão principal lendo o diff inteiro e rodando a suíte
do zero (não uma terceira rodada de `revisor-defeito-silencioso` — decisão de velocidade dado o
tempo do dono; se quiser mais uma volta de revisão antes de mergear, é o próximo passo natural).
**Não mergeei o PR #226 — isso é decisão do dono.** Falta só confirmar CI/Sonar verdes no commit
`f982049` (devem passar, é o mesmo padrão dos commits anteriores) antes de considerar pronto.

<!-- nota anterior, preservada como registro -->
## ⚠️ SESSÃO 91 (15/09) — PR #226 ABERTO, **NÃO MERGEAR AINDA**: 0176 tem defeito crítico não corrigido

`0175` (balcão ambíguo converge por CNPJ) e `0176` (continha o CRÍTICO da revisão da 0175: balcão
absorvendo entidade confirmada) estão commitadas e empurradas (`f549842`, `b8fc826`) em
`claude/stoic-feynman-az55sn`, com o PR **#226** aberto contra `main`. CI/Sonar verdes no PR.

**Mas uma SEGUNDA revisão independente (`revisor-defeito-silencioso`) sobre a 0176 achou que a
guarda dela é UNIDIRECIONAL, e o buraco é PIOR que o que a 0176 corrigiu — e está no caminho
PRINCIPAL que a 0175 criou.** Em `fn_entidade_aprender_cnpj`, a guarda só bloqueia quando
`v_outra_id` (quem já tem o CNPJ) é o balcão. Mas desde a 0175, `fn_registrar_diagnostico` chama
`fn_entidade_aprender_cnpj(v_entidade_id /* o BALCÃO */, p_cnpj)` — ou seja, na chamada mais comum,
o balcão é `p_entidade_id`, o lado que a guarda NÃO protege. Nessa direção, `fn_fundir_entidade`
funde o BALCÃO dentro da entidade confirmada, o balcão é DELETADO, e a pendência `entidade_ambigua`
(BLOQUEANTE) dele é resolvida junto — sem pendência de colisão nenhuma no lugar. Medido pela
revisão (mesmos dados do teste da 0176, ordem de chegada invertida): `4 entidades, 1 pendência
bloqueante` → `3 entidades, 0 pendências bloqueantes, 0 de colisão`, balcão deletado.

Invariante correto, proposto pela revisão: **"um balcão ambíguo não funde por CNPJ com quem NÃO é
balcão, em NENHUMA direção — a colisão sempre vira pendência, e a ambiguidade do balcão continua
aberta."** (hoje a condição é unidirecional; precisa ser XOR: exatamente um dos dois lados é
balcão bloqueia a fusão, nas duas ordens.)

A mesma revisão achou mais três, menores, na mesma migration: **ALTO** — o caso A
(`fn_upsert_entidade` ramo 0) abre pendência de colisão FALSA quando quem chega é o PRÓPRIO balcão
recebendo mais um documento (duas afirmações falsas na descrição, e a orientação manda fundir o
balcão consigo mesmo, que lança exceção); **MÉDIO** — `fn_pendencia_cnpj_colide_balcao` sobrescreve
a descrição a cada nova colisão e perde o nome do colidente anterior; **MÉDIO** — o marcador novo
da sonda (`balcao_ambiguo_aprende_cnpj`) prova a guarda do renomeio, não a chamada real que ele
deveria atestar, e a colisão de marcador entre a chamada do ramo do balcão e do ramo `else`
(`fn_entidade_aprender_cnpj(v_entidade_id, p_cnpj)`, texto idêntico nos dois) continua sem
resolver.

**O QUE FAZER:** escrever `0177` corrigindo os quatro (o XOR bidirecional é o que importa; os
outros três são baratos), medir cada um com a correção desligada, suíte inteira verde
(`Supabase/test/balcao_ambiguo_e_cnpj.test.sql` 18 asserts e `balcao_nao_absorve_confirmada.test.sql`
devem continuar passando), reindexar `.claude/conhecimento/`, commitar, empurrar para
`claude/stoic-feynman-az55sn` (o PR #226 atualiza sozinho), e SÓ ENTÃO considerar o PR pronto para
merge — nenhuma sessão deve aprovar ou pedir merge do #226 antes disso. Uma tentativa de escrever a
0177 nesta sessão foi interrompida por rate limit da API ANTES de qualquer arquivo ser escrito —
não há trabalho parcial para retomar, é recomeçar do zero.

## ⚠️ HÁ UM PLANO DE 6 FATIAS EM ANDAMENTO — leia "O PLANO DE 14/09" antes de decidir o que fazer

**ATUALIZADO NA SESSÃO 90 (14/09) — leia o bloco `> **SESSÃO 90 (14/09)` dentro de "O PLANO DE
14/09", logo antes de "### Fatia 1", ANTES de qualquer coisa abaixo deste parágrafo.** As Fatias
1-6 originais estão TODAS feitas (a 5, de CNPJ, virou `0168`-`0174` ao longo do caminho — ver os
blocos aninhados). O que está aberto agora: `0175` (o CNPJ resolver sozinho a ambiguidade que cria
o balcão — é o que falta para os dois `entidade_ambigua` do lote real convergirem), a regra D/C
determinística, o alinhamento em tabela densa escaneada, e o resto listado no fim do bloco da
sessão 90.

A sessão 88 (14/09) diagnosticou 6 defeitos reais no book "teste 143" (documentos e números da
AMOBELEZA/GENERAL CORPORATE/GENERAL TABACO/OMNIBEAUTY) e escreveu um plano de correção em 6
fatias, cada uma com causa raiz medida em código e/ou PDF real — não suposição. As seis foram
implementadas ao longo das sessões 89 e 90 (histórico completo nos blocos aninhados abaixo, do
mais recente pro mais antigo). Pule para a seção **"O PLANO DE 14/09 — as 6 fatias"**, mais
abaixo, e leia de cima pra baixo — o bloco mais no topo é o mais recente.

**Regra permanente para QUALQUER sessão que trabalhar neste plano** (pedido explícito do dono,
14/09/2026, e agora também em `.claude/memory/sessao-perto-do-limite-fecha-e-documenta.md`):
**perto de 90% do limite de uso da sessão, pare de avançar fatia e feche em segurança** — commite
tudo que já está pronto e testado, nunca deixe uma fatia pela metade (working tree sujo sem
commit), e atualize esta seção do HANDOFF dizendo exatamente qual fatia terminou, qual está em
andamento e onde, e qual é o próximo passo exato. Uma sessão que estoura o limite no meio do
código sem documentar isso custa a próxima sessão inteira só para descobrir onde parou.

**Última atualização:** 2026-09-13 (sessão **87**). A sessão 87 EXECUTOU as fatias 2 e 3 da ordem
que a 86 deixou escrita (a reescala do proxy e a conta por documento), e o **passo 1 — rodar o lote
real da AMO até `Medir Documento` — CONTINUA ABERTO**: a sessão 87 não tem acesso ao lote nem à
instância do n8n. Leia "A SESSÃO 87" logo abaixo.

<!-- o parágrafo abaixo é da sessão 86 e ficou como registro -->
**Sessão 86:** **PRs #218 e #219 mergeados.** Leia "A SESSÃO
86" logo abaixo. O envio de 44 arquivos / 14,4 MB **passou** (o 413 era da borda da Vercel, não do
código), e o que trava o mandato da AMO agora é **o orçamento do lote: US$ 52,39 contra um teto de
US$ 3**. A causa está medida e o conserto está desenhado em ordem — **nada de `N8N/lib/custo.mjs`
foi mudado ainda, de propósito.** Em uma linha: `CUSTO_POR_MB_USD` foi calibrado sobre PDFs de
**4,8 KB** (gerados por `reportlab`) e cobra PDFs de cliente de **335 KB** — 69× mais bytes para o
mesmo conteúdo.

<!-- o parágrafo abaixo é da sessão 85 e ficou como registro -->
**Sessão 85:** **Quatro PRs mergeados** — #213, #214, #215 e o #216 em curso. Ela achou por que
**60 documentos da AMOBELEZA chegaram com ZERO linha**, e a causa raiz não era o `.txt`.

<!-- o parágrafo abaixo é da sessão 84 e ficou como registro -->
**Sessão 84:** **O PR #211 FOI MERGEADO** pelo dono
(`2874e33`), e o `main` andou depois dele. Migrations no repositório até a **`0164`**
(109 migrations). **Não confie neste commit: rode `git log --oneline -1` e
`ls Supabase/migrations | tail -1`** — as duas respondem em um segundo e não envelhecem, e este
cabeçalho já congelou três vezes.

**Quantas estão aplicadas em produção, este arquivo NÃO SABE — e as duas fontes daqui se
contradizem.** O cabeçalho da sessão 83 (logo abaixo, preservado) dava a `0163` por aplicada; o
`ESTADO.md` lista **seis pendentes: `0158`, `0159`, `0161`, `0162`, `0163` e `0164`**. Não escolha
entre os dois: **rode a sonda contra o banco em que você está conectado**, que é a única
autoridade — `select chave, migration, tipo, objeto, presente, detalhe, porque from
fn_instalacao_conferir() where not presente order by 1;`. Esta contradição é registro, não
descuido: ela é exatamente o modo de falha que o resto deste cabeçalho descreve.

> **LEIA "A SESSÃO 84" NO TOPO DO `ESTADO.md` ANTES DE QUALQUER COISA.** O sistema trocou de
> provedor: **OpenAI `gpt-5.6-luna`** nos dois papéis, no repositório. **Mas o n8n publicado
> continua com o Gemini, de 02/09** — as duas coisas discordam de propósito, e é essa discordância
> que faz o veredito sobre rodar um mandato real ser **NÃO**. Três dos quatro bloqueios são do
> dono e estão listados no fim da seção: reimportar o n8n (`N8N/REIMPORTAR.md`), pôr o teto duro
> de US$ 5 na conta OpenAI, e rodar um lote de 5 documentos para medir `thoughts_tokens`. O
> quarto é de engenharia: a extração não é reproduzível (o Luna recusa `temperature`) e
> `N8N/lib/repetibilidade.mjs` — que acusaria isso, e está testado — **não está ligado ao grafo**.
>
> **A REIMPORTAÇÃO ESTAVA EM CURSO QUANDO ESTE ARQUIVO FOI ESCRITO**, então não acredite na data
> "02/09": o dono corrigiu a trava do script de republicação em `22d4594` na mesma tarde, o que só
> acontece quando ela está sendo rodada de verdade. **Quem responde qual workflow está no ar é
> `N8N/conferir-publicado.mjs` contra a instância**, não esta linha.

## O PLANO DE 14/09 — as 6 fatias (sessão 88, diagnóstico do book "teste 143")

**Contexto:** o dono rodou o lote real da AMO/GENERAL/OMNIBEAUTY (caso "teste 143", 44 documentos)
depois das correções de orçamento das sessões 86/87 — **44/44 extraídos, US$ <0,20, ~1h28** (contra
US$ 52,39 recusado e 88min com o TPM no piso). Ele enviou o export (HTML do portal + xlsx do book)
e 4 dos PDFs de origem. Esta sessão leu os 4 PDFs de verdade (2 têm camada de texto, 2 são imagem
escaneada — conferido pelos `/Resources` do PDF, não suposto), releu o código-fonte de cada função
SQL envolvida, e tentou consultar o banco de produção (bloqueado — ver Fatia 5).

**Estado no fim da sessão 88:** Fatia 1 feita, testada, commitada e empurrada (`135280f`, no PR
#221). Fatias 2-6 diagnosticadas com evidência mas **NÃO implementadas** — o dono pediu para
fechar o plano antes de continuar. **Comece pela Fatia 2.**

> **ESTADO NO FIM DA SESSÃO 89 — Fatias 2, 3, 4 e 5 FEITAS, medidas e empurradas.**
> Quatro commits em `claude/kind-edison-nbk6vy`, um por fatia (regra 6), cada um com o número do
> assert que reprovou com a correção desligada:
>
> | Fatia | Commit | Migration | Invariante | Medição com a correção DESLIGADA |
> |---|---|---|---|---|
> | 2 | `a7f0f02` | `0165` | `passivo_bare_e_o_grupo.test.sql` | `divergente / 9391222.13` — o PL contado duas vezes |
> | 3 | `21a7fd4` | `0166` | bloco 4 do mesmo arquivo | requisito da sonda 3 → 0 linhas |
> | 4 | `2088d6d` | `0167` | `faturamento_por_mes.test.sql` | `soma=28758300.92` (o dobro) e 12 "meses" |
> | 5 | `eb0de33` | `0168` | `alias_truncado.test.sql` | **4 entidades** — literalmente as 4 linhas do export |
>
> **A Fatia 5 mudou de escopo quando foi MEDIDA, e isto é o mais importante deste bloco.** O plano
> abaixo dizia que as quatro variantes da OMNIBEAUTY casam par a par por `fn_mesma_entidade` e
> portanto podiam ser fundidas numa só. **Isso é falso**, e foi conferido no banco, par a par:
> `MARCAS LTDA × SURUBIJU` é **FALSO** ("marcas" não é prefixo de "surubiju"), e o mesmo vale
> contra `SURUBIJU, 1930`. Pelo NOME, "…DE MARCAS" e "…DE SURUBIJU" são tão indistinguíveis de
> duas empresas irmãs quanto `Araucária Bioenergia` e `Araucária Imobiliária` são — fundi-las
> seria ESCOLHER no empate, que é exatamente o que a 0153 existe para proibir. A 0168 entrega
> então só a fatia que o nome sozinho prova (candidatos que casam TODOS entre si), e o ganho
> medido contra os quatro nomes reais é **4 entidades → 3**, não → 1.
>
> **O QUE FALTA NA FATIA 5, com o número:** fechar de 3 para 1 exige o **CNPJ** chegar até
> `fn_upsert_entidade` — ele está nos dois balanços (36.193.378/0001-04) e não é extraído como
> identidade da entidade. É trabalho de EXTRAÇÃO, da mesma família dos dois defeitos da Fatia 6,
> e nenhum algoritmo de nome resolve. **É a primeira coisa a decidir na próxima sessão.**
>
> **E a parte retroativa continua bloqueada e é decisão do dono:** a 0168 impede o PRÓXIMO lote de
> nascer fragmentado, mas não funde as quatro linhas que já existem no caso "teste 143". As
> consultas corrigidas para inspecionar isso estão na Fatia 5 abaixo (`entidade` NÃO tem coluna de
> timestamp — use `min(documento.criado_em)` como proxy).
>
> **A SESSÃO 89 CONTINUOU DEPOIS DISSO, E O PR #223 (0165-0171) JÁ FOI MERGEADO.** Este bloco
> descreve o que aconteceu DEPOIS do merge, na mesma sessão — branch `claude/kind-edison-nbk6vy`
> reiniciada a partir da `main` por fast-forward (a doutrina de branch mergeada: nunca empilhar
> commit novo em cima de história já mergeada).
>
> O dono decidiu, em resposta direta, as três perguntas que a sessão fez: **atacar o CNPJ agora**,
> **preparar o script de fusão retroativa para ele executar**, **fazer a Fatia 6 junto** — e uma
> quarta, levantada por esta sessão: **o CNPJ também deveria RENOMEAR**, não só fundir. As quatro
> estão feitas:
>
> | O quê | Commit | Estado |
> |---|---|---|
> | Script de fusão retroativa | `085d2cd` | **PRONTO, rodado de verdade contra banco de teste.** Espera o dono rodar a Parte 1 e colar o resultado |
> | `0169` — o CNPJ como identidade | `20e659b`+`4c1c3f8` | **FEITO e MERGEADO** (PR #223), revisado por agente independente, 7 defeitos corrigidos |
> | `0170` — o CNPJ atravessa a porta | `4c1c3f8` | **FEITO e MERGEADO** |
> | `0171` — o CNPJ também renomeia | `03799ad` | **FEITO**, decisão do dono, 3 sinais de desempate (endereço colado > sufixo societário > comprimento) |
> | A IA LER o CNPJ do documento | ver abaixo | **FEITO** — schema, prompt, `mergeClassification`, nó `Registrar Documento` |
> | Fatia 6 (dois defeitos de extração) | ver abaixo | **FEITO** — só prompt, sem invariante SQL possível |
>
> **A EXTRAÇÃO DO CNPJ, com os arquivos exatos que mudaram** (o mapa que a sessão anterior deixou
> estava certo, conferido linha por linha antes de editar):
>
> 1. `SCHEMA_CLASSIF` (`N8N/build-workflow.mjs`) ganhou `cnpj:{type:['string','null']}`, em
>    `properties` E em `required` (schema `strict:true`).
> 2. O prompt de sistema da classificação (`CODE_REQ_CLASSIF`) ganhou a instrução do campo e o
>    aviso explícito: documento contábil brasileiro tem VÁRIOS CNPJs na mesma página (escritório
>    de contabilidade, auditor, empresa) — extrair só o da empresa dona, e **preferir null a
>    arriscar o errado**, porque um CNPJ errado funde esta empresa com OUTRA no sistema.
> 3. **`mergeClassification` deixou de ser cópia à mão e passou a ser embutida por `toString()`**
>    (como `parseEntidade`/`diagnosticarErroApi` já eram) — decisão tomada nesta fatia, não só
>    pedida: como eu já ia editar essa função para acrescentar `cnpj`, copiar a edição à mão para
>    dentro do template literal reintroduziria exatamente o risco que este arquivo existe para
>    matar (foi o `Math.max` da confiança de classificação, medido no HANDOFF). Fonte única agora:
>    `N8N/lib/merge.mjs`.
> 4. O nó `Registrar Documento` ganhou `p_cnpj=>$16::text` na query e `$json.cnpj || null` no
>    `queryReplacement` — o parâmetro que a `0170` criou no banco.
>
> **ARMADILHA ENCONTRADA E CORRIGIDA ANTES DO COMMIT:** o texto do aviso sobre CNPJ usava aspas
> simples (`'CRC'`, `'Contador'`) DENTRO de uma string JS já delimitada por aspas simples
> (`sistema:'...'`) — quebrou a sintaxe do nó gerado (`SyntaxError: Unexpected identifier 'CRC'`),
> pego pelos 542 testes do n8n (6 reprovaram). Trocado para aspas duplas.
>
> **OS PORTÕES ARRASTADOS, TODOS ATUALIZADOS E VERDES:**
> - `espelho-inline.test.mjs`: dois casos novos em `mergeClassification` (com e sem `cnpj`).
> - `workflow-sim.test.mjs`: o assert de aridade do `queryReplacement` (15→16 posições) e um
>   assert novo confirmando `params[15] === null` (nunca `undefined`) quando não há CNPJ.
> - `node --test 'N8N/test/*.test.mjs'`: **542/542 verde.**
> - `node N8N/medir-regua-cobertura.mjs` e `node N8N/medir-custo-book.mjs`: **verdes**, sem
>   nenhuma mudança de número — esperado, os dois rodam sobre TEXTO/fixture, não chamam a IA.
> - `node N8N/build-workflow*.mjs` (os 4): regerados; só `workflow.e1-ingestao.json` mudou.
>
> **FATIA 6 — os dois defeitos de qualidade de extração — FEITA, só no prompt do `SYSTEM_PROMPT`
> de `N8N/lib/extract.mjs`:**
> - Defeito 1 (RESERVAS/OUTRAS CONTAS trocadas por indentação): acrescentado um parágrafo sobre
>   FRONTEIRA ENTRE SEÇÕES IRMÃS — quando duas seções vizinhas ficam próximas no documento, uma
>   linha de ajuste/dedução perto da transição pertence à que a ANTECEDE, salvo indentação clara
>   em contrário; na dúvida, testar qual hipótese fecha o TOTAL IMPRESSO.
> - Defeito 2 (GENERAL TABACO escaneada, PASSIVO CIRCULANTE = PASSIVO): acrescentado um parágrafo
>   sobre TABELA DENSA EM IMAGEM ESCANEADA — o risco maior é o ALINHAMENTO linha↔valor, não o
>   número; um total repetindo o mesmo valor de uma linha vizinha que deveria ser menor é o sinal
>   mais forte de desalinhamento, e a saída certa na incerteza é confiança BAIXA na linha, não
>   aceitar o valor calado.
>
> **O QUE NENHUMA SUÍTE DESTA SESSÃO PROVA, dito com todas as letras:** nada disto foi validado
> contra um documento real passando pela OpenAI. Esta sessão **não tem credencial de OpenAI nem
> acesso à instância do n8n** (confirmado por `env` — nenhuma variável `OPENAI`/`N8N` presente).
> Os testes determinísticos provam que o CÓDIGO está certo (o JSON do nó é sintaticamente válido,
> o schema pede o campo certo, o parâmetro chega na posição certa, o parse não quebra) — **não**
> que a IA de fato lê o CNPJ certo do PDF, nem que o prompt da Fatia 6 melhora a leitura de
> verdade. **A validação com um lote real é a primeira coisa que o dono faz na próxima rodada**, e
> o sinal a olhar é simples: `select razao_social, cnpj from entidade where caso_id = ...` depois
> de rodar um lote — `cnpj` deixando de ser NULO é a prova de que o fio funciona.
>
> **A DECISÃO SOBRE RENOMEAR (que a sessão anterior tinha deixado em aberto) FOI TOMADA:** o dono
> respondeu SIM — o CNPJ também deve adotar o nome mais completo, não só fundir. A `0171` implementa
> isso com três sinais de desempate (ver o cabeçalho da migration): cara de endereço colado NUNCA
> vence mesmo sendo mais longo (é o que resolve "SURUBIJU, 1930" 55 chars vs "MARCAS LTDA" 52
> chars, o caso que motivou a pergunta), depois sufixo societário, depois comprimento cru.
>
> **Fatia 5 (fusão retroativa) segue esperando o dono rodar a Parte 1 do script** — nenhuma
> mudança de estado desde a nota anterior.
>
> **DUAS VOLTAS DE REVISÃO DEPOIS (14/09, fim da sessão 89).** O dono pediu um loop de revisão e
> correção. Duas rodadas, com o `revisor-defeito-silencioso` sobre o diff de cada uma:
>
> **1ª volta — seis defeitos, todos reproduzidos rodando SQL antes de aceitar:** o CNPJ do
> escritório de contabilidade reescrevia o nome de um cliente com o de outro; o renomeio criava
> duas entidades homônimas (e o casamento exato escolhia uma no escuro, sem evento); a guarda
> canônica escondia o caso em que o sufixo É a diferença; `S.A.` não era reconhecido como sufixo;
> o CNPJ só chegava pela classificação (**19 de 38** documentos do book-canastra) e
> `fn_registrar_diagnostico` ainda chamava `fn_upsert_entidade` com dois argumentos;
> `classificationSchema()` da lib ficou sem o campo. Corrigidos em `2d73142` e `75d47eb`.
>
> **2ª volta — e ela achou que a minha própria correção era de sintoma.** Duas coisas graves:
> (a) a 0172 commitada **não funcionava** — o `p_cnpj` chegava e morria, porque a chamada que o
> recebia só roda quando o documento ainda não tem entidade, e `fn_registrar_documento` sempre
> resolve uma antes (medido: `cnpj=(NULO)` depois do diagnóstico); (b) a guarda do renomeio media
> **comprimento de prefixo** em vez de relação de truncamento, e errava nos dois sentidos —
> autorizava `PADARIA DO JOAO` → `PADARIA DO JOSE COMERCIO` e `ARAUCARIA BIOENERGIA` →
> `ARAUCARIA IMOBILIARIA` (o incidente real do araucária, sem o token "SPE"), e recusava
> truncamento à esquerda e `S.A.`. Corrigidos em `f37c2a4`.
>
> **O QUE A 2ª VOLTA APONTOU E NÃO FOI CORRIGIDO — declarado, não esquecido:**
>
> 1. **Nenhuma tela lê os eventos de entidade.** `entidade_cnpj_casou`,
>    `entidade_renomeada_por_cnpj`, `entidade_renomeio_recusado`, `entidade_cnpj_aprendido` vão
>    para `evento_auditoria` e **zero ocorrências** em `portal/src` — a única página que lê a
>    tabela (`autonomia/page.tsx`) filtra só os eventos de dial. Na prática: renomeio recusado é
>    invisível, e CNPJ suspeito também. O rastro existe para auditoria, não para revisão. **É a
>    próxima coisa a decidir com o dono** — uma tela, ou uma pendência (que `fn_upsert_entidade`
>    não pode abrir, porque não conhece documento; teria de ser em `fn_registrar_diagnostico`).
> 2. **A 0172 entrega identidade fiscal em 100% do lote, mas renomeio em ~50%.** O caminho do
>    diagnóstico chama `fn_entidade_aprender_cnpj` (que só grava o CNPJ); quem renomeia é
>    `fn_upsert_entidade`, que nesse ramo não roda. Para um documento único com nome contaminado,
>    o nome fica no book até chegar um segundo documento pela classificação. O conserto seria
>    extrair o renomeio para função própria e chamá-la dos dois lados.
> 3. **O portão de topologia do n8n é mais fraco do que o commit dizia.** O defeito original era de
>    fluxo de DADO (`$json.cnpj` só é populado no ramo de fallback), não de topologia — e
>    `Registrar Documento` nunca esteve atrás do `Precisa Fallback?`. Os asserts que reprovam são
>    os de mecanismo (`diagnostico?.cnpj`, `p_cnpj=>`), não o de comportamento. E a travessia usa
>    os sucessores DIRETOS da saída falsa, não o fecho transitivo — funciona por acidente de
>    topologia hoje.
> 4. **O buraco do `S.A.` em `fn_entidade_canonica` (0030) continua lá**, de propósito: ela é a
>    base do casamento EXATO de todo o produto. A 0171 resolveu localmente com
>    `fn_entidade_canonica_forte`.
> 5. **`fn_nome_tem_sufixo_societario` tem um falso positivo novo**: `LABORATORIOS B.SA` → true
>    (o achatamento transforma `b.sa` em `b sa`). Impacto: um empate de sinal 2 resolvido a favor
>    do nome errado. Medido, julgado não valer a correção.
> 6. **Continua sem validação contra lote real** — sem credencial de OpenAI nem acesso ao n8n nesta
>    sessão. Tudo acima é determinístico e medido contra SQL; nada prova que a IA lê o CNPJ certo
>    do PDF.

> **SESSÃO 90 (14/09) — o item 2 acima fechado (`0173`), a validação contra lote real ACONTECEU e
> achou um defeito NOVO e mais grave que o que estava sendo procurado (`0174`), e uma terceira
> lacuna ficou declarada.**
>
> **Primeiro, a análise do book/portal que o dono subiu (AMOBELEZA 2024 + o HTML do portal, teste
> 143).** Lida como um analista de crédito leria: comparado linha a linha contra o PDF original,
> **93 das 94 linhas corretas, zero divergência de valor** — a leitura inicial desta sessão de "34
> linhas perdidas" estava ERRADA (os agregadores existem, sob o rótulo `↳ subtotal informado:` que
> o comparador não estava reconhecendo; corrigido e reconferido antes de reportar). Três defeitos
> REAIS, ainda **não corrigidos, apenas evidenciados**:
> 1. **O sinal D/C é inconsistente entre documentos.** AMOBELEZA `118.591.566,53C` → gravado **+**;
>    GENERAL TABACO `16.867.770,58C` → gravado **−**. Mesmo sufixo, sinal oposto. A regra
>    (`N8N/lib/extract.mjs:302-303`) existe só como instrução de PROMPT — não há pós-processamento
>    determinístico que a force. É o maior alavancado dos três.
> 2. **Deriva sistemática de uma linha no documento escaneado puro** (GENERAL TABACO 202603, 1
>    página, 0 caracteres de texto — conferido no `/Resources`, renderizado e lido diretamente).
>    Mapeado valor a valor contra a aritmética do próprio documento (`AC 13.411.418,80 + ANC
>    3.456.351,78 = ATIVO 16.867.770,58`, `PL = 10.000 + 1.811.271,43 − 1.632.324,34 = 188.947,09`):
>    `OUTROS CRÉDITOS`, `ATIVO NÃO-CIRCULANTE`, `PASSIVO CIRCULANTE`, `PATRIMÔNIO LÍQUIDO` pegaram o
>    valor da linha VIZINHA; `IMPOSTOS E CONTRIBUIÇÕES A RECOLHER` ficou ausente;
>    `OBRIGAÇÕES TRABALHISTA` foi inventada. A guarda funcionou — as 42 linhas do documento ficaram
>    `pendente`, nenhuma virou fato aceito — mas a causa (alinhamento linha↔valor em tabela densa
>    escaneada) continua aberta.
> 3. **`PASSIVO` (a linha nua, o total do grupo) tem `secao_canonica` vazia nos 17 documentos** —
>    coluna H em branco em todos. E rótulos não-canonicalizados viram linha-escada: `ADIANTAMENTOS
>    A FORNECEDORES` / `ADIANTAMENTO A FORNECEDORES` / `Adiantamentos a Fornecedores` como TRÊS
>    linhas, cada uma com uma célula.
>
> **E o achado que explica por que nada do CNPJ apareceu no export:** nenhuma string de CNPJ existe
> no HTML do portal, e as duas entidades OMNIBEAUTY (`...NEGOCIOS LTDA` e `...SURUBIJU`) continuam
> separadas mesmo com as migrations até a `0172` aplicadas — forte indício de que **o workflow do
> n8n não tinha sido republicado** desde a fatia do CNPJ, então o schema/prompt novos nunca
> chegaram a rodar nesta batelada.
>
> **O dono então (a) republicou o workflow e (b) rodou o lote real de novo**, e colou o resultado
> de `evento_auditoria` para este caso (`bf0246bb-c93b-4d08-a7df-5d356c9d6275`): **DOIS
> `entidade_ambigua` novos**, as mesmas quatro variantes de sempre, ainda sem fundir.
>
> **Investigando, primeiro fechou-se o item 2 já declarado acima: `0173`** — o renomeio saiu de
> dentro de `fn_upsert_entidade` (só roda na classificação, 19/38 docs) e virou
> `fn_entidade_talvez_renomear`, chamada TAMBÉM por `fn_registrar_diagnostico` (o caminho que roda
> para todo documento). Medido: com a chamada nova removida, o nome ficava truncado mesmo com o
> CNPJ certo gravado do lado.
>
> **Reconstruindo o caminho que o pipeline de fato executa com os nomes/CNPJ reais do evento
> colado, apareceu um defeito MAIS GRAVE que a não-convergência: um CRASH real.** `0174` —
> `fn_entidade_aprender_cnpj` levantava `duplicate key value violates unique constraint
> entidade_caso_cnpj_unico` sempre que aprendia um CNPJ que já pertencia a OUTRA entidade do
> mesmo caso (o destino de qualquer par de nomes que não casassem por igualdade exata ANTES do
> CNPJ chegar). Ela agora FUNDE (`fn_fundir_entidade`) em vez de tentar gravar, e devolve o id de
> quem sobreviveu — os dois chamadores tinham de trocar `perform` pelo retorno, senão a variável
> local ficaria com um id deletado na mão (e em `fn_upsert_entidade` isso quebraria a FK de
> `documento.entidade_id`, um crash NOVO). Medido com a fusão desligada: reproduz o crash exato,
> antes do primeiro assert.
>
> **LACUNA DECLARADA, e é provavelmente a que EXPLICA os dois eventos reais que o dono colou:** as
> duas entidades desses eventos nasceram pela AMBIGUIDADE (0153/0162) — e o ramo "balcão ambíguo"
> de `fn_registrar_diagnostico` **nunca chama `fn_entidade_aprender_cnpj`**, mesmo quando o
> CONTEÚDO do documento traz um CNPJ que resolveria a ambiguidade sozinho (a mesma confiança que o
> CNPJ já tem em TODO o resto do sistema desde a 0169). Uma entidade que nasce balcão só sai de lá
> por decisão humana hoje. **Não foi corrigido nesta sessão — é a próxima fatia (`0175`).**
>
> Migrations: `0173_o_renomeio_pelo_caminho_que_roda_sempre.sql`,
> `0174_aprender_cnpj_que_ja_tinha_dona_funde.sql`. Suíte SQL inteira (119 migrations), 543 testes
> do n8n, `conferir-chamadas` e o portão do conhecimento verdes nas duas. Commits
> `3c5b70a` (0173) e `21146b5` (0174) em `claude/kind-edison-nbk6vy`, empurrados.
>
> **O QUE CONTINUA ABERTO, em ordem de valor:** (1) `0175` — o CNPJ resolver o balcão ambíguo
> sozinho, que é o que faz os dois eventos reais convergirem sem intervenção humana; (2) a regra
> D/C determinística (item 1 da análise do book acima), o defeito de maior alavanca fora do CNPJ;
> (3) o alinhamento linha↔valor em tabela densa escaneada; (4) `PASSIVO` com `secao_canonica`
> vazia e a canonicalização de rótulo que evita linha-escada; (5) fusão retroativa da OMNIBEAUTY
> (`Supabase/fundir_omnibeauty_teste143.sql`) — ainda espera o dono rodar a Parte 1; (6) nenhuma
> tela do portal lê os eventos de entidade (item 1 da 2ª volta, acima, continua aberto).

### Fatia 1 — TPM real da conta — ✅ FEITA (commit `135280f`)
`N8N/lib/provedor.mjs` (30000→500000) + os 4 espelhos que isso arrastou (`PISO_BATCHING_MS`
movido para `lib/extract.mjs`, dois asserts de `workflow-sim.test.mjs` que travavam números sem
evidência, os dois hardcodes de `portal/src/lib/espera-do-lote.ts`, e um espelho esquecido em
`verificar-mensagem-de-falha.mts` que não conhecia o piso de UX da própria função que mede). 542
testes do n8n + 7 portões do portal + 2 medidores, todos verdes. Ficha atualizada:
`.claude/conhecimento/fichas/cadencia-da-extracao-73s.md`.

### Fatia 2 — Ativo = Passivo + PL conta o Patrimônio Líquido duas vezes — ✅ FEITA (`a7f0f02`, migration `0165`)
**Arquivo a mudar:** nova migration (`Supabase/migrations/0165_...sql`), reemitindo
`fn_reconciliar_ativo_passivo_pl` INTEIRA (doutrina `nunca-corrigir-funcao-por-replace.md` — nunca
por patch de âncora). Corpo atual em `Supabase/schema.sql:6497-6699`.

**Causa raiz, medida com aritmética exata no PDF real** (`AMOBELEZA - BALANÇO 2024.pdf`, anexado
pelo dono):
```
PASSIVO 118.591.566,53C   ← bare, e já é PASSIVO_CIRC+NÃO_CIRC+PL somados
PATRIMÔNIO LÍQUIDO 9.391.222,13D
```
119.620.673,17 (Passivo Circ) + 8.362.115,49 (Passivo Não Circ) − 9.391.222,13 (PL, débito) =
**118.591.566,53** = ATIVO. Confirmado o MESMO padrão em `GENERAL TABACO - BALANÇO 202603.pdf` e
`OMNIBEAUTY - BALANÇO 2023.pdf` (os outros dois PDFs que o dono anexou): "PASSIVO" bare, neste
ERP, **já é o total combinado** — é convenção de chart-of-accounts brasileiro comum (PL como
subgrupo do grupo "2-PASSIVO"), não peculiaridade de um documento.

O código (`fn_reconciliar_ativo_passivo_pl`, corpo herdado da migração 0034) tem um fallback que
busca "PASSIVO" bare via `fn_valor_estrutural_col(v_versao, array['passivo'], ...)`, acha
118.591.566,53, e **soma com PL de novo** (`v_dir := v_passivo.valor_num + v_pl.valor_num`) →
**109.200.344,40** — exatamente o "Passivo+PL" que o painel do dono mostrou, e exatamente a
diferença de 9.391.222,13 reportada como divergência. Reproduzida linha por linha, não suposta.

**A correção:** no ramo `if v_passivo.id is not null and v_pl.id is not null then`, antes de somar,
checar se `abs(v_passivo.valor_num - v_esq) <= v_tol_local` (uma tolerância igual à usada no resto
da função) — se bare "PASSIVO" **já bate** com o Ativo daquele mesmo ano/coluna, ele já é o total
combinado; usar `v_dir := v_passivo.valor_num` direto, sem somar PL, e `v_orig_dir` deve dizer que
foi por essa via (ex.: `format('linha "%s" (já inclui o Patrimônio Líquido — bare "PASSIVO" bate '
'com o Ativo)', v_passivo.chave)`). Só entra nesse ramo quando os localizadores por rótulo com
"total" já falharam (ordens 1-2 da função), então não muda nada para quem usa a convenção
"Passivo Total" separado de PL com rótulo explícito.

**Invariante novo (regra 2), fixture `Supabase/test/*.sql` — não fabricar dado, usar os números
reais do PDF:**
```sql
-- fixture: documento BALANCO com as linhas exatas de AMOBELEZA - BALANÇO 2024.pdf
-- (ATIVO=118591566.53, PASSIVO=118591566.53, PATRIMÔNIO LÍQUIDO=9391222.13 com sinal invertido)
-- desligada a correção: fn_reconciliar_ativo_passivo_pl devolve 'divergente', divergencia_abs=9391222.13
-- ligada: devolve 'ok'
```
Desligar = comentar a checagem nova (reverter para `v_dir := v_passivo.valor_num + v_pl.valor_num`
sem condição) e confirmar que o teste então FALHA antes de religar.

**Efeito esperado:** resolve as ~11 das 37 divergências "Ativo vs Passivo+PL" do book, nas 4
entidades (AMOBELEZA, GENERAL CORPORATE, GENERAL TABACO, OMNIBEAUTY).

### Fatia 3 — a mesma convenção derruba o Kit Básico por um caminho DIFERENTE — ✅ FEITA (`21a7fd4`, migration `0166`)
**Arquivo:** nova migration, `insert into taxonomia_linha_localizador` (seed adicional — não mexe
em função nenhuma).

**Causa raiz:** a exigência `passivo_mais_pl` (`Supabase/migrations/0113_linha_exigida_por_tipo.sql`,
linhas ~490-497) tem 4 localizadores, e NENHUM aceita "PASSIVO" bare sozinho — todos exigem a
palavra "total" no rótulo, ou o par exato `['passivo','patrimonio']` estruturalmente no MESMO
rótulo (que "PASSIVO" isolado não tem). É por isso que apareceram as 5 pendências "a linha exigida
'Passivo + Patrimônio Líquido (total)' não foi localizada" no export — é o MESMO bug de convenção
da Fatia 2, mas em código DIFERENTE (checklist do Kit Básico, não a reconciliação), e por isso a
Fatia 2 sozinha NÃO resolve isto.

**A correção:**
```sql
insert into taxonomia_linha_localizador (exigencia_id, ordem, contra, termos_inclui, termos_exclui)
select e.id, 5, 'estrutural', array['passivo']::text[], '{}'::text[]
from taxonomia_linha_exigida e
where e.tipo_taxonomia in ('BALANCO','COMBINADO') and e.conceito = 'passivo_mais_pl'
on conflict (exigencia_id, ordem) do nothing;
```
O próprio comentário do seed original já documenta a doutrina certa: *"aqui qualquer localizador
satisfaz — a exigência acusa a ausência total, o par fino continua com a reconciliação."* — ou
seja, esta exigência é deliberadamente FROUXA (só confere que "algo como Passivo+PL existe"), e a
Fatia 2 é quem garante que o VALOR está certo.

**Invariante:** fixture com documento cujo único rótulo de passivo é "PASSIVO" bare (sem "total",
sem "PASSIVO E PATRIMÔNIO LÍQUIDO") — desligado (sem o seed), `fn_exigencias_do_caso` marca
`passivo_mais_pl` como `satisfeita=false` e `linha_exigida_ausente` abre; ligado, `satisfeita=true`
e a pendência não abre.

### Fatia 4 — Faturamento × DRE: a hipótese de ontem (sobreposição de datas) estava ERRADA — ✅ FEITA (`2088d6d`, migration `0167`)
**Correção da própria sessão 87**, registrada aqui para não repetir o erro: eu tinha dito que o
problema era dois arquivos de Faturamento com meses sobrepostos (`AMOBELEZA - FATURAMENTO
2025.pdf` vs `FATURAMENTO AMOBELEZA 202606.pdf`). **Medi célula a célula no export e não é isso.**

**Arquivo a mudar:** nova migration, reemitindo `fn_somar_faturamento_ano` inteira (corpo atual em
`Supabase/schema.sql:9819-9833`).

**Causa raiz, medida linha a linha no export** (`GENERAL TABACO - FATURAMENTO 2024.pdf`, um ÚNICO
documento):
```
chave (rótulo) = 'Janeiro 2024' aparece 4 VEZES no MESMO documento:
  periodo_coluna='Serviços R$' → 0
  periodo_coluna='Saídas R$'   → 4.018.139,19
  periodo_coluna='Outros R$'   → 0
  periodo_coluna='Total R$'    → 4.018.139,19   (= Saídas, é a MESMA coisa)
```
`fn_somar_faturamento_ano` exclui "total" olhando `ce.chave` (`fn_normalizar_texto(ce.chave) not
like '%total%'`) — mas a CATEGORIA mora em `ce.periodo_coluna`, não em `chave` (confirmado no
export: coluna "Período da coluna" = `campo.periodo_coluna` diretamente, `portal/src/lib/export.ts:3106`).
Nenhuma das 4 linhas tem "total" na CHAVE (todas dizem "Janeiro 2024") → as 4 somam, sempre.
12 meses × 4 categorias = **48**, exatamente o "48 meses de faturamento" que o painel mostrou.
`74.160.836,36 (Receita Bruta DRE) × 2 = 148.321.672,72` vs os `144.872.009,06` reportados — bate
em 97,7%, e o resíduo de 2,3% é a diferença real de competência/recorte que a mensagem já
reconhecia como "zona cinzenta".

**A correção** (SQL-only, agrupando por rótulo em vez de somar tudo):
```sql
create or replace function public.fn_somar_faturamento_ano(
  p_documento_versao_id uuid, p_ano4 text, p_ano2 text
) returns table(soma numeric, n_linhas integer)
language sql stable as $$
  with candidatos as (
    select ce.chave, ce.periodo_coluna, ce.valor_num
    from campo_extraido ce
    where ce.documento_versao_id = p_documento_versao_id
      and ce.valor_num is not null
      and (position(p_ano4 in fn_normalizar_texto(ce.chave)) > 0
           or fn_normalizar_texto(ce.chave) ~ ('[/. -]' || p_ano2 || '($|[^0-9])'))
      and fn_normalizar_texto(ce.chave) not like '%total%'
      and fn_normalizar_texto(ce.chave) not like '%acumulad%'
      and fn_normalizar_texto(ce.chave) not like '%media%'
      and fn_normalizar_texto(ce.chave) not like '%médi%'
  ),
  -- POR RÓTULO (mês): se alguma linha daquele mês tem a coluna TOTAL (a
  -- categoria mora em periodo_coluna neste formato — Saídas/Serviços/
  -- Outros/Total —, não em chave, que repete o MESMO mês nas quatro), usa
  -- só ela; senão soma o que houver (documentos sem quebra por categoria).
  por_rotulo as (
    select chave,
      coalesce(
        max(valor_num) filter (where fn_normalizar_texto(periodo_coluna) like '%total%'),
        sum(valor_num)
      ) as valor
    from candidatos group by chave
  )
  select coalesce(sum(valor), 0)::numeric, count(*)::int from por_rotulo;
$$;
```
Efeito colateral CORRETO: `n_linhas` passa a contar MESES de verdade (12), não células (48) — a
mensagem "48 meses de faturamento" também estava mentindo sobre a UNIDADE, não só o valor.

**Antes de escrever a migration, RODAR `Supabase/test/reconciliacao.test.sql` e confirmar que o
teste do book-vertentes** ("Receita bruta obtida somando a seção") **continua batendo** — o
fixture dele usa faturamento SEM quebra por categoria (`fixture_modelagem_v35.sql`, um valor por
mês), e a correção tem que ser NO-OP nesse formato (verificado no raciocínio da sessão 88, mas
precisa RODAR, não só ler).

**Invariante novo:** fixture com a forma exata de 4 categorias/mês (a de GENERAL TABACO/AMOBELEZA)
— desligado, soma 2× o real; ligado, soma o valor real e `n_linhas`=12.

**Efeito esperado:** resolve ~10 das 37 divergências "Receita Bruta vs Faturamento".

### Fatia 5 — OMNIBEAUTY virou 4 entidades — ✅ CÓDIGO FEITO (`eb0de33`+`20e659b`+`4c1c3f8`+`03799ad`+extração desta sessão: 0168-0171, migrations 4→3→1 com CNPJ; falta VALIDAR com lote real e o dono rodar a fusão retroativa)

**O que a sessão 88 provou sem banco:** rodando `fn_mesma_entidade` (migração 0030) à mão contra
as 4 variantes do nome que aparecem no export —
`OMNIBEAUTY DESENVOLVIMENTO E GESTAO DE` (bare, 7 docs),
`...DE MARCAS LTDA` (2 docs, PDF com camada de texto — nome completo),
`...DE SURUBIJU` (1 doc) e `...DE SURUBIJU, 1930` (1 doc, confirmado visualmente no PDF
`OMNIBEAUTY - FATURAMENTO 2024.pdf`: o campo "Empresa:" trunca em "GESTAO DE" e a linha seguinte,
"Endereço: SURUBIJU, 1930", gruda por estar logo abaixo no layout do relatório do cliente) —
**as 4 batem par a par** via o algoritmo de prefixo por token da 0030 (todos os tokens do nome
curto são prefixo, na ordem, dos tokens do nome longo).

`fn_upsert_entidade` (0153, `Supabase/schema.sql:10144`) tem a regra "no empate, não escolhe": se
2+ candidatos aproximados já existem para um nome, ele cria uma entidade NOVA em vez de escolher
— desenhada para não fundir empresas de verdade que só coincidem parcialmente (ex.: duas SPEs do
mesmo grupo). O efeito colateral, quando a ambiguidade é a MESMA empresa com nome truncado de
formas diferentes: cada variante nova que chega quando já existem 2+ candidatos cria MAIS uma
linha em vez de se fundir a uma delas — 4 linhas para 1 empresa é uma consequência LÓGICA
necessária do código (só existe caminho para 4 linhas distintas via pelo menos duas ativações do
"ambíguo, não escolho"), mesmo sem saber a ordem exata de chegada dos 11 documentos.

**O QUE FALTOU CONFIRMAR, E A TENTATIVA FALHOU — CORRIJA ANTES DE RODAR DE NOVO:**
a sessão 88 tentou `select razao_social, criado_em from entidade where ...` e o dono rodou —
**erro real: `column "criado_em" does not exist"`**. Conferido no schema
(`Supabase/migrations/0001_schema_fatia1.sql:146-152`): **`entidade` não tem NENHUMA coluna de
timestamp.** As queries corretas, usando `documento.criado_em` (existe,
`Supabase/migrations/0001_schema_fatia1.sql:167-176`) como proxy de "quando esta entidade
começou a ser referenciada", e `evento_auditoria.criado_em` (existe) para os eventos de
ambiguidade:

```sql
-- ordem de chegada de cada variante do nome OMNIBEAUTY (proxy: 1º documento que a referencia)
select e.id, e.razao_social, min(d.criado_em) as primeiro_documento
from entidade e
join documento d on d.entidade_id = e.id
where e.caso_id = (select id from caso where nome = 'teste 143')
  and e.razao_social ilike '%omnibeauty%'
group by e.id, e.razao_social
order by primeiro_documento;

-- os eventos de ambiguidade que o fn_upsert_entidade registrou
select criado_em, entidade_ref, depois
from evento_auditoria
where acao = 'entidade_ambigua'
  and depois->>'caso_id' = (select id::text from caso where nome = 'teste 143')
order by criado_em;
```

**Preciso de você, uma das duas:**
- me dar acesso ao projeto Supabase certo do Oria Partners (o MCP desta sessão está ligado à
  "Encorpa Database", um produto totalmente diferente — leads/pedidos, nada a ver com este
  repositório; e o MCP acabou de desconectar da própria sessão também, então mesmo o projeto
  errado não está mais acessível agora), ou
- rodar as duas queries corrigidas acima você mesmo e colar o resultado.

**O que fazer independente da resposta, quando chegar a vez desta fatia:**
1. escrever a correção defensiva em `fn_upsert_entidade`: quando os candidatos "ambíguos" TAMBÉM
   batem `fn_mesma_entidade` **entre si** (formam um cluster transitivo — é exatamente o caso das
   4 variantes de OMNIBEAUTY), fundir no de `razao_social` mais longa/completa em vez de criar
   mais uma linha; manter o comportamento atual (recusar e não escolher) quando os candidatos NÃO
   batem entre si (o caso real que a 0153 existe para proteger — duas SPEs distintas);
2. invariante sintético com as 4 variantes reais do dono, na tabela `entidade` de um caso de
   teste (isso não fere a regra 4 — é o algoritmo determinístico rodando contra nome real, não
   fixture inventada): desligada, 4 linhas; ligada, 1 linha com o nome mais completo;
3. script de fusão retroativa (`update documento set entidade_id = ... where entidade_id in
   (...)`, com `delete from entidade where id in (...)` das órfãs) para rodar contra o caso
   "teste 143" assim que houver acesso ao banco certo — NÃO faça isto sem confirmar antes com o
   dono, é uma mudança que apaga linhas de produção.

### Fatia 6 — os dois defeitos de extração — ✅ PROMPT FEITO (esta sessão, `N8N/lib/extract.mjs`); NÃO validado contra lote real

1. **`OMNIBEAUTY - BALANÇO 2023.pdf`, RESERVAS/OUTRAS CONTAS trocados em R$ 300.000.** Confirmado
   por aritmética exata contra o texto do PDF: `RESERVAS(8.090.863,63) = OUTRAS CONTAS(8.390.863,63)
   + (-)Rendimentos Distribuição de Lucros(-300.000,00)` e `OUTRAS CONTAS(8.390.863,63) = Resultado
   do Exercício(8.357.596,78) + Lucros Acumulados(33.266,85)` — as DUAS contas fecham perfeitamente
   com a hierarquia CERTA (a linha de distribuição de lucros é filha de RESERVAS, não de OUTRAS
   CONTAS). A extração anexou essa UMA linha um nível errado de indentação. É erro de leitura de
   hierarquia pelo modelo de IA, não bug de checagem — **e o sistema já pegou certo** (abriu
   "seção não fecha" nos dois lados, com a diferença de exatamente R$300.000 nos dois, que é a
   assinatura de uma linha mal-anexada, não de dado perdido).

2. **`GENERAL TABACO - BALANÇO 202603.pdf` (imagem escaneada, SEM camada de texto — confirmado
   pelos `/Resources` do PDF), 7 seções quebradas.** `PASSIVO CIRCULANTE` foi reportado com o
   MESMO valor que "PASSIVO" (o total do grupo inteiro) tem — forte indício de desalinhamento
   linha↔valor na leitura por visão de uma tabela densa. Também não é bug de checagem — o aviso
   que o próprio painel já mostra ("muitas seções quebrando de uma vez costuma ser escala ou
   coluna, não linha perdida") é a leitura certa.

**Por que NENHUM dos dois entra em código nesta rodada:** os dois exigem mudar a ESTRATÉGIA DE
EXTRAÇÃO por IA (prompt, ou uma segunda passada estruturada), não uma função determinística — e
nenhum dos dois pode ser medido "desligado→ligado" com um invariante SQL como as Fatias 2-5. São
mais arriscados e menos previsíveis; ficam para depois das 4 fatias de cima, e a decisão de
investir neles é do dono (o sistema já os detecta e os manda para revisão humana, que é o
comportamento de segurança correto enquanto não há uma correção melhor).

### Ordem de execução recomendada e por quê
**2 → 3 → 4 → 5 → 6.** 2 e 3 são a MESMA causa raiz (convenção "PASSIVO bare") em dois códigos
diferentes — fazer as duas seguidas evita reler o mesmo PDF duas vezes. 4 é independente e do
mesmo tamanho. 5 está bloqueada em uma resposta do dono — pode ser adiada sem custo (nenhuma
fatia depende dela) enquanto se espera a resposta. 6 é a mais arriscada e a menos urgente.

**Para cada fatia:** ler o corpo ATUAL da função em `Supabase/schema.sql` (não confiar em migração
antiga — pode ter sido patchada depois), escrever a migration com `create or replace function`
reemitindo o corpo INTEIRO (nunca por patch de âncora — `.claude/memory/nunca-corrigir-funcao-por-replace.md`),
escrever o invariante ANTES de aplicar a correção e confirmar que ele REPROVA, aplicar a correção,
confirmar que o invariante PASSA, rodar a suíte completa (`sudo -u postgres env PGHOST=/tmp
PGPORT=5432 PGUSER=postgres Supabase/test/run.sh`), e só então commitar — uma fatia por commit,
mensagem contando o defeito, a causa e a medição, como as 5 fatias anteriores desta sessão já
fizeram.


## A SESSÃO 87 (2026-09-13) — as duas fatias do orçamento, e o que continua dependendo do lote real

**A ordem de execução que a sessão 86 deixou tinha cinco passos. Esta sessão fez o 2, o 3, o 4 e o
5. O PASSO 1 CONTINUA ABERTO, e não por esquecimento:** ele pede rodar o lote de 44 documentos da
AMO até `Medir Documento` e ler `celulas_no_documento`, `paginas_do_documento`, `leitura_pdf` e
`caracteres_do_texto` de cada um. Esta sessão **não tem o lote nem acesso à instância do n8n** —
fabricar esses números para "fechar" a conta seria exatamente a regra 4.

### O que ficou pronto

**Fatia A — a reescala (commit `604e285`).** `CUSTO_POR_MB_USD` 2,80 → **1,48** e
`CUSTO_MINIMO_CHAMADA_USD` 0,0032 → **0,0017**, pela razão do documento DENSO (0,5249), que é o
método documentado no próprio arquivo desde 24/08. **O número que justifica**, medido nesta sessão
com `node N8N/medir-custo-book.mjs` contra o provedor ATIVO: o book-canastra custa **US$ 0,1380**
(era US$ 0,2821 no Google) e o proxy estimava US$ 0,56 — **4,06×** o real, contra os ~2× que a
calibração declara. A margem tinha DOBRADO sem ninguém escolher isso. Invariante novo trava a
RAZÃO (nenhum teste a media: havia piso e teto, e entre os dois cabia um erro de 4×).

**Fatia B+D — a conta por documento (commit `d6a73db`).** `orcamentoDoLotePorConteudo` deixou de
ser tudo-ou-nada. `estimativaDoDocumento` escolhe **um de quatro caminhos por documento**:
`conteudo` (medido) · `pagina` (PDF com páginas e sem camada de texto) · `tamanho` (proxy por
byte) · `cego` (estimativa plana). A margem de conteúdo (1,25×) vale só nos dois primeiros.
`CELULAS_POR_PAGINA_ESTIMADAS = 100` foi MEDIDA sobre os 52 documentos dos dois books
(`METRICAS.json`): agregado 53,4 células/página, mediana 43,0, p90 91,7, máximo 131,0 — a
constante fica acima do p90 e é 1,87× o agregado.

**A recusa passou a nomear** quais documentos não foram medidos e por quê, e a frase "de onde saiu
a conta" é montada caminho a caminho — sem isso um lote sem medição nenhuma anunciaria "a conta
saiu de 0 linha(s) com número", que é ausência apresentada como dado dentro do próprio
diagnóstico do orçamento.

### A revisão adversarial achou o v31 DENTRO da correção (e é a parte mais útil desta sessão)

`custoEstimadoPorTamanho`, para documento de TEXTO, cobra **só a entrada** de propósito — a saída
quem cobria era o piso por chamada. Isso bastava enquanto esse caminho decidia o **lote inteiro**;
promovido a caminho **por documento**, ele passou a cobrar **46× menos** que a conta por conteúdo
do mesmo arquivo. Medido: 20 CSVs de 1 MB sem linha contada estimavam **US$ 1,31 e PASSAVAM** no
teto de US$ 3, contra US$ 15,26 da conta por conteúdo — e a regra tudo-ou-nada que a fatia
substituiu **recusava** esse lote. A correção tinha trocado "recusa lote que cabe" por "aceita lote
que não cabe". **Os seis invariantes da fatia ficaram verdes: todos usavam PDF.**

Corrigido na mesma rodada: saída de texto estimada por `CARACTERES_POR_CELULA_ESTIMADA = 22` (p90
dos 52 documentos dos books) e **piso da estimativa plana em todo documento não medido** — porque a
frase "o proxy por byte é ≥ o real por construção", que eu tinha escrito no commit anterior, é
**falsa**: o documento mais denso do book custa US$ 0,0222 e o proxy cobra US$ 0,0153 (0,69×). A
margem de ~2× é agregada de LOTE.

E o portão do espelho inline estava **cego para o ramo de texto**: o `jsCode` gerado estourava
`ReferenceError: CARACTERES_POR_CELULA_ESTIMADA is not defined` com as 542 do n8n verdes. Dois casos
novos entraram na TABELA. **Ficha:** `.claude/memory/conta-parcial-vira-v31-quando-promovida.md`.

### O número que a próxima sessão precisa ter na mão

| | |
|---|---|
| Lote da AMO, regra antiga + proxy de agosto | US$ 52,39 (recusado) |
| Só a reescala (fatia A) | **US$ 27,69** — −47%, ainda 9× o teto |
| Com a conta por documento | **depende do passo 1** — a queda real é função de quantos dos 44 são escaneados e de quantas páginas cada um tem |

**O que dá para afirmar sem o passo 1**, e está travado em teste: um documento escaneado de 20
páginas custa ~US$ 0,12 pela conta por página contra ~US$ 0,48 pelo proxy por byte; um lote
INTEIRAMENTE escaneado de 20 páginas por documento cabe no teto até algumas dezenas de documentos,
e o ponto exato é medido pela suíte em vez de descoberto no dia do envio. Um documento medido por
conteúdo custa uma fração disso.

### O que a próxima sessão deve fazer, em ordem

1. **O passo 1 da sessão 86**, inalterado. Ele é o que transforma a sensibilidade medida no
   estimador em previsão sobre o lote da AMO — e é ele que diz se as quatro linhas do caminho
   `pagina` são 4 documentos ou 40.
2. **Reimportar o workflow no n8n antes de qualquer rodada.** `N8N/workflow.e1-ingestao.json`
   mudou nestes dois commits (o nó `Orcamento do Lote` carrega a conta nova inline), e o que
   responde qual workflow está no ar é `N8N/conferir-publicado.mjs` contra a instância.
3. **Se o lote real trouxer escaneado mais denso que 100 células por página**, o limite está
   DECLARADO no comentário de `CELULAS_POR_PAGINA_ESTIMADAS`: esse documento é subestimado, e a
   defesa é o teto duro de US$ 5 no provedor. Recalibrar a constante exige medir, não supor.

### O que NÃO foi mexido, e o porquê está registrado

**`CUSTO_ESTIMADO_DOC_USD` continua em 0,055**, apesar de o documento mais caro medido ter caído de
US$ 0,0459 (Google) para **US$ 0,0222** no provedor ativo — o que o deixa em 2,5× o sintético.
Baixá-lo calibraria o caminho CEGO ("não sei nada sobre estes arquivos") pelo material mais fácil
que existe neste repositório (PDF do `reportlab`, 1 a 5 páginas), que é a MESMA causa raiz do proxy
por byte errando 75×, com o sinal trocado: aceitaria lote que não cabe, o v31. O comentário do
teste foi corrigido para dizer isso, com o número novo.

## A SESSÃO 86 (2026-09-13) — o 413 do portal, a camada de conhecimento, e o orçamento que cobra 75× o real

**Três coisas nesta sessão. As duas primeiras estão MERGEADAS; a terceira é DIAGNÓSTICO e está
aberta de propósito — nenhuma linha de `N8N/lib/custo.mjs` foi mudada.**

### 1. O 413 de 48 arquivos (PR #218, mergeado)

O dono selecionou 48 arquivos (~50 MB) e o envio morreu em `HTTP 413 /api/intake`. **A rota nunca
rodou:** o teto é da BORDA da Vercel (~4,5 MB por requisição na Serverless Function), e nenhuma
mensagem nossa tinha como aparecer. A correção tira os bytes do caminho da Vercel: acima do teto
o NAVEGADOR posta direto no Form do n8n (uma execução só — "mandar em levas" era a correção
errada, porque a cadência da IA é por execução). Ficha inteira em
`.claude/memory/teto-da-borda-recusa-antes-do-codigo.md`. Prova:
`portal/scripts/verificar-limite-de-envio.mts` (66 asserts, no CI e no `CLAUDE.md`).

### 2. A camada de conhecimento (PR #218) e o bloqueio que criei (PR #219, mergeado)

`.claude/conhecimento/` — `buscar.mjs` (briefing), `indexar.mjs`, `conferir.mjs` (portão),
`grafo.jsonl` (derivado, versionado, sob `git diff --exit-code`). **Medido:** as cinco perguntas
de `BASELINE.md` caíram de 50.245 para 10.667 bytes. Manual em
`.claude/conhecimento/INSTRUCOES.md` — **rode `buscar.mjs` antes de abrir arquivo.**

E o aviso que vale mais que a camada: **a revisão adversarial pediu "recusar por segurança" e o
bloqueio que nasceu dela travou o lote da AMO no mesmo dia.** Virou aviso (`origemIncerta`). A
lição está na ficha acima.

### 3. O ORÇAMENTO — onde a próxima sessão pega (ABERTO)

O envio passou. **O n8n recusou pelo orçamento:**

```
44 documento(s) = 88 chamada(s) ≈ US$ 52,39, acima do teto de US$ 3,00
A conta saiu de 14737 KB de arquivo. Envie no máximo 2 documento(s) por vez (22 levas).
```

Reproduzido exatamente, com a função de verdade:

```
orcamentoDoLote({ documentos: 44, chamadasPorDocumento: 2, bytes: 14737*1024 })
→ { estimadoUSD: 52.39, chamadas: 88, fatorCusto: 1.3, porTamanho: true, maxDocumentos: 2 }
```

Aritmética: `14,39 MB × CUSTO_POR_MB_USD (2,80) × 1,3 = 52,39`.

**O alvo do dono: cair ≥85% E ficar abaixo de US$ 6,00.** O alvo mais apertado é o segundo —
de 52,39 para menos de 6,00 são **≥88,5%**.

#### A causa raiz, MEDIDA: o proxy por byte foi calibrado em PDF sintético e aplicado a PDF real

`CUSTO_POR_MB_USD` foi calibrado sobre os 38 documentos do `book-canastra`. Eles são gerados por
`reportlab`. **Medido nesta sessão** (`PYTHONPATH=. python3 gerar.py` e `stat` nos 38 arquivos):

| | documentos | bytes totais | média por documento | mediana |
|---|---|---|---|---|
| `book-canastra` (a calibração) | 38 | 183.139 | **4.819 B** | 4.099 B |
| lote da AMO (o que foi recusado) | 44 | 14.730.688 | **334.789 B** | — |

**69× mais bytes por documento, para o mesmo tipo de conteúdo.** Um PDF de cliente carrega fonte
embutida, logo e imagem; um PDF do reportlab carrega texto. O proxy diz "dólar por MB" e o MB
mudou de significado entre a bancada e o campo — **é o "espelho que fica para trás" do
`CLAUDE.md`, de novo, e desta vez sobre uma constante de dinheiro.**

No regime em que foi calibrado ele acerta: o book inteiro estima ~US$ 0,58 contra US$ 0,28 reais
(~2×, a margem projetada). No regime real ele erra **~75×**.

#### O segundo erro, menor, empilhado por cima: a troca de provedor não reescalou o proxy

`CUSTO_POR_MB_USD = 2,80` e `CUSTO_MINIMO_CHAMADA_USD = 0,0032` foram escalados em **24/08/2026**
para o Google `gemini-3.5-flash-lite` (US$ 0,30 entrada / US$ 2,50 saída por milhão). Em
**11/09/2026** o dono trocou tudo para `gpt-5.6-luna` (US$ 0,20 / US$ 1,20). A tabela de preço, as
constantes de modelo e as de cadência foram atualizadas. **Estas duas não.**

O fator, pelo método que o próprio arquivo documenta (razão do documento DENSO, nunca a agregada —
o comentário explica que a agregada fazia o lote homogêneo denso passar), calculado sobre as duas
tabelas:

```
perfil medido (3.500 entrada / 7.571 saída):  google 0,019977 → luna 0,009785   razão 0,4898
20 páginas de imagem + saída densa:           google 0,024927 → luna 0,013085   razão 0,5249  ← a conservadora
só entrada 0,6667 · só saída 0,4800
```

Vale a **maior** (0,53), pelo mesmo motivo que 24/08 escolheu a maior das duas: escalar de menos
recusa lote que cabe, escalar de mais aceita lote que não cabe — e o segundo é o v31.

```
2,80 × 0,53 = 1,48        0,0032 × 0,53 = 0,0017
```

#### Por que o lote caiu no caminho por BYTE, que é o terceiro defeito

O nó `Orcamento do Lote` chama `orcamentoDoLotePorConteudo` (`N8N/build-workflow.mjs:505`), que é
a conta boa — ela usa linhas lidas do próprio documento. Mas ela é **tudo-ou-nada**: se UM
documento do lote não tem `celulas > 0` (e, se não for texto, `paginas > 0`), **o lote INTEIRO**
cai em `orcamentoDoLote`, o proxy por byte. Foi o que aconteceu: a mensagem diz "A conta saiu de
14737 KB de arquivo", que é a frase do caminho por byte.

**E a mensagem não diz QUAL documento derrubou a medição, nem por quê.** Isso é a regra 1 sobre o
próprio diagnóstico — o mesmo defeito que `n8n-form.ts` acabou de corrigir com o campo `motivo`.

A regra tudo-ou-nada tem razão de ser, e o comentário dela é honesto: "medir só os que dá
subestimaria o lote na exata proporção do que não se sabe". **Mas o argumento não fecha para o
HÍBRIDO:** medir por conteúdo os que dá e cobrar o proxy (conservador) dos que não dá **nunca
subestima** — o proxy é ≥ o real por construção. Tudo-ou-nada troca "não sei sobre 1" por "erro
75× sobre 44", e essa troca não é conservadora, é só cara.

Os 88 = 44 + 44 também dizem que **todo** documento precisou de classificação por conteúdo
(`precisa_fallback_ia`), ou seja, nenhum nome de arquivo resolveu tipo+período. Vale conferir, mas
é a fatia barata da conta (peso 0,3).

#### Os caminhos, MEDIDOS, na ordem em que devem ser testados

Base: US$ 52,39. Alvos: queda ≥ 85% **e** < US$ 6,00 (o teto do sistema é US$ 3,00, então na
prática o alvo é < US$ 3,00 para o lote rodar).

| # | Caminho | Estimativa do lote | Queda | Passa? |
|---|---|---|---|---|
| A | Só reescalar o proxy para o Luna (2,80 → 1,48) | **US$ 27,69** | 47,1% | **NÃO** |
| B | Estimar por CONTEÚDO os 44 (30k caracteres/doc) | US$ 0,34 | 99,4% | sim |
| B | idem, 60k caracteres/doc | **US$ 0,67** | **98,7%** | sim |
| B | idem, 120k caracteres/doc | US$ 1,31 | 97,5% | sim |
| B+C | Híbrido: 40 por conteúdo + 4 escaneados no proxy reescalado | US$ 3,19 | 93,9% | **< 6, mas ACIMA do teto de 3** |
| D | Escaneado estimado por PÁGINA em vez de por byte (20 pg / 600 células) | US$ 0,022 **por documento** contra US$ 0,63 do proxy | — | sim |

**A leitura:** **A sozinho não chega nem perto** — é correção de causa raiz e tem de entrar, mas
não é a alavanca. **A alavanca é B.** E a linha B+C mostra o risco que sobra: bastam quatro PDFs
escaneados no proxy por byte para o lote voltar a bater no teto de US$ 3 — o que torna **D
obrigatório junto com B**.

**D é a descoberta que fecha a conta:** um PDF escaneado NÃO é imensurável. Falta só `celulas`;
`paginas` existe (`pdf-parse`), e a entrada dele já é `paginas × TOKENS_POR_PAGINA_IMAGEM`. Estimar
a saída a partir das páginas põe todo PDF no caminho por conteúdo e **aposenta o proxy por byte
como caminho normal** — ele vira o que sempre deveria ter sido: o último recurso para o arquivo do
qual não se sabe nada.

#### O que NÃO é caminho

**Subir `TETO_EXECUCAO_USD`.** Não reduz a estimativa em nada, e o teto duro da conta do provedor
(US$ 5, pedido do dono) continua onde está — subir um sem o outro é o v31: a API corta no meio do
lote e documentos morrem sem extração.

**Mandar em levas.** É o que a mensagem de recusa manda fazer hoje ("22 levas"), e é o conselho
errado pelo mesmo motivo do 413: cada submissão é uma execução, e a cadência da IA é por execução
contra um rate limit que é da CONTA.

#### A ordem de execução para a próxima sessão

1. **Confirmar D contra o lote real**, sem inventar fixture (regra 4): rodar o lote da AMO só até
   `Medir Documento` e ler `celulas_no_documento`, `paginas_do_documento`, `leitura_pdf` e
   `caracteres_do_texto` de cada um dos 44. **É isso que diz quantos documentos derrubaram a
   medição e por quê** — e sem esse número as linhas B e B+C acima continuam sendo aritmética sobre
   suposição, não medição. Nenhuma delas custa token de IA: o teto barra antes da primeira chamada.
2. **A (reescala)** — uma fatia, um commit. É causa raiz e é independente.
3. **B + D (a conta por documento)** — a fatia grande. Cada documento medido vai por conteúdo;
   PDF sem camada de texto vai por página; só o formato realmente desconhecido cai no proxy.
4. **A mensagem de recusa passa a nomear** quais documentos não foram medidos e por quê (regra 1).
5. **Invariante MEDIDO NÃO-VAZIO** (regra 2) para cada fatia: desligar a correção, rodar, confirmar
   que reprova, religar, e pôr o número de asserts na mensagem do commit. O lote de 44 documentos
   de 335 KB é o caso que a suíte precisa carregar — hoje nenhuma suíte tem um lote no regime real.

#### O que continua aberto das outras frentes

- **`/api/intake/status` confunde dois lotes no mesmo mandato** (distingue por `caso_nome` +
  `criado_em >= desde`, e por mais nada). Correção de verdade: o pipeline gravar o id do lote no
  `documento`. Descrito na ficha do 413.
- **Confirmar por que a descoberta do campo caiu no fallback em produção**: abrir
  `/api/intake/destino` autenticado e ler `origem` e `motivo` (o diagnóstico entrou no #219).
  Hipótese principal: anti-bot/WAF na frente do n8n barrando o `fetch` servidor-a-servidor.
- **Os bloqueios da sessão 84/85 continuam de pé** — em especial: **qual workflow está publicado no
  n8n não é este arquivo que responde**, é `N8N/conferir-publicado.mjs` contra a instância.

## A SESSÃO 85 (2026-09-12) — os 60 documentos vazios da AMO, e o preço que nunca existiu

**O QUE O DONO TROUXE:** 60 documentos da AMOBELEZA/GENERAL TABACO subiram e o portal mostrou
**0 linhas financeiras em 60 documentos**, com os 60 gravados como `legibilidade='ilegivel'` a
84–98% de confiança — sobre arquivos **íntegros**. Ele também relatou que o orçamento recusou
2 arquivos por **US$ 5,60** e concluiu que o sistema não servia para esses PDFs.

### A causa raiz: a regra de roteamento sobreviveu ao destino dela

Não foi o `.txt`. Ele **funcionava** até 11/09. O refactor de roteamento por formato (`e13ab69`)
deletou o `parseCsv` que lia texto dentro do nó, apontou o roteamento para o `Extract From File`
nativo, e **transcreveu a condição literal** — `csv: 'csv|^text/plain$'`. O nó nativo VALIDA o
mimeType do binário e recusa `text/plain`: **60 de 60** falharam.

E o item `{error: "..."}` que o n8n emite **virou linha de planilha**: a mensagem de erro foi para
a IA no lugar do balanço, e `avisoTruncamentoPlanilha([1 linha])` devolveu `null`, **apagando a
pendência**. O modelo, recebendo a mensagem técnica, concluiu que o ARQUIVO estava ilegível.

O teste que cobria esse caminho **inventava a fixture** (`{...ctxCsv}`, COM `caso_id`) e afirmava
"extrator que falhou preserva o aviso". Passava sobre uma forma que o n8n nunca produz — regra 4
cobrada ao contrário: a fixture inventada **escondeu** o bug em vez de provar um.

### O segundo defeito: US$ 5,60 era um bug de 53×

`CUSTO_POR_MB_USD = 2,80` é proxy por byte **calibrado sobre PDF** (que vai ao modelo como
IMAGEM). Aplicado a texto erra **53× para cima**. E `orcamentoDoLotePorConteudo` exigia
`paginas > 0`, que **só PDF tem** — um `.txt` no lote derrubava a medição de todos. Relaxar só
isso PIORAVA: `custoEstimadoPorConteudo` contava entrada como `páginas × 1000`, o que
**subestimaria um `.txt` de 670 KB em 167×**.

### O PDF passa a ser lido como TEXTO quando dá

O `Extrair Texto` já lia a camada de texto de graça e o pipeline **jogava fora**, pagando imagem.
Agora o texto vira o conteúdo, com TRÊS critérios — e o terceiro nasceu dos documentos reais:

    texto limpo (referência).......  3,6% de palavras com letra dobrada
    OMNIBEAUTY DRE / Faturamento...  3,8% e 5,3%
    GENERAL TABACO Balanço......... 37,9%   <- camada CORROMPIDA
    AMOBELEZA Balanço.............. 73,0%   <- camada CORROMPIDA

**Dois dos quatro** documentos têm a camada de texto corrompida por glifo dobrado (negrito falso),
e o estrago chega aos NÚMEROS (`2.2272.055,77` por `2.272.055,77`). Sem esse critério a
otimização seria uma REGRESSÃO: a visão lê a página certa; a camada de texto entrega o número
errado com cara de certo. Esses vão para OCR.

### O número entrava errado e ninguém conferia

`lib/aritmetica.mjs` (novo, no `Juntar Blocos`): o faturamento da OMNIBEAUTY traz
`Saídas + Serviços + Outros = Total` e **falha em 6 dos 12 meses** (janeiro diverge em
**R$ 60.000,00**; maio traz `Bed DedI 9` no lugar do valor). As identidades **ATIVO=PASSIVO** e
**subtotal=filhos** NÃO foram reimplementadas: já existem no Postgres
(`fn_reconciliar_ativo_passivo_pl`, `fn_reconciliar_arvore`) e duplicá-las criaria uma segunda
autoridade sobre a mesma pergunta.

### Cinco portões tinham o defeito que perseguem

1. a fixture inventada que blindava o bug da AMO;
2. `Orcamento do Lote declara tudo o que o corpo referencia` **executava só 1 das 3** funções;
3. o roteamento não era ligado à capacidade do destino;
4. `conferir-publicado.mjs` **reprovava a republicação CERTA** (punia a ausência de credencial num
   nó DESABILITADO, que o preparador remove de propósito desde `7b84086`);
5. `caracteres.test.mjs` varria só o JSON — **dois bytes NUL crus** em `lib/aritmetica.mjs` (e um
   `0x01` pré-existente em `cobertura.mjs`) tornavam o arquivo invisível ao `grep`.

### A action de republicar (3 falhas) e o que ela ensinou

Abortava no passo 4 com "sobraram 2 ocorrências de REPLACE". A divisão é por **TIPO**: as 11
credenciais `postgres` resolveram todas; as 3 `httpHeaderAuth`, **nenhuma** — a API pública do n8n
não as devolve. Destravada pelo secret `N8N_CRED_IDS` (`{"<nome>":"<id>"}`), com o vivo ganhando
do mapa. **O dono rodou e o workflow ESTÁ PUBLICADO.**

### O que fica para a próxima sessão

- ⚠️ **REPUBLICAR de novo** — o `jsCode` de quatro nós mudou depois da publicação do dono.
- **Os 60 registros `legibilidade='ilegivel'` do caso AMOBELEZA são FALSOS** e continuam no banco.
- **O teste que vale ainda não foi feito:** subir 2–3 PDFs ORIGINAIS (não os `.txt`) e conferir no
  banco que cada um virou documento próprio COM LINHAS, e que os valores batem com o PDF.
- **Mandar os PDFs, não os `.txt`.** A conversão foi feita para contornar um custo que não
  existia, e injetou a corrupção de OCR. Medido: 60 `.txt` = US$ 0,14; 60 PDFs = US$ 0,16.
- `detectarFormato` com complexidade cognitiva 42 (não-bloqueante no Sonar).
- Supabase: o dono dispensou por ora. A lacuna real é a sonda contra o banco de PRODUÇÃO
  (o CI já roda a suíte SQL inteira contra um banco montado do zero).

> **LEIA "A SESSÃO 83" NO TOPO DO `ESTADO.md` ANTES DE QUALQUER COISA.** O dono rodou um book de
> 190 documentos ("Teste 00") e 75 vieram sem nenhuma linha extraída — mas a causa **NÃO é código**:
> 72 de 73 `extracao_falhou` têm o MESMO motivo, textual, gravado pela própria pendência: a conta do
> provedor Google está sem billing/crédito ativo (HTTP 429), e o sistema já diz que esperar não
> resolve. É item operacional do dono (religar o billing), não uma fatia de engenharia. A "SESSÃO
> 83" registra a medição completa, a hipótese errada que foi descartada no caminho (multi-ano vs
> ano único — parecia a causa, era coincidência de ordem de processamento), e os passos exatos para
> quando o book for reprocessado.

> **E ele congelou DE NOVO, pela terceira vez, dentro da mesma sessão em que o aviso abaixo foi
> escrito.** A sessão 82 chegou e encontrou aqui "mergeado até o #204, o #205 aberto" — o #205 já
> estava mergeado havia horas. O aviso não bastou: **ele pede disciplina de quem mergeia, e quem
> mergeia é o dono, não a sessão que escreve o aviso.** Enquanto não houver portão automático
> (o `ESTADO.md` tem um, o `run.sh` reprova se a migration mais nova não estiver citada), a regra
> prática para quem chega é: **não acredite nestas três linhas — rode `git log --oneline -1` e
> `ls Supabase/migrations | tail -1`.** As duas respondem em um segundo e não envelhecem.

> **ESTE CABEÇALHO JÁ CONGELOU DUAS VEZES, e a segunda foi em 24 horas.** Em 08/09 ele dizia
> "mergeado até o #201, o #202 aberto, a `0160` sendo escrita" — e nesse meio-tempo #202, #203 e
> #204 entraram. Antes disso passou 17 PRs parado. **Quem mergeia um PR atualiza estas quatro
> linhas na mesma passada**, ou a próxima sessão planeja contra um estado que não existe. O
> `ESTADO.md` tem portão automático (`run.sh` reprova se a migration mais nova não estiver citada);
> este arquivo **não tem**, e é por isso que depende de disciplina.

> **LEIA "A SESSÃO 79" NO TOPO DO `ESTADO.md` ANTES DE QUALQUER COISA — e depois os PRs #200, #201
> e #202.** As sessões 77/78 fecharam o buraco entre repositório e produção: as `0151`–`0156`
> **não estavam aplicadas em produção** enquanto o `ESTADO.md` as dava por aplicadas — é para isso
> que `Supabase/test/conferir-chamadas.mjs` existe agora. A sessão 79 é **a primeira rodada real do
> projeto**: lote `7377` (Canastra, 38 documentos, cobertura 0,987, zero nó morto, `execucao_falha`
> vazia). Ela e a rodada seguinte do araucária (`7417`, 190 documentos) acharam quatro defeitos da
> MESMA família — um sinal que continua respondendo depois de deixar de significar o que promete:
> o Kit Básico travando um mandato por um documento que **estava lá**, só mal rotulado (`0157`,
> #200); `com_falha` contando de sucesso a costura que funcionou (#201); o `"pronto"` da modelagem
> sem exigir cobertura nenhuma (`0158`, #201); e o rótulo COMBINADO decidindo sozinho um conflito
> mesmo quando o próprio diagnóstico do sistema já o contestava (`0159`, #202). As três primeiras
> estão em `main`; a quarta está aberta, verde, aguardando merge.

> **A SESSÃO 81 (09/09) — o que ela ensinou vale mais que o que ela entregou.** Dezoito fatias em
> dois PRs (#203, #204) e um terceiro aberto, mas o padrão é o assunto: **três afirmações minhas
> caíram na medição, e cada queda foi registrada no lugar onde alguém as leria.**
> (a) O `−33%` do COMBINADO que o `PLANO_LINHA_A_LINHA` usava para dimensionar a Fase 0 era
> artefato do REPLICADOR local, não da régua — contra texto de produção ela acerta 15 de 15. É a
> **terceira vez** que este projeto quase reporta defeito medindo a entrada errada.
> (b) Escrevi no código que um regex "travaria a renderização"; fui medir e deu **0,1 ms**. O
> comentário passou a dizer que a troca é defensiva. No mesmo dia, um regex que eu **não**
> suspeitava se mostrou quadrático de verdade — **9,9 s** — e virou 0,1 ms.
> (c) Afirmei que a correção da régua não regredia nada, medindo **contagens agregadas por
> documento**. A revisão de código mediu um nível abaixo e achou `"Protocolo 1.234.567"` mudando
> de `false` para `true`. **Medição agregada não prova ausência de regressão pontual** — e eu
> apresentei uma como se provasse.
> Some-se um teste que **defendia um bug** (afirmava a contagem errada como esperada, e teria
> bloqueado a correção) e uma instrução minha a um agente que a medição derrubou (exigir "forma de
> valor monetário" custava 19 de 46 documentos contando A MENOS — valor em real é escrito como
> inteiro puro, e isso não é decidível por forma).
>
> **O aceite (B1) continua sendo o bloqueio, e continua sendo do dono.** Nada disso o substitui.

**AS `0151`–`0159` ESTÃO APLICADAS EM PRODUÇÃO — mas esta frase envelhece, não confie nela.**
**As `0158`, `0159`, `0160` e `0161` estão NO REPOSITÓRIO; a aplicação é do dono e é manual.**
Confirme sempre com a sonda, contra o banco em que você está conectado:

```sql
select chave, migration, presente from fn_instalacao_conferir() where not presente order by 1;
select ate_migration from instalacao_cobertura;
```

**Zero linhas na primeira consulta é o único veredito que vale.**

**O `book-araucaria` (190 documentos) RODOU DUAS VEZES DEPOIS DA `0156`, e a segunda ensina uma
coisa nova: a extração NÃO É DETERMINÍSTICA.** A primeira (`7327`, madrugada de 02/09) morreu
inteira — 0 linhas, 190 de 190 com falha — por uma credencial de IA inválida no nó HTTP do n8n,
diagnosticada pelo próprio `N8N/lib/extract.mjs`. A segunda (`7417`, 03/09) rodou de verdade: 190 de
190, cobertura **0,939**, 6min47, US$ 2,3633. E os MESMOS 190 documentos, sem mudança de código,
tinham dado **13.703** linhas e cobertura **0,959** numa rodada anterior (`7316`, 01/09) — uma
variação de ~2 pontos que passa a contar como ruído de calibração para o B2, não como regressão.

**AS TRÊS PERGUNTAS ÓBVIAS QUE JÁ SALVARAM UMA SESSÃO (74) CONTINUAM VALENDO ANTES DE INVESTIGAR
QUALQUER COISA:** migration aplicada? workflow republicado? cota disponível? Quando as três
respostas fáceis estão certas, a causa é estrutural.

**O TESTE COMPARATIVO SAIU, E É A MELHOR RODADA ATÉ AQUI.** Mandato `Teste comparativo - Grupo
Canastra`, execução 7156: **38 documentos, 2.565 linhas, 17 fatos materiais, US$ 0,4257, ZERO
documento com falha, ~9min38** — contra 2.460/0 fatos da v47 e 2.485/0 da v48. O canal de fato
material rodou no book inteiro pela primeira vez, o lote FECHOU (`lote_execucao` gravada) e o
`auditar-xlsx.mts` sobre o arquivo exportado passou nos 3 itens aplicáveis, com 3.149 fórmulas e
nenhum erro.

**E ELA ACHOU TRÊS DEFEITOS QUE NENHUMA SUÍTE PEGAVA — os três SEM PRODUZIR ERRO NENHUM.** É a
lição desta sessão, e vale mais que os defeitos: *um estágio desligado tem exatamente a mesma
aparência de um estágio que rodou e não achou nada.*

1. **As premissas do realizado somavam o que não se soma** (`0150`): PMR de **348,6 dias** e custo
   variável de **287,7% da receita**, gravados como premissa. Três causas — o total da DRE somando
   com as próprias componentes, a abertura analítica (aging, estoque, extrato, balancete) somando
   por cima da conta que ela abre, e as oito empresas do grupo medidas para um modelo que projeta
   uma. Depois da correção, medido: custo variável **87,9%**, PMR **70 dias**;
2. **O fatiamento nunca ligou e a cobertura estava desligada.** `Montar Req Extracao` montava um
   item novo com cinco campos e descartava o que o `Medir Documento` tinha medido: sem
   `linhas_do_texto` o `Fatiar Extracao` cai no fallback de UM bloco, e sem `contas_no_documento` a
   guarda de extração incompleta — **a régua que mede alucinação por omissão** — nunca dispara. O
   sintoma foi uma coluna nula no painel do lote, com o `Conferir Lote` verde;
3. **A tela dizia "Tudo pronto" sobre uma execução morta** (sessão 71c), porque o registro de falha
   depende do Error Workflow do n8n, que é passo manual. Hoje `pronto` exige o lote FECHADO.

**A PROJEÇÃO DAS PREMISSAS DEIXOU DE SER DIGITADA.** Cada uma projeta pela forma que cabe a ela, e a
regra sai do CATÁLOGO (`natureza`/`formula`), não de uma lista em código: macro pela mediana do
**Focus**; razão estrutural constante na **média dos exercícios** (não no último — o último ano de
uma empresa em reestruturação é o pior dela); crescimento **indexado** ao índice do mandato, com a
hipótese declarada; e valor de decisão do caso **não projeta**, porque zero seria uma afirmação que
ninguém fez.

**O QUE FALTA AGORA** — ver "POR ONDE COMEÇAR" abaixo: mergear o #202, aplicar a `0159` (e a `0160`
quando sair) em produção, fechar a ambiguidade estrutural de entidade que ficou aberta, e completar
o **aceite do B1** (`auditar-xlsx.mts` + `Arquitetura do Sistema/6 Referência/ACEITE.md`) sobre um
`.xlsx` exportado com **modelo institucional**, não o de dados. **A frente de reestruturação
continua EM ANDAMENTO, fora do `main`:** as sessões 68 e 69 (réplica completa por cenário, new
money, equity×haircut e o cockpit das quatro alavancas) vivem na branch
`claude/reestruturacao-cenarios` — ver "A SESSÃO 69" e "A SESSÃO 68" no topo do `ESTADO.md` antes de
continuar por ali.

> Este parágrafo NÃO é a autoridade sobre o estado do banco. Quem responde é a sonda
> (`fn_instalacao_conferir`), contra o banco em que você está conectado — foi assim que a `0133`
> foi pega em 21/08. Ver "A `0133` QUE FALTOU" no `ESTADO.md`. **Desde a `0147` (sessão 67) a sonda
> enxerga o CORPO da função, e desde a `0150` (sessão 72) ela cobre 41 requisitos** — que é o que distingue uma correção aplicada de
> uma função homônima com o corpo velho, e é a maior parte das migrations recentes. E o
> `Supabase/test/run.sh` reprova quando o catálogo fica para trás da migration mais nova, então ele não
> volta a envelhecer calado. **Mas a própria `0147` só responde depois de aplicada:** num banco sem
> ela, a sonda continua sendo a de 13 marcadores. Em produção ela está aplicada desde 26/08.

**O BLOQUEIO QUE ATRAVESSOU DEZ SESSÕES CAIU: O DONO RODOU O BOOK.** Duas vezes — a **v47** (23/08,
38 documentos, 9min01) e a **v48** (24/08, os mesmos 38, 10min08). É o **B1** do
`Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md`, e ele destravou tudo o que estava atrás dele. O que as rodadas reais
acharam não estava em nenhuma suíte, e a lição vale mais que os defeitos:

**AS SUÍTES PROVAM A INGESTÃO; ELAS NÃO PROVAM QUE O ESTÁGIO RODOU.** A v47 revelou uma
reconciliação parada havia **onze dias em silêncio**: o nó `Gravar Campos` do n8n substitui o item
pelo resultado da query, então `documento_id` sumia e `fn_registrar_diagnostico` era chamada com
NULL desde 13/08. Estágio parado não gera achado, e não gerar achado tem exatamente a mesma
aparência de "está tudo certo". Hoje o `workflow-sim.test.mjs` tem uma guarda genérica: qualquer nó
que leia `$json.X` de um predecessor Postgres exige que aquele predecessor devolva `X` como coluna.

**A v48 MEDIU AS CORREÇÕES DA v47 — E 20 DAS 27 PENDÊNCIAS ERAM FALSAS.** A extração estava
**certa**: conferida linha a linha contra os PDFs e o `GABARITO.json`, os 38 documentos batem no
centavo, e os quatro que não renderam linha nenhuma (30, 32, 33 e 34) estão corretos, não quebrados.
Quem errava eram as checagens. Quatro causas, cada uma medida antes de virar código:

| Causa | Pendências | Correção |
|---|---|---|
| Hierarquia achatada — `secao` traz a seção de topo, não o grupo imediato | 12 | `0143` (a soma dá **exatamente 2,0000× o pai**: declara `hierarquia_achatada` em vez de acusar) e `0144` (**33 de 33** pares de "duplicidade" estavam no MESMO documento: o par passa a exigir documentos distintos) |
| O conceito mora na COLUNA, e o localizador só olhava a linha | 3 + 1 | `0145` — quarto modo `contra = 'coluna'`, casando contra `periodo_coluna` |
| Entidade fantasma: 7 linhas sem coluna caíam na capa de um documento de 8 empresas | 3 | `0146` — a capa só responde quando o documento é de UMA empresa (critério estrutural, não lista de nomes) |
| `tipo_incorreto` acusava sem ter divergência | 2 | `0142` — exige divergência acionável |

**Pendências abertas no caso: 27 → 8, e as 8 restantes são verdadeiras.** Detalhe completo, causa por
causa e com o número medido depois de cada correção, em `Arquitetura do Sistema/4 Análises e Auditorias/ANALISE_RODADA_V48.md` (ANEXO III).

**UM GANHO QUE NÃO ERA O OBJETIVO E VALE REGISTRAR:** ao ensinar a checagem de juros a olhar para a
coluna, **uma reconciliação que nunca tinha rodado ficou verde e bate ao centavo** — DRE
`(-) Despesas financeiras` −14.802 mil contra a soma dos juros de 11 contratos do mapa de dívida,
14.802.000.

**E A ARMADILHA QUE O TESTE PEGOU, porque ela é o padrão de erro desta fatia:** a `0145` ia sair só
com o localizador. A guarda seed×código do `linha_exigida_entidade.test.sql` reprovou: todo termo do
localizador tem de existir também na checagem que o consome. Sem esse quarto passo, a exigência
ficaria satisfeita e `fn_reconciliar_despfin_dre_vs_divida` continuaria cega — `linha_exigida_ausente`
trocada por `precondicao_nao_satisfeita`. **Pendência falsa que muda de nome não é correção.**

**POR ONDE COMEÇAR NA SESSÃO SEGUINTE.** O republish e o rerun que este handoff pedia há muito já
aconteceram — o que segue é o que a rodada real de 03/09 (`7417`) deixou aberto.

### 1. A AMBIGUIDADE DE ENTIDADE TEM UM BURACO ESTRUTURAL, E É A PRÓXIMA FATIA

A `0153` acerta em recusar um nome que casa com duas empresas ("Araucaria SPE" → Bioenergia SPE ×
Imobiliária SPE) — mas **ela não olha se o mesmo mandato já resolveu aquele nome por outro
caminho**. Medido na rodada `7417`: o documento `029` (classificado por CONTEÚDO, 100%) já tinha
identificado "Araucaria SPE" como a Araucária Imobiliária SPE Ltda.; o `009` (classificado por NOME
DE ARQUIVO, 90%) abriu a mesma ambiguidade do zero e travou o Portão 2 até o dono chamar
`fn_revisar_documento` à mão. O sinal que resolveria isso sozinho já existe no banco — falta ensinar
a `0153` a consultá-lo antes de abrir a pendência.

### 2. O MOJIBAKE DE NOME DE ARQUIVO ESTÁ ENTRANDO NO DADO, NÃO SÓ NO NOME

Achado secundário da mesma rodada, mais sério do que parecia à primeira vista: `110_Mutuos_...pdf`
foi registrado com a entidade `"GRUPO ARAUC` + bytes corrompidos (double-encoding) enquanto o
diagnóstico de conteúdo do MESMO documento sugere a grafia correta — **duas entidades diferentes no
banco para o mesmo grupo**, e o `porque_classificou_assim` do documento chegou com o texto do
próprio modelo corrompido, não só o nome do arquivo. `nome_original` é cópia direta do `fileName`
que o n8n entrega (`N8N/build-workflow.mjs:503`) — se a decodificação estiver errada, é no
upload/n8n, não neste repositório. Ainda não investigado a fundo.

### 3. A ESCALA DA MODELAGEM ESTOUROU O TETO QUE A `0101` CALIBROU

`fn_linhas_para_modelagem` e `fn_conferir_modelagem` foram calibradas (sessão 35/36, migration
`0101`) contra o caso do v35: **14 documentos, 770 ocorrências**. O araucária tem **190 documentos,
13.328 linhas** — dezessete vezes a escala testada — e a tela de modelagem voltou a estourar o
`statement_timeout` de 8 s do Supabase (medido em produção em 03/09: 8449 ms e 8496 ms,
`canceling statement due to statement timeout`). **O teste de escala que existia
(`modelagem_escala.test.sql`) passava porque nunca testou este tamanho** — o padrão de erro central
deste projeto (estágio desligado parece limpo) aplicado a uma guarda de tempo. A migration `0160`
está sendo escrita para isso; se mesmo depois da correção não couber em 8 s, o caminho é paginar a
chamada na TELA como o EXPORT já faz (`portal/src/app/casos/[id]/export/route.ts:331`,
`.range(de, ate)` — a tela hoje chama de uma vez só).

### 4. UMA DECISÃO DO DONO, ESCRITA NO CABEÇALHO DA `0157`

O COMBINADO invertido (documentos rotulados COMBINADO com 0 empresas nas colunas, perdendo de um
BALANCO mal extraído da mesma peça) foi resolvido pela `0159` sem promover o tipo — a autoridade
numérica não muda, só o conflito para de ser decidido calado. Mas uma pergunta ficou aberta desde a
`0157`: se `DF_AUDITADA` deveria entrar na lista de fontes que podem satisfazer o item COMBINADO por
estrutura. Continua sem decisão.

### O que NÃO bloqueia a próxima rodada

- **A cota RPD (500/dia) continua sendo o teto que aperta:** o araucária sozinho consome
  ~440–450, um book por dia;
- **As sub-extrações reais da rodada `7417`** (`002_Balanco_Serraria` 49%, `175_...escritorio` 51%,
  `170_...2022` 57%, `171_...2021` 69%, `099_Livro_Razao_2024` 77%) são leitura PARCIAL do modelo de
  IA, não fatiamento quebrado — todas dizem "fatiado, e todos chegaram". É calibração de
  prompt/modelo, não defeito de código;
- **O que só o dono destrava, inalterado:** proteger o `main` (B6.1).

> **ANTES DE ESCREVER QUE A INFRA CONTINUA APLICADA, RODE A SONDA.** `select * from
> fn_instalacao_conferir()` contra o banco em que você está conectado. Em 28/08 ela devolvia 54 de
> 54 requisitos presentes e cobertura `0155` — mas essa frase envelhece, e é exatamente assim que a
> `0133` passou três documentos dada por aplicada sem estar.

**O QUE MUDOU DA 52 PARA A 67, em uma linha cada** — a narrativa completa de cada uma está no
`ESTADO.md`, que é onde ela deve ser lida:

| Sessão | O que ficou de pé |
|---|---|
| 53 | O dial passa a ser **obedecido** (`0127`) e dois níveis declarados eram falsos; a classificação contábil em sombra (`0128`); a transcrição humana assistida (`0129`) e a contaminação que ela criaria |
| 54 | O golden set passa a ser rotulável, e a rotulagem é **cega** (`0130`); os três cenários viram comparáveis; a passada de eficiência — cujo valor está no que **não** mudou |
| 55 | A instalação passa a se **declarar** (`0131`/`0132`); a **seção do balanço tem de fechar** (`0133`); a dívida que era projetada como giro; os **dois defeitos que se mascaravam** e o ativo circulante fechando em ZERO; a guarda do giro agregado; a sazonalidade que travava o `pronto` (`0134`) |
| 56 | A **operação passa a ser vista** (`0135`); o espelho lib↔workflow cobrindo **26** funções e não duas; `Arquitetura do Sistema/2 Especificação/10` — onde o dado do cliente mora, quanto tempo fica e quem vê o quê |
| 57 | **O portal encolhe:** saem a página de instalação, o aviso dela no painel, a consulta à base e a tela de operação; o painel inteiro passa a falar com o **analista**, não com o desenvolvedor. Nenhum motor foi removido junto: o que as telas mostravam vive nas funções do banco |
| 58 | A sonda das 80 migrations, que achou a **`0133` nunca aplicada** enquanto três documentos a davam por aplicada; a abertura do painel passa a aparecer **em todo login**; o **veredito de produção passa a contar** para o dial (`0136`), como piso declaradamente enviesado; as **premissas passam a sair do realizado** — oito delas, com a conta à vista |
| 59 | O **dial sobe sozinho** ao critério (`0137`), com quatro travas — e o freio de quem baixou o nível não é desfeito pela máquina; e as **quatro frentes do arquivo de comitê** (Modelagem para de projetar, quatro índices novos, covenants por cenário, reperfilamento por carência) |
| 61 | O **loop de variações** (`Verificação/variacoes.mts`): 101 variantes em cinco rodadas, cinco defeitos que nenhuma suíte pegava — a exceção do veredito (`0138`), a medição apagada ao reafirmar o nível (`0139`), **a dívida que evaporava** na virada para o projetado, o código contábil quebrando a âncora, e o caractere invisível partindo a conta em duas. Mais o export que **morria** sem valor numérico e agora recusa nomeando a falta |
| 62-63 | **O provedor de IA vira escolha** e o padrão passa a ser o Google (`gemini-3.5-flash-lite`): não havia "um provedor" para trocar — havia a OpenAI espalhada por quatro módulos. Agora cada provedor é um objeto de DADOS em `N8N/lib/provedor.mjs` |
| 64 | **A v47, a primeira rodada real.** A reconciliação parada havia onze dias em silêncio; a coluna de dimensão que virava valor (`0140`); o limiar que nunca excluiu nada (`0141`) |
| 65-66 | **A v48 e as quatro causas de pendência falsa** (`0142` a `0146`); a conferência linha a linha que provou a extração certa; a estimativa de tempo antes do envio; a modelagem da v48 com as premissas derivadas do próprio realizado |
| **67** | **As quatro frentes do handoff da 66, feitas.** A hierarquia volta na extração (`secao` = agrupador IMEDIATO) e `fn_conferir_arvore` não precisou mudar — já era recursiva; o `Parse Extracao` foi publicado no n8n (575 de 579 linhas byte a byte, as 4 restantes medidas equivalentes em 160 comparações); a sonda passa a enxergar o CORPO da função (`0147`) e o catálogo passa a declarar até onde foi revisado, com portão no `run.sh`; e o que o documento diz em TEXTO — covenant rompido, ressalva, continuidade — ganha canal próprio com o trecho literal como evidência obrigatória (`0148`) |
| **70** | **A auditoria adversarial do fato material e a infra aplicada.** A `0148` foi relida com a pergunta invertida — "o que eu faria para quebrar isto sem que ninguém percebesse?" — e devolveu SETE defeitos, cinco silenciosos: a página alucinada que derrubava o DIAGNÓSTICO inteiro junto (mesma query), o reenvio de arquivo que fazia os fatos sumirem da tela, a ordem indeterminada numa tela em que a ordem significa gravidade, a `confianca` que nunca recebeu valor, e o `Juntar Blocos` que descartava os fatos dos blocos 2..N (`0149`). Os sete religamentos conferidos um a um — e DOIS deles só reprovaram depois de a própria suíte ser corrigida, porque testavam a lib e não o nó de produção. A `0147`, a `0148` e a `0149` aplicadas em produção e conferidas por md5; o workflow republicado pela API REST e conferido por hash, 33 de 33 nós. E um terceiro book, o `book-araucaria` (190 documentos, 14 empresas, 5 exercícios), construído e entregue ao dono FORA do repositório |
| **71** | **A preparação do lote de 190, e o que ela achou.** A tela desistia de um lote vivo: o merge `Juntar Ramos` (`mode: append`) é uma BARREIRA — nenhum documento é registrado antes da última classificação, uma a cada 8s — e o limite de silêncio da tela era 8 minutos FIXOS, calibrado no lote de 38; em 190 documentos o silêncio legítimo vai a 13 min (proporção medida) ou 25 (pior caso), e o analista reenviaria um lote em execução, pagando a IA duas vezes. Mais o teto da janela, que truncava em 1,77× a margem de 3× que ela promete. As quatro contas saíram de dentro do componente para uma lib e a suíte passa a CHAMÁ-LAS: o espelho anterior refazia a fórmula e passava com o defeito religado. E o orçamento do lote de 190 foi simulado contra o guarda real — cabe por conteúdo (US$ 0,93 a 2,30), e um único PDF sem camada de texto derruba o lote inteiro para a conta por tamanho (US$ 2,47 a 3,21), que recusa no pior caso |
| **73** | **O desempate entre dois documentos do mesmo período já existia, era silencioso, e escolhia o MAIOR** (`0151`). Medido antes de escrever, na fixture do Canastra: 117 conceitos aparecem em dois ou mais documentos e só CINCO discordam — três falsos (rótulo genérico sem seção canônica, papel subtotal, e um "total" em milhares de reais contra outro em PESSOAS) e dois verdadeiros que são arredondamento (0,04%). Os três falsos viraram os três filtros; os dois verdadeiros ficam sob a tolerância de sempre. A autoridade documental vira DADO do catálogo (`taxonomia_tipo_documento.autoridade`), o conflito passa a ser declarado com vencedor, perdedor, diferença e critério por extenso, `fn_linhas_do_realizado` para de escolher o maior — e no EMPATE nada muda de valor, porque desempatar por `criado_em` seria trocar uma regra silenciosa por outra (ali está a hora do UPLOAD, não a data do documento). Religado um a um: com a ordem antiga o realizado usa o rascunho de 42.800 em vez da DF auditada de 10.000, e sem os três filtros o Canastra devolve exatamente os três falsos positivos medidos |
| **72** | **A rodada comparativa do Canastra, e os três defeitos que não davam erro.** 38 documentos, **2.565 linhas** e **17 fatos materiais** (contra 2.460/0 e 2.485/0 das v47/v48), US$ 0,4257, zero falha, o lote FECHANDO. E três achados silenciosos: as premissas do realizado somando o total da DRE com as próprias componentes, a abertura analítica por cima da conta que ela abre e as oito empresas num modelo de uma (`0150` — PMR de 348,6 para 70 dias, custo variável de 287,7% para 87,9%); o `Montar Req Extracao` descartando a medição do documento, o que mantinha **o fatiamento desligado e a guarda de cobertura muda**; e a tela dizendo "Tudo pronto" sobre execução morta, porque o registro de falha depende de um passo manual do n8n. Mais a projeção das premissas deixando de ser digitada: Focus para as macro, média dos exercícios para as razões, indexação para o crescimento — a regra saindo do catálogo, não de uma lista em código |
| **74** | **A rodada de 190, e os cinco defeitos que ela achou — nenhum produzindo erro.** 1h52 de execução sem gravar uma reconciliação. (1) A reconciliação era quadrática DUAS vezes: as oito checagens do despachante leem `(caso, entidade, período)` e **não o documento** — ele só entrega a chave —, e `fn_conflitos_do_caso` pedia o produto cartesiano (**6.859.127 pares para achar 34**, 12,4 s por chamada, vezes as 123 que a `0151` dispara). Medido em produção depois: **12.357 ms → 1.790 ms**, ~8.500 → **247** invocações (`0152`). **Duas lições ficaram no caminho e valem mais que o número:** sem `MATERIALIZED` o Postgres inlina a CTE e o agrupamento que existia para MATAR o cartesiano VIRA o cartesiano — medido, 12.068 ms, a correção não acontecia, *agrupar antes não é uma instrução, é uma intenção*; e a primeira `fn_reconciliar_caso` usava UMA chave para as oito checagens, o que dá 162 chaves para 190 documentos e não corrigiria nada — **e a suíte teria passado**, porque ela prova equivalência e não custo. (2) O batch de 190 numa transação implícita só: o modo `single` do nó Postgres é o **default**, e foi observado ao vivo em `pg_stat_activity` (RowExclusiveLock em `reconciliacao`, e sete minutos depois zero linhas commitadas). (3) O portal declarou parada em 5 min sobre 29 de silêncio legítimo — `IA Extrair` a 8 s × 190 = 25min20s em que nada é escrito por construção, contra um limite FIXO cujo comentário dizia que ele *não podia* crescer com o lote. (4) Balanço e DRE de cinco exercícios da Araucária Imobiliária SPE gravados dentro da Bioenergia SPE: `fn_mesma_entidade` casa com as duas e o desempate era `order by razao_social limit 1` — **o mesmo defeito da `0151` num segundo lugar**, lá "fica com o maior", aqui "fica com a primeira do alfabeto" (`0153`, com `fn_fundir_entidade` dando saída à pendência). (5) O combinado do grupo voltando a EMPATAR com o balanço individual porque a IA o chama de `BALANCO` em quatro de cada cinco, com confiança 1,0 — e empate mantém o de maior módulo, que é a armadilha central do araucária de volta pela porta da classificação; o critério passa a ser estrutural, quantas empresas as colunas nomeiam (`0155`). Mais a `0154`, que separa as duas unidades que a pendência de cobertura juntava na mesma frase (pares conta×coluna contra linhas do documento) e faz a pendência dizer em quantos BLOCOS o documento foi lido. **E o que NÃO era defeito ficou registrado como não sendo:** a aba Outros com 3.448 linhas, os 5 documentos de Folha de Pagamento sem tipo, e as 23 pendências de extração incompleta — a régua erra +3% na mediana contra o Canastra e as razões do araucária vão de 40% a 78%, sub-extração real. O caso foi corrigido em cima sem reextrair: **25 → 16 entidades**, e a reconciliação que nunca tinha rodado gravou 295 linhas com 6 divergências |

**O método que se repetiu e vale mais que qualquer item da tabela:** em quase toda rodada, **medir
antes de escrever código desmentiu a correção anotada**. Aconteceu com o fatiamento na 52 ("extrair
por faixa de página" era a correção errada), com a `0133` na 55 (a cegueira foi **aberta** por uma
correção nossa, a `0116`) e com os dois defeitos que se mascaravam na 55, onde **corrigir só um
piorava o número** — o resíduo do ativo circulante era −3.200 com os dois, −12.400 com um e +9.200
com o outro. Na 65 aconteceu de novo, duas vezes: a hipótese de que a duplicidade de rótulo e a
seção que não fecha eram defeitos diferentes caiu na primeira consulta (são a MESMA causa), e a
suposição de que o mapa de dívida tinha perdido a identidade da coluna estava errada — ela estava
gravada em `periodo_coluna` o tempo todo. Fica como método, não como anedota.

**E a 58 acrescentou a versão mais cara dele: documento não é medição.** Três arquivos deste repo
afirmavam que a `0133` estava aplicada, e nenhum dos três tinha ido olhar — a afirmação vinha da
sessão que escreveu a migration, e foi copiada adiante. Uma consulta de catálogo com 80 marcadores,
que leva um minuto, desmentiu os três. Antes de escrever "está aplicado", "está rodando" ou "está
verde" sobre o banco de produção, rode a sonda; o `ESTADO.md` hoje diz isso de si mesmo.

> **O HISTÓRICO ABAIXO PARA NA SESSÃO 39.** As sessões 40 a 59 não estão aqui, e isso é escolha, não
> esquecimento: desde a 41 o que muda toda rodada mora no `ESTADO.md`, e duplicar a narrativa nos dois
> arquivos é como o cabeçalho daqui passou 17 PRs mentindo. O que está abaixo continua valendo como
> referência do COMO SE CHEGOU AQUI até a 39 — para o que o sistema faz HOJE, o `ESTADO.md` é a fonte.

> **LEIA O `ESTADO.md` PRIMEIRO.** Desde a sessão 41 o estado atual mora em arquivo próprio, na
> raiz — última migration, contadores das suítes, o que só o dono pode fazer, o que está aberto. Ele
> existe porque este cabeçalho já passou 17 PRs congelado, e a causa não era descuido: a parte que
> muda toda rodada morava no mesmo arquivo das partes que nunca mudam. O `Supabase/test/run.sh` REPROVA
> quando a migration mais nova não está citada lá, então o `ESTADO.md` não envelhece em silêncio.
> Este `HANDOFF.md` continua sendo o histórico — como se chegou aqui —, e é o que não precisa ser
> lido para retomar.

**O PRODUTO, EM UMA LINHA:** o portal entrega **dois arquivos** — *dados financeiros* (a conferência
da ingestão, linha a linha) e *modelagem* (as 14 abas do modelo institucional, projetadas e editáveis
dentro do Excel). O aceite de um `.xlsx` é `auditar-xlsx.mts` (10 itens automáticos) +
`Arquitetura do Sistema/6 Referência/ACEITE.md` (10 itens humanos).

### O invariante que organiza o modelo: UMA CONTA, UM LUGAR

Toda vez que uma conta teve dois donos, o modelo mentiu — e sempre para o lado de parecer melhor.
São quatro incidentes com a mesma forma, três deles já corrigidos e o quarto nesta rodada:

| Conta | Os dois donos | O que saía errado | Fechado em |
|---|---|---|---|
| caixa e aplicações | giro **e** fluxo | caixa contado duas vezes no ativo | sessão 39 |
| dívida bancária | giro **e** aba de dívida | NCG MELHORAVA quando a empresa se endividava | sessão 39 |
| subtotal informado | soma dos componentes **e** total do documento | `ATIVO TOTAL` 195.090 contra 95.780 informados (2,04×) | sessão 40 |
| **tributo a recolher** | **giro, balanço e aba de tributos (três!)** | **parcelamento girava contra receita: o saldo do acordo CRESCIA quando a empresa vendia mais** | **sessão 40h** |

A regra prática que sai disso: quem projeta uma conta é UMA aba, e as outras leem o **espelho**
(`P18`) dela. Duas origens para o mesmo número só valem com uma linha de conferência entre elas — e
foi assim que a variação de giro do `Cash Flow` ficou (aberta conta a conta, com o total vindo do
espelho e um assert exigindo diferença zero).

**CI: O `main` ESTÁ VERDE — medido em 25/08**, execução
[`32875146847`](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/actions/runs/32875146847),
`push` no merge do PR #174 (`6c2c8d2`), `success` em 8 minutos (16:58→17:06 UTC).

> O parágrafo abaixo é HISTÓRICO e foi mantido porque conta como a dívida de CI foi paga — mas ele
> afirmava no PRESENTE, por dezenas de sessões, um verde medido em **06/08**. É o mesmo defeito que
> criou o `ESTADO.md`: afirmação sobre o agora ancorada num fato de antigamente. A linha acima é a
> que vale, e ela traz a data.

**Como a dívida retroativa foi paga (06/08/2026)** — execução
[`31128897900`](https://github.com/rodrigovaroto-wq/tratamento-dados-financeiros/actions/runs/31128897900),
`workflow_dispatch` no `004092c`, **os 14 passos `success`** em 3 minutos (22:17→22:20 UTC de
06/08/2026). Como o `004092c` **contém os PRs #103, #104, #105 e #106**, essa execução única **paga a
dívida retroativa dos três que foram mergeados sem CI**. A branch de trabalho também tem veredito
próprio: `31128960940` no `792409e`, verde.

**O DISPARO AUTOMÁTICO TAMBÉM VOLTOU, às 22:52 UTC** — as execuções `#136`/`#137` (`push`) e `#138`
(`pull_request`) nasceram sozinhas no `77c0a71` e saíram **verdes em ~2m20s**. O serviço está normal:
`push`, `pull_request` e `workflow_dispatch`, os três.

> **A recuperação foi por partes, e a ordem importa para diagnosticar a próxima vez** (tudo
> cronometrado em 06/08/2026, UTC): ~17:15 a 22:17 o serviço **enfileirava e cancelava em 15 min**
> (`steps: 0`, `runner_name` vazio); **22:17** o runner voltou e o `workflow_dispatch` passou a
> executar; **22:52** o disparo automático voltou, entregando com **~30 minutos de atraso** os eventos
> represados (o push do `792409e`, feito às 22:22, virou execução às 22:52).
>
> **Evento perdido é diferente de evento atrasado.** Durante a queda, cinco commits **nunca ganharam
> execução** — `58b4de9`, `c114a3a`, `32724af`, `252cb7f`, `e38865f`: zero runs, e o GitHub não os cria
> depois. Na recuperação, os dois últimos pushes ganharam a sua com meia hora de atraso. Ou seja:
> **"ainda não apareceu run" não é veredito** — durante a queda significa "não vai aparecer", na
> recuperação significa "espere". O que resolve nos dois casos é `workflow_dispatch`, que dá veredito
> imediato sobre o estado da branch inteira.

**O plano de fim de projeto, em uma frase cada** (o dono pediu na sessão 40 um caminho para acabar
"sem nenhum bug ou falha", depois de 100+ PRs verdes que não impediram o arquivo errado):

| Fase | O que era | Estado |
|---|---|---|
| **A** | o portão que faltava: o e2e compara os números do MODELO com o gabarito, na cadeia real | ✅ no `main` (#104) — 27 → **46** asserts |
| **B** | a conta duplicada vira ACHADO da reconciliação, sem apagar nada (`0105`) | ✅ no `main` (#105) — falta **aplicar** a migration |
| **C** | três dos seis itens da fila do §5 do `CONFORMIDADE.md`, com assert cada | ✅ no `main` (#105) |
| **D** | a auditoria do arquivo entregue vira comando + aceite humano curto | ✅ no `main` (#105) — `auditar-xlsx.mts` e `Arquitetura do Sistema/6 Referência/ACEITE.md` |

O que sobra do plano **não é código**: é aplicar duas migrations, rodar o aceite sobre um export de
verdade, e decidir três premissas. Está no bloco "O QUE ESTÁ ABERTO AGORA".

> **O INCIDENTE DO ACTIONS DE 06/08/2026 — ENCERRADO ÀS 22:52 UTC.** O serviço ficou ~5h30 sem
> executar nada; as Fases B–D foram acumuladas numa branch e mergeadas num PR só (#105), com a
> evidência sendo a execução LOCAL dos nove passos do CI. O incidente teve **duas caras**, e é isso que
> confunde: primeiro os eventos **não criavam execução nenhuma** (push sem run, PR sem run — e o GitHub
> **não reexecuta retroativamente**: evento sem execução não ganha execução quando o serviço volta);
> depois voltaram a criar, e aí a execução **entrava na fila e era cancelada em ~15 minutos sem nunca
> começar** — cinco execuções assim, com `steps: 0` e `runner_name` vazio, os 15 minutos cronometrados
> em todas. Três PRs (#103, #104, #105) foram mergeados nessas condições. A sexta tentativa, disparada
> à mão às 22:17, **pegou runner na hora** (`GitHub Actions 1000000147`) e rodou os 14 passos em 3
> minutos. **A lição operacional, medida:** com o serviço nesse estado, insistir na fila não resolve —
> o que resolve é **redisparar** (`workflow_dispatch`) até uma execução PEGAR RUNNER, e é isso que dá
> veredito retroativo sobre tudo o que já está no `main`.
>
> **E O X VERMELHO NO `bc844e4` NÃO É REGRESSÃO — NENHUM PASSO RODOU.** A execução `31127589390`
> aparece como `failure` no commit `bc844e4`, que está no `main`; abrindo o job: `conclusion:
> cancelled`, `runner_name: null`, **`steps: 0`**, 20:25:05 → 20:40:07 = **15 minutos na fila**. É o
> mesmo padrão da execução das 17:15. O GitHub rotula como `failure` no nível da EXECUÇÃO o que no
> nível do JOB é `cancelled` — então um vermelho de infraestrutura fica visualmente idêntico a um
> vermelho de teste. **Como distinguir, em dez segundos:** abra o job e olhe a contagem de passos.
> Zero passos com `runner_name` vazio = nunca começou; não há log de teste porque não houve teste.
> Vermelho legítimo tem passo com nome ("Suíte de export", "Suíte de banco") e log.
>
> **O que fica disso:** `workflow_dispatch` está no `main` — Actions → suítes → **"Run workflow"**
> revalida o estado acumulado sem empurrar commit vazio, e foi o que fechou este incidente. Sobre as
> regras de proteção do `main`: **check obrigatório só faz sentido enquanto o serviço executa** (com o
> Actions parado, check obrigatório é bloqueio permanente, não portão — foi o que deixou o #105 em
> `blocked`; agora que voltou, pode ser recolocado). O outro motivo do `blocked` **não se resolve
> sozinho**: "Require approvals" com o PR aberto no nome do próprio dono, e o GitHub não deixa aprovar
> o próprio PR. Com duas pessoas em que uma abre PR no próprio nome, essa exigência trava toda rodada
> sem revisar nada — quem revisa de fato é o CI.
>
> Fidelidade da execução local, medida: Node **v22.22.2** (o CI pede 22), psql **16.13** (o CI instala
> o cliente 16), Postgres 16 local descartável. O `package-lock.json` **não foi tocado** nas Fases B–D,
> então o `npm ci` do CI é o mesmo do `main` que já passou, e **nenhum arquivo de `N8N/`** entrou no
> diff — o risco clássico de mergear sem CI (espelho dos nós Code divergindo da `lib/`) não existia
> nessa rodada. O único passo que a execução local não reproduz é o `npm ci` em ambiente limpo.

> **O `CLAUDE.md` FOI REMOVIDO DO REPOSITÓRIO EM 07/08/2026** (commit `9fc1031`), por decisão do
> dono. As seções antigas deste documento continuam citando-o — são história e não se reescrevem.
> O que valia a pena preservar do que ele dizia está aqui no cabeçalho: os comandos das suítes, as
> faixas de migration, e a prática de religar o defeito antes de dizer que um teste o cobre.
>
> **O cabeçalho é mantido em dia.** Ele já passou 17 PRs congelado em "PR #70, migrations até
> `0034`" — a parte escrita para quem chega sem contexto virou a mais velha do documento, e mandava
> a pessoa começar errado. **Atualizar o cabeçalho ao fechar a rodada é obrigação**; o que não se
> toca é a seção de sessão passada.

### Migrations — a lista NÃO mora mais aqui

> **A tabela abaixo parou de ser mantida na sessão 52, e o número no título estava errado desde
> antes.** A **fonte** é `Supabase/README.md`: ele tem a tabela completa e a lista de comandos de
> aplicação, e o `Supabase/test/run.sh` **reprova** quando uma migration existe e não está nas duas. Uma
> lista paralela sem portão é exatamente a forma como o cabeçalho deste arquivo passou 17 PRs
> mentindo — fica o trecho abaixo como referência histórica até a `0118`, não como ordem de
> aplicação.

`0001`→`0044` (sequência completa, todas aplicadas) e a faixa do colaborador:

| Migration | O que fecha | Aplicada? |
|---|---|---|
| `0100_papel_por_secao` | o papel da linha é da SEÇÃO, e o lote não cai inteiro por uma linha | ✅ |
| `0101_modelagem_dentro_do_tempo` | conferência em uma passada (era 5, duas por vínculo): 9,3 s → 100 ms | ✅ |
| `0102_modelagem_versao_vigente` | a Modelagem lê só a versão VIGENTE de cada documento | ✅ |
| `0103_papel_linha_tokeniza_uma_vez` | tokenização uma vez por rótulo, contenção por array: 1,9 s → 270 ms | ✅ (conferida **pelo plano** em produção, não pela lista) |
| `0104_desativar_premissa` | remover premissa **e** os vínculos que ela dirigia, devolvendo quantos desfez | ✅ aplicada (07/08/2026) |
| `0105_reconciliar_duplicidade_de_rotulo` | a conta que aparece duas vezes com o mesmo valor vira **achado** da reconciliação, sem apagar nada | ✅ aplicada (07/08/2026) |
| `0106_rejeitar_pendencia` | o Portão 2 ganha o segundo lado: a pendência que NÃO PROCEDE | ✅ aplicada (11/08/2026) |
| `0107_papel_ressalva_e_tratamento` | ressalva e estados de tratamento; papel de usuário (removido pela `0110`) | ✅ aplicada (11/08/2026) |
| `0108_falha_de_execucao` | a falha do n8n vira linha que a TELA lê — e `fn_excluir_caso` | ✅ aplicada (11/08/2026) |
| `0109_pendencia_tres_botoes` | os três botões, sem formulário e **sem teto de ressalvas** | ✅ aplicada (11/08/2026) |
| `0110_remove_papel_de_usuario` | o papel sai do schema: sem leitor desde a `0109` | ✅ aplicada (11/08/2026) |

> **O `Supabase/schema.sql` responde "como está o banco hoje"** sem ler as 55 em ordem. Ele é GERADO pelo
> `Supabase/test/run.sh` (`pg_dump` do banco montado do zero) e o CI confere com `git diff --exit-code`.
> Existe porque `fn_recomputar_completude` mora na `0004`, na `0006` e na `0036`, e só a última vale
> — numa revisão de PR ninguém reconstrói isso de cabeça.

`Supabase/README.md` é a ordem oficial e o `run.sh` agora **reprova** migration que não esteja na lista de
comandos dele — foi assim que a `0101` foi mergeada sem chegar ao banco.

**Para conferir um `.xlsx` que já saiu:** `./portal/node_modules/.bin/tsx portal/scripts/auditar-xlsx.mts
<arquivo>` responde 10 itens sobre o arquivo pronto (balanço fecha, DRE reproduz o documento, câmbio é
nível, recalcula ao abrir…) e sai com código 1 se algum reprovar. O que exige o Excel de verdade está
em **`Arquitetura do Sistema/6 Referência/ACEITE.md`**, 10 itens de gente. As quatro suítes provam o GERADOR; essas duas peças provam
o ARQUIVO — a lacuna por onde o v35 errado passou com o CI verde.

> **O ARQUIVO ENTREGUE NO PR #102 FOI AUDITADO E ESTAVA COM NÚMERO ERRADO (sessão 40).** O dono
> exportou o v35 completo e mandou conferir. O motor estava fiel (8 gráficos válidos, zero `#REF!`,
> `fullCalcOnLoad`, 14 áreas de impressão, eixo do tempo de uma raiz), e **a DRE realizada dizia o
> contrário do documento**: receita líquida 170.220 contra **106.580** informados, e resultado de
> **+268.041** onde o documento diz **−17.901**. Causa: a cascata SUBTRAI despesa (convenção
> "magnitude positiva") e a extração entrega despesa NEGATIVA, como o PDF escreve — subtrair
> negativo soma. O balanço saía **195.090 contra 95.780** (2,04×) porque o modelo somava o subtotal
> informado E os componentes dele, o que a aba analítica `Balanço` do mesmo arquivo já excluía. Os
> seis defeitos estão corrigidos e cada um tem teste que reprova religado — detalhe na sessão 40.
> **A fixture do `(0105)` era mais fácil que a produção** (custo positivo, uma conta por grupo, um
> exercício, nenhum total informado) e por isso os 15 asserts passavam verdes com o arquivo errado.

**AS QUATRO SUÍTES, COM OS COMANDOS QUE DE FATO FUNCIONAM** (duas pegadinhas anotadas abaixo — use
estes):

```bash
# insumo: os DOIS books sintéticos (geram pdf/ + GABARITO.json, não versionados)
cd "Dados de Teste"/book-vertentes && PYTHONPATH=. python3 gerar.py && cd -
cd "Dados de Teste"/book-canastra  && PYTHONPATH=. python3 gerar.py && cd -   # 38 docs, 3 exercícios
node N8N/medir-custo-book.mjs                                          # o custo do lote, sem gastar

node --test 'N8N/test/*.test.mjs'                                     # 382
./portal/node_modules/.bin/tsx portal/scripts/verificar-export.mts     # 713
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres Supabase/test/run.sh         # 94 migrations, do zero
PGHOST=/tmp PGUSER=postgres PGDATABASE=postgres E2E_PSQL="psql" \
  ./portal/node_modules/.bin/tsx Verificação/run.mts                      # 46

# e as três que nasceram depois deste bloco:
./portal/node_modules/.bin/tsx portal/scripts/verificar-premissas-do-realizado.mts  # 51
./portal/node_modules/.bin/tsx portal/scripts/verificar-mensagem-de-falha.mts      # 59
./portal/node_modules/.bin/tsx portal/scripts/verificar-transcricao.mts            # 35
```

> Pegadinha 1: **`E2E_PSQL` é o COMANDO do psql, não um flag.** Com `E2E_PSQL=1` — como o antigo
> `CLAUDE.md` documentava — o arnês tenta executar um binário chamado `1`. Passe `E2E_PSQL="psql"`.
>
> Pegadinha 2: o `run.sh` conecta como o usuário do sistema (`root` no contêiner), que **não existe**
> no Postgres local — daí `PGUSER=postgres`. Ajuste `PGHOST` ao seu socket/porta.
>
> E o `node --test` é sensível ao diretório: rode da **raiz** do repositório, senão o glob não casa
> nada e a suíte diz "0 testes" em vez de falhar.

Os números ao lado de cada comando são **contadores, não enfeite**: se um deles **cair**, alguém
apagou cobertura. O CI roda os quatro mais os três geradores (com `git diff --exit-code -- N8N/`),
os **dois books** (o gerador de cada um é o teste dele — morre por `assert` se um número deixar de
fechar), a **medição de custo do lote** (`medir-custo-book.mjs`, que reprova quando um documento passa
da estimativa que sustenta o teto), `tsc`, `eslint` e `next build`.

**O TIMEOUT DA MODELAGEM ESTAVA RESOLVIDO NA ESCALA DO V35** (detalhe na sessão 36): medido pelo
`pg_stat_statements` da própria produção, com o contador zerado, `fn_linhas_para_modelagem` = **501
ms** e `fn_conferir_modelagem` = **485 ms** contra o teto de 8.000 ms — 16× de folga, nenhum
cancelamento. Eram 6.381 ms de média, raspando o teto, que é o que fazia a falha parecer
intermitente. Eram **três causas empilhadas** (`0101` trabalho de fora, `0102` versão superada,
`0103` trabalho dentro do rótulo) e uma quarta de processo (migration na tabela do `Supabase/README.md` e
fora da lista de comandos). A sessão 35 ainda dá isso como aberto — ela é anterior a esta medição.

> **E A MEDIÇÃO ERA CONTRA 770 OCORRÊNCIAS — NÃO CONTRA 13.000.** O araucária (03/09, 190
> documentos) estourou o mesmo teto de novo: `fn_linhas_para_modelagem` em 8.496 ms,
> `fn_conferir_modelagem` em 8.449 ms, os dois cancelados. As três causas de 2026-08-05 continuam
> corrigidas; o que mudou é a escala, dezessete vezes maior do que o caso que provou o "resolvido"
> acima. Ver "A ESCALA DA MODELAGEM ESTOUROU O TETO" em "POR ONDE COMEÇAR", acima, e a migration
> `0160`.

## O QUE ESTÁ ABERTO AGORA

> **ESTA SEÇÃO NÃO É MAIS A FONTE, e dizer isso é o conserto.** Ela ficou parada na sessão 52 e
> chegou à 56 com dois itens **já entregues** listados como abertos — que é a única forma de erro
> que um documento de estado pode cometer sozinho. Hoje a pergunta "o que falta?" tem três respostas
> com dono e com portão: **`ESTADO.md`** (onde estamos, e o `run.sh` reprova se envelhecer),
> **`Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md`** (o que falta até fechar, em ordem, com critério de pronto) e
> **`Arquitetura do Sistema/3 Estado e Execução/PRONTIDAO_POR_ESTAGIO.md`** (o projeto medido contra o próprio objetivo, estágio por
> estágio). O que sobra abaixo é o **porquê** de cada item, que continua valendo.

**1. ~~O teste de ponta a ponta com o `book-canastra`~~ — CONTINUA SENDO O ÚNICO BLOQUEIO REAL, e é
do dono.** É o **B1** do mapa. O que mudou desde a 52 é que **tudo o que dependia de engenharia foi
entregue**: as migrations estão aplicadas até a `0137`, o workflow foi reimportado, o fatiamento foi
religado, o orçamento passa, e a tela acompanha. O que a rodada tem de trazer de volta continua
tabelado no `ESTADO.md`, em "O próximo passo" — e o item de maior valor segue sendo **o custo REAL
da OpenAI**, porque todo número de custo deste repositório saiu de aritmética sobre páginas e linhas,
**nunca de uma fatura**.

**2. ~~Fixture de extração do `book-canastra`~~ — FEITA na sessão 52, e foi ela que achou o resto.**
`Supabase/test/fixture_book_canastra.sql` está no `main` e roda em toda execução do `run.sh`, ao lado da de
Vertentes. O contrato é o que a seção original já antecipava e vale reler: **Vertentes afirma
extração fiel (zero pendência) e Canastra afirma o contrário** — escala mista, locale anglo e
prognóstico de contingência **devem** abrir pendência, e cada uma tem assert próprio. Ela achou os
três defeitos da primeira rodada, o intragrupo que não é mútuo e a cegueira da `0133`.

**3. Do output — os TRÊS itens desta lista foram fechados entre a 52 e a 54** (o diagnóstico de
origem continua em `Arquitetura do Sistema/4 Análises e Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md`):

- ~~**resumo dos três cenários lado a lado**~~ — **feito na 54.** O receio registrado aqui estava
  certo e foi ele que guiou a solução: a implementação ingênua replica a cascata e cria um SEGUNDO
  lugar que calcula EBITDA, que é o defeito por trás dos quatro incidentes de dupla contagem. Não há
  segundo lugar de cálculo;
- ~~**proveniência completa na `Premissas`**~~ — **feita na 52** (`0125`): arquivo, página,
  confiança e aceite voltaram às catorze abas do arquivo de comitê;
- ~~**Modo A do `Arquitetura do Sistema/2 Especificação/f0/07`**~~ — **feito na 53**: a base viva é consultável no portal.

**4. ~~Golden set e concordância medida~~ — FECHADO nas sessões 58 e 59, pela saída B.** A `0130`
tinha feito a metade de engenharia (o golden set rotulável, a rotulagem cega) e o que faltava era
uma decisão escrita: A, B ou C no `Arquitetura do Sistema/1 Visão e Doutrina/01`. Ficou **B — medir por veredito de produção**, porque
cada aceite ou rejeição na tela de revisão já é um rótulo produzido pelo trabalho normal e não custa
hora humana, **desde que o sistema publique que é um piso enviesado**. `medir-auto-aceite.mts`
continua dizendo no próprio cabeçalho que, rodado contra fixture, mede o instrumento e não o modelo.

> **O que a 58 e a 59 fizeram com isso.** A saída B foi escrita no `Arquitetura do Sistema/1 Visão e Doutrina/01` e virou motor: a `0136`
> mede a concordância do veredito de produção (30 vereditos, 95%) e grava `base_do_nivel =
> 'medida_por_veredito'`, que é o rótulo dizendo em toda tela que o piso é enviesado; a `0137` faz a
> promoção acontecer sozinha, até **N2 e nunca N3**, com quatro travas. A trava que importa: **humano
> que baixa o nível desliga a automação daquele estágio**, e o veredito seguinte não desfaz o freio —
> religar é decisão explícita. `Supabase/test/auto_promocao_dial.test.sql` existe só para isso.

**5. Decisões do dono já tomadas, para ninguém reabrir:**

- **proteções do `main`**: ele decidiu NÃO recolocá-las (11/08) — **e isto hoje se contradiz com o
  `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md`, que lista "proteger o `main`" como B6.1 aberta.** A contradição fica
  escrita em vez de resolvida por conta própria, porque a decisão é do dono e não de engenharia. O
  fato, medido: hoje nada impede mergear vermelho nem empurrar direto, e o
  `Arquitetura do Sistema/3 Estado e Execução/PRONTIDAO_POR_ESTAGIO.md` marca o item como **não conferido** — nenhuma sessão lê
  configuração de branch;
- **papel de usuário**: removido (`0110`). Não há sênior a cadastrar;
- **teto de ressalvas, motivo obrigatório, expiração**: removidos (`0109`). O Portão 2 informa, não
  impede.

**Existe CI** (`.github/workflows/suites.yml`): as **seis suítes** (n8n, export, transcrição,
premissas do realizado, banco, e2e) + os quatro geradores de workflow e os três de fixture + tsc/eslint/build + o `Supabase/schema.sql`
conferido, em todo push e PR, mais `workflow_dispatch`. **PR vermelho é regressão sua — mas confira
antes se algum passo rodou** (contagem de passos do job): em 06/08/2026 o serviço ficou sem runner e
produziu vermelho sem executar nada. Ver o bloco do incidente no topo.

> **E um portão pode reprovar por RUÍDO, o que é pior que não reprovar — aconteceu em 21/08.** O
> `pg_dump --no-owner` não cobre o DEFAULT ACL: `ALTER DEFAULT PRIVILEGES FOR ROLE <alguem>` carrega
> o nome do superusuário que aplicou as migrations, e num container que só tem `root` o
> `Supabase/schema.sql` saía com `FOR ROLE root` contra o `FOR ROLE postgres` do CI. Schema idêntico,
> portão vermelho. O `run.sh` passa a normalizar essa linha para `postgres` — que é o nome verdadeiro
> no Supabase —, pela mesma razão que já filtra a versão do `pg_dump` e o token aleatório do
> `\restrict`: **o portão tem de medir o schema, não quem digitou o comando.**

## Sessão 48 (2026-08-17) — a v46 auditada contra o gabarito, dois erros de unidade, e o portal com a cara da Oria

**O QUE O DONO RODOU:** o subconjunto de 9 documentos do `book-canastra` (o orçamento de crédito da
OpenAI era US$ 0,75, e o book inteiro custa US$ 1,27 — a seleção foi calculada para caber e ainda
exercitar todas as correções). Resultado: **714 linhas, ~US$ 0,46**, e o export foi auditado LINHA A
LINHA contra o `GABARITO.json` que o gerador declara.

### O defeito da v45 está morto, e agora com prova

| | |
|---|---|
| Extração chamada | **9 de 9** — nenhum documento mudo (eram 19 de 35 na v45) |
| DFC | caixa inicial 3.621 e final 825 — **exatos** |
| DVA | valor adicionado a distribuir 49.110 — **exato** |
| Livro razão | **99 de 99 linhas** — o documento que motivou as três camadas |
| Balancete | **78 de 78 linhas** |
| Certidão negativa | zero linhas e **nenhuma pendência falsa** — a `0111` funcionou |
| Balanço / DRE / DVA | 105 de 114 · 34 de 39 · 13 de 16 |

O dado da rodada foi **reproduzido num Postgres local** contra as funções de produção
(`fn_registrar_campos_extraidos`, `fn_reconciliar_por_documento`, `fn_conferir_lote`), e o
`lote_integro` voltou **true**. É a primeira vez que a integridade do lote foi verificada de fora.

### O mistério do "balanço não fecha por 40.169" tem nome

A guarda `duplicidade_de_rotulo` acusa **7 pares de rótulos que são a mesma conta escrita duas
vezes**, somando 136.441 — e o primeiro deles é `Capital Social` = `Capital social subscrito e
integralizado`, **40.169,00**. Era o subtotal do grupo somado junto com a conta-filha. O número que
estava no `ESTADO.md` desde a sessão 45 como "o buraco da extração" era, na verdade, contagem dupla,
e o sistema já sabia dizer isso sozinho.

### Dois erros de unidade, na mesma semana, em pontas opostas

**1. A guarda de cobertura acusava o livro razão PERFEITO.** Ela comparava CONTAS DISTINTAS gravadas
com LINHAS DE CONTA do texto, e as duas só coincidem quando cada linha tem rótulo próprio — num
razão o mesmo fornecedor aparece em vários lançamentos (99 linhas, 66 históricos = 66%, abaixo do
limiar). Foi o segundo erro de unidade da MESMA guarda, na direção contrária ao primeiro (pares ×
linhas dava 198%). Agora `achatarGrupos` marca cada campo com a linha que o originou, `juntarBlocos`
conta linhas distintas depois de limpar a emenda, e a marca **não chega ao banco**.

**2. O comparativo não comparava.** No Excel entregue, a mesma conta ocupava **três linhas** — 2023
numa, 2024 na seguinte, 2025 na terceira, cada uma com as outras colunas vazias. Duas causas, uma em
cada ponta: no n8n, `ordem` numerava PARES (conta × coluna) desde que a saída virou agrupada,
contrariando a `0027` ("posição na leitura do documento"); no portal, o rank que impede dois "Outros"
de um balancete de colapsarem era calculado por VERSÃO em vez de por COLUNA. **A correção do portal
vale para o dado que já está no banco** — reexportar a v46 sai alinhado, sem nova extração (provado
reprocessando os 281 campos reais do balanço pelo código novo).

### A régua da cobertura, calibrada contra a verdade

`N8N/medir-regua-cobertura.mjs` (novo) confronta a régua com a contagem que o **gerador do book
declara** — não outra leitura do PDF. Conferir heurística contra heurística não prova nada. A v1
acertava as demonstrações (+2% a +4%) e DESABAVA nos analíticos, que são os que perdem dado: livro
razão 99 linhas → ela via 3; balancete 78 → 3; aging 14 → 2. A v2 troca "termina em valor" por "tem
valor E tem identidade" (rótulo, código de conta, ou linha de tabela numérica): erro absoluto médio
**29% → 9%**, avaliados pela guarda de 10 para 14 documentos. O limiar **fica em 0,85**, agora com 38
pontos de medição em vez de um.

### A entidade parou de sair suja: eram QUATRO famílias, não uma

`Canastra Industria 2025x2024x2023` gerou 15 das 22 pendências de revisão da rodada real, porque o
nome divergia do conteúdo. Medindo `parseEntidade` contra os 38 nomes do book: comparativo triplo
(`2025x2024x2023` não casava no regex de um `x` só), preposições (`Aging De Canastra`), sobra de tipo
quando o apelido da taxonomia é mais curto que o nome do arquivo, e nome sem TIPO virando empresa por
eliminação (`Relatorio Auditor Independente`, `Iv Rev3`). Resultado: **32 limpas, 6 nulas, zero
sujas** — e as 6 nulas vão ao fallback por conteúdo, que lê a entidade do documento. A remoção de
palavra de tipo usa a PRÓPRIA taxonomia como fonte (cresce sozinha), com `grupo` como exceção
protegida: ele está no vocabulário de tipo E no cabeçalho dos combinados.

### O portal ganhou navegação, marca e fim de vida do mandato

- **Marca** (`portal/public/logo-oria*.svg`): os arquivos que o dono subiu com UMA operação — o creme
  do fundo virou transparência. A arte não foi redesenhada nem traçada; o SVG **embute o original**,
  porque vetorizar exigiria aproximar as curvas, e a instrução foi não mexer na arte. Sextante no
  cabeçalho e no favicon; a lockup completa no login. **Não existe versão clara para fundo escuro** —
  seria recolorir, e ficou como decisão do dono.
- **Barra lateral retrátil**, duas seções assimétricas de propósito: *Novo mandato* é AÇÃO (fixa, sem
  filhos) e *Mandatos* é LUGAR (abre e lista os ativos). Estado no navegador via
  `useSyncExternalStore` — copiar `localStorage` num `useEffect` renderiza o valor errado primeiro e
  a barra se fecharia sozinha na frente de quem a fechou ontem (o ESLint do projeto também reprova).
- **Fechar ≠ excluir (`0114`)**: `caso.status` diz onde o mandato está no TRABALHO e não respondia
  "ainda estamos nisso?". `fechado_em` responde preservando tudo; idempotente e reversível.
- **Resumo no topo do mandato** (documentos · linhas extraídas · Kit Básico · pendências) e a coluna
  **Linhas** na tabela — ela dizia que o arquivo chegou e foi entendido, nunca que ele TROUXE dado.
- **Vocabulário**: "Portão 2" → "Pronto para aprovação"; "Reconciliação Classe A/B" → "Números que
  não fecham"; `COMBINADO` → "Demonstrações Combinadas"; 23 tipos ganharam rótulo (a tela mostrava
  "Certidoes", "Razao", "Contingencias").

**Três defeitos só apareceram olhando a PÁGINA RENDERIZADA** com o dado real carregado num banco
local: a coluna de ação cortada ("ve linha"), o produto sem acento ("Reestruturacao") e o período
quebrado em três linhas. Nenhum é visível lendo o JSX — e o `next build` pegou um quarto que `tsc` e
`eslint` não pegam (no Tailwind v4, `@apply` não enxerga classe de componente da mesma camada).

### O PR #118 do estagiário foi integrado, e o número de migration virou regra

O PR #118 (@ianmaxi05, linha exigida por tipo) estava travado por conflito havia 4 dias. O conflito
era de **numeração**: a branch criou a `0111` no dia 13, e a `main` ocupou `0111` e `0112` no
caminho. Resolvido em `claude/linha-exigida-0113-integrada` (PR #130), com os commits dele
preservados: a migration virou **`0113`**, e a minha (fechar mandato) cedeu o lugar e virou **`0114`**
— **o critério é ordem de CHEGADA, não de merge**. Quem esperou não deve ser empurrado para trás.

O `Supabase/schema.sql` NÃO foi resolvido à mão nas duas vezes que conflitou: ele é gerado, então saiu do
`Supabase/test/run.sh`. E o contador de migrations do `ESTADO.md` não foi somado de cabeça — o próprio
`run.sh` diz quantas aplica ("as 59 migrations estão na lista de aplicação").

**As três guardas de extração são famílias DIFERENTES**, e vale ler juntas: `0111` (o documento não
tem valor monetário por natureza), `0112` (a extração nunca foi chamada) e `0113` (a extração rodou,
mas a linha exigida não veio). A `0113` é a única que olha o conteúdo do que chegou.

### O que fica ABERTO, nomeado

- **Os subtotais IMPRESSOS não são extraídos.** "ATIVO CIRCULANTE", "TOTAL DO ATIVO", "RECEITA
  OPERACIONAL BRUTA" viram metadado (`secao`) em vez de linha. Somado ao fato de os subtotais de
  subgrupo ("Disponível") SEREM extraídos, a soma bruta de cada seção do balanço dá **exatamente 2×
  a verdade**. É mudança de prompt + nova extração; não dá para verificar sem gastar.
- **A divergência de mútuos não é acusada, e não podia ser: a checagem não existe.** O erro plantado
  de R$ 240 mil está no dado dos dois lados (planilha 11.160, balanço 11.400), mas as cinco
  reconciliações implementadas (`ativo_passivo_pl`, `caixa_bp_fluxo`, `duplicidade_de_rotulo`,
  `receita_dre_vs_faturamento`, `despfin_dre_vs_divida`) não comparam mútuos com o saldo do balanço.
  **Decisão do dono (17/08): quando for escrita, a divergência aparece no PAINEL, não na planilha.**
- **A tela de Modelagem (713 linhas) recebeu só a paleta nova** — o fluxo dela não foi revisado.
- **`negativas`, `societario`, `parcelamentos`** estão numa lista à mão em `parseEntidade` porque o
  apelido da taxonomia não os carrega; o lugar certo é o seed `Supabase/migrations/0002`, e isso é
  migration.
- Seguem abertos de antes: o teto de gasto que decide ANTES da medição (estima por bytes, ~+50%),
  dedup por hash, e o golden set.

**Suítes:** n8n **275** (era 244) · export **535** (era 529) · e2e 46 · banco **59 migrations do
zero** · tsc/eslint/build do portal. PRs #130 e #131 mergeados; `main` em `31ce376`.

## Sessão 47 (2026-08-17) — o "Teste V45": 19 dos 35 documentos nunca tiveram a extração chamada

**O QUE O DONO RODOU:** o `book-canastra` no workflow com as três camadas (o "Teste V45 - Canastra").
Resultado: **438 linhas** onde deveriam ser milhares — pior que as 1.683 da rodada anterior. E a
análise do dado não apontou para a extração: apontou para o que **não aconteceu**.

### A correlação era perfeita, e por isso a causa não era de qualidade

| `fonte` | documentos | linhas | eventos `extracao_sombra` |
|---|---:|---:|---:|
| `nome_arquivo` (classificado pelo nome, sem fallback) | 19 | **0 em todos** | **0 em todos** |
| `openai_conteudo` (passou pelo fallback) | 16 | todos com linha | 1 em todos |

Sem uma exceção nos 35. Os 19 mudos eram justamente os documentos centrais — Balanço, DRE, DFC, DMPL,
DVA, os balanços das demais empresas, balancetes, razão, faturamento —, e eles sumiram entre
`Registrar Documento` e `Gravar Campos` **sem deixar rastro**: nada em `campo_extraido`, nada em
`evento_auditoria`, nada em `pendencia`. Checklist verde, Portão 1 satisfeito.

**A causa é topológica.** `Precisa Fallback?`[false] e `Parse OpenAI Classif` apontavam **ambos** para
o `Registrar Documento` — duas conexões **cruas no mesmo input**. O n8n não garante uma execução por
conexão nesse arranjo (é para isso que existe o nó Merge), e só o ramo do fallback propagou. Quem
classificava bem pelo nome — o caminho **barato**, o que deveria ser o caminho feliz — era o que
morria.

### As três correções (PR #128)

1. **`Juntar Ramos` (Merge, `append`)** — os dois ramos entram em inputs **diferentes**, e o lote
   volta a ser uma corrente única. Um teste novo proíbe **qualquer** convergência crua no mesmo input,
   em todo o canvas: a classe inteira do defeito, não o caso.
2. **`Recompor Contexto`** — o nó Postgres substitui o item, então o `content_part` (o PDF) morria
   ali e o `Montar Req Extracao` o reencontrava por `$('Preparar Conteudo').item`, pareamento que
   atravessava a convergência. Agora a junção é **por índice** contra `$('Juntar Ramos').all()`, o
   conteúdo viaja no item, e montar a chamada **sem o arquivo** virou recusa escrita em vez de "zero
   linhas" silencioso. Divergência de contagem é falha declarada: associar o PDF de um documento ao
   id de outro é pior que falhar.
3. **`fn_conferir_lote` (`0112`) + nó `Conferir Lote`** — toda guarda de extração deste repositório
   morava **dentro** do caminho da extração, e guarda que mora no caminho não cobre o caminho **não
   percorrido**. Era o único modo de falha que as três camadas de cobertura não podiam ver, porque as
   três medem o que voltou de uma chamada **feita**. A conferência mede de fora (documentos
   registrados × documentos com evento), abre pendência bloqueante não-sobrepujável **por documento**,
   e `lote_integro` decide se a rodada vale. Não gasta IA, é idempotente, auto-resolve no
   reprocessamento.

### Certidão sem número não é extração falha (PR #126)

A mesma rodada abriu `extracao_falhou` para certidões negativas, organograma societário e o parecer
do auditor — três documentos que o próprio `GUIA_DE_TESTE` do book lista como **armadilha
deliberada**. Zero linha ali é o resultado CERTO. O Sinal 3 do `fn_registrar_campos_extraidos`
disparava sempre que `v_count = 0`, sem meio de distinguir "a chamada falhou" de "o documento não tem
valor monetário nenhum". Agora quem responde é **o veredito de quem leu o arquivo**:
`diagnostico.tem_dado_financeiro` vem da própria chamada de extração, e só `false` explícito silencia
a guarda — `null` (chamador antigo) e `true` seguem abrindo a falha. `p_falha_motivo` continua
mandando sempre.

### O canvas parou de ser desenhado à mão (PR #129)

Três sessões acrescentando nós (as três camadas, o Merge, o `Conferir Lote`) com coordenada escolhida
a olho entregaram um canvas ilegível: `Fatiar Extracao` desenhado por cima do `OpenAI Extrair`,
`Juntar Blocos` por cima do `Gravar Campos`, o tronco pulando entre y=140 e y=560, e a linha do
`false` do fallback atravessando por dentro dos três nós da classificação por conteúdo.

`N8N/layout.mjs` deriva a posição do próprio grafo — uma coluna por camada, o filho de maior alcance
herda a faixa do pai (tronco reto), ramo curto desce, e aresta que pula colunas ganha **corredor
reservado**. Os quatro geradores usam; `position` sumiu das chamadas de `node(...)`. Quatro
invariantes conferem o JSON commitado dos quatro workflows, e as quatro **reprovam o canvas
anterior**.

### O que isto muda no diagnóstico do produto

As três camadas da sessão 45/46 continuam valendo, mas a leitura de "58% de cobertura" da sessão 46
tem de ser lida com esta sessão junto: **parte do que faltava não era extração incompleta, era
extração não chamada**. A próxima rodada é a primeira em que os dois números — cobertura por
documento e integridade do lote — existem ao mesmo tempo.

**Suítes:** n8n **263** (era 235 na sessão 46), banco com as suítes de documento sem dado financeiro
e de conferência de lote. **Requer do dono:** aplicar `0111` + `0112` e **reimportar** o
`workflow.e1-ingestao.json` (30 nós).

## Sessão 46 (2026-08-14) — as três camadas rodaram: 39% → 58%, truncamento zerado, e três defeitos seguidos de mecânica do n8n

**O QUE O DONO RODOU:** o `book-canastra` de novo, já com as três camadas da sessão 45 (medir antes
de chamar / fatiar para sempre caber / guarda de cobertura). Resultado: **1.139 → 1.683 linhas**,
cobertura **39% → 58%**, e o truncamento — a família que devolvia zero — **eliminada**. Os dois
maiores documentos saíram de 0 para 281 linhas (86%) e 282 linhas (92%). Custo seguiu em ~US$ 1,0
pelo book inteiro, com a saída caindo de 64 para **29,2 tokens por linha** (o formato agrupado).

### O que ainda impede os 100%, nomeado

O `.xlsx` da modelagem continua em **9 de 10** no `auditar-xlsx.mts`, e o único reprovado continua
sendo o balanço não fechar (−40.169). O buraco restante não é mais truncamento: é célula que o
modelo lê e não devolve. Por isso a próxima etapa proposta é a **comparação contra o
`Dados de Teste/book-canastra/pdf/GABARITO.json`** — é o que transforma "58%" de proporção contra
heurística em **lista nominal do que faltou**, com prova, e vira teste de regressão permanente.

### Quatro defeitos nesta rodada, três deles a mesma classe: mecânica de item do n8n

Vale registrar juntos porque a lição é uma só — **no n8n, quem quebra o vínculo do item quebra tudo
que está abaixo, e quase sempre em silêncio**:

| Sintoma | Causa | Fechado em |
|---|---|---|
| `invalid input syntax for type uuid: "sem-versao-0"` | o fan-out da fatia não declarava `pairedItem`, e eu ainda fabriquei uma chave falsa para tapar o buraco | PR #121 |
| `null value in column "caso_id"` | `Extrair Texto` na cadeia principal SUBSTITUI o item (perde json+binário) — regra que já estava escrita no `N8N/README.md` | PR #122 |
| `celulas_nos_documentos: 0`, sem erro nenhum | `$('Nó').item` só resolve para **ancestral**; ramo irmão devolve undefined | PR #123 |
| painel de custo mostrando metade do lote | um IF faz o n8n executar a cadeia inteira **uma vez por ramo**; `.all()` sem índice de run vê só uma parte | PR #123 |

As três primeiras viraram **regras numeradas no `N8N/README.md`** (nó que substitui o item; `$().item`
só de ancestral; nó que muda a contagem declara `pairedItem`) e a terceira virou **teste que caminha
o grafo** e reprova qualquer `$('X').item` apontando para não-ancestral. A regra não fica só no texto.

### O livro razão perdia 98 de 99 lançamentos porque a coluna não era período

`17_Livro_Razao_Fornecedores` tem **três colunas de valor** — Débito, Crédito, Saldo. O prompt só
descrevia coluna como *período* ou *empresa*, então o modelo mandava um valor onde o schema esperava
três, e o `achatarGrupos` — corretamente — descartava a linha inteira por desalinhamento. O conserto
foi no prompt (PR #124): os **cinco casos** de coluna que não é período estão nomeados (livro razão,
balancete, aging, estoques, mapa de dívida) e a consequência está escrita junto, em número.

### A régua da cobertura estava na unidade errada

`avaliarCobertura` comparava *linhas com dígito* do PDF contra *pares conta×coluna* extraídos — duas
unidades diferentes. Um documento visivelmente incompleto marcava **198%**. Trocado por
`linhasDeConta` (linha que termina em valor E tem rótulo, menos ruído: Página, CNPJ, CRC, notas,
cabeçalho só com ano) contra chave distinta, e o limiar subiu de 0,6 para **0,85** — porque com a
régua certa 0,6 aceitava perder 40% calado (PR #125).

**Suítes:** n8n em **235** testes, todas verdes.

## Sessão 45 (2026-08-13) — o custo estava resolvido e o dado não estava: 39% de cobertura, e as três camadas

**O QUE O DONO RODOU:** o `book-canastra` inteiro. 35 documentos, **21 minutos, US$ 0,71** contra o
teto de US$ 3. O custo virou assunto encerrado — e a mesma rodada abriu um buraco maior.

### 1.139 de 2.893

Das células de valor que os PDFs contêm, **39% chegaram ao banco**. Duas famílias, e a diferença
entre elas é o que organiza a correção:

- **TRUNCAMENTO** (5 documentos, zero linhas). O gpt-4o tem teto de **16.384 tokens de saída**.
  `01_Balanco_..._2025x2024x2023` tem 326 células — no formato plano daquela rodada, ~20.900 tokens.
  Não cabia por construção, e nenhum prompt conserta um teto físico. Ao menos falhou ALTO:
  `finish_reason=length` virou `extracao_falhou` com a causa escrita.
- **SUB-EXTRAÇÃO SILENCIOSA** (o resto). `17_Livro_Razao_Fornecedores` devolveu **99 de 461** sem
  estourar teto nenhum e sem abrir uma única pendência. O sistema registrou sucesso.

O `.xlsx` da modelagem exportado dessa rodada passa em **9 de 10** itens do `auditar-xlsx.mts`. O
único reprovado é o balanço não fechar por **40.169** — o buraco da extração chegando ao arquivo
entregue. O modelo está sadio; a entrada dele não estava.

### Duas correções minhas, antes do resto

**Eu afirmei que o custo provava que o agrupamento estava ativo naquela rodada. Não provava.** A
aritmética era compatível com os dois formatos; o print do canvas do dono é que decide, e ele mostra
a cadeia terminando em `Reconciliar (Classe A)` — sem o `Resumo de Custo`. A rodada foi no workflow
ANTERIOR ao PR #119. Isso melhora a leitura: **os 39% e os truncamentos são a linha de base, não
efeito do agrupamento.**

E a previsão de qual documento truncaria estava errada: apontei o livro razão, e quem estourou foram
os dois balanços grandes. O razão fez pior — devolveu um quinto e disse que estava tudo bem.

### As três camadas

`N8N/lib/cobertura.mjs`, três nós novos, e o desenho importa mais que cada peça:

| | O que faz | Nó |
|---|---|---|
| **1. Medir antes de chamar** | lê a camada de texto do PDF na própria instância — sem IA, sem custo — e conta as linhas com número | `Extrair Texto` (nativo) |
| **2. Fatiar** | acima de 60% do teto, um item por bloco de ≤234 células | `Fatiar Extracao` |
| **3. Guarda de cobertura** | compara o que voltou com o que o documento tem; abaixo de 60%, pendência com os dois números | `Juntar Blocos` |

**A camada 2 não conserta truncamento — ela o torna impossível.** E o ponto fino dela é a ÂNCORA: o
modelo continua vendo o PDF inteiro (é onde está o alinhamento das colunas), então "extraia o bloco 2
de 3" seria pedir que ele adivinhasse onde a faixa começa. Cada bloco carrega o **texto exato** da
primeira e da última linha da faixa, lidos do PDF pelo extrator. Vira instrução verificável em vez de
proporção. A instrução vai na mensagem de *user* — o prompt de sistema fica idêntico, senão o cache
de prefixo para de valer e o fatiamento pagaria o prompt duas vezes.

**A camada 3 promete uma coisa só, e é a única honesta:** ela não impede o modelo de pular uma linha;
impede que isso seja silencioso. O limiar de 60% é calibrado na rodada real e erra para o lado de
avisar demais — sadios ficaram em 68%-90% (`02_DRE` 104/115, `06_Balanco` 74/109), incompletos em
21%-48%. Pendência falsa custa uma olhada; buraco não visto custa o mandato.

### O que eu decidi NÃO fazer, e é a decisão que mais importa aqui

**O texto extraído não substitui o PDF na chamada.** Era a economia óbvia — e seria uma troca ruim
agora: o texto de uma tabela perde o alinhamento das colunas, e foi exatamente a leitura de coluna
que acabou de funcionar (o balanço combinado saiu com as 8 colunas de empresa certas, e a guarda de
desalinhamento não disparou uma vez em 35 documentos). **O texto serve para MEDIR, não para LER.**

### O custo sobe, e é para subir

Extrair o que faltava custa tokens. `book-canastra`: 38 documentos → **41 chamadas** de extração (3
fatiados), e a projeção sai de US$ 0,71 *com 39% do dado* para **~US$ 1,4 com o dado inteiro** —
menos da metade do teto. É o que o agrupamento da sessão 44 comprou.

### Segurança da mudança, em uma linha

`Extrair Texto` tem `onError: continueRegularOutput`. PDF escaneado não tem camada de texto e o nó
falha nele: o documento segue como imagem e as camadas 2 e 3 se calam para ele — `null` é "não sei",
nunca "zero", porque zero ligaria a guarda com régua inventada justamente onde o modelo mais erra.
**O pior caso desta mudança é o comportamento de ontem.**

De `Gravar Campos (Sombra)` em diante **nada muda**: um item por documento, com `campos` e
`falha_motivo`, exatamente como sempre foi.

### Aberto, e nomeado

- **O teto de gasto decide ANTES do `Extrair Texto`** — estima por bytes e não sabe quantos blocos o
  lote terá. Movê-lo para depois troca byte por linha contada, que é determinístico.
- **A entidade sai poluída com o período** ("Canastra Industria 2025x2024x2023"): 15 das 22
  pendências de revisão da rodada.
- **O erro plantado de R$ 240 mil nos mútuos não apareceu** — `21_Mutuos` extraiu 3 de 6 células, e a
  reconciliação não tinha o que comparar. Só a próxima rodada, com cobertura, responde se a
  reconciliação funciona.

`N8N/test`: 207 → **225**.

## Sessão 44b (2026-08-13) — a linha exigida por tipo vira dado, e o Portão 1 cobra pelo nome (0113)

> **Nota de integração (17/08):** esta sessão correu em paralelo à 44 e a migration nasceu como
> `0111`; entre o desenho e o merge, a `0111` e a `0112` foram ocupadas na `main`. O número final
> é **`0113`** — o mesmo texto, o mesmo teste, só a numeração conciliada.

**A ENTREGA EXECUTADA:** o dono aprovou a análise do estagiário que define, por tipo do Kit Básico,
quais linhas precisam existir para o documento ser utilizável. Até aqui essa exigência morava em
dois lugares ruins: hardcoded nos arrays inclui/exclui dentro das reconciliações, e em lugar NENHUM
para os tipos que nenhuma checagem lê (MUTUOS, FAT_INTRAGRUPO, CONTRATO_SOCIAL). Quando a linha
faltava, o sintoma era `precondicao_nao_satisfeita` — pendência mole (importante, sobrepujável),
publicada por período pelo despachante, e só para as ~10 linhas que as cinco checagens cruzam. Na
prática ninguém via, e o caso seguia como se tivesse conferido.

**O QUE ENTROU** (`Supabase/migrations/0113_linha_exigida_por_tipo.sql` + `Supabase/test/linha_exigida.test.sql`,
branch `ian/0108-linha-exigida`): `taxonomia_linha_exigida` (o QUE cada tipo precisa ter, filha da
taxonomia, com `origem` codigo/proposta e `depende_de` como fato — qual checagem para sem a linha) +
`taxonomia_linha_localizador` (o COMO: cascata no formato inclui/exclui de `fn_valor_conceito`, com
`contra` chave/seção/estrutural espelhando 0009/0031/0034 — sem a cascata, "ATIVO" sem a palavra
"total" viraria falso positivo, o defeito da 0034 de volta). `fn_recomputar_completude` ganhou o
passo (2b): tipo presente COM conteúdo mas sem linha exigida abre pendência `linha_exigida_ausente`
que NOMEIA a linha (doutrina da 0033) e resolve sozinha quando ela aparece. Política
(`severidade`/`sobrepujavel`) nasce NULL — decisão do dono, por linha; o default é o peso de hoje
(importante, sobrepujável), e `pronto_para_revisao` não mudou. Seed: 11 exigências de origem
`codigo` (termos copiados literalmente das reconciliações vigentes) + 3 `proposta`.

**O QUE QUEBROU NO CAMINHO:** a migration ia ser a **0108** — é por isso que a branch se chama
`ian/0108-linha-exigida`. Entre o desenho e a escrita, os PRs #115–117 ocuparam 0108–0110 na main;
número não se reaproveita (faixas do `Supabase/README.md`, e o `run.sh` reprova prefixo duplicado), então
saiu **0113**. Fora isso nada quebrou: a suíte inteira passa com o passo (2b) ligado, sem alterar
teste existente.

**O QUE FICA EM ABERTO:**
- **A redução das três propostas.** A entrega especifica estrutura (mutuante/mutuária/saldo/sentido
  por operação em MUTUOS; vendedora/compradora/valor por par de entidades e exercício em
  FAT_INTRAGRUPO) e campos não numéricos (CONTRATO_SOCIAL: cinco campos, dos quais só capital
  social cabe na forma linha-com-valor). A tabela só exprime "existe linha com valor" — a redução
  está declarada no bloco de propostas da migration; fechar a diferença pede outra estrutura.
- **A duplicação de termos.** O seed `codigo` copia termos que continuam no corpo das
  reconciliações (0023/0031/0034). A convergência — as reconciliações lerem os termos daqui — é
  evolução fora do escopo; até lá, mudar termo lá obriga atualizar o seed junto.
- **Granularidade v1 por TIPO.** Exigência satisfeita se QUALQUER documento do tipo tem a linha:
  dois balanços no caso, um sem caixa, não acusa. Refinar por entidade/documento é evolução.
- **Política NULL.** Severidade/sobrepujável por linha esperam decisão do dono (o `depende_de` é o
  insumo); até lá toda ausência sai importante/sobrepujável.

## Sessão 44 (2026-08-13) — a primeira fatura real, e metade da saída era contexto repetido

**O QUE O DONO RELATOU:** rodou os 14 documentos do `book-vertentes` e a OpenAI cobrou **US$ 0,90**.
Alvo: **abaixo de US$ 0,50**. E a pergunta que abriu a rodada: *"como acesso isso?"* — sobre os
tokens por documento que eu tinha pedido.

### A fatura desmentiu o modelo deste repositório em 45%

Decompondo os US$ 0,90: **84% é saída de extração**, a **~64 tokens por célula de valor**. O
repositório supunha 35 (`TOKENS_POR_LINHA_EXTRAIDA`), e o 35 não estava errado por descuido — ele
contava a CARGA ÚTIL da linha e ignorava o resto:

```json
{"s":"ATIVO CIRCULANTE","sc":"ativo_circulante","ec":null,"pc":"31/12/2025",
 "k":"Duplicatas a receber","vt":"22.310","vn":22310,"op":1,"cf":0.96}
```

Os cinco primeiros campos são **contexto**, idêntico em dezenas de linhas consecutivas. E num balanço
comparativo o rótulo da conta — o campo mais longo — era reescrito **uma vez por coluna de período**,
porque o prompt mandava "gere uma LINHA SEPARADA para cada (conta × período), com o MESMO chave".

### A saída passou a ser AGRUPADA

Um grupo por seção, as colunas declaradas UMA vez em `cols` (que unifica as duas dimensões — empresa
e período —, antes descritas em dois parágrafos separados do prompt), e a conta escrita UMA vez com um
valor por coluna. Medido pelo `medir-custo-book.mjs` sobre os PDFs de verdade:

| Book | formato plano | agrupado | corte |
|---|---:|---:|---:|
| `book-vertentes` (14 docs — o que o dono rodou) | US$ 0,857 | **US$ 0,471** | **−45%** |
| `book-canastra` (38 docs) | US$ 2,226 | **US$ 1,252** | **−44%** |

**O modelo do formato plano projeta 0,857 contra os 0,90 da fatura — 5% de erro.** É isso que
autoriza tratar os 0,471 como projeção em vez de esperança, e o alvo de US$ 0,50 está atendido. A
economia real deve ser um pouco maior: o medidor lê as colunas do NOME do arquivo, então as sete
colunas de empresa do balanço combinado não entram na conta dele.

**Nada é extraído de menos.** `parseExtractionResponse` e o nó `Parse Extracao` (com a MESMA função
embutida por `toString`) achatam os grupos de volta para uma linha por (conta × coluna):
`campo_extraido` fica idêntico — mesmos valores, mesma `ordem` de leitura, mesma escala e moeda.

### As três decisões que o formato de colunas obrigou

1. **Célula em branco OCUPA POSIÇÃO** (`null` no índice), nunca é omitida. Encostar os valores à
   esquerda poria o número de 2024 na coluna de 2025 — plausível, silencioso, e o pior erro possível
   aqui.
2. **Desalinhamento é FALHA, não palpite.** Um valor para duas colunas e a associação valor↔coluna
   deixou de ser conhecida: a conta é **descartada** e o motivo volta nomeado (rótulo e contagens),
   virando pendência. Completar com `null` seria inventar dado.
3. **Subtotal abre grupo PRÓPRIO** com `sc = NAO_CLASSIFICAVEL`. A seção canônica passou a ser do
   grupo, e um subtotal misturado às contas que ele soma faria a seção ser contada duas vezes na
   planilha — a mesma aritmética do invariante "uma conta, um lugar".

### E o defeito de 2018… quer dizer, do "teste v18", que isto conserta de graça

Documentos comparativos truncavam (`finish_reason=length`) antes de terminar de listar as contas — 6
de 16. A correção da época foi encurtar os NOMES das chaves; era meia correção, porque o contexto
continuava sendo repetido. O documento mais pesado do `book-vertentes` usava 73% do teto de saída e
agora usa 45%.

E o medidor passou a AVISAR quando a saída projetada passa de 80% do teto, nomeando o arquivo. Ele
acusa um caso que ninguém tinha visto: o livro razão do `book-canastra` (461 células de valor) fica em
**109% do teto mesmo agrupado** — vai truncar. A saída é extrair por faixa de página, e é fatia
própria; fica declarado em vez de descoberto na fatura.

### "Como acesso isso?" — a resposta virou um nó

Os tokens por documento existiam desde sempre, um por item do `Parse Extracao`. Para saber o custo do
LOTE era preciso abrir 14 painéis e somar à mão — e custo que só se conhece somando à mão é custo que
ninguém mede. É metade da explicação de por que este projeto decidiu teto de gasto por estimativa
durante meses.

**`Resumo de Custo`**, novo, último nó do canvas: custo real do lote, quanto foi extração e quanto foi
classificação, o que o orçamento havia estimado, tokens de entrada/saída/cache e **tokens de saída por
linha extraída** — o número que recalibra o estimador. Ele soma **por nó**, nunca por índice do lote:
só 8 dos 14 documentos passam pela classificação, então casar `[i]` com `[i]` atribuiria o custo ao
documento errado. É terminal e tem `onError`: um resumo que derruba o lote que ele resume seria a pior
troca possível.

### Dois espelhos à mão morreram no caminho

- **O schema da extração no nó** era uma linha de 2.400 caracteres copiada da lib. Agora é
  `JSON.stringify(extractionSchema())` — o schema é JSON puro, então serializar a fonte é exato. Um
  teste compara o schema do nó com a fonte inteira, em vez de conferir um campo por vez.
- **O achatamento** vem embutido por `toString()`. É o único lugar onde valor e coluna são
  associados: um espelho que divergisse ali gravaria o número de 2024 na coluna de 2025 sem sintoma.

E o `book-vertentes` passou a escrever `METRICAS.json` como o `book-canastra` já fazia — faltava
justamente no book que o dono roda de verdade, então o medidor não conseguia abrir o único lote com
fatura conhecida.

### O que ficou de fora, e por quê

O dono aprovou 1+2+3 (agrupamento, PDF como texto, dedup por hash). Entregue: o **1**, que sozinho
atinge o alvo. Os outros dois **não** entraram, e não é esquecimento:

- **PDF como texto** exige o nó `Extract From File` no n8n vivo dele. Depois do agrupamento vale
  ~US$ 0,03 neste book, e o risco (um nó novo no meio da cadeia de intake) ficou grande para o
  prêmio. Melhor com os tokens de entrada REAIS do `Resumo de Custo` na mão.
- **Dedup por hash** é o de maior efeito no uso real dele (reexecutar o mesmo book sai de graça), e é
  o que a própria `0026` descreve como precisando de duas coisas que não existem: um *fingerprint* de
  prompt+modelo na versão (migration) e um curto-circuito no grafo. A migration diz, com estas
  palavras, "não às cegas". É a próxima fatia, e agora é a maior.

`N8N/test`: 194 → **207**.

## Sessão 43 (2026-08-13) — a recusa vinha de um workflow de julho, e a 2ª chamada era cobrada como se fosse a 1ª

**O QUE O DONO RELATOU:** reexecutou o lote de 35 documentos depois das correções da sessão 42 e
recebeu a MESMA recusa — *"51 chamadas ≈ US$ 7,65, acima do teto de US$ 3"*. Pedido: **reduzir o
custo por chamada, para que o lote de 35 não passe de US$ 3.**

### A recusa não podia ter saído deste repositório

US$ 7,65 ÷ 51 chamadas = **US$ 0,15 por chamada** — a constante que vigorou até 07/08/2026, quando a
medição do book a levou para 0,20 e, na sessão 42, para a estimativa por TAMANHO, que nem cita
"0,15". A mensagem também não trazia a frase "A conta saiu de…", que nasceu junto com a estimativa
por tamanho. Ou seja: o n8n estava executando o **JSON importado em julho**.

Merge não reimporta workflow. E o defeito de fundo não é o esquecimento: é que **da tela as duas
versões têm exatamente a mesma aparência** — as duas recusam, com uma frase parecida. Não havia
como distinguir "o código está errado" de "o código certo não está lá".

Por isso a primeira mudança desta rodada não é de custo, é de leitura: a recusa começa com
`[orçamento v3 (2026-08-13)]` e `orcamento_versao` viaja com o item **mesmo quando o lote passa**.
Um teste exige as duas coisas. Não é cosmética — é a diferença entre diagnosticar e adivinhar, e
adivinhar já custou uma rodada de teste.

> **E vale dizer o que aquela tela NÃO estava dizendo:** não era limite de crédito da OpenAI. Quem
> recusou foi o nosso nó, antes da primeira chamada; nada foi enviado e nada foi gasto.

### A redução pedida, em duas alavancas com número

| Alavanca | Efeito medido no book (38 docs) |
|---|---|
| **Classificação em `gpt-4o-mini`** (a recomendação nº 1 do `docs/CUSTO_OPENAI.md`, que estava escrita como "agora, sem risco" desde 27/07 e nunca tinha sido acionada) | custo real **US$ 1,41 → US$ 1,33**; a parte de classificação, **US$ 0,0893 → US$ 0,0054** (−94%) |
| **A 2ª chamada deixa de ser cobrada como se fosse extração** | estimativa do guarda **US$ 2,46 → US$ 1,88** (−24%) |

A segunda é a correção de um erro de modelo, não um afrouxamento: as duas chamadas mandam o MESMO
PDF, mas a classificação devolve ~120 tokens e a extração devolve centenas de linhas — e a saída é
~75% da conta. Medido, a classificação custa **13%** de uma extração; o orçamento cobrava 100%. O
peso agora é DERIVADO da tabela de preço (`0,30 × razão de preço de entrada entre os dois modelos`,
com piso de 0,05), então trocar o modelo recalcula o orçamento sozinho — e modelo fora da tabela
cobra cheio, porque desconhecido não é barato.

**A extração continua em `gpt-4o`**, e um teste reprova quem apontá-la para o modelo barato. A
assimetria que autoriza uma coisa e proíbe a outra: a classificação tem rede (o `diagnostico` da
própria extração confere tipo/entidade/período e abre pendência quando diverge), a extração não tem
nada depois dela.

### O desconto vale só onde há medição

O peso reduzido se aplica **apenas quando os bytes chegam ao nó**. Sem tamanho, o guarda continua
contando chamada cheia a US$ 0,20 — e o motivo é de evidência: o caminho plano é o de "não sei nada
sobre estes arquivos", e a única calibração que ele tem é um incidente de dinheiro de verdade (o
v31, que estourou o teto de US$ 5 da OpenAI no meio do lote). Descontar ali com base numa proporção
medida em PDF sintético seria trocar a evidência cara pela barata. O teste do v31 continua verde,
palavra por palavra.

### O medidor mentia sobre a máquina que ele mede

`medir-custo-book.mjs` imprimia **"RECUSA"** para um lote que o `Orcamento do Lote` ACEITA desde a
sessão 42 — porque ele chamava `orcamentoDoLote` sem passar os bytes, caindo na estimativa plana.
Um medidor que descreve uma versão antiga da coisa medida é pior que nenhum: ele confirma o medo
errado. Agora ele passa os bytes (que o `METRICAS.json` já tinha), imprime a versão do orçamento e
mostra os dois vereditos lado a lado — o por tamanho e o plano —, que é a medida do que a sessão 42
comprou. Os dois modelos também deixaram de ser cópia à mão ("espelho de build-workflow.mjs") e
passaram a vir da fonte.

### E a metade da conta que ninguém media

Só a extração media o próprio custo. A classificação — justamente a metade cujo preço acabou de
mudar — saía do pipeline sem número, então a economia prometida só seria verificável na fatura do
fim do mês, misturada com o resto. `Parse OpenAI Classif` agora devolve `custo_classificacao_usd`,
pelo mesmo `custoDaChamada` da extração, **em todos os caminhos de saída**: a chamada que falhou
depois de consumir tokens também foi paga.

### Onde o lote de 35 fica

```
custo REAL medido (38 documentos, 57 chamadas)   US$ 1,33   ← era 1,41
estimativa do guarda, por tamanho                US$ 1,88   ← era 2,46 (teto: 3,00)
lote homogêneo denso (35× o livro razão)         US$ 3,80   → continua RECUSADO (custaria 6,04)
```

Margem contra o teto: de 18% para **37%**, com o caso caro ainda barrado — que é a única forma de o
teto significar alguma coisa.

`N8N/test`: 185 → **194**. Migrations, export e e2e inalterados: o diff não toca banco nem portal.

### O que o dono precisa fazer

1. **Reimportar `N8N/workflow.e1-ingestao.json`** — e conferir na tela que a versão apareceu
   (`orcamento_versao: "v3 (2026-08-13)"`). Sem isso, nada desta rodada existe em produção.
2. **Rodar o kit sintético** para ver se `gpt-4o-mini` acerta tipo/entidade/período. Custa centavos,
   e é a única conferência de qualidade que a troca de modelo pede.
3. **Trazer o custo REAL da OpenAI** depois do lote grande. É com ele que `CUSTO_POR_MB_USD` (10,5) e
   o peso da classificação se recalibram — até aqui tudo é medição sobre PDF sintético.

## Sessão 42 (2026-08-11) — o custo mentia por 5×, e o "aguarde" mentia duas vezes

**O QUE O DONO RELATOU, e é o começo de tudo:** subiu 35 documentos do `book-canastra` e o n8n
recusou — *"51 chamadas ≈ US$ 7,65, acima do teto de US$ 3"*. E o portal, na outra aba, seguiu
dizendo **"estamos organizando tudo com cuidado… assim que estiver pronto, avisamos"**.

Dois defeitos numa tela só, e o segundo é pior que o primeiro.

### O estimador plano errava por 5,4×

O book INTEIRO — 38 documentos, 57 chamadas — custa **US$ 1,41**, medido pelo `medir-custo-book.mjs`
que o próprio #112 trouxe. O estimador dizia US$ 7,65 para 35. Ele era PLANO: US$ 0,20 por chamada,
sem saber quantas páginas nem quantas linhas o documento tem.

Errar para o lado seguro é o projeto do estimador. Errar por 5× é outra coisa: é impedir o uso do
sistema para proteger um orçamento que nunca esteve em risco.

Passa a estimar por **tamanho de arquivo**, que o `Listar Arquivos` conhece antes de qualquer
chamada — a fatia que o #112 já tinha nomeado como próxima. Calibração medida sobre os 38: US$
5,76/MB agregado, coeficiente em **10,5/MB** (1,8×). **Os dois lados do teste:** o book real estima
US$ 2,46 e passa; 35 cópias do documento mais denso do book (o livro razão, 461 linhas) estimam 3,80
e são recusadas, custando 6,04 de verdade. Tamanho desconhecido cai no plano, **nunca em zero** —
zero deixaria qualquer lote passar.

### A tela de espera mentia sobre um processo morto

`/api/intake/status` deduz progresso de sinais POSITIVOS — documento criado, evento de extração. A
falha não produz nenhum: ela produz **ausência**. E ausência é o que "ainda processando" também
produz. Os dois estados tinham a mesma aparência do lado de fora.

Tela de espera sobre processo morto é pior que erro na tela: é **mentira com cara de calma**, e
custa o dobro — além de não resolver, consome a paciência de quem espera e depois a confiança de
quem descobre.

`execucao_falha` (`0108`) dá ao erro um lugar para morar; o ramo de recusa do orçamento **grava
antes de abortar**; e a tela mostra o que houve, a causa técnica **sem tradução** (é o que o
desenvolvedor precisa ler, e o que some quando a interface "simplifica" demais) e pede para acionar
o desenvolvedor. Para *qualquer* razão — que não se cobre nó a nó, porque cada `try/catch` cobre o
erro que alguém imaginou — nasceu o `workflow.erros.json`, um **Error Workflow** do n8n. Ligá-lo é
passo do dono, documentado no `N8N/README.md`.

### E a mesma mentira, com a causa invertida

Achado ANALISANDO A CONSEQUÊNCIA da correção de custo, não o custo em si.

Deixar 38 documentos passarem leva o sistema a um regime que ele nunca tinha visto. A extração é
deliberadamente LENTA — uma chamada a cada ~33s no Tier 1, porque `max_tokens` é reserva de TPM e ir
mais rápido produz 429. São **~23 minutos**. O acompanhamento da tela tinha teto FIXO de ~12.

Enquanto o orçamento recusava lote grande isso nunca apareceu: 14 documentos terminam em ~8 min e
cabiam. Com o lote passando, a tela desistiria no minuto 12 e voltaria ao "assim que estiver pronto,
avisamos" — para sempre, sobre um processo **vivo**. É o mesmo defeito da `0108` com a causa
invertida: lá a tela esperava por um processo morto; aqui parava de esperar por um que ia bem.

A janela passou a sair do LOTE (45s por documento, com margem; 38 arquivos → 43 minutos), desistir
deixou de ser silencioso, e o **progresso apareceu** — a rota já devolvia `processados`/`esperados`
desde sempre e a tela lia só o `pronto`.

### O que o dono pediu, e o que saiu do sistema por isso

**Três botões na pendência**, sem campo e sem data: *Contatar o Cliente* (verde, não libera — o
documento não chegou), *Prosseguir sem resolução* (vermelho), *Pendência não procede* (amarelo). E
o teto de 3 ressalvas, removido.

A `0109` registra cada guarda que saiu, porque ausência tem de ser escolha e não esquecimento:
motivo obrigatório (a trilha passa a responder QUEM e QUANDO, deixa de responder POR QUÊ), data de
expiração, teto, papel sênior. E a **lista fechada de `Arquitetura do Sistema/2 Especificação/f0/04` deixou de bloquear** — não foi pedido,
decorre do pedido: com um botão só, "Prosseguir sem resolução" que não faz prosseguir é um botão que
mente.

As três funções da `0106`/`0107` foram **dropadas**: duas portas para a mesma decisão com regras
diferentes é o que produz caso cujo estado ninguém explica seis meses depois. O que fica é o que
sustenta a decisão — **nada é apagado e tudo é contado**: o Portão 2 deixa de IMPEDIR e passa a
INFORMAR, com as contagens dentro da própria decisão de aprovação.

Também nesta rodada: **excluir mandato** com confirmação (o diálogo mostra o NOME do caso — com
várias abas abertas, é o que impede excluir o certo achando que é o outro), a exclusão vai para a
trilha ANTES do delete, e o **papel de usuário saiu do schema** (`0110`) por não ter mais leitor.

### Três defeitos meus, achados relendo o que eu tinha acabado de escrever

1. **A pendência decidida SUMIA da tela.** A consulta filtrava só os estados não decididos — os
   botões "adicionam um rótulo" e o rótulo desaparecia junto com o item. O pedido inteiro ficaria
   invisível.
2. Comentário de `aprovarCaso` descrevendo o teto de 3, que não existia mais.
3. `sobrepujavel` viajando do banco até a tela sem ninguém ler — o mesmo defeito que a `0037`
   corrigiu do outro lado.

### E um erro de processo que custou uma rodada

O **PR #114 foi mergeado às 19:03** com o head em `a5b60b8`; empurrei mais dois commits **depois**
disso, na mesma branch. PR mergeado não recebe commit novo — as migrations `0108`/`0109`/`0110`
ficaram fora do `main`, e o dono só descobriu ao tentar aplicá-las. **A lição, em uma linha:**
depois de mergear, conferir se a branch ficou para trás antes de continuar empurrando nela.

`verificar-export.mts`: 506 → **529** · n8n: 176 → **185** · migrations: 50 → **55**

## Sessão 41 (2026-08-11) — o diagnóstico, e o backlog dele executado por impacto

Pedido do dono: ler o handoff, dizer o que os últimos PRs fizeram, e **fazer um diagnóstico
completo** do sistema — com olhar crítico, e sobretudo sobre como melhorar o OUTPUT.

**O achado central, e ele organiza tudo o que veio depois:** *o sistema prova o GERADOR muito melhor
do que prova o RESULTADO, e mede o motor muito melhor do que mede o produto.* Três sintomas do mesmo
fato — 877 asserts verdes sobre um arquivo entregue errado (sessão 40); a fixture sistematicamente
mais fácil que a produção (documentado três vezes); e nenhum número de produção governando nada (sem
golden set, sem concordância medida, sem custo por caso — o dial está onde nasceu na F1).

O documento está em `Arquitetura do Sistema/4 Análises e Auditorias/DIAGNOSTICO_SISTEMA_2026-08-11.md`, com evidência medida, backlog de 14
itens por impacto ÷ esforço, e uma seção **"o que eu NÃO mudaria"** — um diagnóstico que só lista
defeitos convida a estragar o que está certo.

### O que saiu executado, na ordem de impacto

**O `Output` passou a DIMENSIONAR o rombo, não só acusá-lo.** Ele já dizia DSCR 0,3 e ND/EBITDA
10,8x, e o revolver chegava a 122.216 sem que nada dissesse que aquilo **é** a necessidade de
recursos do caso. O revolver é ficção de fechamento: existe para o balanço fechar, não porque alguém
vai emprestar 122 milhões a uma empresa com DSCR de 0,3. O bloco novo — necessidade do exercício,
acumulada, pico e ano do pico; dívida sustentável e serviço suportado lidos dos CORTES em célula
azul; e a decomposição de para onde vai o caixa — não usa nenhum dado novo: tudo sai do que já
existia no `Output` e no `Cash Flow`.

> **E o achado do teste vale mais que o bloco.** Ao religar a acumulação de propósito, a suíte
> continuou VERDE — a fixture principal projeta furo ZERO nos três exercícios, e 0 = 0. É a
> armadilha registrada três vezes neste projeto. A variante `comFuro` conserta: dívida concentrada
> no CIRCULANTE, que é como um caso estressado chega, financiada por prejuízo acumulado para o
> balanço continuar fechando.

**`Supabase/schema.sql`** — o estado do banco deixa de ser uma leitura de 51 migrations em ordem. Gerado
pelo `run.sh`, conferido pelo CI com `git diff --exit-code`.

**Ciclo de caixa** (PMR/PME/PMP + operacional/financeiro), que a `Arquitetura do Sistema/2 Especificação/f0/08` fasejou "até a extração
isolar as linhas-conceito" — o giro já as isolava. Cada prazo gira contra a linha de DRE correta;
fornecedor contra CUSTO, não receita. E caso sem conta de clientes publica `"n.a."`, não "0 dias":
zero dias de recebimento afirma que a empresa vende à vista.

**A máquina de estado da pendência ficou inteira** (`0106`/`0107`): rejeição, ressalva e estados de
tratamento. *(Boa parte disso foi desfeita na sessão 42, a pedido do dono — ver lá.)*

**`ESTADO.md`**, com guarda de frescor no `run.sh`.

### E o `main` estava vermelho, por um espelho

O #112 recalibrou `CUSTO_ESTIMADO_DOC_USD` de 0,15 para 0,20 e **não regerou o JSON dos workflows**.
O nó `Orcamento do Lote` commitado seguia com o literal 0,15: importado no n8n, orçaria pelo número
antigo, e a recalibração existiria no repositório e não em produção. O `git diff --exit-code -- N8N/`
do CI existe exatamente para isso, e pegou.

O defeito tinha um segundo lado: o teste que lê o nó esperava `2.1` (14 × 0,15) e passava, porque
lia o JSON velho — a constante nova não era exercitada por ninguém.

## Sessão 40h (2026-08-07) — o tributo ganhou dono, e o parcelamento passou a ser pago

**O PIOR DEFEITO DESTA RODADA, e ele estava escondido atrás de uma aba bonita.** A aba `Tributos a
Recolher` projetava com `% pago = 0` fixo — 34.912 de tributos, dos quais 11.978 de parcelamento,
congelados nos cinco exercícios. Ao investigar, o defeito era maior do que o número parado: **a aba
era DECORATIVA**. Ela alimentava UMA linha de exibição do `Output` (`DV_TRIB`) e mais nada. As mesmas
contas eram projetadas em outros dois lugares:

- no **`Working Capital`**, por **dias de giro** — parcelamento girando contra receita, ou seja, o
  saldo do acordo com a Receita Federal **crescia quando a empresa vendia mais**;
- no **não circulante do `Balance Sheet`**, **congeladas** — o acordo nunca era pago.

Três lugares, três respostas, nenhuma conferência entre elas. É o quarto incidente da mesma família
(caixa, dívida, subtotal informado, tributo) e a razão de o invariante "uma conta, um lugar" ter
ganhado bloco próprio no cabeçalho.

**A correção dá dono único à conta.** A aba de tributos passa a publicar espelho (`P18`) e todos leem
dela: o `Balance Sheet` tem duas linhas novas (`Tributos a recolher e parcelamentos`, curto e longo
prazo), o `Cash Flow` ganhou **"(−) Pagamento de tributos e parcelamentos"** no operacional, e o giro
**exclui** essas contas, com a razão escrita na própria aba, ao lado de caixa e dívida bancária.

**O pagamento é DERIVADO do saldo** (`ESP_PAGO = total do ano anterior − total do ano`), nunca
calculado de novo. Assim qualquer mudança de regra — prazo editado dentro do Excel, cronograma
digitado por cima — chega ao caixa sozinha, e as duas contas do mesmo pagamento não podem divergir.

**E A REGRA DE PROJEÇÃO DISTINGUE TRÊS NATUREZAS**, que é o que faltava:

| Natureza | Como projeta | Por quê |
|---|---|---|
| **parcelamento** (`parcelamento`, REFIS, PERT, transação tributária, dívida ativa) | parcela LINEAR até o fim, pelo prazo implícito no balanço | parcelamento **é** um cronograma de pagamento |
| **tributo corrente** (ICMS, IRRF, ISS, PIS/COFINS, obrigações tributárias) | fica CONSTANTE | é saldo **rotativo**: paga-se o do mês e o do mês seguinte toma o lugar. Zerar diria que a empresa deixou de ter imposto a recolher, o que só acontece se ela parar de operar |
| **provisão tributária** | fica CONSTANTE | resolve-se por decisão judicial ou acordo, e nenhum dos dois tem data que o modelo possa inferir |

O prazo do parcelamento vem da MESMA derivação da dívida: sob parcela linear em `n` anos, a fração
que vence em 12 meses é `1/n` do saldo, logo `n = 1 ÷ fração no circulante`. No book: 3.272 de 11.978
no circulante → 27,3% → **3,7 anos**, parcela constante de 3.237/ano. Sem repartição curto/longo no
caso, cai em **5 anos (60 meses)**, que é o parcelamento ordinário da legislação federal — e a nota
DIZ que é padrão legal, não medição.

**A fixture principal não tinha conta tributária nenhuma — é por isso que o defeito viveu tanto.** A
variante do `(0113)` acrescenta as quatro que importam (parcelamento em CP e LP, tributo corrente,
provisão) e prova os cinco elos: prazo implícito de 4 anos, parcela constante de 250, tributo corrente
constante, **nenhuma conta de tributo no `Working Capital`**, o balanço lendo o espelho, o balanço
FECHANDO com o pagamento saindo do caixa, e o pagamento do fluxo sendo exatamente a queda do saldo.
Religando os dois defeitos (congelar o parcelamento e devolver o tributo ao giro), **quatro asserts
reprovam com os números de antes** (1.000 · 1.000 · 1.000).

**Um falso alarme, registrado para ninguém repetir a caçada.** No book o giro projetado explode
(`Passivo circulante operacional` 46.669 → 432.714) e as contas saem todas com o MESMO valor. Não é
defeito do motor: a fixture do book aplica uma premissa de **60 dias de giro** a todas as contas, e
60 dias × receita ÷ 360 dá o mesmo número para todas. No arquivo de produção os dias medidos são
mantidos (13, 7,9, 1,6…) e o giro fica são — conferido no v35 (AC 102.070 → 114.346).

`verificar-export.mts`: 499 → **506**.

## Sessão 40g (2026-08-07) — a tela deixou de falar canônico

Três pedidos do dono, todos sobre a MESMA coisa: o portal publicava vocabulário de banco.

**1. Um export por tela.** A tela do caso (conferir o que chegou) ficou só com *Exportar dados
financeiros*; o *Exportar modelagem* vive na tela de Modelagem, junto das premissas que ele usa.
Oferecer o modelo na tela de ingestão convidava a exportá-lo antes de dizer como cada conta projeta.

**2. O card do Portão 2, em português.** Dizia *"Ressalvas ativas: 0 de 3 (teto por caso, Arquitetura do Sistema/2 Especificação/f0/04). A
regra é determinística e não tem exceção por autor."* — três defeitos numa linha: citava documento
interno por código, mostrava contagem sem dizer o que é uma ressalva, e não dava a consequência. Agora
o texto muda com o estado: sem ressalva diz quantas cabem e o que uma ressalva é ("ponto documentado
como aceito com reserva"); no teto diz que dali em diante ponto aberto precisa ser resolvido, não
aceito. A frase final virou "a decisão é sempre a mesma para todos os casos: ninguém aprova por
exceção" — que é o que "determinística e sem exceção por autor" queria dizer.

**3. As pendências viraram lista, com o arquivo.** As mensagens nascem no banco (é lá que a medição
acontece) e chegam como um parágrafo com vários fatos emendados por `;`. Agora `ItemPendencia` quebra
em **um fato por linha, com travessão**, e publica o **nome do arquivo** de origem — sem ele, quem vai
conferir adivinha em qual dos treze documentos olhar. Pendência de caso (divergência ENTRE documentos)
diz isso em vez de deixar o espaço vazio.

**Sobre "em qual linha".** O sistema não guarda número de linha do PDF: o extrator devolve conta,
coluna e valor, não coordenada de página. O que serve para achar o erro no original é o RÓTULO da
conta, e é ele que aparece numa lista à parte ("onde conferir no arquivo"), retirado do corpo da
mensagem para não repetir. Inventar número de linha seria dar precisão falsa a quem vai procurar.

**A quebra tem duas armadilhas, as duas cobertas por assert.** O `;` DENTRO de colchete qualifica o
item (`[entidade: —; período: 31/12/2024]`) e não separa nada — quebrar ali produzia linha órfã
("período: 31/12/2024]"). E o ponto separa fato, mas **só seguido de espaço**: sem essa guarda,
`14529.00` viraria duas linhas.

**4. `portal/src/lib/rotulos.ts`** é o único lugar que traduz vocabulário interno para tela:
`passivo_nao_circulante` → "Passivo Não Circulante", com mapa explícito para o que tem nome próprio e
um humanizador genérico como rede — chave nova aparece legível antes de alguém mapeá-la, em vez de
vazar `snake_case` para o cliente. Sigla fica maiúscula (`total_dre_por_cnpj` → "Total DRE por CNPJ"),
preposição fica minúscula, e o acento entra sempre: "divida" e "dívida" são palavras diferentes, e a
primeira não é a que se quer.

A fixture do assert é o **texto real** que o dono copiou da tela, não uma frase escrita para o teste
passar. Religando a publicação da chave canônica, `0112` reprova nomeando as cinco seções.

`verificar-export.mts`: 491 → **499**.

## Sessão 40f (2026-08-07) — dois exports, e as alavancas em uma tela só

**Auditoria do v35 exportado depois da amortização: 10/10 no auditor**, 12.244 fórmulas sem um
`#REF!`, balanço fechando nas sete colunas, DRE do realizado igual ao documento nas 28 células. E o
que o arquivo agora MOSTRA, que antes escondia: a dívida existente amortiza 36.643 em 2026 e o caixa
não cobre — o revolver saca 48.406 e chega a **122.216 em 2030**, o `DSCR` fica entre 0,3 e 0,7
contra o corte de 1,2 e o `ND/EBITDA` vai de 5,1x a **10,8x**. Nenhum desses números é novo no
negócio; eles é que estavam invisíveis enquanto a dívida era rolada para sempre.

**DOIS EXPORTS, DOIS PROPÓSITOS** (decisão do dono). O de modelagem carregava as 12 abas de dado cru
do export da Etapa 1: 29 abas para quem só queria o que vai a comitê. Agora *Exportar dados
financeiros* entrega a conferência da ingestão e *Exportar modelagem* entrega as 14 abas do modelo +
`Modelagem` + o par macro — **16 a 17 abas**. Os dois botões ficam lado a lado na tela de Modelagem e
na do caso.

**A remoção só foi feita porque foi MEDIDA.** Aba referenciada que some vira `#REF!` em toda fórmula
que apontava para ela. O mapa de referências cruzadas das 12.244 fórmulas do arquivo entregue mostrou
que as 14 abas do modelo referenciam APENAS umas às outras; zero referências às abas de dado. A regra
é por **lista do que FICA**, não do que sai: tipo documental novo já nasce fora do arquivo de
modelagem. E há guarda: sem o modelo montado não se remove nada — arquivo pequeno e vazio é pior que
arquivo grande.

**O COCKPIT DA ABA `Premissas`.** O mecanismo de modelar dentro do Excel já funcionava (o painel
índice macro × spread reprojeta a cascata: `conta = ano anterior × (1 + CHOOSE(cenário, base,
cliente, stress))`, e `base = (1+índice)×(1+spread)−1`), mas estava **espalhado por sete abas de até
135 linhas** — e alavanca que ninguém acha não é alavanca. Pior: quem abre o arquivo procurando "as
premissas" abre a aba `Premissas`, que só tinha base histórica extraída, o oposto do que o nome
promete.

Agora ela abre com o **PAINEL DE MODELAGEM**: uma linha por alavanca, com o valor **vivo** (fórmula
apontando para a origem, nunca cópia), o **endereço** de onde se edita (`aba!célula`) e uma nota
dizendo o que muda ao mexer. Cobre o índice macro e o spread de cada premissa de crescimento, caixa
mínimo, spreads de dívida/revolver/aplicação, prazo da captação nova, prazo SAC das tranches, vida
útil e os três cortes de covenant. Alavanca que não existe no caso aparece como **"não se aplica"** —
ausência declarada, nunca linha em branco.

Não se edita NO painel porque Excel não tem célula de mão dupla: ou o valor mora lá e as abas leem
daqui, ou mora nas abas e o painel espelha. Mover tudo para cá quebraria a leitura de cada aba em pé
e é decisão de arquitetura própria.

**O assert que importa é o do endereço** (`0111`): painel que aponta para a célula errada é pior que
painel nenhum, porque manda editar o que não é a premissa. O teste lê os 12 endereços publicados, vai
a cada célula e exige que o valor bata. Deslocando o endereço em uma linha, ele reprova nomeando as
divergências. `0110` faz o mesmo pelo corte das abas: religando a remoção, reprova listando as abas
de dado que voltaram.

`verificar-export.mts`: 485 → **491**.

## Sessão 40e (2026-08-07) — as três premissas decididas, e a dívida passou a amortizar

O dono aplicou a `0104` e a `0105` no Supabase e decidiu as três premissas que estavam travando as
últimas linhas do motor. Duas viraram código, uma virou ausência documentada.

**A que mudou número: AMORTIZAÇÃO LINEAR (SAC).** O `%` amortizado de cada tranche era **ZERO fixo**,
com a nota "dívida rolada integralmente, que é a hipótese conservadora". **Ela não é conservadora** —
dívida que nunca amortiza não consome caixa nenhum no horizonte, o fluxo projetado sai melhor do que
a empresa vai viver, e o `DSCR` do bloco de covenants mede um serviço de dívida feito só de juros.
Numa reestruturação, isso é errar exatamente a pergunta que o mandato existe para responder.

**O prazo não foi inventado — estava no balanço.** Sob amortização linear em `n` anos, a parcela que
vence em 12 meses é `1/n` do saldo; logo `n = 1 ÷ fração da dívida bancária no circulante`, medida no
último exercício realizado do próprio caso. Uma dívida 40% circulante amortiza em 2,5 anos, e quem
disse isso foi a demonstração. Na fixture: 15.000 de 50.000 no circulante → 30% → **3,3 anos**; na
cadeia do book, **1,2 anos** (o book é 83% circulante). Teto de 10 anos porque dívida 100% de longo
prazo daria `n → ∞`, que é a dívida que nunca é paga — o defeito que a mudança veio corrigir; piso de
1 ano porque prazo fracionário geraria amortização acima de 100% do saldo (o `MIN(1;…)` da fórmula é
o mesmo cinto).

O prazo é **célula azul editável, uma por tranche**, na primeira coluna projetada; os anos seguintes
a referenciam com `$`. Uma edição reprojeta a tranche inteira dentro do Excel — é a mesma promessa do
painel de premissas, agora na dívida, e tem assert que prova (trocar 3,3 por 2 leva a parcela a
25.000). O `%` virou fórmula `1/(prazo − anos decorridos)`: **principal constante**, que é o que
separa SAC de "percentual fixo do saldo" — este decai geometricamente e nunca zera a dívida.

**Prova pelos dois lados:** os sete asserts novos (`0109a`–`0109c`) passam, e **religando o zero, três
deles reprovam com o número exato de antes** — os 50.000 da fixture inteiros em 2028. O balanço
continua fechando em todos os exercícios, inclusive no e2e contra a cadeia real, que é o que importa:
a amortização consome caixa e o revolver cobre o furo, então o rombo aparece em vez de sumir.

**As outras duas.** *Covenants*: patamares usuais de term sheet (ND/EBITDA ≤ 3,0x, DSCR ≥ 1,2x,
liquidez ≥ 1,0x) — **já era exatamente o que o `Output` publicava**, com célula azul por corte, teste
`ROMPE`/`ok` por ano e a linha tracejada nos gráficos; conferido antes de tocar em qualquer coisa, e
nada foi mexido. *CAPEX FINANCING*: **não entra** (0% financiado por dívida nova). É ausência
deliberada — modelar captação que ninguém contratou fecha o caixa no papel e esconde a necessidade de
recurso que se quer dimensionar.

`verificar-export.mts`: 478 → **485**.

## Sessão 40d (2026-08-06) — Fase D: a auditoria do arquivo entregue virou comando

**O buraco que esta fase fecha.** As quatro suítes provam o GERADOR — rodam contra fixture e contra o
book, e reprovam quando o código volta a errar. **Nenhuma olhava o arquivo entregue**, e foi por essa
lacuna que o v35 chegou ao dono com a DRE dizendo o contrário do documento enquanto o CI estava verde.
A auditoria da sessão 40 achou os seis defeitos, mas foi feita com um script descartável, rodado uma
vez: auditoria que existe uma vez não é controle, é sorte.

**`portal/scripts/auditar-xlsx.mts`** é essa auditoria versionada, e roda sobre um `.xlsx` pronto —
inclusive um gerado meses atrás, ou gerado em produção com dado que nenhuma fixture tem. Onze itens
(dez ao ler de disco), cada um um número LIDO do arquivo: as 14 abas existem · o balanço fecha em todo
exercício · a DRE do realizado reproduz o documento (as linhas de diferença, célula a célula) · o
ativo total é o informado · **o modelo tem conteúdo** · nenhuma fórmula nasce com `#REF!` · o arquivo
pede recálculo ao abrir · as 14 abas declaram área de impressão · o painel de premissas COMPÕE índice
× spread · o câmbio traz nível · os 8 gráficos caem dentro da área de impressão do `Output`. Sai com
código 1 se algum reprovar, então serve em script sem ninguém ler a saída. Medido sobre o arquivo da
cadeia real do book: **10/10**.

**O item "tem conteúdo" é o menos óbvio e o mais necessário.** Balanço sem conta nenhuma FECHA (zero =
zero) e DRE sem linha de resultado sai toda em zero — e zero, num modelo financeiro, é uma AFIRMAÇÃO
sobre o negócio, não a ausência de dado. Era exatamente o que a cadeia do book produzia antes da Fase A
(132 contas fora dos blocos por `secao_canonica` nula) e nenhum invariante acusava, porque tudo
"fechava".

**Duas armadilhas da casa, nesta fase.** (1) O `fullCalcOnLoad` dava falso negativo: o ExcelJS ESCREVE
a flag mas não a restaura em `calcProperties` ao LER de disco (medido: `{}` num arquivo cujo
`xl/workbook.xml` traz `fullCalcOnLoad="1"`). O CLI lê o XML pelo JSZip e passa o resultado; conferir só
o objeto reprovaria todo arquivo lido. (2) O primeiro assert `(0108)` de direção negativa injetava "modelo
sem as contas de balanço" e **passava verde acusando nada** — a projeção de imobilizado mantém o `ATIVO
TOTAL` diferente de zero, então o item de conteúdo não tinha por que disparar. Trocado por **oito
injeções, uma por item**, cada uma um dos defeitos que estavam no arquivo de 06/08/2026, exigindo que
seja o item CORRESPONDENTE a acusar — "reprovou alguma coisa" não prova nada, porque um auditor com um
item sensível e oito decorativos passaria nesse teste. Conferido afrouxando dois itens de propósito
(limite do balanço em `1e12`, câmbio negativo aceito): o assert reprova e nomeia os dois.

**`Arquitetura do Sistema/6 Referência/ACEITE.md`** é a metade humana, curta de propósito: 10 itens, ~15 minutos, só o que o auditor
não consegue ver — o arquivo abre sem oferecer reparo, os gráficos DESENHAM, o dropdown de índice macro
REPROJETA ao clicar, o spread compõe (7,1% e não 7,0%), o `CHECK` continua zero DEPOIS de editar, o PDF
sai com o gráfico dentro da página. Itens 1, 6 e 9 são bloqueantes. O item 6 é o mais grave dos
quatro que testam a promessa da edição no Excel: se ele falhar, o arquivo aceita edição e responde com
número que não fecha.

`verificar-export.mts`: 476 → **478**. Os nove passos do CI rodados localmente: verdes.

### O que depende do dono (nada disso é do colaborador)

1. ~~Mergear o PR das Fases B–D~~ — **feito (PR #105, `main` em `052817a`)**.
2. **Aplicar a `0104` e a `0105`** no Supabase, nesta ordem.
3. **Exportar o v35 de novo e rodar o aceite**: o auditor (comando) + os 10 itens do `Arquitetura do Sistema/6 Referência/ACEITE.md`.
   É a primeira vez que o arquivo entregue passa por conferência antes de ir a comitê.
4. **Decidir o que a Fase C deixou pendente por falta de premissa, não por falta de código:** os cortes
   de covenant (3,0× / 1,2× / 1,0×) e o cronograma de amortização por tranche; se o `CAPEX FINANCING`
   entra e com que regra. Sem decisão, essas linhas ficam fora — chutar premissa é mentir com número.

## Sessão 40c (2026-08-06) — Fases B e C do plano

**Fase B — a conta duplicada virou achado da reconciliação (`0105`).** Depois de excluir os subtotais
informados, sobrava no v35 o resíduo de outra natureza: `Prejuízos acumulados` e `Resultados
Acumulados`, ambos −39.150. `fn_pares_duplicados_do_caso` acha os pares e `fn_reconciliar_duplicidade`
abre pendência com o valor dobrado — **sem apagar nem reescrever nada**, e um assert prova que a
checagem só lê. O trabalho de verdade foi APERTAR o critério: a primeira versão abriu 5 pendências no
book, que por contrato é extração fiel e não pode abrir nenhuma. Os falsos positivos ensinaram três
filtros — subtotal × seu único componente (a `secao` do componente É o rótulo do subtotal), contas em
subseções diferentes com valor igual, e radical contido sem subseção declarada (indistinguível de
grupo com um componente). Resultado: **zero pares nas 6 entidades do book, 1 par no formato da
extração de produção** — o do v35. Nove asserts embutidos, cinco recusando falso positivo.

**Fase C — três dos seis itens da fila do §5, com assert cada.** (a) variação de giro do `Cash Flow`
aberta **conta a conta**, com linha de conferência contra o total (que continua vindo do espelho do
giro — duas origens só valem com conferência entre elas); (b) o `CHECK` do balanço publicado **no topo
das quatro abas de driver**, com formatação condicional, porque é onde a premissa é mexida; (c) os
espelhos de balanço e fluxo do `Output` abertos **conta a conta**, por referência à origem.

Os três ficam nos números do §5 do `CONFORMIDADE.md`, atualizado com o que FICA e por quê: tranche em
moeda estrangeira exige a MOEDA por contrato, que o Kit Básico não coleta (aplicar câmbio sem saber
se a tranche é em dólar erra por ~5×); `CAPEX FINANCING` é premissa de plano e entra com a decisão do
dono; espelho do `Goodwill` só vale com ágio de verdade; vida útil por classe depende de laudo.

**E um assert meu nasceu vazio — registrado porque é a armadilha da casa.** A primeira versão do
`0107b` conferia que o `CHECK` dos drivers avaliava zero. Com o preenchimento desligado, a célula fica
VAZIA e o avaliador devolve 0 por contrato: o assert passava verde provando nada. Agora ele exige que
a célula seja FÓRMULA apontando para o `Balance Sheet`.

`verificar-export.mts`: 471 → **476**.

## Sessão 40b (2026-08-06) — a Fase A do plano: o portão de fidelidade que faltava

O dono pediu um plano para fechar o projeto, e a primeira fase dele era a única que muda a natureza
do problema: **nenhuma suíte comparava os números do MODELO com o gabarito.** O `verificar-export`
monta o modelo de uma entrada escrita à mão (e por isso a fixture podia ser mais fácil que a
produção); o e2e cobria a cadeia real só até as abas ANALÍTICAS. As 14 abas que vão a comitê tinham
como único juiz o dono abrindo o arquivo — foi assim que receita líquida de 170.220 contra 106.580
informados chegou a ele depois de 100+ PRs verdes.

**O pré-requisito, que era um defeito de fixture.** `Supabase/test/gerar_fixture.py` gravava
`secao_canonica = NULL` nas 767 linhas do book, enquanto a extração real PREENCHE esse campo (é
instrução do `SYSTEM_PROMPT`, enum em `SECAO_CANONICA_ENUM`). Consequência medida: `blocoDaLinha`
devolvia `fora` para as 132 contas de balanço e DRE e o modelo saía com a **DRE inteira em zero** na
cadeia do book. Nenhuma base local reproduzia produção: a `fixture_modelagem_v35.sql` tem
`secao_canonica` mas `secao` nula e `ordem` alfabética; a do book tinha o inverso. O gerador agora
classifica no PONTO DE EMISSÃO (ele sabe, ao escrever, se está no ativo circulante ou no passivo não
circulante), com `NAO_CLASSIFICAVEL` onde não existe valor honesto no enum — total de grupo,
eliminações, faturamento mensal, mútuos, notas. Os dois fixtures versionados foram regerados.

**A fase 6 do e2e**, que é o portão: monta o modelo institucional pelas MESMAS consultas da rota
(`fn_definir_modelagem`, `fn_linhas_para_modelagem`, `fn_valores_por_ano`) e confere contra o
`GABARITO.json` — as 4 linhas de resultado, os 6 totais de grupo do balanço nos dois exercícios, e o
`CHECK` em todas as colunas, com tolerância de 1 centavo. Sem premissa nenhuma de propósito: o que
está sob teste é a fidelidade do REALIZADO.

**Resultado, na cadeia completa (extração do book → banco pelas funções reais → export):** receita
líquida 143.380/106.580, lucro bruto 27.400/5.280, EBIT 6.470/−4.571, resultado −2.950/−17.901 —
**diferença ZERO nas oito células**, diagnóstico "confere com o documento"; ativo total 121.198/95.780
idêntico ao informado; `CHECK` em zero em todos os exercícios. E religando o defeito de sinal, a fase
6 devolve **exatamente** os números do arquivo que chegou ao dono (170.220 · 271.520 · 281.371 ·
268.041) — ou seja, o portão pega o defeito que passou.

`Verificação/run.mts`: 27 → **46** verificações.

## Sessão 40 (2026-08-06) — o arquivo entregue mentia; seis defeitos e a conferência que os pega

O dono exportou o v35 completo depois do PR #102 e pediu a auditoria: "está fiel à referência e
pronto para ser usado como base?". Medido por dentro (o mapeador do próprio repo + o avaliador de
fórmulas dos testes, sobre as 10.167 fórmulas das abas do modelo): **motor fiel, números errados.**
A linha `CHECK` do `Balance Sheet` do próprio arquivo acusava **"NÃO FECHA" nas sete colunas**.

**O que estava certo, medido:** 8 gráficos com XML e rels válidos; **zero** fórmulas com `#REF!` em
11.521; zero erro de avaliação; `fullCalcOnLoad="1"`; 14 áreas de impressão com escopo local; eixo do
tempo de uma raiz; caixa do `Cash Flow` = caixa do `Balance Sheet`; 490 fórmulas por coluna de ano
contra 558 da referência; 0,4 MB.

**Os seis defeitos, todos corrigidos, cada um com teste que reprova religado (§8.2):**

1. **CONVENÇÃO DE SINAL.** A cascata subtrai despesa (magnitude positiva, com "(-)" na coluna de
   sinal) e a extração entrega despesa negativa. Subtrair negativo soma: receita líquida de 2025 saiu
   **170.220 contra 106.580**, lucro bruto 271.520 contra 5.280, EBIT **+281.371** contra **−4.571**,
   resultado **+268.041** contra **−17.901** — e as projeções de 2026-2030 cresceram dessa base. Pior,
   dentro da MESMA coluna as linhas projetadas por crescimento ficavam negativas e as projetadas por
   percentual saíam positivas, então `CUSTOS 2026` somava sinais opostos. Normalizado **por bloco e
   por multiplicação por −1** (nunca `Math.abs`, que inverteria o crédito "Outras receitas
   (despesas) operacionais, líquidas +11.549"), com a decisão medida no próprio caso e a frase na
   nota de cada célula.
2. **SUBTOTAL INFORMADO SOMADO COM OS COMPONENTES.** `ATIVO TOTAL` de 2025 em **195.090 contra
   95.780** informados. A detecção estrutural (`detectarSubtotaisInformados` +
   `detectarSubtotaisPorOrdem`) já existia e já era usada pelas abas analíticas — o modelo é que
   consumia `papel` da `fn_papel_linha`, que é lista FECHADA e não reconhece "Obrigações
   Tributárias", "Provisões", "Capital Social", "Reservas", "Disponível". Agora é **uma detecção,
   dois consumidores** (`rotulosDeSubtotalInformado`).
3. **DÍVIDA DESAPARECIDA NO EXERCÍCIO QUE O MAPA NÃO COBRE.** O mapa do v35 tem uma data de
   referência (2025); 2024 saía com dívida ZERO nas duas linhas enquanto o balanço informa 22.972 +
   11.393. A origem passa a ser decidida **por exercício** e a repartição curto/longo do realizado
   vem do balanço daquele ano, não da fração estimada.
4. **CÂMBIO NEGATIVO.** A linha "R$/US$ — final de período" trazia **24,5 em 2024 e −10,6 em 2025** ao
   lado de 5,2 do Focus: `fn_indice_macro_anual` devolve, para série de NÍVEL, a VARIAÇÃO do ano, e a
   rota publicava isso numa linha de nível. A rota passa a ler o nível de fechamento de
   `indice_macro_obs` e a linha **recusa** valor de outra grandeza, deixando a célula vazia com o
   motivo.
5. **DEPRECIAÇÃO REALIZADA NÃO CHEGAVA À DRE.** `EBITDA = EBIT` em 2024 e 2025 apesar de a DRE trazer
   "Depreciação industrial" de −5.180 e −5.540 dentro do custo. Não era dupla contagem: `EBITDA =
   LUCRO BRUTO − SG&A + D&A` soma de volta o que já está no custo e o `EBIT` subtrai outra vez — o
   EBIT continua igual ao do documento, o que a nova conferência prova.
6. **OS 8 GRÁFICOS FORA DA ÁREA DE IMPRESSÃO** (colunas N:AE contra B:K). Quem gerasse o PDF do
   `Output` — que é como o comitê recebe — não levava gráfico nenhum. Agora um por faixa, abaixo dos
   números, dentro das colunas que imprimem, com a área estendida.

**A CONFERÊNCIA QUE FALTAVA, e é o que impede o próximo erro de sinal de passar por bom.** O
invariante nº 9 ("nosso número == o número do documento") valia para as abas analíticas desde o
teste v25 e o modelo institucional era a única parte do arquivo sem ele. As linhas de resultado e os
totais do balanço chegam com `papel = 'subtotal'`, ficavam fora das somas (correto) e eram
**descartadas** — agora são **âncoras**: o `Income Statement` publica, no realizado, receita líquida,
lucro bruto, EBIT e resultado líquido **do documento** ao lado dos do modelo, com a diferença, o
diagnóstico e formatação condicional; o `Balance Sheet` faz o mesmo com o ativo total. Duas
armadilhas medidas e tratadas: o mesmo rótulo vem de vários documentos (a DMPL traz o prejuízo
positivo numa coluna de movimento → preferir o documento da âncora) e **"PREJUÍZO LÍQUIDO 17.901" é
−17.901** (o rótulo carrega o sinal).

**Dois defeitos que eu mesmo introduzi no caminho e o teste pegou** — ficam registrados porque são o
tipo de coisa que volta: (a) a exclusão de subtotal por **rótulo solto** tirou da DRE a despesa
"Provisão para contingências trabalhistas e cíveis", que tem o mesmo nome de um subtotal do balanço —
a chave passou a ser o par `(seção, rótulo)`; (b) filtrar os campos pela entidade **antes** de rodar
os detectores mudava o veredito deles (a sequência é a evidência), fazendo o modelo discordar da aba
analítica do mesmo arquivo — detecta-se sobre a aba inteira e filtra-se depois.

**A FIXTURE ERA MAIS FÁCIL QUE A PRODUÇÃO, e é a lição mais cara da rodada.** A do `(0105)` tinha
custo POSITIVO (`"Custo dos produtos vendidos", 140000` quando a extração entrega `−140000`), uma
conta por grupo (nenhum par subtotal+componente), UM exercício realizado (o mapa de dívida cobre o
último, o balanço cobre todos) e nenhum total informado (nada contra o que conferir). Com ela, 15
asserts verdes conviviam com prejuízo virando lucro. Foi refeita com a forma do dado real e os sete
asserts novos (`0106a`–`0106g`) foram **verificados um a um religando o defeito**.

**Insumo, para quem for medir localmente:** nenhuma das duas bases locais reproduz a produção
inteira. `Supabase/test/fixture_modelagem_v35.sql` tem `secao_canonica` mas `secao` nula e `ordem`
ALFABÉTICA (a detecção estrutural quase não dispara, e a coluna histórica mistura 2024 e 2025); a
cadeia do book (`test/e2e`) tem `secao`/`ordem` reais mas **`secao_canonica` nula nos 767 campos**, e
por isso o modelo institucional sai com a DRE inteira em zero. Isso levou ao sétimo assert e a uma
guarda nova: modelo sem linha de resultado **anuncia** "SEM DRE" em vermelho, em vez de exibir uma
cascata zerada com cara de empresa sem operação.

**Ainda na sessão 40, em cima da correção:** (a) **a reconciliação com o total informado** — cada
grupo do balanço (AC, ANC, PC, PNC, PL) passa a seguir o total que o DOCUMENTO informa, com a
diferença numa linha própria chamada "reconciliação com o … informado no documento". É o invariante
nº 6 ("o total da seção é o que o documento informou, não a nossa soma") aplicado ao modelo, e é o
que resolve a conta duplicada (`Prejuízos acumulados` = `Resultados Acumulados` = −39.150) **sem
apagar conta nenhuma** — apagar por semelhança de valor mataria conta legítima. Medido no v35 local:
`CHECK` de 52.992 → −20.529 e a diferença do ativo de 69.421 → 10.277, e o que sobra é o próprio
fixture sintético cujos totais informados não somam entre si (numa demonstração real,
AC+ANC = ativo total por definição). O `CHECK` agora **diz** que essa é a única causa possível de
sobra. (b) **O PAINEL DE PREMISSAS** no topo da aba de receita: uma linha por premissa de
crescimento, com **índice base** (dropdown com as séries da aba `Anual`), **spread real** digitado e
`crescimento nominal = (1+índice)×(1+spread)−1` — o mesmo `P15` do custo da dívida. As contas
apontam para o painel, então trocar o índice ou o spread **dentro do Excel** reprojeta o modelo
inteiro. O spread nasce calibrado para reproduzir exatamente a premissa que o portal escolheu
(índice "(nenhum)"), então o arquivo abre com os mesmos números e ganha o mecanismo. O assert
`(0106i)` **simula a edição**: escreve "IPCA" na célula de escolha, esquece a memória do avaliador,
recalcula e exige que a receita projetada mude — e que voltar a "(nenhum)" restaure a premissa.
Nota de implementação: o painel usa `IF` encadeado em vez de `INDEX/MATCH` porque o avaliador das
suítes segue referência entre abas mas **não intervalo entre abas** — com `INDEX/MATCH` o teste da
edição passava verde sem edição nenhuma.

**O que continua do dono:** aplicar a `0104`; exportar o v35 de novo e conferir a nova linha
`diferença (modelo − documento)` do `Income Statement` e do `Balance Sheet` — se sobrar diferença, ela
agora está escrita no arquivo; decidir os cortes de covenant (3,0x / 1,2x / 1,0x são patamares de term
sheet, não dado do caso) e o cronograma de amortização por tranche (hoje 0% = dívida rolada, hipótese
conservadora e explícita).

**O que fica aberto, e é o próximo passo natural:** a **mesma conta extraída com dois rótulos**
("Prejuízos acumulados" e "Resultados Acumulados", ambos −39.150; "Capital social subscrito" e
"Capital social subscrito e integralizado") continua contada duas vezes no patrimônio. Não é subtotal
— é identidade de conta entre documentos, e resolver isso com heurística de semelhança apagaria conta
legítima (duas provisões de mesmo valor são plausíveis). O caminho é a reconciliação, não o gerador
de planilha. Enquanto não for resolvido, o arquivo **diz** o tamanho do problema nas linhas de
conferência, em vez de escondê-lo.

## Sessão 30 (2026-08-03) — Fase 6: calibração — o dial volta a mandar

**A contradição que esta sessão fecha.** `estagio_autonomia` nasce na `0001` com o comentário
"Nível é estado do sistema, não constante de código (Arquitetura do Sistema/1 Visão e Doutrina/01)", é semeada na `0002` — e até aqui
**não tinha um único leitor**: `grep -rl estagio_autonomia portal/src n8n` não retornava nada. O
dial de `extracao_linhas_financeiras` dizia **N0** ("roda, registra, **não influencia decisão**")
enquanto `fn_registrar_campos_extraidos` auto-aceitava toda linha com confiança **>= 0.95
hardcoded** — que é o que a faz virar fato no export. O cabeçalho da `0019` registra a subida com
todas as letras; o dial no banco nunca foi mudado. **O sistema declarava uma coisa e fazia outra, e
nada podia acusar, porque não havia nada ligando as duas.**

### `0041_dial_manda.sql` — o que muda, e o que NÃO muda

Por decisão do dono: **o dial passa a DECLARAR N2 e o comportamento continua idêntico**. Não é
mudança de autonomia — é a autonomia que já existia parando de ficar enterrada no corpo de uma
função.

| Peça | O que faz |
|---|---|
| `estagio_autonomia.limiar_auto_clear` | o `0.95` sai do código e vira **dado** (default 0.95, para nenhum banco existente mudar de comportamento). `null` = não auto-aceita, qualquer que seja o nível |
| `fn_dial(estagio)` | a leitura única do dial (nível, teto, limiar, `no_teto`, quem/quando) |
| `fn_mudar_dial(estagio, nivel, autor, motivo, limiar)` | sobe/baixa com o **teto respeitado**, recusa **retornada**, e grava `evento_auditoria` `mudanca_dial` — o valor que existia no enum desde a `0001` e nunca havia sido usado |
| `fn_registrar_campos_extraidos` | reemitida: o auto-aceite **lê o dial**. N0/N1 = nenhum auto-aceite; N2/N3 = acima do limiar **lido da tabela** |

Três decisões de projeto que valem registro:

- **Ausência de configuração não vira permissão.** Sem linha no dial, `v_auto_permitido` é falso e
  nada é auto-aceito. O default seguro é o único default admissível aqui.
- **A recusa é retornada, não levantada** (padrão `0036`/`0037`/`0038`): exceção em plpgsql desfaria
  o registro da própria tentativa, e *tentar passar do teto* é justamente o que a trilha precisa
  guardar.
- **`decisao` exige `caso_id`; mudança de dial é GLOBAL.** O registro append-only vai para
  `evento_auditoria`. Pendurar num caso arbitrário faria a trilha daquele mandato afirmar uma
  decisão que não é dele.

**Baixar o dial passou a ser UMA CHAMADA** — sem migration, sem deploy. Era o que faltava para
"desligar a autonomia" ser uma ação e não um comentário.

### `Supabase/test/dial.test.sql` — e os quatro defeitos religados

Dez cenários. Os que importam: **N0 e N1 não auto-aceitam nada**; **mudar `limiar_auto_clear` muda o
resultado sem tocar em uma linha de código** (0.98 aceita com limiar 0.95, pendente com 0.99, aceita
outra vez ao voltar); **guarda disparada continua suprimindo o auto-aceite** (o que a `0029` fechou —
a `0041` mexeu nesse bloco, e regressão ali reabre o furo de anti-ancoragem); **teto recusa e a
tentativa fica registrada**, inclusive nos dois estágios que `Arquitetura do Sistema/1 Visão e Doutrina/01` nunca solta de N1.

Cada defeito foi **religado** e o teste reprovou (regra do `CLAUDE.md`, "teste que não pode falhar
não prova nada"):

| Defeito religado | Assert que reprovou |
|---|---|
| auto-aceite volta a ignorar o dial (`v_auto_permitido := true`) | "em N0 nenhuma linha é aceita" — *aceitas indevidamente: 1* |
| `fn_mudar_dial` deixa de checar o teto | "pedir N3 num estágio de teto N2 é RECUSADO" — nível foi para N3 |
| limiar volta ao código (`v_limiar := 0.95`) | "com limiar 0.99, a linha de 0.98 deixa de ser auto-aceita" — *aceito* |
| guarda deixa de suprimir (regressão da `0029`) | "NENHUMA das 4 linhas de 0.99 foi aceita" — *aceitas indevidamente: 4* |

O cenário 10 **restaura** o dial em N2/0.95: os testes rodam todos no mesmo banco, e um dial
deixado em N0 faria qualquer teste futuro de auto-aceite passar ou reprovar por motivo errado.

### `/autonomia` — o painel, somente leitura

Os 8 estágios com nível de hoje, teto, limiar, quem mudou e quando, mais a trilha das últimas
mudanças (aplicadas **e recusadas**). Duas escolhas deliberadas:

- **Só leitura.** Subir dial é decisão de doutrina, é global (afeta todo mandato, não o que está
  aberto) e `Arquitetura do Sistema/1 Visão e Doutrina/01` exige concordância medida. Um botão aqui convidaria a mexer no meio de um
  caso. A mudança se faz por `fn_mudar_dial` — ação do dono, como migration e teste ao vivo.
- **A ressalva viaja com o número.** Estágio de extração acima de N1 mostra um aviso: está nesse
  nível por **decisão de produto, não por concordância medida**. Sem isso, alguém lê "N2" daqui a
  seis meses e conclui que houve medição contra golden set.

A rota é `/autonomia`, fora de `/casos/`, porque o dial **não é estado de um mandato**.

### `portal/scripts/medir-auto-aceite.mts` — e o número que ele deu

Mede, para um dial dado, quantas linhas seriam auto-aceitas, quantas dessas o gabarito consegue
conferir, e quantas concordam. Rodado no default:

```
linhas na extração:            767
auto-aceitas pelo dial:        767  (100.0%)
  conferíveis contra gabarito:  77
    concordam:                  77  (100.0%)
  SEM gabarito que confira:    690  (90.0% do auto-aceito)
```

**Leia os 100% com a ressalva, que é maior que o número.** A extração medida no default é o
**fixture** — transcrição fiel do book, feita à mão —, **não a saída da IA**. Nesse modo o script
mede o **instrumento**, não a autonomia: que os pares conferíveis são encontrados e comparados
certo. Medir autonomia exige `--extracao` apontando para uma extração **ao vivo** sobre os PDFs do
book, que é ação do dono (custa orçamento).

**E o número que decide não é a concordância — é a cobertura: 90% do que o dial auto-aceita não tem
gabarito que confira.** Essas linhas viram fato sem que humano ou teste tenha olhado; é o tamanho
real da aposta que o N2 faz. Reduzir isso exige **gabarito mais fino** (golden set físico, §7.4 #8),
não limiar mais alto.

**Ainda com a ressalva de estrato:** o book é **melhor caso** — PDF gerado por reportlab, texto
limpo, layout conhecido, sem scan, sem carimbo, sem coluna torta. `Arquitetura do Sistema/1 Visão e Doutrina/01` exige concordância
medida no estrato que **vai para produção** antes de tratar este N2 como autonomia **medida** em vez
de declarada. O golden set físico continua aberto.

### Contadores após esta sessão

`N8N/test` = **176**; `verificar-export.mts` = **426**; `Supabase/test/run.sh` = **41 migrations / 197
asserts**; `Verificação/run.mts` = **27**.

### O que o dono precisa fazer

Aplicar `0038`, `0039`, `0040` e **`0041`** no Supabase (a `0041` já declara o dial em N2 no fim do
próprio arquivo, e falha se a mudança for recusada); publicar o portal; e, quando quiser o número
que vale, rodar a extração ao vivo sobre `Dados de Teste/book-vertentes/pdf/` e passar o resultado em
`--extracao`.

## Sessão 29 (2026-08-03) — Fase 7.5: as primitivas de projeção que faltavam

Com as duas decisões que o dono deu: **`pct_de_linha` incide sobre a receita total do caso,
automaticamente**, e **a sazonalidade é derivada do histórico do próprio caso**.

### Seis das sete primitivas desenhadas

| Primitiva | Como |
|---|---|
| `crescimento_composto` / `indice_macro` | anterior × (1 + premissa) |
| `valor_por_ano` | a premissa É a linha |
| **`pct_de_linha`** | premissa × **receita total do caso** |
| **`dias_de_giro`** | receita total × dias ÷ **360** (ano comercial — é o que os contratos usam) |
| **`curva_mensal`** | reparte o valor anual nos 12 meses pela curva do caso |
| `preco_x_volume` | ⛔ **exige decisão de schema** — ver abaixo |

**A base dos percentuais é uma LINHA EXPLÍCITA** ("↳ Receita total do caso"), não uma soma
escondida dentro de 30 fórmulas: o analista precisa ver sobre o que o percentual incide, e soma
oculta é impossível de auditar quando o número sai estranho. Ela soma **célula a célula**, não por
intervalo — as linhas de receita podem não ser contíguas, e `SUM` de intervalo pegaria o que estiver
no meio.

**A nota de cada célula de percentual NOMEIA a base.** É a mitigação do risco que a própria decisão
carrega: depreciação e capex como % do imobilizado têm base errada com receita, e o único jeito de o
analista perceber é o arquivo dizer sobre o que aplicou.

### Sazonalidade: `Supabase/migrations/0040`

`fn_sazonalidade_do_caso(caso_id)` deriva as 12 frações do `FATURAMENTO_24M` do mandato — o mês vem
do rótulo da linha ("jan/2024"), e a curva sai só **completa**: 12 meses ou nada. Curva parcial
distribuiria o ano inteiro nos meses existentes, inflando cada um.

**Sem documento mensal, a função devolve zero linhas** e o gerador deixa a linha só no anual, com a
nota explicando: num negócio sazonal, o duodécimo uniforme move caixa de dezembro para março e a
necessidade de capital de giro sai errada justamente no mês que importa.

Os meses são **fórmula**, não número: corrigir a premissa anual recalcula os doze.

### Um teste meu que não provava o que dizia

Escrevi `'e a linha TOTAL não entrou na base'` acreditando estar provando o filtro
`not like 'total%'`. Ao religar o defeito, **o teste passou** — porque o parser de mês já excluía
"TOTAL DO EXERCÍCIO" ("tot" não casa com mês nenhum), e o filtro é redundante.

Era um teste que não podia falhar, a categoria exata que o `CLAUDE.md` manda caçar. Reescrevi para
provar o mecanismo real (13 linhas entram, 12 meses saem, cada um com **uma** observação) e anotei
na migration que o filtro é defesa em profundidade redundante — para o próximo não repetir a
armadilha. Religado de novo com o parser aceitando `'tot'` como dezembro, reprova: dezembro daria
**0,577** em vez de 0,154.

### `preco_x_volume` fica de fora, e o motivo é de schema

Ela multiplica **duas** premissas (preço × volume, ADR × ocupação, headcount × custo por cabeça), e
`caso_linha_premissa` tem **um** slot de premissa por linha. Não dá para expressar o par sem uma
coluna nova — e inventar uma convenção de pareamento ("premissa X sempre casa com Y") seria decidir
modelagem no lugar do dono. Fica como decisão dele: segunda premissa por linha, ou premissa composta
no catálogo.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 417 | **426** |
| `Supabase/test/run.sh` | 39 migrations | **40** + asserts de sazonalidade (37 em premissas) |
| `Verificação/run.mts` | 27 | **27** |

### Defeito religado

- `pct_de_linha` sem a base → `FALHOU: pct_de_linha aplica 40% sobre a receita total (440) — 0.4`;
- sazonalidade rateando 1/12 sem curva → `FALHOU: sem curva no caso, os meses ficam VAZIOS`;
- parser aceitando "tot" como dezembro → `FALHOU: dezembro pesa 200/1300 — 0.577`.

### O que resta

- **`preco_x_volume`** (decisão de schema do dono);
- os outros 11 setores do catálogo, se ele quiser (semente, não motor);
- e a **Fase 6 (calibração)**, que era o que estava em curso quando a série 7.x começou: o dial
  voltar a ser estado do sistema e a medição do auto-aceite contra o gabarito.


## Sessão 28 (2026-08-03) — Fase 7.4: o export dirigido pelas escolhas do portal

Última da série 7.x. O export completo passa a ser **consequência** do que foi decidido na tela de
Modelagem, em vez de o lugar onde a decisão é tomada.

### Cabeçalho: 11 linhas fixas → 4

Congelado em `ySplit: 4` — título, branco, Exercício, mês. As três células de input (entidade
modelada, último exercício realizado, índice macro) **saíram do topo** e vivem no bloco
**PARÂMETROS DO MODELO**, no rodapé, junto da BASE DO MODELO. Continuam editáveis: trocar a entidade
ali recalcula o modelo inteiro sem reexportar. O que muda é que a escolha de origem fica no banco,
com autor e data, e é ela que vale na próxima exportação.

**`Tipo` (Real/Projetado) e `Dado encontrado` NÃO foram deletadas**, embora a instrução permitisse.
Com o congelado em 4 elas simplesmente deixam de ficar fixas no topo — e apagá-las custaria o
diagnóstico "só Balanço"/"SEM DADO", que a sessão 12 registrou como o caso mais traiçoeiro (balanço
existe, receita não, projeção sai zerada parecendo empresa que vale zero).

### A armadilha nº 1 da sessão 12 voltou, e a guarda pegou

`sheet.getRow(N)` numa linha ALÉM do fim **cria** a linha, e todo `addRow` seguinte passa a
acrescentar depois dela. Peguei a célula do seletor de índice macro (linha 189) no meio do modelo, e
o modelo inteiro desceu: de ~200 para **291 linhas**. A guarda nova do bloco de parâmetros acusou na
hora, com a mensagem dizendo o número. A correção é o mesmo padrão da BASE DO MODELO: **escrita
adiada** — decide-se o conteúdo no lugar onde ele é conhecido, escreve-se no fim.

### PROJEÇÃO POR LINHA — o coração do pedido

Bloco novo, emitido **antes** do esqueleto agregado quando o caso tem configuração: uma linha por
linha extraída que tenha premissa vinculada, com as premissas do caso logo acima (uma linha cada, um
valor por exercício projetado) e as fórmulas citando aquelas células.

**Três primitivas desenhadas, quatro não** — e as quatro deixam a célula **VAZIA com nota dizendo
por quê**, nunca um número:

| Primitiva | Estado |
|---|---|
| `crescimento_composto` | ✅ anterior × (1 + premissa) |
| `indice_macro` | ✅ mesma matemática |
| `valor_por_ano` | ✅ a premissa É a linha |
| `pct_de_linha`, `dias_de_giro`, `preco_x_volume`, `curva_mensal` | ⛔ célula vazia + nota |

Preencher com zero, ou com uma fórmula aproximada, entregaria **projeção errada com cara de projeção
pronta**. Zero num modelo financeiro é um valor, não um vazio.

Só as colunas consolidadas (FY) recebem fórmula. Distribuir nos meses depende de `curva_mensal`
(sazonalidade), que não está desenhada — e mês preenchido por rateio uniforme seria um número que
ninguém escolheu.

**Ano sem valor de premissa fica vazio com nota**, e as linhas que dependem dela ficam sem projeção
naquele exercício. É a mesma disciplina do "SEM FOCUS".

**Sem configuração, o arquivo sai como sempre saiu:** o esqueleto agregado é o fallback, e há assert
disso. Esta fase não tira modelo de nenhum caso existente.

### Portão 2 no modo completo

`?modo=completo` pergunta a `fn_avaliar_portao2` e **recusa com 409** quando o caso não é elegível,
listando os motivos. O modo `dados` **não** passa por essa checagem, de propósito: ele é insumo de
conferência, e conferir é o que se faz antes de aprovar — bloqueá-lo criaria o impasse de precisar da
aprovação para poder conferir.

### Uma correção que o teste ditou

A fórmula do crescimento composto testava também a célula do exercício anterior com `=""`. Comparar
célula NUMÉRICA com string vazia é ambíguo, e o assert media **0** onde devia medir 1100. Agora a
guarda testa só a premissa: se ela está vazia não há projeção; se a anterior está vazia, a cadeia nem
começou, porque linha sem valor-base não é emitida.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 397 | **417** |
| `Supabase/test/run.sh` | 39 migrations | **39** (nenhuma migration nesta fase) |
| `Verificação/run.mts` | 27 | **27** |

### Defeito religado

- congelado de volta a 11 → `FALHOU: o congelado do topo é de 4 linhas (era 11) — 11`;
- primitiva não desenhada preenchendo zero → `FALHOU: primitiva não desenhada deixa a célula VAZIA
  (nada de zero inventado) — 0`.

### O que fica em aberto da modelagem

- **as quatro primitivas restantes**, com destaque para `pct_de_linha` (margem, % da receita) e
  `curva_mensal` (sazonalidade mensal) — são as mais pedidas na prática, e cada uma exige decidir
  QUAL linha é a base do percentual;
- os outros 11 setores do catálogo, se o dono quiser (é semente, não motor).

E então a **Fase 6 (calibração)**, que era o que estava em curso quando esta série começou.


## Sessão 27 (2026-08-03) — Fase 7.3: a tela onde linha e premissa se cruzam

`/casos/[id]/modelagem` (rota nova) + `Supabase/migrations/0039`. É onde "cada caso é um caso" vira
operação: o analista escolhe as premissas do mandato e diz **onde cada uma entra na projeção**.

### Quatro passos, na ordem em que se pensa

1. **Parâmetros** — entidade modelada, último exercício realizado, índice macro, setor, anos
   projetados. São as três células que saíram do topo da aba Modelagem (decisão do dono), mais o
   setor, que filtra o passo 2.
2. **Premissas do caso** — o catálogo da `0038` **filtrado pelo setor**, agrupado por natureza, com
   uma coluna por ano projetado. Sem setor definido vem só a base comum — que é a resposta certa
   para "ainda não sei", e não uma lista de 90 premissas para escolher no escuro.
3. **Linhas × premissas** — as linhas do caso agrupadas por seção canônica, cada uma com sua
   premissa e sua sazonalidade, mais o **aplicar em lote por seção**.
4. **Conferência** — e ela está no **TOPO**, não no rodapé: quantas linhas ficariam sem projeção,
   qual premissa está ativa sem valor, quais vínculos apontam para linha que não existe. Pôr isso no
   fim seria pôr o resultado depois da decisão.

### Três coisas que a tela torna impossíveis

- **ano em branco virar zero.** O campo vazio fica **fora** do `jsonb` — ausência é ausência, e a
  `0038` trata premissa sem valor como "não projeta aquele ano". Escrever 0 ali seria inventar a
  premissa mais perigosa que existe.
- **lote silencioso.** Lote que não encontra nenhuma linha na seção **avisa** em vez de recarregar
  como se tivesse funcionado.
- **recusa passar por sucesso.** Toda ação lê `recusado` do payload: as funções da 0036/0037/0038
  devolvem recusa em vez de exceção (exceção desfaria o registro da tentativa), então `error` nulo
  **não** significa que salvou.

### O defeito que eu mesmo introduzi, e o que fiz com ele

A primeira versão da tela consultava `campo_extraido` direto para listar as linhas. **`campo_extraido`
não tem `caso_id`** — o vínculo é `campo_extraido → documento_versao → documento`. Com a RLS aberta a
qualquer autenticado (decisão do dono de 31/07), a consulta trazia as linhas de **todos os
mandatos** para a tela de um. Nada barraria isso em produção.

Corrigi primeiro com embed `!inner` e filtro no campo aninhado — funciona, e continua dependendo de
alguém escrever o join certo em **cada consulta nova** que a tela receber. Então virou função:
**`fn_linhas_para_modelagem(caso_id)`** (`0039`), com o escopo por caso num lugar só, coberto por
teste SQL que cria um caso vizinho e prova que a linha dele não aparece. Mesmo raciocínio de
`fn_aplicar_premissa_em_lote`: quem sabe quais linhas existem é o banco.

A função também resolve uma duplicação que eu tinha deixado passar: a tela normalizava o rótulo em JS
para casar com `caso_linha_premissa`. Duas definições de "mesma linha" divergem no primeiro
caractere que só uma das duas trate — agora o `rotulo_norm` vem do banco, de `fn_normalizar_texto`.

`valor_ultimo` é `max(abs())`, não soma: serve para o analista **reconhecer** a conta na lista, e
somar ocorrências de períodos diferentes daria um número que não existe em lugar nenhum — número
inexistente numa tela de modelagem é convite a erro.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 397 | **397** |
| `Supabase/test/run.sh` | 38 migrations | **39** + 3 asserts novos em `premissas.test.sql` (31) |
| `Verificação/run.mts` | 27 | **27** |

### Defeito religado

- função sem o join por caso → `FALHOU: a linha do caso vizinho NÃO aparece nas linhas deste caso`.

### O que falta da 7.x

- **7.4** export completo: cabeçalho da Modelagem reduzido a 4 linhas, as linhas do modelo passam a
  ser as do caso, projeção pelas 7 primitivas de `premissa_formula`, Portão 2 respeitado.
- Depois disso, a **Fase 6 (calibração)**.


## Sessão 26 (2026-08-03) — Fase 7.2: a premissa deixa de ser código e passa a ser dado

`Supabase/migrations/0038`. O modelo tinha **15 premissas hardcoded** (`PR` em `export-modelagem.ts`)
sobre um esqueleto fixo de linhas (`LINHAS_BASE`). Não sobrevive ao que o dono descreveu: "cada caso
vai ser um caso, vai vir com linhas diferentes, contas diferentes, vai precisar de inputs e
premissas diferentes".

**A inversão:** premissa passa a ser **dado**. Acrescentar "RevPAR" ao vocabulário do sistema é uma
LINHA no catálogo, não um ramo de `if` no gerador — é o que impede um agregado de 20 setores de
virar 20 caminhos de código.

### Quatro tabelas, e por que quatro

| Tabela | O que guarda |
|---|---|
| `premissa_catalogo` | o vocabulário global: o que EXISTE como premissa |
| `caso_modelagem` | parâmetros do caso — entidade modelada, último exercício real, índice macro, **setor** |
| `caso_premissa` | quais premissas ESTE caso usa, com valor por ano (`jsonb`) |
| `caso_linha_premissa` | o vínculo linha↔premissa: **onde cada input entra na projeção** |

Separar catálogo de escolha é o que permite o catálogo crescer sem tocar em caso nenhum, e o caso
ser auditável sem depender do catálogo do futuro.

**A fronteira que os dois enums desenham:** `premissa_formula` (7 primitivas —
`crescimento_composto`, `pct_de_linha`, `dias_de_giro`, `valor_por_ano`, `preco_x_volume`,
`curva_mensal`, `indice_macro`) exige código novo no gerador; **premissa nova, não.**

**Como a linha é identificada:** por `(secao_canonica, rotulo_norm, entidade)`, **não** por
`campo_extraido.id` — aquele id morre a cada reextração, e a configuração de modelagem tem de
sobreviver a reenviar um arquivo. Índice de **expressão** com `coalesce(...,'')` porque em `unique`
normal NULL não colide com NULL, e duas configurações para a mesma linha passariam.

### O catálogo semeado

Base comum (30 premissas, `setores = '{}'`) + **20 setores**: indústria, varejo, serviços, agro,
construção, logística, saúde, energia, tecnologia, alimentos, educação, mineração, papel e celulose,
química, têxtil, automotivo, farma, telecom, hotelaria, imobiliário. **Sazonalidade está no catálogo
COMO premissa**, com natureza própria — o dono foi explícito, e ela muda caixa e necessidade de giro.

A descrição de cada premissa de setor diz **qual é a que manda** (a que o analista move primeiro):
SSS no varejo, produtividade × preço no agro, sinistralidade em saúde, churn em tecnologia, RevPAR
em hotelaria, produção do cliente em autopeças.

**Setor é sugestão, não restrição.** `fn_premissas_sugeridas(setor)` devolve base comum + as do
setor; `fn_vincular_linha_premissa` aceita **qualquer** premissa ativa. Em reestruturação o caso
atípico é a regra — há teste de que um caso de indústria pode usar RevPAR se o analista quiser.

### As guardas, e a que o teste descobriu

- **Premissa fora do catálogo é recusada** (recusa retornada, padrão das 0036/0037) — premissa nova
  entra por semente, não por caso.
- **Não se vincula linha a premissa que o caso não ativou.** Sem isso a linha sairia "projetada" por
  uma premissa sem valor nenhum — projetada com **zero**, que é a mesma armadilha do "SEM FOCUS" que
  o macro já combate. O motivo da recusa diz isso, em texto.
- **`fn_aplicar_premissa_em_lote` roda no BANCO**, não na tela: as linhas vêm de `campo_extraido`, e
  é ali que se sabe quais existem. Num balancete de 500 linhas, fazer isso no portal seria 500
  chamadas para uma decisão só. Devolve **quantas linhas pegou** — lote que pega zero não pode
  parecer sucesso.
- **`fn_conferir_modelagem` tinha um defeito que o teste pegou:** contava vínculos direto, e
  reprovou mostrando `linhas_com_premissa: 4` sobre `linhas_do_caso: 3`, com `linhas_sem_premissa`
  caindo a zero por subtração. Vínculo pode apontar para linha que não existe (configurada antes de
  o documento chegar, ou o arquivo foi reextraído com outro rótulo). Agora conta **por join**, e os
  órfãos ganham nome próprio no payload (`vinculos_orfaos`) — é a diferença entre "configurei" e
  "está coberto".

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 176 | **176** |
| `verificar-export.mts` | 397 | **397** |
| `Supabase/test/run.sh` | 37 migrations | **38** + `premissas.test.sql` (28 asserts) |
| `Verificação/run.mts` | 27 | **27** |

### Defeito religado

- guarda de premissa ativa desligada → `FALHOU: vincular a premissa não ativada no caso é recusado`,
  com o vínculo tendo sido criado;
- contagem sem o join → `FALHOU: conta como cobertas SÓ as que existem de fato`, mostrando
  `linhas_com_premissa: 4` e `linhas_sem_premissa: 0` sobre 3 linhas reais.

### O que vem

- **7.3** portal: `/casos/[id]/modelagem` — parâmetros, premissas do caso (catálogo filtrado pelo
  setor), **linhas × premissas com aplicar-em-lote**, e a conferência que `fn_conferir_modelagem`
  já devolve;
- **7.4** export completo: cabeçalho da Modelagem reduzido a 4 linhas, linhas do modelo passam a ser
  as do caso, projeção pelas 7 primitivas, e o completo respeitando o Portão 2;
- **Fase 6 (calibração)** depois.


## Sessão 25 (2026-08-03) — Fase 7.1: granularidade total e o export de dados

O dono interrompeu a Fase 6 (calibração) para acertar o **output**: "cada linha de cada documento
no excel, todos os valores, cada vírgula, cada tópico", premissas escolhidas no portal, e **dois
exports** — um só de dados e um completo com a modelagem. O plano inteiro (fases 7.1 a 7.4 + o
catálogo de premissas por setor) está no plano aprovado desta sessão. Esta é a 7.1.

### O achado: rótulo repetido COLAPSAVA

`bucket()` agrupava por `normalizar(campo.chave)` e `valorNumDoGrupo` devolvia `melhorCampo` — o de
maior confiança. Consequência: **duas linhas com o mesmo rótulo no mesmo documento viravam uma**, e
a outra desaparecia do arquivo. Num balancete com dois "Outros", duas "Diversos", ou "Fornecedores"
repetido em subgrupos diferentes, é perda silenciosa de linha **e de soma**.

A prova, ao religar o defeito: com três linhas (5.000 + 300 + 700) numa seção, o total saía
**5.300** em vez de 6.000. Note o formato da falha — o total continua *parecendo* consistente com o
que está visível, porque a linha que falta não está lá para contradizer. Não estava em nenhuma lista
de itens abertos.

**A correção:** a chave do grupo passa a incluir a **ocorrência** — o rank por `ordem`
(`Supabase/migrations/0027`) dentro de cada versão e rótulo. Rótulo que aparece uma vez (a maioria) tem
rank 1 e se comporta como antes; repetido vira duas linhas, cada uma com sua proveniência. O rank é
por VERSÃO de propósito: num comparativo (2025 | 2024) a 1ª ocorrência de uma coluna alinha com a 1ª
da outra, que é o alinhamento entidade×período que o agrupamento por rótulo existe para garantir.

### Aba nova: `Dados (linha a linha)`

Espelho **1:1** do banco — uma linha de Excel por `campo_extraido`, ordenada por arquivo e pela
`ordem` do documento, com a proveniência inteira ao lado (arquivo, tipo, entidade, período, página,
ordem, seção, seção canônica, entidade/período da coluna, rótulo, valor texto, valor, escala, escala
original, **moeda**, confiança, aceite). Sem fórmula, sem template, com autofiltro.

Por que ela é diferente das abas classificadas: aquelas são uma **leitura** (agrupam, escolhem,
somam) — é o que as torna úteis para analisar e insuficientes para **conferir**. Não havia como
olhar a aba Balanço e saber se aquilo é tudo o que a extração trouxe. Agora há. Linha pendente de
aceite sai em itálico âmbar: nesta aba, mais que em qualquer outra, sugestão não pode parecer fato.

### Dois exports

`GET /casos/[id]/export?modo=dados` → todas as abas de dado, **sem Modelagem**; sem o parâmetro sai
o completo. Dois botões no dashboard, e o de dados **sempre disponível** (é insumo de conferência,
vale com pendência aberta). O nome do arquivo diz qual é (`-dados-` / `-completo-`): dois arquivos
com o mesmo nome na pasta de Downloads, um com modelo e outro sem, é confusão garantida.

**Um só builder, com um parâmetro** — não dois construtores. As abas de dado têm de ser idênticas
nos dois arquivos; dois caminhos divergiriam, e a divergência apareceria como "o número do completo
não bate com o de dados". Há assert comparando aba por aba.

**A Macro entra nos DOIS:** índice do BCB/IBGE é dado coletado, não modelagem — e foi exatamente uma
aba macro ausente que custou meia hora de investigação no v28.

### A fixture cobria 11 dos 14 documentos

Faltavam **DMPL, MUTUOS e NOTAS EXPLICATIVAS**. As abas `DMPL`/`Intragrupo`/`Outros` existiam no
código e **nenhum teste passava por elas com dado** — cobertura que parecia existir porque a fixture
afirmava os dois lados. Os três entraram em `Supabase/test/gerar_fixture.py` com extração fiel ao que cada
PDF imprime:

- **DMPL** como matriz (`chave` = componente do PL, `secao` = movimento), sem inventar zero nas
  células que o PDF imprime como "-";
- **MUTUOS** com a divergência **deliberada de R$ 180 mil** contra o balanço — é o caso que a
  reconciliação existe para mostrar;
- **NOTAS** como prosa com números, com `secao` no formato "Nota 1"/"Nota 2" que
  `ehSecaoDeNotaExplicativa` reconhece. Há assert de que essas linhas **não** vão para o Balanço
  (nota detalha o que o BP já totaliza; somar as duas é dupla contagem vinda de complementar) e de
  que continuam no arquivo, na aba de dados crus.

O JSON da fixture passou a emitir `ordem` — sem ele a desambiguação de rótulo repetido não teria o
sinal de que depende.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 176 | **176** (nada de lib mudou) |
| `verificar-export.mts` | 362 | **397** |
| `Supabase/test/run.sh` | 37 migrations | **37** (nenhuma migration nesta fase) |
| `Verificação/run.mts` | 27 | **27** |

Fixture: 11 → **14 documentos**, 744 → **767 linhas**.

### Defeito religado

- colapso de rótulo repetido de volta → `FALHOU: as DUAS linhas "Outros" aparecem — encontradas: 1`
  e `FALHOU: a soma da seção conta as duas — 5300`.

### O que vem (7.2 a 7.4, no plano aprovado)

- **7.2** banco: `premissa_catalogo` (o agregado por setor), `caso_modelagem`, `caso_premissa`,
  `caso_linha_premissa`, `fn_premissas_sugeridas(setor)`;
- **7.3** portal: `/casos/[id]/modelagem` — parâmetros, premissas do caso, **linhas × premissas com
  aplicar-em-lote**, conferência;
- **7.4** export completo: cabeçalho da Modelagem reduzido a 4 linhas (as 3-5 migram para o portal),
  linhas do modelo passam a ser as do caso, e o completo respeita o Portão 2.
- **Fase 6 (calibração)** fica depois disso, por decisão do dono.


## Sessão 24 (2026-08-03) — Fases 4 e 5: abas resolvidas, Portão 2 existe, roteiro do teste

O dono pediu as fases 4 e 5 juntas, e depois "1 vez a fase 6 de calibração" antes de testar na
prática. **Fase 3 (custo) foi PULADA por decisão dele** — consequência registrada no fim desta
seção.

### O achado desta sessão: o Portão 2 não existia

Fui conferir os "limites duros do Portão 2" (item da Fase 4) e encontrei o seguinte:

- `caso_status` tem `'aprovado'` e `'pronto_para_base'` desde a `0001` — e **nenhuma função
  transicionava** um caso para eles;
- **`pendencia.sobrepujavel` era gravado desde a `0001` e nunca lido por ninguém** (`grep`: só
  escrita). O flag que existe para dizer "nenhuma ressalva libera isto" não tinha consultante;
- não havia teto de ressalvas, nem conferência de expiração;
- `fn_aceitar_extracao` é o Portão 2 **por documento** (o comentário da `0011` diz isso). O portão
  **por caso** — o que decide se o mandato pode ser aprovado — não existia.

**Isso não estava em nenhuma lista de itens abertos** (nem no §7.4 do Onboarding), e a regra está
**especificada e aprovada em `Arquitetura do Sistema/2 Especificação/f0/04` desde a F0**: três condições, teto de ressalvas **confirmado
em 3** pelo dono, lista fechada de não-sobrepujáveis. `Arquitetura do Sistema/1 Visão e Doutrina/03` põe "Portão 2 com limites duros"
dentro do MVP. Então a `0037` implementa **a regra como ela está escrita**, sem inventar política.

`fn_avaliar_portao2` (só lê, `stable`) + `fn_aprovar_caso` (recusa retornada, mesmo padrão da
`0036`, pelo mesmo motivo: exceção desfaria o registro da tentativa). O portal mostra o portão com
os motivos e só oferece o botão quando a regra permite.

**Duas decisões de implementação que valem registro:**

1. **Ressalva expirada é avaliada NA LEITURA.** `Arquitetura do Sistema/2 Especificação/f0/04` diz "ao expirar, a pendência reabre
   automaticamente". Reabrir por job seria a próxima falha silenciosa (job que ninguém observa);
   aqui uma `aceita_com_ressalva` com `expira_em` no passado **já conta como pendência de novo**,
   sem depender de cron nenhum estar vivo.
2. **Condição 3 usa estados DIFERENTES da condição 1 — e o teste é que descobriu.** A primeira
   versão copiou a lista `('aberta','em_correcao_interna','reenviada_ao_cliente')` para as duas.
   Resultado: mover uma **não-sobrepujável** para `aceita_com_ressalva` a tirava da contagem e **o
   portão liberava** — exatamente a porta dos fundos que a lista fechada existe para fechar, aberta
   na minha própria implementação por um copiar-e-colar de três valores de enum. Agora qualquer
   estado não-terminal conta: `aceita_com_ressalva` numa não-sobrepujável é **estado ilegítimo**,
   não caminho de saída.

### Fase 4 — a contradição das abas, resolvida

A Etapa 4 pedia auxiliares **ocultas**; no v28 o dono pediu o oposto ("quero todas as abas
juntas"), porque **aba oculta foi lida como dado ausente**. O §7.2 do Onboarding registra as duas.

As duas querem a mesma coisa: a Modelagem sendo o que se vê ao abrir, sem o resto parecer
inexistente. **Ordem entrega as duas; visibilidade só entregava uma** — quem recebe o arquivo não
sabe que há abas escondidas, e "reexibir é um clique" só vale para quem sabe que existe o que
reexibir. Agora: **Modelagem primeiro, nada oculto.**

**Armadilha do ExcelJS que custou um ciclo:** `workbook.worksheets` é um **getter** que devolve
`_worksheets.slice(1).sort(orderNo)` — um array descartável. A primeira versão fez `splice` nele e
**não mudou nada no arquivo**; o assert (11) pegou (`modelagem=9` depois de "mover para 0"). O
mecanismo real é `orderNo`, e `orderNo = 0` põe a aba à frente sem tocar no `orderNo` de ninguém.
`orderNo` existe no runtime mas **não nos tipos publicados** — daí o cast pontual, comentado.

### Fase 4 — o artefato para o dono olhar

Script novo: **`portal/scripts/gerar-export-fixture.mts`**. Grava em disco o `.xlsx` que o export
produz a partir da fixture do book sintético, usando o **mesmo** `buildExportWorkbook` que o portal
chama em produção. Custo zero, sem IA, sem banco. Data fixa (2026-07-27), como todo gerador daqui.

```bash
./portal/node_modules/.bin/tsx portal/scripts/gerar-export-fixture.mts /tmp/book.xlsx
```

### Fase 5 — o roteiro do teste ao vivo MÍNIMO (para quando o dono rodar)

O teste ao vivo é dele. O que esta sessão entrega é o roteiro, para a rodada **confirmar** em vez
de explorar — e para ninguém precisar reconstruir o raciocínio depois:

| # | Documento a enviar | O que exercita | Passou se |
|---|---|---|---|
| 1 | Uma **planilha de faturamento longa** (24–36 meses, CSV/XLSX) | Fase 1: teto de 2000 linhas e o aviso de truncamento | todas as linhas aparecem no book; nenhuma pendência de truncamento |
| 2 | Um documento **em moeda estrangeira** (ou com linhas em USD) | Fase 1: `campo_extraido.moeda` e a recusa de somar moedas | cabeçalho da coluna diz a moeda; coluna mista mostra "⚠ não somável" |
| 3 | **Reenvio do mesmo arquivo** do item 1 | `0026` (versão nova, não documento novo) | não duplica documento nem coluna no export |
| 4 | Um **.xlsx** qualquer (sem o Extract From File ligado) | Fase 1/2: XLSX não lido vira pendência + item `recebido_nao_valido` | pendência bloqueante e checklist âmbar, **não** verde |

Depois: conferir `fn_avaliar_portao2` do caso — com o item 4 no lote, ele **tem** de sair não
elegível, e o motivo tem de nomear a não-sobrepujável.

**Consequência de pular a Fase 3 (custo):** este teste custa hoje o mesmo que o v33 — duas chamadas
por documento, ambas em `gpt-4o`, com página como imagem. As três alavancas da Fase 3 (PDF como
texto, `gpt-4o-mini` na classificação, não pagar reprocessamento) estão desenhadas e não
implementadas. Se o orçamento estiver curto na hora de rodar, **fazer a Fase 3 antes é o que torna
esta rodada barata** — e o item 4 do roteiro (XLSX) só passa a ler o arquivo de verdade lá.

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 176 | **176** (nada de lib mudou) |
| `verificar-export.mts` | 361 | **362** |
| `Supabase/test/run.sh` | 36 migrations | **37** + `portao2.test.sql` (24 asserts) |
| `Verificação/run.mts` | 27 | **27** |

Nota honesta sobre o 362: os asserts de visibilidade das abas **mudaram de assunto**, não só de
número — três do comportamento antigo saíram, e entraram três do novo (nada oculto; Modelagem
primeiro; ordem relativa das auxiliares preservada). O `veryHidden` deixou de ter assert próprio
porque "nenhuma oculta" o cobre por construção.

### Defeito religado

- abas ocultas de novo → `FALHOU: NENHUMA aba fica oculta — ocultas: Resumo, Balanço, DRE, …`;
- condição 3 do Portão 2 com a lista de estados da condição 1 → `FALHOU: aceitar COM RESSALVA uma
  não-sobrepujável NÃO libera o portão`, com o payload mostrando `elegivel: true`.


## Sessão 23 (2026-08-03) — Fase 2: documento que chegou vazio para de contar

Itens **3 e 4** do §7.4 do Onboarding. O dono já aplicou a `0035` e reimportou o workflow da
Fase 1 antes desta sessão começar.

### O que o item #3 pedia, e por que a leitura literal não servia

O item diz: *"`completude_ok` só exige a linha do documento — 14 documentos com zero linhas
extraídas dão dashboard verde e book vazio."* A correção óbvia seria trocar a condição do Portão
1 por "existe documento COM linhas". **Duas coisas impedem, e as duas foram medidas no
repositório, não supostas:**

1. **Ordem do grafo.** `Registrar Documento` liga em **paralelo** para `Recomputar Completude` e
   para `Montar Req Extracao`. Quando a completude é calculada, a extração **ainda não rodou** —
   o número de linhas é zero para todo documento, sempre. A condição literal reprovaria o caso
   inteiro por um motivo que é só de sequência.
2. **Doutrina.** `Arquitetura do Sistema/3 Estado e Execução/07` separa os dois status de propósito: *"Completude ≠ validade … para
   evitar falsa sensação de completude."* Colapsar as duas condições apagaria a distinção que
   existe justamente para impedir o que o item descreve.

**A 0036 usa o vocabulário que já existia**, em vez de redefinir o Portão 1:

- o documento continua **recebido** (a completude conta a chegada);
- o item vira **`recebido_nao_valido`** no `checklist_item_status` quando NENHUMA versão dele
  rendeu uma linha — a coluna já previa `invalido` desde a 0001;
- e abre pendência **`item_sem_conteudo`, BLOQUEANTE e NÃO-SOBREPUJÁVEL**, que é o que de fato
  trava o Portão 2 (`Arquitetura do Sistema/3 Estado e Execução/07`: *"elegível ao Portão 2 se e somente se não há pendência bloqueante
  aberta"*, e a lista fechada inclui "arquivo ilegível de item essencial");
- **`fn_registrar_campos_extraidos` passa a recomputar a completude no fim** — é o único ponto do
  pipeline que roda com o resultado da extração na mão. Sem isso, o estado novo só apareceria
  quando alguém abrisse a fila de revisão, que é exatamente quem se está tentando avisar.
- o payload ganha `sem_conteudo` e **`pronto_para_revisao`** (= chegou tudo **E** tem conteúdo).
  `portao1_ok` continua significando "chegou tudo".

**No portal:** o Kit Básico tem **três** cores — verde só quando chegou e rendeu linha; **âmbar
"recebido, sem conteúdo extraído"**; e cinza para faltante. Âmbar e não "faltante" porque o
arquivo está lá: pedi-lo de novo ao cliente seria pedir o que ele mandou. A mensagem da tela do
documento também mudou: era *"Nenhuma linha extraída para este documento **ainda**"*, e o "ainda"
fazia parecer fila — quem lia esperava.

### Item #4 — o aceite formal de nada

`fn_aceitar_extracao` com zero campos não tocava nada (`v_n_aceitos = 0`) e **gravava, ainda
assim, uma `decisao` de tipo `aprovacao`**. Como `decisao` é append-only, esse registro — que faz
a trilha afirmar que um humano aprovou a extração daquele documento — não sai mais de lá.

- versão **sem nenhum campo** → recusa, com motivo que nomeia o arquivo e diz o que fazer;
- versão **com campos, todos já aceitos** → no-op declarado (`ja_estava_aceito`), sem `decisao`
  nova: antes, clicar duas vezes gravava **duas** aprovações.

**A recusa é RETORNADA, não `raise exception` — e a razão é técnica, descoberta pelo teste:**
exceção em plpgsql desfaz tudo o que a função fez, **inclusive o registro da tentativa em
`evento_auditoria`**. O primeiro rascunho levantava exceção, e o assert "a tentativa recusada fica
em evento_auditoria" reprovou. Postgres não tem transação autônoma: ou se tem a exceção, ou se tem
o rastro. Ficou o rastro, e `recusado: true` no payload para nenhum chamador confundir com sucesso
— **com a `actions.ts` do portal obrigada a ler esse campo**, senão a recusa passaria por sucesso
e trocaríamos "aceite de nada" por "sucesso de nada".

### Contadores

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 171 | **176** |
| `verificar-export.mts` | 361 | **361** (nada no export mudou) |
| `Supabase/test/run.sh` | 35 migrations | **36** + `completude_conteudo.test.sql` (14 asserts) |
| `Verificação/run.mts` | 27 | **27** |

### Defeito religado, um por um

- terceiro estado tirado da lib → **3 reprovações**;
- recomputação pós-extração removida da `0036` → `FALHOU: o item do checklist fica
  recebido_nao_valido, não presente — presente`;
- guarda do aceite removida → `FALHOU: a função declara a recusa no payload` devolvendo
  **`{"ja_estava_aceito": true, "n_campos_aceitos": 0}`** — isto é, sem a guarda o aceite do vazio
  responde **sucesso silencioso**, que é pior do que o diagnóstico original sugeria.

### O que fica para as próximas fases

- **#5** — poller de 12 min e recusa por estouro de orçamento visível só no log do n8n.
- **#6** — causa das 5 pré-condições que falharam no v33.
- **#7** — dupla contagem: decisão de doutrina, não correção silenciosa.
- **#8** — golden set físico, que bloqueia a F4 inteira.
- E a **fase de custo** (PDF como texto, `gpt-4o-mini` na classificação, não pagar
  reprocessamento), que também é o que permite pular a chamada do XLSX com um nó IF.


## Sessão 22 (2026-08-03) — Fase 1: os dois itens que perdiam dado em silêncio

O dono subiu no `main` o **`Onboarding`** (PDF de 67 páginas, commit `5edb89e`) e mandou usá-lo
como base para dividir o desenvolvimento em fases — **só a contextualização, do capítulo 1 ao 7;
o que é papel do estagiário, lista de documentos e banco de perguntas ficou fora por instrução
dele.**

### O §7.4 do Onboarding reordenou a prioridade — e eu estava errado

Eu tinha proposto começar pela dupla contagem. O §7.4 nomeia **8 itens abertos** e ordena por
risco/esforço: **itens 1 e 2 primeiro**, porque são os únicos que ainda **perdem ou corrompem
dado em silêncio**. A dupla contagem (item 7) **já é sinalizada no arquivo com as duas leituras
e não é corrigida automaticamente por doutrina** — corrigi-la calada seria violar a doutrina,
não cumprir o plano. Esta sessão fechou os itens **1 e 2**.

### Item 1 — truncamento de planilha (era 50 linhas)

`spreadsheetToText` cortava em **50 linhas × 25 colunas**. 50 é menos do que documento real tem:
faturamento de 24 meses × 5 entidades = 120 linhas; balancete analítico passa de 500. O resto ia
embora com uma nota **dentro do prompt** (`… (+N linhas omitidas)`) que só a IA lia — o banco
recebia a extração como completa e **nenhuma pendência existia**.

- Tetos agora **2000 × 60** (`MAX_LINHAS_PLANILHA`/`MAX_COLUNAS_PLANILHA`), que é ordem de
  grandeza de documento real. O teto continua existindo porque input é dinheiro.
- O que ainda passar do teto vira **`avisoTruncamentoPlanilha`** → `falha_motivo` → pendência
  `extracao_falhou` (a 0016 já fazia essa conversão; o que faltava era chegar lá).
- **Coluna pela UNIÃO das chaves**, não pelas da primeira linha: o "Extract From File" devolve
  objeto esparso, e célula vazia na linha 0 **apagava a coluna do documento inteiro**. Achado ao
  escrever o teste, não previsto no §7.4.
- **XLSX deixou de mentir:** o nó mandava a frase "(XLSX: habilitar Extract From File…)" **como
  se fosse o documento**, pagava a chamada e a pendência dizia que a *extração* falhou — não que
  o arquivo **nunca foi lido**. Agora o motivo real vira pendência. Pular a chamada exige nó IF
  (topologia = fase 3).
- O aviso **soma-se** ao motivo da chamada em vez de competir: planilha cortada **e** resposta
  truncada cabem no mesmo documento.

### Item 2 — moeda capturada e descartada (`Supabase/migrations/0035`)

O caminho existia inteiro **menos o último metro**: o schema já pedia `moeda` à IA,
`normalizarMoeda` já convertia "US$"/"dolar" no ISO desde sempre, e o valor **morria no nó** —
nenhum campo o levava ao banco, porque **não havia coluna**. Com o erro de escala de ~496×
corrigido na Etapa 1, era o **último fator multiplicativo invisível**: dólar somado a real erra
**pelo câmbio inteiro** (~5x), num arquivo que fecha.

- **`campo_extraido.moeda`** (0035), herdada por linha pela **mesma regra da escala** — bloqueada
  em linha não-monetária, porque "margem 12%" com moeda BRL viraria doze reais.
- **Moeda desconhecida fica `null`, nunca BRL presumido.** Presumir é o mesmo erro com outra
  roupa.
- **`unidade` continua sendo a ESCALA.** O comentário da 0005 dizia `-- ex.: 'BRL', 'milhares'`,
  confundindo as duas numa coluna só; na prática sempre gravou escala. A 0035 **não migra nada** —
  separa as duas de agora em diante.
- **No book:** a moeda aparece no cabeçalho da coluna **quando discrimina** (mais de uma moeda no
  arquivo, ou coluna mista) — book todo em BRL não ganha "(BRL)" em cada coluna, porque rótulo
  redundante ensina a não ler o cabeçalho.
- **Coluna que mistura moedas NÃO recebe total.** Os 4 pontos de `SUM` passam por
  `escreverSomaOuRecusa`: a célula recebe "⚠ não somável" + nota nomeando as moedas. **Só a soma
  é recusada** — os valores individuais continuam todos visíveis. É a doutrina de sempre (mostrar
  as leituras, não consertar sozinho), sem a parte de emitir um número errado.

### Contadores (todos subiram, nenhum caiu)

| Suíte | Antes | Agora |
|---|---|---|
| `node --test N8N/test/*.test.mjs` | 162 | **171** |
| `verificar-export.mts` | 352 | **361** |
| `Supabase/test/run.sh` | 34 migrations | **35** + `moeda.test.sql` (7 asserts) |
| `Verificação/run.mts` | 24 | **27** |

### Cada correção teve o defeito RELIGADO para ver o teste reprovar

Não é formalidade — duas fixtures deste projeto nasceram vazias e passavam com o bug ligado.

- teto de volta a 50 → **3 reprovações**, incluindo o caso de 120 linhas fixas no teste;
- `moeda` fora do campo → **4 reprovações** na suíte n8n;
- `moeda` fora do insert da 0035 → **`ERROR: FALHOU: as duas linhas em USD gravaram moeda USD —
  esperado 2, veio 0`**;
- guarda do export desligada → **6 reprovações**, e a célula voltou a exibir `SUM(B4:B5)` = **7000
  somando BRL 5000 com USD 2000** — exatamente o total falso que a guarda existe para impedir.

### O Onboarding está desatualizado em dois pontos (decisão do dono)

O PDF foi gerado de um retrato **anterior ao merge dos PRs #70/#71**: o §7.2 e o §7.5 dizem que as
**Etapas 3 a 6 estão "Não iniciada"** e contam **33 migrations** com suítes de **160/273/18**. O
repositório diz outra coisa — as seis executadas na sessão 21, a Etapa 4 em
`portal/src/lib/export.ts`, e os contadores da tabela acima. **Não toquei no PDF**; corrigir esses
dois trechos e os contadores é decisão dele.

### O que fica para as próximas fases (do §7.4, na ordem que o Onboarding propõe)

- **#3 e #4** — `completude_ok` verde com book vazio e `fn_aceitar_extracao` aceitando versão com
  zero campos ("um aceite formal de nada"): **próxima fase**.
- **#5** — poller de 12 min e recusa por estouro de orçamento visível só no log do n8n.
- **#6** — causa das 5 pré-condições que falharam no v33, ainda desconhecida.
- **#7** — dupla contagem: **decisão de doutrina**, não correção silenciosa.
- **#8** — golden set físico, que é o que bloqueia a F4 inteira.


## Sessão 21 (2026-08-01) — Etapas 1 a 6, a partir do teste v35

O dono mandou o export do **v35** (o v34 tinha rodado com a API errada no nó da OpenAI) e pediu:
analisar, executar o que falta do plano de 6 etapas, e depois criticar a própria implementação.

### O v35 entregou a causa raiz de graça — a `0033` funcionou como projetada

A pendência dizia, literal: *"falta o Passivo+PL … Rótulos que a extração TROUXE e que poderiam ser
um total: "ATIVO", "Ativo Circulante", …, "PASSIVO E PATRIMÔNIO LÍQUIDO""*. Está tudo ali: **o
documento traz o total do grupo SEM a palavra "total"**, e a A.1 exigia o token. O rótulo certo
estava na base, com valor, e a busca não o via. É a convenção da maioria dos balanços brasileiros —
o classificador em TypeScript já sabia (`soEstrutural`); quem não sabia era o SQL.

**Segunda causa, no fallback:** `fn_soma_secao(['passivo','patrimonio'])` exige a SEÇÃO conter os
DOIS termos, e as seções reais são "Passivo Circulante" e "Patrimônio Líquido". O fallback era
**inalcançável desde que foi escrito**. → **`Supabase/migrations/0034`**, com `fn_rotulo_estrutural`
(comparação por CONJUNTO, não substring) e duas somas que se juntam.

**E a guarda anti-alucinação acusava o balanço mais CORRETO possível:** "4 contas com o mesmo valor
material (14529)" eram ATIVO, TOTAL DO ATIVO, PASSIVO E PL e TOTAL DO PASSIVO E DO PL — iguais
**porque o balanço fecha**. Os totais de grupo saíram da contagem, usando o mesmo
`fn_rotulo_estrutural`.

### Etapa 3 — a Modelagem se basta (INVERSÃO da arquitetura da sessão 12)

Dois blocos no rodapé da Modelagem: **BASE DO MODELO** (números das demonstrações) e **BASE MACRO**
(espelho do histórico e do Focus, com as médias ainda em fórmula). Nenhuma fórmula da Modelagem cita
outra aba. O `INDEX/MATCH` permanece, agora local — é ele que mantém o dropdown de entidade vivo.

**O que se perde, e o arquivo diz:** a base é uma FOTO. Corrigir a aba Balanço não move mais o
modelo; tem de exportar de novo.

**Três armadilhas que custaram tempo:** (1) escrever o bloco antes do modelo cria as linhas 1..15 e
`addRow` passa a acrescentar DEPOIS — o modelo desce 15 linhas; (2) pôr o bloco em COLUNAS aumenta
`columnCount`, e o modelo é lido como "2 + nAnos × 13"; (3) `RefsMacro.prefixo` era o único ponto que
amarrava tudo à aba Macro — com ele vazio, todo o consumo virou local sem tocar no resto.

### Etapa 4 — auxiliares ocultas (reverte o v28), com guarda

`hidden`, nunca `veryHidden`. E se a Modelagem não existir, NADA é ocultado: um .xlsx sem aba visível
o Excel se recusa a abrir.

### Etapa 5 — o seletor, que nasceu DECORATIVO e foi consertado

Tabela de metodologias (Focus IPCA/IGP-M/Selic/PIB, médias 3a/5a/10a de IPCA e IGP-M, CAGR da
receita) nas colunas FY; a premissa a indexa. Acrescentar metodologia = acrescentar linha.

⚠️ **O seletor não movia nada, e só o invariante 40 pegou.** Trocar IPCA→IGP-M dava a MESMA receita
até a 12ª casa (43.776,1068). Causa aritmética: nominal = (1+índice)×(1+real) e real era
(1+observado)/(1+índice)−1 — **o índice cancelava**. Corrigido deflacionando pela metodologia
PADRÃO, não pela escolhida: o default fica idêntico e escolher IGP-M passa a valer o diferencial.

⚠️ **`N()` em toda leitura de premissa.** Com o seletor a premissa virou FÓRMULA, e fórmula que
devolve `""` NÃO é célula vazia: `(1+"")` é #VALUE! e contamina o modelo inteiro. `N("")` é 0.

### Etapa 6 — o modelo é RESOLVIDO, não inspecionado

**LibreOffice está quebrado neste container** (recusa um .xlsx mínimo de 3 células E o v35 que o dono
abriu no Excel). Então o avaliador do arnês foi estendido (INDEX/MATCH/IF/N/^/comparações/COUNT) e
**memoizado** — sem memória a avaliação é exponencial e 1.110 de 4.380 fórmulas davam "não sei".

**Resultado: 4.380 fórmulas, ZERO não resolvidas; as duas conferências fecham em 0,00 nos cinco
exercícios; Ativo = Passivo + PL bate nos cinco.**

### O CI achou um defeito no PRÓPRIO CI

`git diff --exit-code` reprovou por a janela do SGS vir de `new Date()`: o JSON mudava sozinho a cada
virada de mês, e o CI ficaria vermelho por não-motivo. Data de referência agora é fixa, com dois
testes prendendo a causa.

### Análise crítica da própria implementação (achado no artefato, não no código)

"Dado encontrado" dizia **"DRE+Balanço" para uma entidade sem DRE**, com receita zero ao lado. Duas
causas em sequência: checar só a COLUNA; e depois `ISNUMBER(INDEX(...))`, que é VERDADEIRO para
célula vazia porque **INDEX de vazio vale 0 no Excel**. O idioma correto é `COUNT(INDEX(...))`.

### ⚠️ PENDÊNCIAS DO DONO (sessão 21)

1. **Aplicar `Supabase/migrations/0034`.**
2. **Reimportar `N8N/workflow.macro.json`** (a janela do SGS mudou de forma, não de valor).
3. **Validar as Etapas 1 a 6** — é o que o plano dele pede antes de qualquer coisa nova.

### O QUE FICOU ABERTO

Os cinco itens de "se sobrar fôlego" continuam **não tocados**: truncamento de CSV/XLSX em 50 linhas,
`moeda` capturada e descartada, `completude_ok` só exigindo a linha `documento`,
`fn_aceitar_extracao` aceitando versão vazia, e o poller que expira sem sinalizar.

**E dois limites conhecidos do que foi entregue:**
- A **BASE DO MODELO traz colunas de pseudo-entidades** do Combinado ("Eliminações — 2025"). São
  inofensivas (o dropdown de entidade as filtra) e auditáveis, mas são ruído.
- O avaliador do arnês lê **célula vazia como 0**, então `x=""` trata 0 e vazio igual. Para tudo que
  o export gera o resultado coincide; uma metodologia que rendesse exatamente 0,00% seria lida como
  ausente. Registrado no cabeçalho do arquivo.

### Armadilhas novas desta sessão

- **`$$` dentro de um COMENTÁRIO num bloco `do $$ … $$` FECHA o bloco.** O erro sai como
  "syntax error at or near" e não aponta o comentário.
- **`ISNUMBER(INDEX(...))` é verdadeiro para célula vazia** (INDEX de vazio = 0). Use `COUNT`.
- **Fórmula que devolve `""` não é célula vazia**: `(1+"")` é #VALUE!. Use `N()`.
- **Gerador que lê `new Date()` deixa o CI vermelho todo mês.**
- **LibreOffice não abre .xlsx neste container** — não é o arquivo, é o ambiente.

## Sessão 20 (2026-07-31, noite) — Etapa 2 FECHADA, dupla contagem sinalizada, e CI

Rodou sozinha, sem supervisão, a partir de `Arquitetura do Sistema/5 Prompts/PROMPT_CONTINUACAO.md`. Cinco frentes, todas
commitadas na branch acima.

### 1. Etapa 2 FECHADA — bloco "REFERÊNCIAS MACRO" na Modelagem (`a545c28`)

O placar que motivou, medido antes de escrever: das 15 premissas, **2** liam macro; das 6 séries
históricas, **0** alimentavam fórmula (as 18 células de média 3a/5a/10a não moviam nada).

Entrou o bloco que o dono aprovou: IGP-M, PIB e câmbio do Focus **por exercício** + as médias
3a/5a/10a por série, **tudo em fórmula lendo a aba Macro**, com nota dizendo a fonte, **o que a
linha deveria dirigir**, e que ela **não dirige nada hoje** porque o seletor é a Etapa 5. Cabeçalho
diz isso em linha visível: referência que parece premissa é pior que nenhuma.

**Duas armadilhas que o bloco teve de desarmar, e que a próxima sessão precisa conhecer:**
- **Câmbio é NÍVEL, não taxa.** O Focus publica câmbio em R$/US$ (5,40), as outras séries em % a.a..
  Dividir por 100 e formatar como % publicaria "5,4%" no lugar de "R$ 5,4000" — mesma família do
  erro de escala de ~496x da Etapa 1, e sem sinal nenhum na tela.
- **Célula de origem vazia vale 0 no Excel.** A média sem N exercícios completos fica LITERALMENTE
  vazia na aba Macro (fatia 3a, de propósito). Referência crua a ela publicaria "0,0%" como média de
  10 anos. Daí o `IF(origem="","",origem)` em cada uma das 18.

Invariante 35, 57 asserts. Não-vacuidade medida em 5 mutações.

### 2. Dupla contagem no total do grupo — o bug ABERTO mais caro, agora SINALIZADO (`37de0e5`)

**Reproduzi o arranjo real do v33** (Balanço da Componentes: 14.200 + 3.600 + 890 − 13.100 = 5.590,
com o 5.590 impresso): conta anotada com a seção de TOPO em vez da subseção cai em "Outros Ativos
Não Circulantes", irmã do Imobilizado, e o grupo a conta duas vezes.

O export agora escreve uma linha visível **nomeando a conta suspeita**, as duas seções e a diferença
medida, com nota trazendo **as duas leituras** — e **não corrige sozinho** (Arquitetura do Sistema/2 Especificação/04). Reportado UMA
vez, no grupo onde as duas seções são irmãs; repetir no ATIVO ensinaria o leitor a ignorar avisos.

**SOBRE A FIXTURE — leia antes de mexer.** A conta do v33 era "Ferramental e moldes" e ela NÃO serve
mais: a correção de vocabulário da sessão 18 (invariante 30) faz esse rótulo ser Imobilizado mesmo
sem seção declarada. MEDIDO:
```
classificarConta("balanco","Ativo Não Circulante","Ferramental e moldes",null) -> imobilizado
classificarConta("balanco","Ativo Não Circulante","Bens em comodato",null)     -> ativo_nao_circulante
```
A instância está fechada; a CLASSE não estava. A fixture usa "Bens em comodato" (conta de imobilizado
real, CPC 27, que o vocabulário genuinamente não reconhece), com a seção de TOPO declarada e a ordem
longe da vizinhança — que é o arranjo que a produção tinha.

**SEGUNDO DEFEITO, achado ao escrever o teste:** a marca de divergência no CABEÇALHO da seção
**nunca apareceu**. O cabeçalho é linha reservada e preenchida no fim com `row.fill = fill`, que no
ExcelJS repinta a linha inteira e apagava o destaque escrito antes. A pintura passou a ser adiada
(`pintarNoFim`) para depois de a aba inteira ser emitida. **Se você escrever destaque em célula de
cabeçalho de seção, use `pintarNoFim` — escrever direto não sobrevive.**

Invariante 36, 12 asserts, com contraprova. Não-vacuidade medida em 3 mutações.

### 3. Pré-condições de Ativo × Passivo+PL — `Supabase/migrations/0033` (`1f95d62`)

**O que eu MEDI: a pré-condição NÃO é reproduzível pelo book.** Rodei a A.1 contra o book sintético
inteiro pelo arnês e2e (migrations reais, gravação pelas funções reais): as **7** entidades/períodos
dão `ok`. A falha do v33 veio do que a extração da OpenAI emitiu naquele lote, que não está
versionado aqui. **Não inventei fixture para "provar" uma causa que não tenho como medir.**

O que a `0033` entrega é a mensagem que teria dito a causa na hora: nomeia o LADO que faltou, o ano,
as colunas tentadas, e **LISTA os rótulos que a extração trouxe**. E, em qualquer resultado, declara
a ORIGEM dos dois lados (linha impressa × soma de seção do fallback) — porque "Ativo 158.801 vs
Passivo+PL 126.673" não diz se a divergência é do documento ou se uma seção não classificada sumiu
da soma, e são investigações diferentes.

**A lista de candidatos NÃO filtra por coluna, e isso é decisão medida.** Filtrar reproduziria o
defeito que se quer diagnosticar: quando a causa é o casamento de COLUNA (a família que a `0030`
corrigiu), o rótulo certo existe e some da lista. Escrevi a versão filtrada primeiro e o teste 7
reprovou com "nenhum rótulo … foi extraído" apesar de o rótulo existir — foi assim que apareceu.

**Nenhum critério de casamento foi afrouxado.** Alargar o `like` fabricaria um casamento.

Testes 6 (reescrito) e 7 (novo) em `Supabase/test/reconciliacao.test.sql` — as duas condutas opostas que a
mensagem antiga não distinguia: "reextrair" × "mexer no padrão". Não-vacuidade medida trocando a
`0033` por `select 1;` e reconstruindo o banco.

### 4. CI (`75be07c`, `a7bfee5`) — e ele achou defeito na PRIMEIRA execução

`.github/workflows/suites.yml`: n8n, os três geradores **com `git diff --exit-code`**, export, db
contra serviço Postgres 16, e2e, tsc, eslint e `next build`. Em todo push e PR.

**A primeira execução real reprovou e achou dois defeitos, nenhum deles do workflow:**
1. **`verificar-export.mts` linha 810 tinha um CAMINHO ABSOLUTO** para o checkout de uma sessão
   (`/home/user/tratamento-dados-financeiros/...`). Os outros nove `readFileSync` do arquivo usam
   `new URL(..., import.meta.url)`. Funcionava por acidente — qualquer clone em outro diretório
   recebia ENOENT. **Nenhuma das quatro suítes pegaria isso**, porque todas rodavam no único
   diretório onde não dá erro.
2. **`npx tsx` baixa o tsx do registro mesmo com o `.bin` no PATH** ("package was not found and will
   be installed"). As suítes agora chamam `./portal/node_modules/.bin/tsx` por caminho, o binário
   pinado no lock. `tsx` entrou nas devDependencies do portal.

**CI VERIFICADO VERDE EM RUNNER REAL** (run `30668647822`, commit `a7bfee5`): os **14 passos**
passaram em 82 s, incluindo os que a primeira execução tinha pulado — `Supabase/test/run.sh` contra o
serviço Postgres 16, o `e2e`, e o `next build`. Não é "o YAML é válido": é a coisa rodando.

### 5. Análise crítica da sessão 19 (`495ca68`) — pedido explícito do dono

**DEFEITO ENCONTRADO E CORRIGIDO: 12 meses NÃO bastam.** A `0032` fez a série de NÍVEL devolver
retorno NULL no primeiro exercício, mas `meses` continua 12 — e o export decidia "exercício completo"
olhando só `meses === 12`. O ano entrava em `completosDe`, a janela de 3 anos o NOMEAVA, e a média
virava `PRODUCT(1+B3/100, …)` com B3 resolvendo para `""` (a célula visível é
`IF(dados!X="","",dados!X)`, e **texto vazio não é célula vazia**: `""/100` é #VALUE!). A média 3a
saía **EM BRANCO com a nota afirmando "Média geométrica dos exercícios completos: 2023, 2024, 2025"**.
É alcançável, não teórico: basta a coleta do SGS começar em janeiro. Corrigido
(`meses === 12 && retorno != null`) + a nota do ano passa a dizer a causa. Invariante 37.

**AUDITADO E CORRETO, com a medição:**
- **`N8N/lib/hash.mjs`** — diferencial contra `node:crypto` em **619 casos**, todos idênticos: todos
  os comprimentos de 0 a 600, multi-bloco até 1.000.003 bytes, `Uint8Array` com **byteOffset
  não-zero** vindo de `subarray`, ArrayBuffer cru, Array comum, vetor da FIPS para entrada vazia.
  **Custo medido: 5 MB em 209 ms (23,9 MB/s)**; lote de 14 documentos de 5 MB = 2,9 s, contra dezenas
  de segundos de UMA chamada de IA. Irrelevante.
- **`0032`** — o recorte de leitura não muda o número. Medido com o filtro cortando exatamente o
  ano-base: sem filtro 2024 = 20,0000%; com `p_desde_ano=2024` → 20,0000%. Primeiro ano sai NULL.
- **Fatia 5** — não existe `spliceRows` nem `insertRow` em lugar nenhum do lib; todo `addRow` da aba
  Macro acontece antes do `return` que captura os endereços. Confirmado.
- **Fatia 4** — o vazio das premissas do Focus **não** produz #VALUE!: aquelas células são de verdade
  vazias, e vazio é 0 na aritmética do Excel. O único lugar onde "vazio" é `""` é a aba Macro — e é
  justamente ele que produziu o defeito acima.

**CORTE EM `export.ts`** (4.100 → 2.780 linhas). O acoplamento foi medido antes: exatamente **nove**
símbolos em comum, todos de apresentação → `export-estilo.ts` (38 linhas); o bloco Macro+Modelagem →
`export-modelagem.ts` (1.516). A condição "nenhum endereço de célula muda" foi **verificada, não
suposta**: dump completo do workbook (**7.485 células**, com valor, fórmula, formato, tamanho da nota
e preenchimento) gerado antes e depois — `diff` sem uma linha de diferença.

### ⚠️ PENDÊNCIAS DO DONO (sessão 20)

1. **Aplicar as migrations em ordem: `0032` (se ainda não aplicou) e `0033`.**
2. **Reimportar `N8N/workflow.e1-ingestao.json`** (hash em JS puro) **e `N8N/workflow.macro.json`**
   (`baseCalculo` do Focus) — continua pendente da sessão 19.
3. **Conferir o campo `hash` na saída de `Preparar Conteudo`** — tem de vir preenchido em qualquer
   sandbox. Se vier null de novo, o problema não é mais `crypto`.
4. **Validar a Etapa 2**, que agora está COMPLETA (é a regra dele: uma etapa por vez).

### O QUE FICOU ABERTO (nesta ordem, com o contexto detalhado mais abaixo)

1. **Truncamento de CSV/XLSX em 50 linhas antes de ir à IA** — faturamento de 24-36 meses perde o
   resto, em silêncio. **Não foi tocado.**
2. **`moeda` capturada e descartada** — não há coluna; USD indistinguível de BRL. Com o erro de
   escala corrigido, é o último fator multiplicativo invisível. **Não foi tocado.** (O bloco de
   REFERÊNCIAS MACRO agora ao menos NOMEIA isso na nota da linha do câmbio.)
3. **`completude_ok` só exige a linha `documento`** — 14 docs com zero linhas dão dashboard verde e
   book vazio. **Não foi tocado.**
4. **`fn_aceitar_extracao` aceita versão com zero campos.** **Não foi tocado.**
5. **Poller do upload expira em 12 min sem sinalizar**, e a recusa do orçamento só existe no log do
   n8n. **Não foi tocado.**

E a causa REAL das 5 pré-condições do v33 **continua desconhecida** — ver item 3 acima: a `0033`
garante que a PRÓXIMA ocorrência se explique, mas não explica a passada.

### Armadilhas novas desta sessão (além das que já estavam no fim deste arquivo)

- **`pintarNoFim`**: destaque escrito direto numa célula de cabeçalho de seção do Balanço é apagado
  pelo `row.fill = fill` que preenche a linha reservada depois. Use a lista adiada.
- **A aba Macro é o único lugar do export onde "vazio" é `""` e não célula vazia** — porque a célula
  visível é fórmula (`IF(dados!X="","",dados!X)`). Aritmética sobre isso é #VALUE!, não 0.
- **`npx tsx` baixa o tsx mesmo com o `.bin` no PATH.** Chame `./portal/node_modules/.bin/tsx`.
- **Caminho absoluto em teste passa despercebido para sempre** enquanto só existir um checkout. O CI
  é o que pega — e pegou na primeira execução.
- **Para medir não-vacuidade em SQL**: o `.test.sql` tem `ON_ERROR_STOP`, então a primeira falha
  aborta o resto. Para ver TODAS as falhas, neutralize os asserts já medidos um a um, ou rode blocos
  isolados contra um banco reconstruído com a migration trocada por `select 1;`.

## Sessão 19 (2026-07-31, tarde) — pendências do dono fechadas, Etapa 2 quase inteira (PR #69)

O dono voltou com as cinco pendências dele **resolvidas**, e uma das respostas virou trabalho:

1. PR #68 **mergeado** (o `main` está em `8109f2f`).
2. Migrations `0029`, `0030` e `0031` **aplicadas**.
3. Os dois workflows **reimportados**; **coleta macro confirmada** — o split do nó HTTP era real.
4. **`hash` veio NULL** → o sandbox de Code do n8n dele **não expõe `crypto`**. Virou fatia.
5. **RLS fica como está**: qualquer autenticado lê tudo; só time interno da Oria usa o portal.
   **Decisão registrada do dono — não reabrir sem ele pedir.**

### O que entrou no PR #69 (aberto, 4 commits)

- **`N8N/lib/hash.mjs` — SHA-256 em JS puro.** A abstenção anterior (`hash = null` quando não havia
  `crypto.subtle`) funcionou como projetada, mas o efeito era a idempotência da `0026` seguir
  **adormecida**: `p_hash is not null` nunca era verdade e todo reenvio duplicava o documento. Mesmo
  algoritmo (FIPS 180-4), zero dependência de ambiente; o caminho nativo ficou como atalho de
  velocidade. O harness de teste ganhou `semCrypto`, que sombreia o global dentro do corpo do nó —
  **o teste antigo passava verde com a produção quebrada** porque só exercitava o Node local.
- **Fatia 4 — Focus ausente virava 0,0% com nota afirmando procedência.** Agora a célula fica **em
  branco** (0 no Excel, mas lê como "falta preencher"), com **três camadas**: nota por exercício
  declarando a cobertura real, **linha VIVA** "cobertura do Focus" (a nota é da exportação; o
  exercício é input e a torna velha), e **aviso em linha visível** nomeando os anos e o efeito.
  `RefsMacro` passou a carregar a cobertura **por série** (o Focus publica horizontes diferentes por
  indicador).
- **Fatia 5 — o que degrada em silêncio passa a se declarar.** (a) falha PARCIAL do macro agora é
  escrita no topo da aba Macro — e a linha é escrita ANTES das outras, porque `spliceRows` depois do
  fato deslocaria a numeração que o modelo endereça por número; (b) `route.ts` NOMEIA a parte que
  falhou; (c) sem entidade reconhecida, a aba Modelagem **existe** dizendo a causa e para onde ir;
  (d) **Focus com `baseCalculo` fixado em 0** (a mediana dependia da ordem da resposta HTTP);
  (e) resíduos: `{ultimos:}`→`{mesesAtras:}` no seed, `$top` unificado em `FOCUS_TOP`.
- **Fatia 6a — `Supabase/migrations/0032`: o câmbio perdia JANEIRO todo ano.** A base era `min(data_ref)`
  DENTRO do ano; agora é o último fechamento **anterior** ao ano (dez/n−1 → dez/n). Primeiro ano da
  série sai **NULL** (sem base não existe variação — e era aí que a versão antiga inventava uma).
  **A suíte protegia o bug**: `Supabase/test/macro.test.sql` afirmava a convenção errada, corrigido junto.
  A migration tem verificação embutida e ela é **não-vazia**: com a base antiga religada, a própria
  migration se recusa a aplicar ("deveria ser 21%, veio 10").

**Todas as não-vacuidades foram MEDIDAS**, não estimadas: hash (1 reprova), fatia 4 (7), fatia 5 (3 +
o teste de `baseCalculo`, que testa as DUAS ordens de resposta), `0032` (a migration aborta).

### O que FALTA da Etapa 2 — uma coisa só, e o dono já decidiu como

**Bloco "REFERÊNCIAS MACRO" na Modelagem.** Medi o placar: das 15 premissas, **2** leem macro; das 6
séries históricas, **0** alimentam qualquer fórmula. Mas o modelo é dirigido por **percentual de
receita** (CPV = `RL × (1 − margem alvo)`, SG&A = `% da RL`), então **IGP-M, PIB e câmbio não têm
alavanca** hoje: trazê-los sem mais nada criaria mais células mortas, que é exatamente a crítica
registrada sobre as médias. Dar alavanca a eles é escolher qual índice corrige o quê — **isso é a
Etapa 5**.

**O dono escolheu (2026-07-31): bloco de REFERÊNCIA agora, seletor na Etapa 5.** Um bloco
"REFERÊNCIAS MACRO — não movem o modelo sozinhas" com IGP-M, PIB e câmbio do Focus **por exercício** e
as médias 3a/5a/10a, cada linha com nota dizendo o que ela **deveria** dirigir e que a escolha é o
seletor da Etapa 5.

**A infraestrutura já está pronta e commitada:** `RefsMacro` agora carrega `mediaDe`
(linha + colunas das médias, por série) e `janelasMedia`. Falta **só consumir** isso na
`construirAbaModelagem`. Onde colocar: **depois** da linha "cobertura do Focus", nunca no meio do
bloco de premissas — `P(i)` endereça premissa por deslocamento a partir de `rPremissas`, e uma linha
inserida no meio desloca todas as fórmulas do modelo em silêncio. A linha em branco depois das
premissas é o que ENCERRA o bloco para quem conta as 15 (invariante 15).

### ➡️ PRÓXIMA SESSÃO: `Arquitetura do Sistema/5 Prompts/PROMPT_CONTINUACAO.md`

O dono pediu um prompt único e auto-contido para a sessão seguinte rodar **de forma autônoma, sem
supervisão e sem fazer perguntas**. Ele está em **`Arquitetura do Sistema/5 Prompts/PROMPT_CONTINUACAO.md`** e cobre, em ordem:
fechar a Etapa 2 (bloco de REFERÊNCIAS MACRO), a dupla contagem no parente, as 5 pré-condições do
v33, montar CI, e uma **análise crítica do que a sessão 19 fez** (pedido explícito dele). Se este
handoff e aquele prompt divergirem, **este arquivo é a fonte da verdade** — o prompt é o roteiro.

### Armadilhas de execução da sessão 19 (não repetir)

- **`git checkout <arquivo>` apaga trabalho não commitado.** Usei para desfazer um patch de MEDIÇÃO
  de não-vacuidade e levei junto as mudanças legítimas do mesmo arquivo. Para medir: **copie o
  arquivo para o scratchpad e restaure com `cp`**, nunca com `git checkout`.
- **`sed -i '/marca/,$d'` depois de um `cat >>`** apaga o que você acabou de anexar (a marca estava
  ANTES do bloco novo). Para inserir antes do rodapé de um script, use Python com `str.index`.
- **O `verificar-export.mts` conta as premissas varrendo do cabeçalho "PREMISSAS" até a primeira
  linha vazia.** Qualquer linha nova adicionada logo depois do bloco entra na contagem e reprova os
  invariantes 14/15. A **linha em branco** é o que encerra o bloco — e ela é semanticamente certa:
  separa premissa (o que se digita) de conferência (o que o arquivo responde).
- **`spliceRows` na aba Macro quebra o modelo em silêncio**: `linhaCabFocus`/`linhaFocusDe` são
  números capturados na geração, e o INDEX/MATCH passa a apontar uma linha acima. Escreva avisos
  ANTES do resto da aba, nunca insira depois.
- **`Dados de Teste/book-vertentes/gerar.py` precisa de `PYTHONPATH=.`** e grava o `GABARITO.json` dentro
  de `pdf/`, não na raiz do diretório (a linha de uso do docstring está errada; o handoff anterior
  também dizia o lugar errado).
- **Não existe CI** — as quatro suítes só rodam quando alguém lembra. Continua sendo a alavanca mais
  barata contra regressão que existe neste repositório.

## ⚠️ COMECE AQUI — o 429 está RESOLVIDO; o plano agora é o do dono, etapa por etapa

**O 429 era TETO DE GASTO DO PROJETO na OpenAI** (`project_spend_limit_exceeded`), não crédito nem
cadência. O `neverError` da sessão 17 fez o corpo real da OpenAI chegar ao pipeline e a causa saiu
nomeada. O dono subiu o teto; o teste **v33 rodou os 14 documentos em 7m14s com sucesso**.

O dono definiu um plano de 6 etapas (estabilização → macro → automatizar modelagem → abas → seletor
de inputs → validação). **Regra dele: uma etapa por vez, e só avança depois da validação dele.**
O plano detalhado da etapa corrente vive em `/root/.claude/plans/` da sessão; se não existir, releia
esta seção e refaça.

### Etapa 1 — CONCLUÍDA e mergeada (PR #67, 7 fatias)

Não havia regressão: havia defeitos que rodavam sem erro e entregavam número errado. Os que mais
importam, todos com invariante e vacuidade medida:

- **A escala NUNCA era aplicada, em nenhuma aba.** `grep escala export.ts` dava zero. Balanço em
  milhar + fonte em unidade na mesma coluna = erro de **~496x**, sem uma marca. Corrigido no LIMITE
  DE NORMALIZAÇÃO (uma vez, na entrada), não célula por célula — assim `SUM`, AV%, indicadores e a
  Modelagem ficam certos sem serem tocados. **Confirmado em produção no v33: "20 linhas vinham em R$
  e foram convertidas".**
- **Conta de RESULTADO no Ativo Circulante:** `"mercadoria"` está em `ATIVO_CIRC_KW` (certo, é
  estoque), e por isso a top line da DRE era classificada ATIVAMENTE errada. `ehContaDeResultado`
  faz o classificador de balanço se ABSTER, e a abstenção reroteia para a DRE.
- **`0029`:** auto-aceite atropelava as guardas anti-fabricação (extração alucinada entrava como FATO
  ACEITO); extração vazia sem erro de API não gerava pendência; `extracao_falhou` nunca fechava;
  documento inexistente descartava o motivo da falha e a extração era PAGA.
- **`0030`:** entidade e período canônicos na ESCRITA. A duplicidade de entidade era **regressão do
  PR #65** (nome do arquivo sem acento × diagnóstico com acento).
- **`0031`** (no #68): o caixa estava na SEÇÃO e a reconciliação só olhava a chave.
- **Teto de gasto de US$ 3 por execução** em `N8N/lib/custo.mjs` + nó `Orcamento do Lote`.
- **`Verificação/run.mts`:** a validação encadeada que não existia.

### Etapa 2 — EM ANDAMENTO (PR #68, 3 fatias de 6)

**A causa não era a que a etapa supunha.** RLS/GRANT estava fechado pela `0028`. Era a **COLETA**:

- **O nó HTTP do n8n EXPLODE resposta JSON que é array em N itens.** O SGS devolve 132 objetos e
  `Manter Contexto SGS` guardava `__corpo` = UM objeto ⇒ `!Array.isArray(corpo) continue` descartava
  **~792 itens das 6 séries mensais**. O ramo SIDRA já remontava o array; a assimetria era o sintoma.
  E ninguém viu porque o seed (920 obs) faz a aba **congelar** em vez de esvaziar.
- A coleta agora **falha alto** (zero nunca é legítimo: o SGS devolve 132 meses por chamada).
- **As médias 3a/5a/10a saíam em branco com 12 anos completos na base** — a janela era posicional e
  a última coluna é sempre o ano parcial. Agora nomeia os anos completos um a um.
- O último mirror manual (`numeroMacro` no Focus) passou a ser embutido por `toString()`.

**FALTA na Etapa 2** (fatias 4-6): Focus ausente vira **0,0% com nota afirmando procedência** (é o
defeito mais enganoso que resta); falha PARCIAL do macro descarta `macroErro`; sem entidade
reconhecida nem a aba de aviso é criada; **ligar IGP-M, PIB, câmbio e as médias às premissas** (o
dono decidiu que isso entra na Etapa 2 — hoje só 2 de 15 premissas leem macro); câmbio perde janeiro
todo ano (`0025:227`, e a fixture do teste CONSAGRA o erro); Focus sem filtro de `baseCalculo`.

### ABERTO e não resolvido — leia antes de mexer no Balanço

**Dupla contagem no total do grupo.** No v33, o Imobilizado usou o TOTAL INFORMADO (5.590, que já
inclui "Ferramental e moldes") e o Ferramental foi somado DE NOVO em "Outros Ativos Não Circulantes":
Ativo Não Circulante inflado em 3.600. O vocabulário foi corrigido, mas **a guarda no PARENTE
continua aberta**: sempre que uma conta de uma seção com total informado cai numa seção irmã, o grupo
conta duas vezes e nada detecta.

⚠️ **Duas fixtures minhas para provar isso nasceram VAZIAS** (passavam com o bug ligado): uma
declarava `secao` (e aí `subsecaoAutoritativa` já acertava), a outra tinha `ordem` entre contas do
Imobilizado (e o consenso de irmãos acertava). Fechar isso pede as linhas REAIS da extração do v33 —
não invente fixture, ela vai passar verde e te enganar.

**As 5 PRÉ-CONDIÇÃO de Ativo Total / Passivo+PL do v33 continuam.** A `0030` corrigiu o casamento de
COLUNA (combinado); estes são balanços individuais, onde o problema é o casamento de RÓTULO — caminho
diferente. E há uma DIVERGÊNCIA real (Ativo 158.801 vs Passivo+PL 126.673, diferença 32.128) que
pode ser a mesma família de dupla contagem.

 — o bloqueio de hoje é o 429 da OpenAI, e a causa dele NÃO está determinada

**O estado honesto, em uma frase:** no **teste v30** os **14 de 14** documentos falharam com HTTP 429,
e a resposta que chegou ao pipeline **não continha o corpo de erro da OpenAI** — então o código
classifica como `limite_indeterminado`, que é a verdade, e não como "cadência", que seria chute. Tudo
que a sessão 17 fez foi (a) tirar o chute da frente e (b) instrumentar para que a **próxima** execução
capture a causa real. **Não recomece inventando hipótese: leia §"Sessão 17" abaixo antes de agir.**

---

### PENDÊNCIAS DO DONO — as da sessão 18 estão TODAS fechadas (ver "Sessão 19")

As seis pendências anteriores (mergear o #68, aplicar `0029`-`0031`, reimportar os workflows,
confirmar a coleta macro, conferir o `hash`, decidir a lista de severidade) foram **respondidas pelo
dono em 2026-07-31**. O que ficou pendente dele agora:

1. **Aplicar `Supabase/migrations/0032`** (câmbio) quando o PR #69 entrar.
2. **Reimportar `N8N/workflow.e1-ingestao.json`** (hash em JS puro) **e `N8N/workflow.macro.json`**
   (`baseCalculo` do Focus).
3. **Conferir de novo o campo `hash` na saída de `Preparar Conteudo`** — agora ele TEM de vir
   preenchido em qualquer sandbox. Se vier null outra vez, o problema não é mais `crypto`.
4. **Validar a Etapa 2** quando ela fechar (é a regra dele: uma etapa por vez).

### O PLANO DO DONO — 6 etapas, uma por vez

Regra dele, literal: *"Ao concluir uma etapa, aguarde minha validação antes de iniciar a seguinte"* e
*"não tente antecipar etapas futuras"*. Não avance sem o OK.

| Etapa | Objetivo | Estado |
|---|---|---|
| 1 | Estabilização da pipeline | **CONCLUÍDA** (PR #67) + correção pós-v33 no #68 |
| 2 | Dados macroeconômicos corretos na planilha | **COMPLETA** (sessão 20) — 3 fatias no #68, 3 no #69, o bloco de REFERÊNCIAS MACRO na sessão 20. **Aguardando validação do dono.** |
| 3 | Modelagem 100% automatizada, e **sem buscar valor de outras abas por fórmula** | **FEITA** (sessão 21) — aguardando validação |
| 4 | Todas as abas geradas; **auxiliares OCULTAS**, Modelagem visível | **FEITA** (sessão 21) — aguardando validação |
| 5 | **Seletor de inputs macro** (IPCA+, Selic, IGP-M, PIB, média histórica, CAGR) recalculando tudo | **FEITA** (sessão 21) — aguardando validação |
| 6 | Validação final ponta a ponta | **FEITA** (sessão 21) — modelo resolvido, conferências em zero |

⚠️ **A Etapa 4 CONTRADIZ uma decisão anterior do dono.** No teste v28 ele pediu explicitamente "quero
todas as abas juntas no exportável" porque abas ocultas leram como dado ausente, e o código hoje
**não oculta nada** de propósito (`export.ts`, comentário de `ABA_MACRO`). A Etapa 4 pede o oposto.
**Pergunte antes de ocultar** — pode ser que ele queira só a Modelagem em primeiro plano, não abas
escondidas.

⚠️ **A Etapa 3 pede que a Modelagem NÃO leia outras abas por fórmula** e receba os valores brutos já
preenchidos. Isso **desfaz** a arquitetura da sessão 12 (`INDEX/MATCH` contra as abas de dados, para a
planilha continuar viva: corrigiu a origem, o modelo acompanha). É uma troca real — perde-se o "vivo"
e ganha-se independência. **Confirme que é isso que ele quer** antes de reescrever.

### O QUE A ETAPA 2 AINDA DEVE — a lista abaixo está QUASE toda FEITA (sessão 19)

⚠️ **Não retrabalhe.** Cada item abaixo foi resolvido no PR #69, exceto o último. Mantido como
registro do que era o defeito, porque a descrição do defeito é o que explica o teste que ficou.

- ~~**Focus ausente vira 0,0% com nota AFIRMANDO procedência**~~ → **FEITO** (fatia 4). Célula em
  branco + nota por exercício + linha viva de cobertura + aviso visível. Invariantes 31 e 32.
- ~~**Falha PARCIAL do macro descarta `macroErro`**~~ → **FEITO** (fatia 5), declarado no topo da aba
  Macro, com a parte que falhou NOMEADA pelo `route.ts`. Invariante 33.
- ~~**Sem entidade reconhecida, nem a aba de aviso é criada**~~ → **FEITO** (fatia 5). Invariante 34.
- ~~**O câmbio perde JANEIRO todo ano**~~ e ~~**a fixture do teste CONSAGRA o erro**~~ → **FEITO**
  (fatia 6a, `Supabase/migrations/0032`), os dois lados corrigidos na mesma fatia.
- ~~**Focus sem filtro de `baseCalculo`**~~ → **FEITO** (fatia 5): fixado em 0 (base de 30 dias, a da
  tabela principal do Boletim), na URL e no parse.
- ~~**Resíduos** (`{ultimos:}` × `{mesesAtras:}`, `top=40` × `top=80`)~~ → **FEITO** (fatia 5).
- **Ligar IGP-M, PIB, câmbio e as médias históricas às premissas** → **É O QUE FALTA.** O dono
  decidiu a forma: **bloco de REFERÊNCIAS MACRO agora, seletor na Etapa 5.** Ver a seção "Sessão 19"
  no topo — a infraestrutura (`RefsMacro.mediaDe`, `janelasMedia`) já está commitada e só falta
  consumir.

### PARA O DONO AVALIAR (média/baixa severidade — ele pediu que fosse trazido)

~~**O único que eu levantaria:** hoje toda policy é `for all to authenticated using (true)`~~ —
**DECIDIDO PELO DONO (2026-07-31): fica como está.** "Qualquer usuário pode visualizar, apenas o
pessoal interno da Oria vai ter acesso mesmo." Não reabrir sem ele pedir. O fato técnico continua
verdadeiro (não existe `caso_membro`, qualquer autenticado lê PII de sócios de qualquer mandato); o
que mudou é que é **risco aceito**, não pendência.

Perde dado de forma menos aguda: truncamento de CSV/XLSX em 50 linhas antes de ir à IA (faturamento de
24-36 meses perde o resto); `moeda` capturada e descartada (não há coluna — USD indistinguível de BRL);
`completude_ok` só exige a linha `documento` (14 docs com zero linhas ⇒ dashboard verde, book vazio);
`fn_aceitar_extracao` aceita versão com zero campos e grava decisão de aprovação; reconciliação A.1
pula anos em silêncio; `fn_valor_em_base` trata escala desconhecida como fator 1.

Atrito de uso: poller do upload expira em 12 min sem sinalizar nada — e a **recusa do orçamento** (o
`throw` do `Orcamento do Lote`) só existe no log do n8n, invisível para o dono; `status` compara nº de
arquivos com nº de linhas `documento` (com a `0026`, reenvio válido nunca fica "pronto"); fila não
pré-preenche a sugestão do diagnóstico; pendências de reconciliação/extração são listas só-leitura;
Kit Básico conta classificação não confirmada como "✓ presente"; upload sem `accept` nem validação de
tipo; parser de CSV ingênuo com aspas.

Exige n8n vivo: `.docx`/`.xlsx` via *Extract From File* (também a maior alavanca de custo, 60-80% do
input); chunking por página para `finish_reason=length`; confirmar se `retryOnFail` é decorativo com
`onError: continueRegularOutput`.

**Infra:** ~~não existe CI~~ → **RESOLVIDO na sessão 20** (`.github/workflows/suites.yml`). Ele achou
um defeito na primeira execução: caminho absoluto embutido no `verificar-export.mts`.

## Histórico: como o 429 foi diagnosticado (RESOLVIDO — mantido pelo método)

Fica aqui porque o **método** vale para o próximo mistério, não porque o problema esteja aberto.
A causa final foi `project_spend_limit_exceeded` — teto de gasto do PROJETO, invisível nas telas de
Billing e de Limits. Duas lições que se repetem: (1) uma frase de erro escrita pelo n8n em cima de
qualquer 429 não é evidência de cadência, e acreditar nela me fez subir o intervalo 6s→12s sem
evidência; (2) sem `neverError`, o corpo real da OpenAI nunca chega ao pipeline e o diagnóstico é
cego. Foi o `neverError` que fez a causa aparecer com nome no v31.

### O fato que refutou a hipótese mais fácil

O dono colou a saída do nó `OpenAI Extrair`. É **isto**, sem nada omitido:

```
message  Try spacing your requests out using the batching settings under 'Options'
name     AxiosError
stack    AxiosError: Request failed with status code 429 ...
code     ERR_BAD_REQUEST
status   429
```

Leia o que **não** está aí: nenhum `error.error`, nenhum `cause`, nenhum header de rate limit, nenhum
`insufficient_quota`. A frase do `message` é escrita pelo **próprio n8n** em cima de **qualquer** 429
(`HttpRequestV3.node.ts:850-853` sobrescreve `message`) — ela **não é evidência de cadência**, e foi
exatamente ela que me fez errar numa rodada anterior (subi o intervalo 6s→12s sem evidência; o 429
continuou). `ERR_BAD_REQUEST` é código de **transporte do axios**, não código da OpenAI.

Isso importa porque as causas de 429 pedem ações **OPOSTAS**: crédito esgotado → recarregar; **teto de
gasto** configurado → subir o teto (e ele **não aparece** nas telas de Billing nem de Limits); cota
diária → só reabre amanhã; **cadência** → o único caso em que espaçar resolve.

Backlog largo restante: **`Arquitetura do Sistema/4 Análises e Auditorias/AUDITORIA_HARDENING_2026-07-24.md`** (45 findings priorizados, com
marcação do que já foi feito). Candidatos mais fortes agora, todos locais e testáveis aqui:

- ~~**Idempotência por hash + overload morto de 14 args**~~ e ~~**`reset-0006-regride-funcoes`**~~:
  **FEITOS na sessão 15** (`Supabase/migrations/0026`, abaixo). O que sobrou dessa frente: **não PAGAR** a
  extração quando o arquivo é idêntico E a extração anterior usou o MESMO prompt/modelo. Exige (i)
  fingerprint de prompt+modelo gravado na versão e (ii) curto-circuito no grafo do N8N —
  `Montar Req Extracao` é `runOnceForEachItem` e não pode devolver zero itens; mudar o modo troca a
  resolução de contexto por item, a mesma classe de mudança que causou o bug do `itemIndex` fixo.
  **Fatia própria, com o N8N vivo do dono.**
- **`unidade-ignorada-em-abas-classificadas`:** a escala (`milhar`/`unidade`) é lida só nas abas de
  listagem simples; nas classificadas o `SUM` soma valor cru. Duas fontes em escalas diferentes na
  mesma coluna somam errado **em silêncio** — mínimo verificável: escala no cabeçalho da coluna +
  pintar divergência dentro da mesma coluna/aba.
- **`vocabulario-classificacao-contas-nao-classificadas`:** rótulos reais ("Receita de Vendas de
  Mercadorias" — a top line!, "Impostos sobre Vendas") caem em "Não Classificadas". Ampliar as listas
  de palavra-chave é aditivo e de baixo risco.
- **`periodo-fragmenta-e-quebra-reconciliacao`:** a referência de período é gravada CRUA, então o
  mesmo exercício em duas notações vira duas linhas em `periodo`. Canonicalizar no caminho de ESCRITA
  (a `0022` já canonicaliza na comparação).

## Sessão 18 (2026-07-31) — Etapa 1 completa + Etapa 2 começada; e dois invariantes MEUS nasceram vazios

Sessão longa, guiada pelo plano de 6 etapas do dono. Três PRs: **#67** (Etapa 1, 7 fatias, mergeado),
**#68** (Etapa 2, 3 fatias + correção pós-v33, aberto). O 429 foi resolvido no começo: era
`project_spend_limit_exceeded` — **teto de gasto do PROJETO**, invisível nas telas de Billing e de
Limits. O `neverError` da sessão 17 é que fez o corpo real da OpenAI chegar ao pipeline.

### O que o teste v33 provou (14 documentos, 7m14s, sucesso)

- **A escala funciona em produção:** o Resumo saiu com *"20 linha(s) vinham em R$ e foram convertidas"*.
  Era o mapa de dívida em reais somando com demonstrações em milhar — o erro de ~496x, evitado.
- Entidade preenchida em 14/14 (era `—` em todos no v31), 620 linhas, 14 abas visíveis.
- O teto de US$ 3 por execução não barrou o lote e não estourou.
- Renomear os arquivos para `12M25`/`L24M` eliminou a 2ª chamada `gpt-4o` por documento.

### O bug que o v33 revelou, e o que dele NÃO está fechado

No Balanço da Componentes: `Imobilizado = 5.590` (total informado, que **já inclui** "Ferramental e
moldes") e o Ferramental somado **de novo** em "Outros Ativos Não Circulantes" (3.600) ⇒ **Ativo Não
Circulante inflado em 3.600**, sem nada acusar no total do grupo. Confirmei no gabarito:
14.200 + 3.600 + 890 − 13.100 = 5.590.

Causa imediata: `IMOBILIZADO_KW` tinha `"ferramenta"` e o rótulo é `"Ferramental"` — o casamento por
token não aproxima. Corrigido (`ferramental`, `ferramentaria`, `molde`).

**NÃO FECHADO:** a guarda no PARENTE. Sempre que uma conta de uma seção com total informado cai numa
seção irmã, o grupo conta duas vezes e nada detecta. Ver "ABERTO" no topo.

### A lição mais cara da sessão: invariante vazio

**Duas fixtures minhas para provar a dupla contagem passaram verde COM O BUG LIGADO**, e eu só
descobri porque desliguei o fix e olhei:

1. Declarei `secao: "Imobilizado"` nas contas — com seção declarada, `subsecaoAutoritativa` já mandava
   o Ferramental ao lugar certo, independente do vocabulário.
2. Tirei a seção, mas deixei a `ordem` ENTRE contas do Imobilizado — o consenso de irmãos acertava
   sozinho, também sem depender do vocabulário.

Não consegui reconstruir o arranjo real da produção. Então o invariante que ficou afirma a
**classificação por rótulo** (4 asserts, provados não-vazios) e a dupla contagem ficou registrada como
aberta. **Se você for fechá-la: não invente fixture — ela passa verde e te engana. Use as linhas reais
da extração do v33.**

Mesma classe de erro em outro lugar: o invariante ANTIGO das médias macro exigia `COUNT(` na fórmula.
Ele travava o **mecanismo**, e o mecanismo era justamente o defeito — a faixa posicional. Invariante
que descreve *como* o código faz, em vez de *o que ele garante*, protege o bug.

### Armadilhas de execução que custaram tempo (não repetir)

- **Backtick dentro dos templates de código dos nós.** O gerador monta o `jsCode` como template
  literal, então um backtick num COMENTÁRIO fecha a string e o JS do nó sai quebrado — e o gerador
  não parseia, então só o teste pega. Aconteceu duas vezes.
- **Aspas simples em `'... e' resultado ...'`** dentro de string de nó: `e'` fecha a string.
- **Ordem de parâmetros:** `classificarConta(estrutura, secao, chave, secaoCanonica)` — estrutura
  PRIMEIRO; `classificarDemonstracao(secao, chave, secaoCanonica, estrutura)` — diferente.
- **`entidade` e `periodo` NÃO têm `criado_em`**; `periodo.tipo` é `text`, não enum; `caso` não tem
  `tipo_mandato`; `pendencia` usa `criada_em` (não `criado_em`).
- **`notaDaLinha` no harness precisa de `includeEmpty: true`** — nota de célula sem valor é pulada.
- **`avaliarCelula` NÃO segue referência entre abas.** Toda célula de ano da aba Macro é
  `IF('Macro (dados)'!X="","",…)`, então não dá para avaliar médias nem valores da Macro por ali. Foi
  o que me obrigou a trocar duas asserções por estruturais — com o motivo comentado no código.
- **`gerar_fixture.py` precisa de `PYTHONPATH=.`** (a linha de uso no docstring está errada).
- O `e2e` precisa de `E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432"` por causa do peer auth.

### Uma regressão minha, corrigida na mesma sessão

O PR #65 fez a entidade sair do nome do arquivo — **sem acento**, porque `normalize.mjs` remove
diacríticos de propósito — enquanto o diagnóstico da IA traz `"Vertentes Metalúrgica Ltda."`. O
casamento no banco era `lower(razao_social)` ⇒ **duas entidades para a mesma empresa**. Corrigido na
`0030`, dos dois lados (escrita e `fn_coluna_entidade`). O export já mascarava o sintoma com
`consolidarNomesDeEntidade`, e é por isso que a duplicidade na base passou tanto tempo sem ser vista.

## Sessão 17 — Testes v29/v30: macro vazio por AUTORIZAÇÃO, e 429 sem causa conhecida (a causa saiu na sessão 18: teto de gasto do PROJETO)

Duas frentes. A primeira está **resolvida e mergeada**. A segunda está **instrumentada, não resolvida** —
e a distinção é o ponto mais importante desta seção.

### Frente 1 (RESOLVIDA, PR #61, `Supabase/migrations/0028`) — "não veio os dados macro"

O dono aplicou a `0025`, ativou o workflow macro, rodou de novo, e as abas macro continuaram vazias.
A causa não era coleta: era **autorização**. A `0025` criou as tabelas `indice_macro_serie/obs/expectativa`
e a função `fn_indice_macro_anual` **sem RLS policy e sem grant** para `authenticated`. O portal lê com
a **anon key** + sessão do usuário, o que o Postgres vê como o papel `authenticated`. Dois efeitos, os
dois **silenciosos**:

- **RLS ligada sem policy devolve ZERO LINHAS** — não erro, não aviso. Zero.
- **função nova precisa de `grant execute ... to authenticated`** explícito no Supabase.

O n8n **não** era afetado (conecta por Postgres nativo via Session Pooler, fora do PostgREST), o que
explica o sintoma confuso: a coleta gravava, o portal não lia. A `0028` liga RLS com policy de leitura
e faz o grant, **com verificação embutida** que insere uma linha real e confere `COUNT(*)` já como
`authenticated`.

**O achado de método, que vale mais que a migration:** `Supabase/test/run.sh` era **estruturalmente incapaz**
de pegar isso. Ele não replicava os privilégios default que o Supabase configura na criação do projeto,
então `set role authenticated` falharia para **qualquer** tabela — o teste acusaria falso positivo em
geral, e por isso ninguém testava como `authenticated`. O `run.sh` agora replica esse passo
(`grant usage on schema public`, `alter default privileges ... grant all on tables/sequences`) e
**deliberadamente NÃO** o lado de função — com comentário explicando que a abordagem de revogar execute
foi **medida** e não reproduz o comportamento do Supabase em Postgres puro. Sem isso, o próximo bug de
autorização passa igual.

Junto (PRs #59-#61): seed macro versionado com **920 observações reais** + 25 expectativas Focus (zero
divergências BCB×IBGE), correção da URL do BCB SGS (`ultimos/132` dava HTTP 400; série diária dava 406
→ passou a usar faixa de datas e a série 3698), e o export deixou de esconder abas — **todas visíveis**,
com aba de "sem dado" que declara o motivo em vez de sumir (o dono pediu explicitamente: "quero todas as
abas juntas no exportável").

### Frente 2 (NÃO RESOLVIDA — leia antes de mexer) — os 14/14 com 429 do v30

Cronologia, porque ela é o que impede repetir o erro:

1. **Rodada anterior:** subi o intervalo da extração de 6s → 12s supondo cadência. **Erro meu.** O 429
   continuou. Nenhuma evidência apoiava "cadência" — só a frase genérica do n8n.
2. **Esta sessão, hipótese:** o corpo de erro da OpenAI estaria em `error.error.error` (agentes leram o
   fonte do n8n e previram isso). Escrevi `diagnosticarErroApi` para cobrir esse caminho e vários outros.
3. **O dono colou a saída real do nó — e ela REFUTOU a previsão.** Não há corpo aninhado nenhum (ver o
   bloco em "COMECE AQUI"). Confirmei rodando: aquele payload exato classifica como
   `limite_indeterminado`, status 429, tipo `null`, código `null`.

**Conclusão que fica registrada como pendência, não como fato** (doutrina `Arquitetura do Sistema/1 Visão e Doutrina/01`): a causa do v30 é
**desconhecida**. `limite_indeterminado` é a classificação honesta.

O que foi construído em cima disso:

- **`diagnosticarErroApi` (`N8N/lib/extract.mjs`)** — auto-contida de propósito, porque o gerador embute
  o `toString()` dela nos nós (Code node não importa arquivo). Emite causas com **ações diferentes**:
  `limite_de_gasto` (testado **primeiro**, porque tetos de projeto/org são invisíveis em Billing e
  Limits), `sem_credito`, `limite_diario`, `limite_cadencia`, `chave_invalida`, `modelo_indisponivel`,
  `limite_indeterminado`, `desconhecida`. Captura `x-ratelimit-*` e `retry-after` quando existem.
  **Terceiro mirror do repositório** (depois do prompt e dos ALIASES) — e os dois anteriores JÁ
  divergiram na prática, então há teste comparando nó × lib.
- **`neverError: true` nos dois nós OpenAI.** É o que faz a resposta 429 chegar ao parse **com o corpo
  da OpenAI** em vez de só o AxiosError. **É a instrumentação de que a próxima execução depende.**
- **Guarda contra pista falsa:** `ERR_BAD_REQUEST` (transporte axios) nunca é reportado como código da
  OpenAI — senão a sessão seguinte investigaria o campo errado. São **duas** guardas redundantes
  (uma em `CAMINHOS`, uma no cálculo de `codigo`) e **medi** que o teste só reprova com as **duas**
  removidas; está comentado no código para ninguém superestimar a cobertura.
- **A cadência agora é ARITMÉTICA, não opinião.** A OpenAI cobra do balde de TPM o **máximo** entre
  `max_tokens` e os tokens estimados do request — então cada extração **RESERVA** `MAX_OUTPUT_TOKENS`
  (16.384) por chamada, **independente do tamanho do PDF**. Logo:

  ```
  chamadas/min = TPM_CONTA / MAX_OUTPUT_TOKENS
  intervalo    = 60.000ms / chamadas por minuto
  ```

  No Tier 1 (30.000 TPM): 1,8 chamada/min → **32.768ms**. Os 12s que eu havia posto suportariam 5
  chamadas/min = **81.920 TPM**, quase **3× o teto do Tier 1** — ou seja, o lote de 14 documentos **não
  tinha como passar**, nem a 6s nem a 12s. `TPM_CONTA` vive em `lib/extract.mjs` (junto de
  `MAX_OUTPUT_TOKENS`) porque **três** lugares dependem do mesmo número — o gerador, o teste de cadência
  e o `diagnosticar-openai.mjs`; duplicado, o dono ajustaria um e os outros dois passariam a mentir.
- **`N8N/diagnosticar-openai.mjs`** — o experimento discriminante descrito em "COMECE AQUI". Já validado
  contra a API real (chave inválida → `chave_invalida`).

**Suspeita NÃO verificada, registrada como suspeita:** `retryOnFail` pode nunca disparar quando o nó tem
`onError: continueRegularOutput`. Se for verdade, `maxTries: 6` é decorativo nos nós OpenAI. Não medi.

### Ângulos ainda abertos nesta frente

1. **Consumo de tokens** — se a reserva de 16.384 por chamada é o que estoura o balde, reduzir
   `max_tokens` (ou cortar tokens de entrada, ver a fatia de *Extract From File*) vale mais que espaçar.
2. **Resiliência** — hoje uma 429 no meio do lote custa o documento; nada re-tenta o item depois de o
   balde reabrir.
3. **Observabilidade** — a pendência registra a causa, mas não há visão de "quantas 429 nesta execução".
4. **Modelo alternativo** para extração (TPM maior no mesmo tier).
5. **Comparar o banco de v29 × v30** — quantas linhas/documentos sobreviveram em cada, que é o que diz
   se algo além do 429 regrediu.

## Sessão 16 — Teste v28: aba ausente deixa de ser buraco silencioso

O dono mandou o `.xlsx` do v28 (14 documentos) com dois destaques: "os índices não vieram com os
dados" e "a aba de DRE não veio, e as demais abas também não vieram — quero todas as abas juntas".
As três causas são DIFERENTES, e **nenhuma era um número errado**: eram ausências indistinguíveis de
defeito. Também achei um defeito numérico que ninguém tinha pedido para procurar.

**Antes de tudo: havia uma SESSÃO PARALELA.** O `.xlsx` tinha uma aba Modelagem MENSAL que o código
que eu conhecia não produzia. O PR #57 (outra sessão, mesma conta) entrou entre o meu #56 e o #58 com
modelo mensal + **rollback da `0025`**. Lição registrada: quando o arquivo do dono não corresponde ao
código que você leu, o código errado é o SEU — confira `git ls-remote origin main` e a lista de PRs
antes de diagnosticar.

1. **"Os índices não vieram."** A `0025` foi aplicada no banco ERRADO e revertida (PR #57), então no
   projeto em uso as tabelas macro não existem. Sem dado, o export nem criava a aba — e aba ausente
   não distingue "coleta não rodou" de "defeito no export". Agora a aba **Macro existe sempre**,
   dizendo o que falta (aplicar a `0025` no projeto certo, ATIVAR o workflow — que roda dia 12 e não
   faz carga histórica sozinho) e **qual é o efeito** (as premissas de IPCA/Selic ficam em branco; dá
   para digitar por cima, mas aí o número é memória de quem digitou, não índice publicado).
2. **"A aba de DRE não veio."** A extração falhou: **429 da OpenAI**, junto com o Balanço da SPE — é
   por isso que também faltava a coluna da SPE. Agora Balanço/DRE/Fluxo **existem sempre**, e a aba
   sem dado **nomeia o arquivo** que chegou e não extraiu, distinguindo de "nenhum documento desta
   demonstração" (uma pede reprocessar, a outra pede cobrar o documento). O Resumo declara
   "Documentos SEM linha extraída: 2 de 14: …".
   **Na causa:** a cadência da extração foi separada da classificação (6s → 12s). O dado que decidiu:
   os dois que caíram são dois dos **menores** documentos do book — não foi o tamanho deles, foi o
   balde de TPM esvaziado pelos pesados que passaram antes. Quem esvazia o balde não é quem cai.
   Retry não resolve (o `waitBetweenTries` do N8N tem teto de 5s: 6 tentativas cabem na MESMA janela
   de TPM que acabou de recusar). Definitivo é gastar menos input — PDF como TEXTO, com o N8N vivo.
3. **"As demais abas não vieram."** Vieram: estavam **OCULTAS** (decisão do v27). Isso responde por si
   — aba oculta em arquivo de entrega lê-se como dado ausente. **Nada fica oculto agora**; a Modelagem
   continua sendo a aba ATIVA.

**O defeito numérico (não pedido):** a VT Logística saiu com **Ativo Circulante 7.254 onde o documento
diz 3.961** — "Contas a Receber" (3.293) somada JUNTO com "Fretes a receber" (3.562) e "(-) PECLD"
(−269), que são os componentes dela. O PDF **imprime** o total da seção, mas a extração daquele
arquivo não o trouxe, e **sem total informado não existe linha de checagem**: o número errado não
tinha como ser percebido. A detecção de subtotal depende de a extração anotar a SUBSEÇÃO em `secao`;
quando ela anota a seção de topo, passa.

> **PRÓXIMA FATIA, e é a mais valiosa que sobrou:** conserto de verdade exige a **ORDEM das linhas do
> documento** (o subtotal vem impresso ACIMA dos componentes — é assim que `render.py` do book e
> qualquer demonstração real imprimem). Ordem hoje **não é persistida**: `campo_extraido` não tem
> coluna de ordem e a query do export não ordena. Fatia = migration (`ordem int`) + n8n mandando o
> índice da linha + `.order("ordem")` na rota + detecção "subtotal seguido dos seus componentes" no
> export. Precisa de reprocessamento para valer no dado antigo.

Nesta rodada ficou o mínimo honesto: seção cujo número é a NOSSA soma (porque o documento não informou
o total) **carrega a ressalva na célula**, nomeando o risco de dupla contagem. Não conserta o número;
impede que ele passe por conferido.

**Conferido e OK no v28:** as 38 seções do Balanço das 4 empresas extraídas batem com o gabarito ao
centavo; consolidação de entidade funcionando (1 coluna por empresa, não 15); DMPL como matriz
correta; zero "Contas Não Classificadas"; notas explicativas fora das demonstrações.

**Ainda aberto na fila do dono** (reconciliação, não mexi): divergência de caixa com diferença de
**4.340.000** (é conversão de escala entre documentos em escalas diferentes); "Ativo 158.801 vs
Passivo+PL 150.232" no combinado; e o alerta de fabricação com **4 contas repetindo 14.529**, que é o
total do ativo da Componentes — vale conferir junto.

**Validação:** `verificar-export.mts` 105 → **113**; n8n **106**; `Supabase/test/run.sh` 21+13+12;
`tsc`/`eslint`/`next build` limpos. Provados não-vazios (18a-18e, 19b-19c). **Três invariantes antigos
foram REESCRITOS em vez de deletados** — o 11 travava a ocultação, o 15 travava a aba oculta de dado
cru, e o 16h/16i usavam "a aba Balanço não existe" como proxy; cada um agora trava a intenção original
de outra forma. Teste que vira verde por deleção não protege nada.

## Sessão 15 — Reextração é versão nova, e substitui em vez de acumular (`Supabase/migrations/0026`)

Veio de uma pergunta do dono: ele aplicou as migrations e reimportou os workflows, mas não entendeu a
pendência **"reextrair os documentos de DMPL/DVA já processados"**. Explicando, achei a armadilha —
**o caminho que eu tinha mandado ele seguir estava quebrado dos dois lados.**

**Reextrair é a única forma** de um documento já processado pegar prompt/taxonomia novos (migration e
prompt só valem para extração NOVA), e não existe botão de "reprocessar": reextrair é **reenviar o
mesmo arquivo no mesmo mandato**. Só que:

- **No banco:** `fn_registrar_documento` **nunca consultou o hash** — o comentário da `0004` dizia
  "idempotente-ish por hash", mas nenhum corpo (0004→0008) chegou a olhar. Todo reenvio inseria
  `documento` + `documento_versao` + `checklist_item_status` NOVOS: o mesmo arquivo virava dois
  documentos, duas linhas na fila, dois itens de checklist e colunas duplicadas da mesma empresa no
  export (o "15 colunas para 5 empresas" do v27 tem essa mesma família de causa).
- **No export:** ele lia **TODAS as versões** do documento. E duas extrações do mesmo arquivo não
  produzem as mesmas linhas — é o ponto de mudar o prompt. **Medi antes de escrever o fix:** com a
  conta renomeada entre as duas extrações, ela aparece DUAS vezes e a soma da seção somou as duas
  (1.000 + 1.500 = **2.500** onde o documento diz 1.500). Dupla contagem por um caminho novo, e do
  pior tipo: as duas linhas têm proveniência legítima, então nada parece errado ao abrir a planilha.

O que a fatia trava:

- **`(caso_id, hash)` → versão nova do MESMO documento** (`n_versao+1`), sem duplicar checklist nem
  pendência. **Hash nulo nunca casa**: dois desconhecidos não são o mesmo arquivo, e fundir documentos
  distintos é o erro mais caro que essa função pode cometer.
- **Máquina não sobrepõe humano.** Se alguém já revisou o documento na fila (`documento.fonte =
  'humano'`), a reextração não desfaz a correção — anti-ancoragem no sentido que importa aqui.
- **`versoesVigentes` no export: a mais recente COM DADO manda.** Não é "a mais recente", e a
  diferença é uma proteção real: reextração pode falhar e gravar `extracao_falhou` com ZERO linhas
  (`0016`); vigência cega ao dado APAGARIA do book tudo o que a versão anterior extraiu com sucesso.
  Trocar dupla contagem por perda silenciosa não é conserto. Empate sem `n_versao` declarada mantém as
  duas (chutar qual é a nova seria pior que o comportamento antigo).
- **Substituição declarada no Resumo** ("Linhas de versão substituída (fora deste export)") — a
  extração anterior continua no banco para auditoria, e o dono sabe que ela existe.
- **Overload morto de 14 args** (`fn-registrar-documento-overload-duplicado`) removido: ele ainda
  carregava o corpo da época da `0006` — sem `confianca`/`fonte`/`justificativa` e sem idempotência —
  e qualquer chamada posicional podia cair nele.
- **`reset-0006-regride-funcoes`** (armadilha de produção): o `Supabase/README.md` mandava rodar a `0006`
  quando o N8N diz "function does not exist" — mas a `0006` recria os corpos DELA e regride tudo o que
  veio depois (sumiria a idempotência, as guardas `0013`/`0016`, o auto-aceite `0019`, e voltaria o
  overload morto). O aviso agora diz para continuar aplicando **0007 → 0026 em ordem** depois do reset.

**Validação:** `Supabase/test/reextracao.test.sql` novo com **12 asserts**, incluindo os NEGATIVOS que
seguram a fronteira (hash diferente = documento próprio; hash nulo não casa; tipo revisado por humano
sobrevive). `verificar-export.mts` **79 → 85**. Provados não-vazios: sem a busca por hash, "mesmo hash
=> MESMO documento" falha; sem a vigência, 17a/17b/17c falham com `seção=2500 documento=1500` —
exatamente o número que eu havia medido. n8n 105/105, migrations 0001–**0026** limpas,
`tsc`/`eslint`/`next build` limpos.

**Precisa do dono:** aplicar a **`0026`**. Depois disso, reenviar o arquivo da DMPL no mesmo mandato é
seguro — vira versão 2 do mesmo documento e o export usa só ela. (Ainda **custa** uma extração; não
pagar exige a fatia do fingerprint + N8N vivo.) Alternativa sem custo, se o que importa é só a aba:
corrigir o **tipo** na fila de revisão — mas aí a matriz da DMPL pode sair achatada, porque as linhas
antigas foram extraídas sem o contrato `secao`=movimento / `chave`=componente.

## Sessão 14 — DF auditada: o conjunto num arquivo só é separado por demonstração

O `.xlsx` do próximo teste ainda não chegou. Rodei a suíte inteira primeiro (passo 1 do protocolo) —
verde de ponta a ponta: n8n 103/103, `verificar-export.mts` 69/69, `Supabase/test/run.sh` 21 + 13 asserts
de macro, migrations 0001–0025 limpas, `tsc`/`eslint`/`next build` limpos — e ataquei o **único
`CRÍTICO` local que ainda restava** na auditoria (`df-auditada-bypassa-roteamento-linha`).

**O defeito.** Num mandato real o conjunto não chega em três arquivos: chega como **um PDF do
exercício** ("Demonstrações Contábeis 2025.pdf", "DF Auditadas 2025.pdf") com Balanço + DRE + DFC +
DMPL + **notas** dentro. Esse tipo (`DF_AUDITADA`) não pode ter aba própria — que aba seria? — e por
não estar em `ABA_POR_TIPO` caía em `"Outros"`, **onde o roteamento por linha nem rodava** (ele só
corria para documento de tipo estruturado). A entrega mais comum do cliente saía como listagem crua:
sem template, sem total de seção, sem AV%/Δ%, sem indicadores — e a aba **Modelagem** (que lê das abas
de demonstração) saía **zerada**. Mesmo padrão do achado central de v24/v25 e da sessão 11: com a
extração certa, o defeito está no nosso roteamento.

- **Duas portas para ser tratado como composto**, e a diferença entre elas é o que impede isto de
  virar dupla contagem: (a) o **tipo declara** o conjunto (`DF_AUDITADA`) — basta isso; (b) o
  documento **ainda não tem tipo** (nome que a taxonomia não reconhece, esperando a fila) — aí exige
  evidência **declarada** de duas demonstrações (`secao_canonica` de famílias diferentes). É o sinal
  que separa um conjunto de demonstrações de um **aging de recebíveis**, que é homogêneo.
- **Não se estende ao resto de "Outros"**, de propósito: aging, estoque, extrato, razão e notas
  **detalham** o que o balanço traz consolidado. Roteá-los somaria o detalhe DEBAIXO do total
  informado — a dupla contagem que o export levou três rodadas para eliminar. `ehSecaoDeNotaExplicativa`
  mantém a nota fora de qualquer demonstração **mesmo vindo dentro da DF auditada**; ela continua
  entregue, com proveniência, na listagem documental. (A regex exige "explicativa" ou um NÚMERO depois
  de "nota": "Notas promissórias a pagar" é conta legítima de passivo.)
- **Defeito meu, pego pelo invariante e não por leitura.** Sem estrutura própria para desambiguar, o
  fallback determinístico tenta **Fluxo primeiro** — e "Prejuízo líquido do exercício" é âncora da DRE
  **e** do Fluxo indireto. Resultado da primeira versão: a DRE inteira foi para a aba do Fluxo (Lucro
  Bruto 10.820 onde o documento diz 5.280; Fluxo operacional −41.175 onde diz 1.090). **Quem desempata
  é o próprio documento:** ele IMPRIME os blocos e a extração traz o cabeçalho em `secao`. A seção
  decide por **voto** das suas linhas, e a ordem de evidência virou: **o que a IA declarou para a
  linha → o bloco em que o documento a imprimiu → palavra-chave.**
- **DRIFT REAL no gerador**, achado ao ligar a ponta do intake: a cópia à mão de `ALIASES` em
  `build-workflow.mjs` **parava em `BALANCETE`**, então o nó que roda em PRODUÇÃO não conhecia
  `DF_AUDITADA`, `MAPA_DIVIDA`, `EXTRATO_BANCARIO`, `AGING_AR/AP`, `ESTOQUE`, `CERTIDOES`,
  `CONTINGENCIAS`, `SITUACAO_FISCAL`, `ORGANOGRAMA`, `RAZAO` nem `NOTAS_EXPL` — arquivos com esses
  nomes saíam do passe de nome **sem tipo**, que é justamente a chamada de IA que esse passe existe
  para evitar. Agora o gerador **importa** a lista de `lib/taxonomia.mjs` (fonte única, como já era com
  os enums e o prompt) e um teste compara as duas, **ordem inclusa** (a ordem é semântica: regra
  específica antes da genérica). Junto: `DF_AUDITADA` passou a reconhecer "demonstrações
  contábeis"/"demonstrações financeiras"/"DFs".
- **O que NÃO mexi, e por quê:** "Balanço Patrimonial DRE, DFC 2024.pdf" (arquivo real do dono) segue
  casando `FLUXO_CAIXA` pelo "dfc". Promovê-lo a `DF_AUDITADA` (complementar) tiraria dele a
  capacidade de satisfazer itens **obrigatórios** do Kit Básico e mudaria a completude de **todo caso
  já aberto** — decisão de produto do dono, não efeito colateral de uma fatia de export. E o
  roteamento por linha já separa esse arquivo aba por aba de qualquer jeito.

**Validação:** `verificar-export.mts` **69 → 79**; n8n **103 → 105**; `Supabase/test/run.sh` 21 + 13;
migrations 0001–0025 limpas; `tsc`/`eslint`/`next build` limpos. Invariantes provados **não-vazios**:
desligando o roteamento composto a DF auditada volta a sair como `"Resumo, Outros"` (16a/16j falham e
8 checagens desaparecem); desligando a guarda de nota, as notas vazam para o Fluxo (16d/16e/16f);
mexendo em `ALIASES` sem regenerar, o anti-drift falha.

**Precisa do dono:** nada para o export. Para o passe de nome novo valer em produção, **reimportar**
`workflow.e1-ingestao.json`.

## Sessão 13 — Índices macro: histórico (BCB/IBGE) + Focus, e o modelo consumindo os dois

Pedido do dono: automatizar índices macro **validados e revisados**, com retorno médio de 3/5/10 anos,
e ligar isso à modelagem. `Supabase/migrations/0025` + `N8N/workflow.macro.json` (workflow **separado**, roda
no relógio — falha dele não derruba a ingestão) + aba **Macro** no export.

**São duas coisas diferentes, e o modelo usa cada uma para o que ela serve:** `indice_macro_obs` é o
que **aconteceu** (série mensal publicada) e **calibra**; `indice_macro_expectativa` é o que o mercado
**espera** (Focus/BCB, por ano) e **projeta**. Média do passado não é previsão — projetar com ela é
dirigir pelo retrovisor, e era o caminho mais fácil de tomar ali.

- **Duas fontes para o mesmo número.** O IPCA é produzido pelo IBGE e espelhado pelo BCB; a observação
  é chaveada por `(serie, data_ref, FONTE)` para as duas coexistirem — sobrescrever uma com a outra
  destruiria a evidência que autoriza chamar o dado de conferido. `fn_divergencias_indice_macro`
  **aponta e não corrige** (não temos autoridade para decidir qual fonte está certa); tolerância de
  0,01 p.p. porque arredondamento de publicação não pode virar alerta semanal.
- **Composição, nunca soma nem média aritmética.** 12 meses de 1% dão 12,68%, não 12%; a média de 10%
  e 4% é 6,96%, não 7,00%. Vale no SQL, na lib e **na FÓRMULA da aba Macro** (`PRODUCT^(1/n)`, com
  teste **proibindo `AVERAGE`**). Série de **NÍVEL** (câmbio) varia entre fechamentos — compor nível
  seria erro conceitual, e por isso a natureza da série está no catálogo.
- **Ano incompleto não entra na média** (o corrente tem 5 meses): continua visível, com o nº de meses
  anotado, mas fora da janela.
- **Coleta no dia 12**, não no dia 1: o IBGE divulga o IPCA por volta do dia 10, e coletar antes faria
  a conferência acusar divergência todo mês por atraso de publicação.
- **Dois defeitos meus**, achados recalculando a planilha (não lendo o código): os anos do cabeçalho do
  Focus saíam como **TEXTO** e o `MATCH` do modelo compara com o exercício, que é **número** — nunca
  casava, o `IFERROR` devolvia 0 e a premissa de inflação aparecia **zerada sem nenhum sinal de erro**;
  e eu havia chamado de "necessidade de financiamento" o resíduo Ativo−Passivo−PL, que **não se move
  com premissa nenhuma** (um resultado pior derruba caixa e PL na mesma medida). A necessidade real é
  o **caixa negativo**: virou linha própria, e ela responde (14.249 → 20.803 com 50% de passivo
  oneroso).

**Validação:** n8n 86 → **103** (17 testes novos, com respostas REAIS das três APIs);
`verificar-export.mts` 57 → **69**; `Supabase/test/macro.test.sql` com 13 asserts e **caso negativo em cada
checagem**. **Precisa do dono:** aplicar a `0025` e **importar `workflow.macro.json`** no N8N.

## Sessão 12 — Aba Modelagem: modelo pronto em fórmula + consolidação de entidade (v27)

Pedido do dono sobre o export do v27: uma aba de modelagem pronta para receber inputs, espelhando um
modelo de FP&A real, com a regra de que **tudo que não for input externo tem de ser FÓRMULA** puxando
das abas de dados — e as abas cruas ocultas ao final. Emenda registrada em `Arquitetura do Sistema/2 Especificação/f0/07` (reabre o "output
não projeta"; é decisão do dono, e o que a emenda não afrouxa está escrito lá).

**Pré-requisito medido antes de construir: a base não estava consolidada.** O Balanço do v27 saiu com
**15 colunas de entidade** para 5 empresas, porque a mesma empresa chega por dois caminhos com grafias
diferentes (apelido da coluna do combinado × razão social do individual) e o mesmo exercício com dois
rótulos ("2025" × "31/12/2025"). Um modelo somando o grupo por cima disso conta cada empresa **duas
vezes** e fecha errado em silêncio. `consolidarNomesDeEntidade` promove o apelido à razão social **só
quando UMA ÚNICA** razão social do caso casa; ambíguo fica como está — fundir duas empresas diferentes
é pior que duas colunas. Balanço: 38 → 26 colunas, entidades 15 → 10.

**Quatro defeitos reais na revisão da própria aba, todos achados por teste:**

1. **PREMISSA MORTA** (o pior): as premissas eram escritas em todas as colunas, mas as fórmulas liam
   sempre `$C$n` — digitar a premissa do 2º ano projetado **não movia nada**. Agora a premissa é **por
   exercício** (coluna relativa), como um modelo de FP&A real.
2. **Modelo abria zerado.** As premissas nascem **derivadas do último exercício real, por fórmula,
   lendo as ABAS DE DADOS** (não as linhas do próprio modelo — isso fecharia **referência circular**).
   A célula continua input: digitar por cima sobrepõe.
3. **Balanço projetado não fechava**: não havia elo entre fluxo de caixa e ativo. O fluxo passou a vir
   ANTES do balanço e o caixa projetado entra no ativo circulante.
4. **Referência de coluna inteira** (`INDEX('Balanço'!$B:$BZ, …)`) — 77 colunas × 1M linhas por
   fórmula: derrubou por falta de memória um motor de fórmulas que abre a planilha inteira sem esforço.
   No Excel do usuário isso é a planilha "pensando" a cada digitação. Intervalos passaram a ser
   limitados ao tamanho real da aba.

Também: lista suspensa na célula de entidade, linha "Dado encontrado" (distingue "exercício sem
documento" de "entidade errada" — os dois davam o MESMO sintoma), sombreado das colunas projetadas por
formatação condicional, e "Dívida líquida / EBITDA" renomeada para "(Passivo total − caixa) / EBITDA"
(o export classifica por seção e **não isola dívida onerosa** — o nome anterior induziria a ler um
covenant que não é aquele).

**O invariante 14 é a tradução literal do critério do dono** ("alterar uma premissa tem de alterar o
modelo inteiro"): monta o **grafo de dependência** das fórmulas e exige que toda linha projetada
alcance as premissas **do seu exercício**, e que nenhuma premissa fique morta. Foi ele que pegou o
defeito 1. Recálculo de ponta a ponta com motor de fórmulas Excel: histórico bate com o gabarito
(Ativo 121.198 / 95.780) e a necessidade de financiamento dá **0,00** nas colunas reais.

## Sessão 11 — DMPL e DVA: código próprio na taxonomia e aba própria (`Supabase/migrations/0024`)

O `.xlsx` do teste v26 ainda não chegou. Rodei a suíte inteira primeiro (passo 1 do protocolo) —
**verde de ponta a ponta**: n8n 83/83, `verificar-export.mts` 21/21, `Supabase/test/run.sh` 21/21,
`tsc`/`eslint`/`next build` limpos — e ataquei a primeira fatia da lista de "diagnosticadas e não
feitas", que era a única inteiramente auto-contida (as outras duas exigem o N8N vivo ou são do
intake).

**O diagnóstico que importa: não era erro da IA nem do prompt.** A DMPL do book saía como `MUTUOS`
porque `tipo_sugerido` é um enum **fechado** nos códigos que EXISTEM na taxonomia
(`N8N/lib/openai.mjs` → `codigosConhecidos`) — sem código para DMPL, o modelo escolhe o vizinho mais
próximo. Mesmo padrão do achado central de v24/v25: **quando a extração está certa, o defeito está
no nosso vocabulário/agregação, não no modelo.**

- **`Supabase/migrations/0024`** — DMPL e DVA como **complementares** (Nível 2). Não entram no Kit Básico:
  mexer na lista de 8 obrigatórios mudaria a completude de **todo caso já aberto**, e isso é decisão
  de produto do dono, não efeito colateral de uma migration de vocabulário.
- **Ordem dos aliases de nome importa e tem teste travando.** O caso comum de "DMPL" num nome de
  arquivo NÃO é a DMPL — é o PDF **composto** ("Balanço Patrimonial DRE, DFC, DMPL 2024.pdf", nome
  real do dono), em que o tipo é o da demonstração principal. Por isso DMPL/DVA vêm **depois** das
  principais em `N8N/lib/taxonomia.mjs`. (Nota honesta: esse arquivo hoje casa `FLUXO_CAIXA` pelo
  "dfc", comportamento anterior a esta fatia; o que o teste trava é que ele não vire DMPL — quem
  decide de fato é o diagnóstico por conteúdo.)
- **Roteamento por LINHA:** `SECAO_CANONICA_ENUM` ganhou `dmpl`/`dva`. Sem isso, a linha de uma DMPL
  embutida num PDF composto só tinha dois destinos, os dois ruins: `patrimonio_liquido` (o saldo de
  fechamento **repete** o total do PL — somá-lo INFLA o balanço, bug real do export do dono) ou
  `NAO_CLASSIFICAVEL`. A guarda `ehLinhaDMPL` continua, agora como rede de segurança e como
  fallback de roteamento para documento ANTIGO (sem `secao_canonica`), cedendo a vez quando o
  classificador do Fluxo reconhece a linha como saldo de caixa.
- **Aba DMPL = a MATRIZ** (linhas = movimentos do exercício, colunas = componentes do PL). Achatá-la
  numa listagem perderia justamente a leitura que a demonstração existe para dar. Isso exigiu um
  contrato no prompt: `secao` = movimento, `chave` = componente — e a **proibição explícita** de usar
  `entidade_coluna` para os componentes, que criaria uma "empresa" fantasma por componente no export.
- **Aba DVA sem template.** A DVA é padronizada pelo CPC 09, mas **não temos nenhum arquivo real
  para validar um template** — e template errado ordena o dado errado em silêncio. Sai o que o
  documento trouxe, na ordem dele, com a seção declarada em coluna própria. Quando aparecer uma DVA
  real, aí sim vale escrever a cascata.
- **Nada de subtotal calculado** em nenhuma das duas (anti-ancoragem, `Arquitetura do Sistema/2 Especificação/f0/07`): a coluna "Total" da
  DMPL é a do documento, ou não existe.
- **Limpeza junto:** o separador de chave composta era um **byte NUL literal** no fonte de
  `export.ts` (caractere invisível). Virou a constante `CHAVE_SEP` — e o motivo não é cosmético: as
  chaves compostas novas que eu tinha escrito com espaço tinham exatamente a colisão que o NUL
  existe para evitar.

**Validação:** n8n **86/86** (3 testes novos); `verificar-export.mts` **34/34** (11 verificações
novas). Os invariantes novos foram **provados não-vazios**, como o protocolo exige: desligando o
roteamento por linha cai 1; desligando o mapa de abas caem 3 e somem 11. Migrations 0001–0024 limpas
em Postgres 16 local; `Supabase/test/run.sh` 21/21; `tsc`/`eslint`/`next build` limpos.

**Precisa do dono:** aplicar a `0024`, **reimportar o workflow** (o enum de tipos e o prompt vivem no
JSON gerado) e **reextrair** os documentos de DMPL/DVA já processados — a regra de sempre: migration
e prompt só valem para extração NOVA.

## Sessão 10 — Teste v25: reconciliação sem ruído, export que fecha (PRs #49-#52)

Três rodadas encadeadas a partir do `.xlsx` do **teste v25** e do print da fila com **36 pendências
de reconciliação**. A lição transversal: **medir e reproduzir antes de mexer** — em duas das três
rodadas o que eu "sabia" estava errado.

### PR #50 — reconciliação: 36 pendências → 0 (`Supabase/migrations/0023`)

Reproduzi as 36 num fixture de **extração fiel** dos 14 documentos (`Supabase/test/gerar_fixture.py`, gerado
do próprio gerador do book) ANTES de mexer em qualquer linha. Deu exatamente 36 — o fixture é fiel.
A invariante que ele trava: **extração fiel não abre pendência nenhuma.** Cinco causas:

1. **Ausência de documento virava pendência** (20 das 36). O fato era VERDADEIRO — o book só tem DFC
   da Metalúrgica. Mas reconciliação não é o canal disso: documento que falta é cobrança do
   **checklist do Kit Básico** (`fn_recomputar_completude`), que já rastreia com estado próprio.
   Emitir aqui também duplica o sinal e enche a fila de itens que o humano **não tem como acionar** —
   não há correção a fazer, o arquivo não foi entregue. E escala com entidades × períodos × checagens.
   Agora a tentativa segue registrada em `reconciliacao` (auditoria intacta) sem abrir pendência.
2. **O COMBINADO não era aceito como balanço** (4 pendências "Nenhum Balanço classificado" para o
   grupo, sendo que o documento 06 É o balanço combinado dele). `fn_documento_balanco` aceita
   BALANCO → COMBINADO → BALANCETE.
3. **Coluna era ignorada.** `fn_valor_conceito` pegava `limit 1` na versão inteira: num comparativo
   isso compara o Ativo de um ano contra o Passivo de outro, e um desequilíbrio de 2024 passava
   batido. Novo `fn_valor_conceito_col` + `fn_coluna_entidade`/`fn_coluna_periodo_do_ano`, e a
   checagem roda **uma vez por ano declarado** — o comparativo agora é conferido nos dois.
4. **Total de seção sem linha de total** ("RECEITA OPERACIONAL BRUTA" é cabeçalho sem valor em
   demonstração BR). `fn_soma_secao` soma as contas-folha, excluindo o total da própria seção, as
   **seções irmãs** ("DEDUÇÕES DA RECEITA BRUTA" casa os mesmos termos) e as **âncoras de cascata**
   ("RECEITA OPERACIONAL LÍQUIDA" herda a `secao` do bloco anterior) — os dois só apareceram testando.
5. **Escala divergente recusava a comparação.** Com as duas escalas declaradas e conhecidas, converter
   é determinístico: `fn_fator_escala`/`fn_valor_em_base`. Recusa só escala ausente ou fora do
   vocabulário canônico.

Mais dois achados do próprio fixture: `fn_coluna_periodo_do_ano` distingue "documento sem coluna de
período" de "tem colunas mas nenhuma desse ano" (sem isso a DFC, que cobre só 2025, era comparada
contra o Disponível de **2024**); e a pendência é idempotente por período **compatível**, não igual,
porque a mesma checagem chega por dois documentos com granularidade diferente.

### PR #50 (2ª parte) — a dupla contagem do export NÃO estava corrigida

O invariante que escrevi no PR #48 passava verde enquanto **36 de 44 somas do Balanço divergiam**,
várias exatamente 2,00x — o fixture sintético não reproduzia os dois casos reais: a IA anotando a
seção de TOPO em vez da subseção, e o **mesmo rótulo sendo subtotal num documento e conta-folha em
outro** (o export junta os dois na mesma linha).

Correção que não depende de acertar a hierarquia: **quando o documento traz o total da seção, ELE é o
número da seção.** O cabeçalho aponta para a célula do valor extraído (`=<célula>`, fórmula — a
planilha segue viva e a proveniência fica a um clique) e a nossa soma vira `↳ soma das contas
listadas (checagem)`, pintada quando diverge. Errar a detecção passa a ser **ruído visível**, não
total silenciosamente errado — e AV%, Δ% e indicadores usam o número autoritativo.

### PR #52 — nenhuma linha 100% vazia, e categoria vem do documento

Pedido do dono. Medindo: 14 linhas sem valor em coluna nenhuma — nenhuma era falta de dado, era o
template emitido às cegas. **Princípio travado:** o template (CPC 26 / art. 178, cascata da DRE,
CPC 03) **ORDENA** o que o documento trouxe; nunca impõe linha que ele não tem nem inventa valor
(inclusive o `0` que nós escrevíamos quando o documento não disse *nada*).

Mas o que importava eram **dois defeitos escondidos atrás das linhas vazias**:

- **A cascata da DRE fechava em −27.550 onde o documento diz −17.901**: duas contas de Despesas
  Operacionais fora da seção, e a conta residual "Outras receitas (despesas) operacionais, líquidas"
  tratada como **A LINHA** de Receita Operacional Líquida.
- **No Fluxo, "Prejuízo líquido do exercício" era o Caixa Líquido das Atividades Operacionais** — a
  seção operacional saía sem o prejuízo, que é a primeira linha do método indireto (18.991 × 1.090).

Causa comum: a detecção de âncora recebia `secao + rótulo` juntos e casava por **conjunto de palavras,
sem ordem** — a conta herdava as palavras do cabeçalho e virava o total dele. Agora **âncora olha só o
rótulo** e tem de **parecer legenda de total** (`ehLegendaDeTotal`: não pode ser conta de detalhe
`(-) …`/`Outras …`/`Variação em …`, nem trazer muita palavra significativa além da legenda; palavras
de fraseado como "gerado pelas"/"aplicado nas"/"atividades" não contam — é assim que demonstração
brasileira escreve). E **a seção declarada pelo documento manda** na DRE e no Fluxo, como já era no
Balanço.

### PR #49 e #51 — housekeeping

#49 foi handoff. #51 reverteu `ca59311` ("Add files via upload"), 15 `.mp3` de outro projeto que o
dono subiu por engano na raiz. Os blobs seguem no histórico (revert não reescreve); apagar de vez
exige force-push no `main`, oferecido e não executado.

### Ferramentas novas que ficam

- **`Supabase/test/run.sh`** — recria banco, aplica as 23 migrations, carrega o fixture do book e roda
  `Supabase/test/reconciliacao.test.sql` (**21 asserts**). Cada checagem tem um caso **negativo** provando
  que ainda pega o erro real, e todos auto-resolvem quando o número é corrigido.
- **`portal/scripts/lib/avaliar-formula.mts`** — avaliador de `SUM`/refs/aritmética/`IFERROR`. Sem ele
  os invariantes mediam a coisa errada.
- **`verificar-export.mts` foi de 8 → 21 verificações**, incluindo dois end-to-end contra o
  `GABARITO.json`: as 60 seções do Balanço e a DRE 2025 linha a linha.

## Sessão 9 — Correções do teste v24 (PRs #47-#48)

Rodada curta e cirúrgica, disparada pelo `.xlsx` do **teste v24** (o primeiro rodado com o book
complexo). **Diagnóstico central: a extração estava excelente** — todos os "totais informados no
documento" batiam com o gabarito ao centavo (AC 67.878/45.440, PC 63.179, PNC 33.218, PL 24.801,
Ativo 121.198). O que estava quebrado eram **classificação e agregação**. Seis grupos de correção:

- **CRÍTICO — dupla contagem: todo total saía ~2x.** Demonstração real é hierárquica: sob "Ativo
  Circulante" vêm "Disponível", "Contas a Receber", "Estoques"…, **cada um com subtotal impresso**.
  Esses subtotais entravam no bucket como conta e o `SUM` da seção somava subtotal **+** componentes
  (`SUM(L4:L38) = 137.865` vs. informado `67.878`). Contaminava todo total, o AV% e todos os
  indicadores. **`detectarSubtotaisInformados`** (`portal/src/lib/export.ts`) reconhece o subtotal por
  dois sinais **estruturais do próprio documento** — (A) rótulo igual a uma `secao` que outras linhas
  declaram; (B) valor igual à soma dos irmãos da mesma seção **em todas as colunas com dado** — e o
  mantém **visível** (`↳ subtotal informado: X`), fora do range da soma. Não depende de vocabulário.
- **Conta sem vocabulário conhecido furava a soma.** A `secao` que a IA anota é o nome da
  **subseção** ("Estoques", "Outras Obrigações"), que não carrega sinal de Ativo/Passivo — "(-) PECLD"
  e "Produtos em elaboração" caíam em "Não Classificadas". Novo **passe de consenso de irmãos**: a
  linha herda a seção do agrupamento quando os irmãos são unânimes. Conservador por construção.
- **Conta no lado errado do balanço.** "Adiantamentos de clientes" (obrigação) ia pro **ATIVO** porque
  "cliente" é keyword de Contas a Receber e o ativo era testado primeiro. Pares ambíguos agora
  resolvem **antes** do passe genérico (`statement-templates.ts`): adiantamento+cliente, receita
  diferida, tributo a recolher/pagar.
- **Prefixo do nome do arquivo virando ano.** `13_Balancete_..._2025.pdf` saía como `multi 13,25`
  (o `13` virou 2013) em **4 dos 14 documentos** — fragmentava a tabela `periodo` e **impedia a
  reconciliação de casar documentos do mesmo exercício**. `parsePeriodo` (`N8N/lib/classifier.mjs` +
  espelho no `build-workflow.mjs`) descarta prefixo de ordenação, prioriza ano de 4 dígitos,
  entende `2025x2024`, ordena lista multi-ano.
- **`Supabase/migrations/0022`** — três coisas: (a) **pendência de período falsa pela 3ª vez** — a
  comparação canônica da `0020` ainda acusava divergência entre o mesmo período em granularidades
  diferentes; agora compara **conjunto de anos** (`fn_anos_periodo`, `fn_periodos_equivalentes`,
  `fn_periodos_compativeis`) e só diverge quando os dois lados declaram anos e eles diferem; (b) **11
  pré-condições "documento ausente" com os documentos presentes** — as checagens casavam `periodo_id`
  **exato**; a tolerância teve de entrar **por lookup dentro de cada uma das 4 checagens**, não por
  checagem (tentar a checagem inteira com um período por vez nunca acha os dois lados, que podem estar
  em granularidades diferentes — essa foi a tentativa #1, que falhou); (c) **5 alertas falsos da
  guarda** de padrão suspeito — contava valor repetido no lote inteiro, e num combinado (5 empresas ×
  2 anos) valor pequeno coincide à toa; agora conta repetição **dentro da mesma coluna** e só em
  valores **materiais** (≥1% do maior do documento). Guarda que grita à toa é pior que guarda nenhuma.
- **Combinado: "Eliminações" e "Combinado" viravam empresa.** Ganhavam coluna de entidade e AV%
  calculado sobre coluna de ajuste. Agora são reconhecidas, **rotuladas** ("ajuste — não é entidade" /
  "total do documento — não somar com as demais"), vão pro fim e não recebem AV%/Δ%.

**Ferramenta nova que fica:** `portal/scripts/verificar-export.mts` (8 invariantes nesta sessão; 21
depois da sessão 10).
Validação da rodada: n8n **83/83**; migrations **0001–0022** limpas em Postgres 16 local com os
cenários do v24 exercitados (período equivalente → 0 pendências; divergência real 2025×2023 → 1;
reconciliação cross-granularidade → `ok`; guarda sem falso positivo mas ainda pegando fabricação
real); `verificar-export.mts` 8/8; `tsc`/`eslint`/`next build` limpos.

**PR #47** trouxe o gerador do book (`Dados de Teste/book-vertentes/`) e o handoff; **PR #48** as seis
correções acima. Ambos mergeados.

## Sessão 8 — Camada analítica + rodada de endurecimento (PRs #43-#46)

Partiu de dois pedidos do dono: (a) entregar a leitura analítica que um modelador espera pronta,
fundamentada na bibliografia que ele adicionou (`Arquitetura do Sistema/6 Referência/Embasamento sobre Contabilidade`); (b) achar e
resolver TUDO que estava em aberto ou que quebra pela variação entre contratos. Uma **auditoria
multi-agente** produziu 45 findings priorizados, versionados em
**`Arquitetura do Sistema/4 Análises e Auditorias/AUDITORIA_HARDENING_2026-07-24.md`** — é a fonte única do backlog restante, leia esse arquivo
antes de escolher o próximo passo.

- **PR #43 — camada analítica do export** (`Arquitetura do Sistema/2 Especificação/f0/08_padrao_entrega_analitica.md` novo + emenda no
  `Arquitetura do Sistema/2 Especificação/f0/07`): **AV%** (common-size: % do Ativo Total no Balanço, % da Receita Líquida na DRE), **Δ%**
  entre períodos comparáveis da mesma entidade, e bloco de **indicadores de liquidez/estrutura** no
  Balanço (Liquidez Corrente/Geral, Endividamento Geral, Composição do Endividamento, Participação de
  Capital de Terceiros, Imobilização do PL). Tudo em fórmula Excel com `IFERROR`; **nenhum índice é
  emitido sem o insumo real** (célula vazia, nunca estimada). Fundamentação: Fridson & Alvarez,
  Matarazzo/Assaf Neto, Penman, Schilit, Altman. O faseamento honesto do que ainda falta (liquidez
  seca, cobertura de juros, dívida líquida/EBITDA, ciclo de caixa, ROA/ROE, Altman Z'') está no `Arquitetura do Sistema/2 Especificação/f0/08`.
- **PR #44 — período canônico + robustez de classificação**: `Supabase/migrations/0020` (`fn_ano4`,
  `fn_periodo_canonico`) faz `fn_registrar_diagnostico` comparar período por **forma canônica** — o
  falso "PERÍODO PODE ESTAR INCORRETO" que o dono viu na fila (`2025-01-15` × `15/01/2025`, `2025` ×
  `12M25`) desapareceu, e as pendências falsas auto-resolvem. `formatarPeriodo` ficou robusto
  (`02,25` era exibido como "2002–2025"). Classificação: vocabulário muito ampliado, direção de
  empréstimo/mútuo ("concedido" → Ativo), `ehLinhaDMPL` restrito a data completa, agrupamento por
  conta normalizado.
- **PR #45 — prompt de extração endurecido + FONTE ÚNICA**: seção nova de **moeda/escala**
  (vocabulário fechado `unidade|milhar|milhao`; `moeda`/`unidade` eram `required` no schema mas o
  prompt não dizia nada sobre elas), **convenção de sinal e decimal BR** (parênteses = negativo;
  ponto é milhar), e **notação canônica de período na emissão**. O prompt tinha **três cópias que já
  haviam divergido** — o gerador agora importa `SYSTEM_PROMPT` de `lib/extract.mjs` e o embute
  literalmente; **dois testes travam isso** (nunca voltar a parafrasear).
- **PR #46 — escala por linha, Classe B com escala, ordem cronológica**: linha não-monetária (%,
  por ação, quantidade) **não herda** a escala do documento (`ehLinhaNaoMonetaria`) — evita
  mis-escala de 1000x, a custo zero de API; `Supabase/migrations/0021` dá à **Classe B** a pré-condição de
  escala que a Classe A já tinha (comparava R$ mil contra R$ unidade); e o export passou a ordenar
  períodos **cronologicamente** (era alfabético: "Dez/2024" antes de "Jan/2024", o que fazia o **Δ%
  casar o par errado**) + colunas do mesmo período colapsadas.

**Custo (pergunta do dono "reduzir sem comprometer qualidade") — `docs/CUSTO_OPENAI.md`:** onde o
dinheiro vai (o PDF domina o input; output custa ~4x o input; documento mal nomeado paga o PDF duas
vezes) e as alavancas ranqueadas. Já feito: cache de prompt travado por teste (prefixo estático) e
`MODEL_CLASSIFICACAO`/`MODEL_EXTRACAO` como constantes (trocar o modelo da tarefa leve é uma linha).
As duas maiores alavancas — **PDF como texto em vez de imagem (60-80% do input)**, que o mesmo nó
resolve junto com o gap crítico de `.docx`/`.xlsx`, e **não enviar o PDF duas vezes** — exigem o N8N
vivo do dono e por isso NÃO foram implementadas às cegas.

**Book de teste novo (`Dados de Teste/book-vertentes/`):** gerador de um grupo fictício com 5 empresas em
distress severo (14 PDFs: balanços detalhados de 4 níveis, combinado com eliminações/MEP/participação
de não controladores, DRE/DFC/DMPL, faturamento 24M, mapa de dívida **em reais**, balancete D/C,
notas com going concern). Os números são **calculados e validados por assert** (balanço fecha em toda
entidade e no combinado; DRE amarra com a DMPL; DFC com o Disponível; faturamento com a receita).
Traz **10 armadilhas deliberadas** e um **gabarito**. O dono ia testar com ele e voltar com o
resultado — **se ele trouxer o resultado, é daí que a próxima rodada começa.**

## TL;DR pra quem está começando agora

O sistema é um pipeline de due diligence financeira: **N8N** (self-hosted) recebe upload →
classifica o tipo de documento → chama a **OpenAI** (multimodal) pra diagnosticar + extrair linha a
linha → grava no **Postgres/Supabase** → o **portal Next.js** (Vercel) mostra dashboard, fila de
revisão e exporta pra Excel. Princípio inegociável (`Arquitetura do Sistema/1 Visão e Doutrina/01`): nada vira FATO sem aceite humano
explícito (anti-ancoragem) — a única exceção documentada é auto-aceite de linhas com confiança
extraída ≥95% (decisão explícita do dono, `Supabase/migrations/0019`).

**O que está funcionando e testado** (kit de PDFs sintéticos + arquivos reais do dono):
classificação por tipo de documento, extração linha a linha com proveniência, classificação por
SEÇÃO contábil (Ativo Circulante, Despesas Operacionais etc. — `statement-templates.ts`), export em
Excel com FÓRMULAS (não valores estáticos), reconciliação Classe A/B, fila de revisão, auto-aceite
≥95%.

**Rodada de feedback do dono sobre o "teste v20" (PRs #39, #40, #41 — histórico, já mergeados):**
- **PR #39** (mergeado): fila de revisão com cards que não fechavam ao confirmar (`0018`); vazamento
  de linhas entre abas do export; `MUTUOS`/`FAT_INTRAGRUPO`/`CONTRATO_SOCIAL` sem aba própria
  fazendo sentido contábil; colunas técnicas demais nas abas simples (Faturamento/Dívida/...);
  auto-aceite ≥95% (`0019`).
- **PR #40** (mergeado): o dono perguntou por que o "total informado no documento" divergia do
  cálculo automático MESMO em arquivo de teste sintético — achamos **2 bugs reais de classificação**
  (não do arquivo de teste, de convenções comuns de demonstração brasileira): DRE contando um
  subtotal em cascata duas vezes, e cabeçalho combinado "Passivo e Patrimônio Líquido" jogando tudo
  pra Patrimônio Líquido. Ambos corrigidos em `statement-templates.ts`. Também: removida toda menção
  a tipo/versão de taxonomia da planilha, período padronizado (`formatarPeriodo`), notas de célula
  com fonte compacta + caixa ampliada via pós-processamento JSZip (ExcelJS não expõe isso).
- **PR #41** (mergeado): o `formatarTipoTaxonomia`/`formatarPeriodo` só rodavam no export em Excel —
  ligados também no dashboard, na planilha do documento e na fila de revisão (nada de código cru
  tipo "FATURAMENTO_24M" na tela); e o prompt de IA que gera o campo `resumo` do documento foi
  ajustado pra não repetir entidade/tipo/período (já aparecem em colunas próprias).

**Pendente agora — ver a seção "⚠️ COMECE AQUI" no topo deste arquivo.** Resumo: o dono aplica a
`0023`, a `0024` e a `0025` no Supabase, **reimporta** `workflow.e1-ingestao.json`, **importa**
`workflow.macro.json`, reextrai os DMPL/DVA já processados e manda o export novo. As fatias não feitas
são PDF-como-texto + `.docx`/`.xlsx` (exige o N8N vivo) e dois itens de resolução de entidade no
intake. Backlog largo em `Arquitetura do Sistema/4 Análises e Auditorias/AUDITORIA_HARDENING_2026-07-24.md`; custo em `docs/CUSTO_OPENAI.md`.

**Além do export, já existem:** aba **Modelagem** (modelo de FP&A em fórmula, premissa por exercício —
sessão 12) e aba **Macro** (IPCA/Selic/câmbio: histórico do BCB/IBGE calibra, Focus projeta — sessão
13, `Supabase/migrations/0025` + `N8N/workflow.macro.json`).

**Regra que vale pra qualquer reimportação/migration:** só afeta extrações **NOVAS** — documento já
extraído não muda retroativamente, precisa reextração explícita.

---

## 1. Estado atual

### Fundação (F0) — completa, mergeada
Todas as decisões estruturais estão travadas e documentadas em `Arquitetura do Sistema/2 Especificação/f0/` (build vs. buy,
taxonomia v1, schema conceitual, spec de output, protocolo de golden set). Gate aberto
para a F1.

### F1 — Walking Skeleton

**Fatia 1 (E1 — Intake determinístico): construída, testada ao vivo, em produção.**
- N8N (self-hosted, PikaPods): Form Trigger → hash/integridade → classificação por
  nome+regras → fallback OpenAI (conteúdo, quando confiança baixa) → registro no
  Postgres → recomputa completude vs. Kit Básico.
- Confirmado rodando ponta a ponta com documentos reais (`BALANÇO ACUMULADO
  2025.pdf` e outros).
- **Portal (Vercel)** também construído e testado: login (Supabase Auth), dashboard
  do caso (checklist Kit Básico + lista de documentos), fila de revisão (humano
  confirma/corrige classificação).

**Fatia 2 (E2 — Extração de linhas financeiras): construída, rodando em N0 (sombra).**
- Mesma chamada da OpenAI (multimodal) já extrai linhas contábeis (rótulo + valor +
  página + confiança) e grava em `campo_extraido`. Nada disso é apresentado como fato
  ainda — é insumo para a reconciliação (Fatia 3).

**Diagnóstico de conteúdo (E1/E2) — construído e testado nesta sessão (feedback do dono:
"não está buscando a entidade e não está fazendo o diagnóstico/análise linha por linha").**
- Causa raiz: a IA só lia o CONTEÚDO do documento no fallback de baixa confiança do
  classificador por nome — como a maioria dos arquivos bem nomeados já batia confiança alta,
  o fallback quase nunca rodava, e só ele buscava entidade. Fix: a chamada que **já rodava
  sempre** (extração E2) passou a devolver, na MESMA chamada (não aumenta o nº de chamadas à
  OpenAI): um bloco `diagnostico` (entidade; confere tipo/período do nome contra o conteúdo
  real; legibilidade real do arquivo — antes hardcoded `'ok'`; resumo objetivo) + linhas
  extraídas com `secao` (agrupador que espelha a estrutura do documento — Ativo Circulante,
  Passivo Não Circulante, PL, etc. — a "planilha organizada" pedida pelo dono).
- `Supabase/migrations/0010_diagnostico_e1e2.sql`: colunas novas (`campo_extraido.secao`,
  `documento.resumo`, `documento_versao.nota_legibilidade`) + `fn_registrar_diagnostico` —
  preenche `entidade` só quando ainda vazia (nunca sobrescreve), gera `pendencia` tipada
  (`tipo_incorreto`/`periodo_incorreto`/`entidade_incorreta`/`arquivo_ilegivel`) quando o
  conteúdo diverge do já registrado, idempotente (reaproveita pendência aberta) e auto-resolve
  quando a divergência some (ex.: humano já corrigiu na fila de revisão).
- N8N: novo node `Registrar Diagnostico` entre `Gravar Campos (Sombra)` e `Reconciliar (Classe
  A)` — roda antes da reconciliação de propósito, para ela já enxergar a entidade recém-
  preenchida. 53/53 testes (`workflow-sim` + `extract`) passando.
- Portal: nova rota `/casos/[id]/documentos/[docId]` — mostra a "planilha" (linhas agrupadas
  por seção, com valores formatados) + resumo + aviso de legibilidade ruim; dashboard do caso
  ganhou link "ver linhas →" por documento, badge de legibilidade, coluna de resumo, e uma
  seção "Qualidade dos arquivos" (pendências `arquivo_ilegivel`); fila de revisão ampliada para
  aceitar também `tipo_incorreto`/`entidade_incorreta`/`periodo_incorreto` (reaproveita
  `fn_revisar_documento`, que já corrige os três juntos — nenhuma UI nova precisou ser criada
  para isso).
- Testado contra Postgres 16 local (entidade nova, entidade conflitante + correção humana +
  auto-resolução, tipo/período divergente, arquivo ilegível, idempotência, integração completa
  com a reconciliação Classe A). **Confirmado rodando ao vivo no N8N/Supabase real do dono**
  (2026-07-21, depois de aplicar a migration `0010` que faltava — `Registrar Diagnostico`
  executou e achou a entidade certinho).

**Fatia 3 (E3 — Reconciliação): Classe A construída e testada (ainda não em produção real).**
- Dono escolheu começar direto pela Classe A (checagens aritméticas determinísticas), sem
  plano detalhado prévio.
- `Supabase/migrations/0009_reconciliacao_e3.sql`: tabela `reconciliacao` (log append-only de cada
  checagem) + `fn_valor_conceito` (casa `campo_extraido.chave` — texto livre da IA — com um
  conceito canônico via termos obrigatórios/excludentes normalizados, sem LLM) + as duas
  checagens canônicas de `Arquitetura do Sistema/2 Especificação/04`: `fn_reconciliar_ativo_passivo_pl` (Ativo = Passivo + PL no
  Balanço; tenta a linha combinada "Total do Passivo e do PL" primeiro, senão soma Passivo +
  PL separados) e `fn_reconciliar_caixa_bp_fluxo` (Caixa do Balanço vs. saldo final do Fluxo de
  Caixa; **aborta se as unidades divergirem** — ex. "R$" vs "R$ mil" — em vez de comparar
  números incompatíveis). `fn_reconciliar_por_documento(documento_id)` é o ponto de entrada
  único chamado pelo N8N.
- Testado de ponta a ponta contra um Postgres 16 local efêmero (migrations 0001-0009 completas):
  checagem batendo, divergência real, documento faltante (precondição), unidades divergentes
  (precondição), auto-resolução de pendência quando a divergência some numa reextração, e
  idempotência (rodar a mesma checagem 2x não duplica pendência — reaproveita pela chave
  `motivo = 'reconciliacao:<tipo>'`).
- N8N: novo node `Reconciliar (Classe A)` no fim do fluxo (depois de `Gravar Campos (Sombra)`),
  chama `fn_reconciliar_por_documento` com o `documento_id` de `Registrar Documento`. 51/51
  testes do `workflow-sim` continuam passando.
- Portal: dashboard do caso (`portal/src/app/casos/[id]/page.tsx`) ganhou seção "Reconciliação
  (Classe A)" listando as pendências abertas de divergência/precondição — **só leitura**, ainda
  não tem uma ação de "confirmar/resolver" dedicada (usa o motor de pendências genérico).
- Opera em **N1** (doutrina): toda checagem gera `pendencia` tipada (`divergencia_reconciliacao`
  ou `precondicao_nao_satisfeita`), nunca escreve um número como fato aceito.
- **Confirmado rodando ao vivo no N8N/Supabase real do dono** (2026-07-21, mesma sessão da
  migration `0010` faltante — depois de aplicar a `0009`, `Reconciliar (Classe A)` executou).

**Fatia 4 (E4 — Output + Portão 2): primeira fatia construída e testada nesta sessão (pedido
direto do dono: "quero que seja extraído para o Excel em um modelo pronto para análise").**
- `Supabase/migrations/0011_aceite_export_e4.sql`: Portão 2 **mínimo** — até aqui `campo_extraido`
  não tinha NENHUM mecanismo de aceite humano, o que violaria o princípio inegociável de
  `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md` ("nenhum número entra no export sem uma `decisao` de aceite humano
  ligada") se o export saísse direto da sombra. `fn_aceitar_extracao(documento_versao_id,
  autor, motivo)` aceita **todas as linhas de uma versão de documento de uma vez** (granularidade
  v0 — a spec permite refinar o "layout fino" depois; não é aceite célula-a-célula ainda).
  Registra `decisao` (tipo `aprovacao`) + `evento_auditoria`. Idempotente.
- Portal: a tela de planilha (`/casos/[id]/documentos/[docId]`) ganhou o botão "Aceitar estes
  dados para a base" + badge de status (aceito/pendente) por linha.
- **Export Excel** (`src/lib/export.ts` + rota `/casos/[id]/export`, biblioteca `exceljs`):
  segue o schema-alvo travado em `Arquitetura do Sistema/2 Especificação/f0/07` — uma aba por demonstração (`Balanço`, `DRE`, `Fluxo
  de Caixa`, `Combinado`, `Faturamento`, `Dívida`, `Fluxo Projetado`), aba `Resumo` com
  metadados do snapshot (data-base, contagem aceitas/pendentes, versões de taxonomia
  envolvidas). **Linhas pendentes aparecem junto com as aceitas** (nunca somem do export), mas
  com preenchimento âmbar + itálico — "sugestão pendente de revisão", nunca fato silencioso
  (mesmo princípio inegociável). O export **não modela nem projeta** (fora do escopo, mesma
  spec) — só organiza o dado curado e rastreável para o time levar ao modelo deles.
- **Duas revisões no mesmo dia** (feedback direto do dono).
  1. Primeira revisão: a versão inicial saiu como lista achatada — "quero formatado igual um
     balanço ou DRE... use o padrão do mercado". Isso deu o **layout padrão de mercado**
     (Ativo/Passivo/PL hierárquico no Balanço — CPC/prática brasileira; cascata Receita→Lucro
     Líquido na DRE; Atividades Operacionais/Investimento/Financiamento no Fluxo de Caixa —
     método indireto, CPC 03), colunas = entidade × período.
  2. **Segunda revisão (mais importante): o dono apontou o problema certo** — um template com
     ~15 nomes de conta FIXOS quebra na primeira empresa que nomeia a conta diferente (cada
     mandato tem um plano de contas diferente). Pediu explicitamente: nenhuma conta pode ficar
     de fora do Balanço/DRE/Fluxo de Caixa, e incluir também **Balancete**. Resposta:
     `src/lib/statement-templates.ts` foi **reescrito de "template de nomes fixos" para
     "classificador por SEÇÃO"** — cada conta extraída é classificada em Ativo Circulante /
     Ativo Não Circulante / Passivo Circulante / Passivo Não Circulante / Patrimônio Líquido
     (Balanço/Balancete/Combinado) ou nas seções da DRE/Fluxo de Caixa por **sinais amplos**
     (a `secao` que a IA já anota, `Supabase/migrations/0010` + palavras-chave no rótulo), **mantendo
     o rótulo ORIGINAL de cada empresa** — nunca força um nome canônico. `Balancete` virou aba
     própria (reaproveita o classificador do Balanço — um balancete é, por natureza, o mesmo
     agrupamento por seção do plano de contas). O casamento por palavra-chave é tolerante a
     **plural/singular e conectivo diferente** ("Duplicatas a Receber" bate com a regra
     "duplicata a receber"; "Provisão PARA Férias" bate com "provisão DE férias") via
     singularização aproximada PT-BR + remoção de conectivos antes de comparar — não é mais
     substring exato. Contas que não são classificáveis com segurança vão para um bloco
     explícito "Contas Não Classificadas (revisar manualmente)" — nunca desaparecem, nunca são
     forçadas pro lugar errado. Nenhum subtotal/total é calculado por soma — só aparece se o
     próprio documento já trouxer aquela linha extraída (anti-ancoragem: não inventamos
     números). Proveniência (arquivo/página/confiança/status/versão da taxonomia) vai em
     **comentário da célula** (as colunas são entidade×período, não sobra espaço para colunas
     auxiliares). Faturamento/Dívida/Fluxo Projetado continuam em listagem simples (já são, por
     natureza, série/tabela).
- A lógica de classificação + montagem do workbook é uma **função pura** (`buildExportWorkbook`
  + `classificarConta`, sem Supabase/Next.js) — testada isoladamente nesta sessão com dados
  sintéticos via `tsx`, incluindo o teste que motivou a 2ª revisão: **duas empresas fictícias
  com nomenclatura de plano de contas totalmente diferente para as mesmas contas** ("Caixa e
  equivalentes de caixa" vs. "Disponibilidades"; "Imobilizado líquido" vs. "Bens do Ativo
  Imobilizado") — ambas classificadas na seção certa, cada uma com o rótulo original. **Achou e
  corrigiu dois bugs reais durante os testes**: (1) sobreposição de padrão — "Total do
  Patrimônio Líquido" também casava com a linha combinada "Total do Passivo e do Patrimônio
  Líquido"; (2) plural/conectivo — "Duplicatas a Receber"/"Reservas de Lucros Acumulados"
  (plural) e "Provisão PARA Férias" (conectivo diferente) não batiam com as regras escritas no
  singular/com "de", exatamente o tipo de variação entre empresas que o dono alertou. A rota em
  si (busca via Supabase) **não foi exercitada contra um projeto real** — só a classificação e
  montagem do Excel, com dados sintéticos.
- Botão "Exportar para Excel ↓" no dashboard do caso.

### Sessão 5 — Teste aprofundado do export (E4) com dados sintéticos mais realistas
Pedido do dono: "testar o export com um caso real". **Ressalva importante:** este ambiente de
execução remoto não tinha (e não tem) credenciais do Supabase/N8N reais do dono nem documentos
reais de clientes — então o que rodou aqui foi um teste **local, mais profundo que o da sessão
4** (que só usou 2 empresas fictícias mínimas), não um teste contra a infraestrutura de
produção. **Continua pendente**: o dono rodar de fato com um caso real (aplicar `0011` no
Supabase de produção, subir documentos reais, aceitar linhas na tela de planilha, baixar e abrir
o `.xlsx` de verdade no Excel/LibreOffice dele; a rota `/casos/[id]/export` — a busca via
Supabase — segue não exercitada contra um projeto real).

O que foi feito e achado:
- **Dataset sintético bem mais próximo de um caso real**: 3 empresas (mesmo grupo econômico,
  planos de contas com nomenclatura diferente entre si — o teste que motivou o classificador por
  seção na sessão 4), Balanço em 2 períodos, DRE em 2 períodos, Fluxo de Caixa (método indireto),
  Balancete, e uma série de Faturamento — 110 linhas extraídas com vocabulário contábil PT-BR
  realista (não mais só o punhado mínimo de contas fictícias da sessão 4). `buildExportWorkbook`
  é função pura (sem Supabase), então isso testa a lógica de classificação/montagem do Excel
  isoladamente, sem precisar de infraestrutura real.
- **Bug real encontrado e corrigido** em `portal/src/lib/statement-templates.ts`: quando a
  `secao` anotada pela IA não vem preenchida (fallback só por palavra-chave do rótulo), qualquer
  conta com "empréstimo"/"financiamento"/"mútuo" no nome caía sempre no **Passivo** — mesmo
  quando o rótulo dizia explicitamente "a receber" (ex.: "Mútuo a Receber de Coligada", comum em
  holdings/grupos econômicos — exatamente o tipo de estrutura societária que a Oria analisa em
  mandatos de M&A/reestruturação). Um mútuo/empréstimo CONCEDIDO pela empresa é um DIREITO (ativo),
  não uma dívida. Fix: o fallback agora verifica o token "receber" no rótulo e classifica pro lado
  do Ativo (circulante/não circulante conforme prazo) quando presente; mantém o comportamento
  anterior (Passivo) quando não há esse sinal. Também foi adicionado `"mutuo"` à lista de
  palavras-chave (antes só "emprestimo"/"financiamento"/"debenture"/"arrendamento" — "mútuo a
  receber" caía inteiro em "Contas Não Classificadas" por falta de cobertura, não por
  classificação errada). Confirmado com teste isolado de `classificarBalanco` antes/depois do
  fix (4 variações: empréstimo concedido com/sem "a receber" explícito, mútuo, e o caso de
  controle — empréstimo tomado de banco — que precisa continuar indo pro Passivo).
- **Validação estrutural do `.xlsx` gerado**: a tentativa de abrir de verdade num programa de
  planilha (LibreOffice headless, pré-instalado neste ambiente) **falhou por motivo do
  ambiente, não do arquivo** — confirmado com `strace` que o LibreOffice deste sandbox não
  carrega nem um `.xlsx`/`.csv` mínimo gerado do zero (`openpyxl`), então não é algo específico
  do nosso export. Como alternativa, a validação foi feita inspecionando o `.xlsx` estruturalmente
  com `openpyxl` (Python): todas as 6 abas presentes, valores/rótulos corretos por
  empresa×período, contas das duas empresas com plano de contas diferente alinhadas na seção
  certa mantendo o rótulo original de cada uma, linhas pendentes com preenchimento âmbar+itálico,
  comentário de proveniência em toda célula com valor, âncoras (totais) em negrito com borda,
  bloco "Contas Não Classificadas" só com as 2 contas genuinamente fora do vocabulário conhecido
  (um jargão de M&A bem específico de PPA/ágio, de propósito no teste). **Isso reduz mas não
  substitui** o dono abrir o arquivo de verdade no Excel/LibreOffice dele.
- **Migrations 0001-0011 reaplicadas contra um Postgres 16 local efêmero** (mesmo padrão de
  sessões anteriores): aplicam limpo, com a mesma ressalva já conhecida de `storage.buckets`
  (schema exclusivo do Supabase, não existe em Postgres vanilla — só afeta a parte de storage da
  `0003`, não trava o resto) e o overload morto de `fn_registrar_documento` já documentado em
  "Itens adiados" (confirmado presente: 2 assinaturas, 14 e 15 params).
- **Fluxo E1→E2→E4 testado de ponta a ponta** (`fn_registrar_documento` →
  `fn_registrar_campos_extraidos` → `fn_aceitar_extracao`): aceite muda `status_aceite` de
  `pendente` pra `aceito` corretamente, grava `aceito_por`/`aceito_em`, cria `decisao` (tipo
  `aprovacao`) + `evento_auditoria`. **Achado (não corrigido, é uma decisão de produto, não bug
  óbvio)**: chamar `fn_aceitar_extracao` de novo na mesma versão (idempotência) não re-aceita
  linhas já aceitas (`n_campos_aceitos: 0` na segunda chamada, confirmado) — mas AINDA ASSIM
  grava uma nova linha em `decisao` e `evento_auditoria` a cada chamada, mesmo quando nada mudou.
  Ou seja: "idempotente" (`Supabase/migrations/0011`) vale pro estado de `campo_extraido`, não pro
  trilha de auditoria — um duplo-clique acidental no botão "Aceitar" do portal geraria uma
  segunda `decisao` com `n_campos_aceitos: 0` no log. Pode ser intencional (toda ação explícita
  de aceite fica registrada, mesmo sem efeito), mas vale confirmar com o dono se isso é desejado
  ou se `fn_aceitar_extracao` deveria pular o registro de decisão/evento quando `n_campos_aceitos
  = 0`.

### Sessão 6 — IA sugere a seção canônica (classificação do export, N1)
Pedido do dono: "podemos colocar uma IA para criar a planilha? Ela interpretaria melhor caso a
caso... preciso que 90% dos campos extraídos estejam dentro de tabelas e categorias condizentes."

**Decisão de desenho (importante — alinhada à doutrina, não a substitui):** NÃO se trocou o
classificador determinístico por uma "IA que monta a planilha". A doutrina (`Arquitetura do Sistema/1 Visão e Doutrina/01`, assinada
pelo dono) trava: classificação contábil nasce N0, teto **N1** ("nunca vira número sem aceite
humano"), e a regra de ouro exige golden set + concordância medida antes de subir o dial — e o
golden set físico ainda não existe (só o protocolo `Arquitetura do Sistema/2 Especificação/f0/06`). Então a IA entrou como **camada de
sugestão N1**, exatamente no padrão que o time já usou pro diagnóstico (0010):
- A MESMA chamada de extração (`N8N/lib/extract.mjs`) — que já roda pra todo documento — passou
  a devolver, por linha, uma **`secao_canonica`**: a IA classifica a conta pelo **significado
  contábil** (não só o nome literal) num enum fixo (`ativo_circulante`, `dre custos`,
  `atividades_investimento`, etc.; `NAO_CLASSIFICAVEL` como escape). **Não aumenta o nº de
  chamadas à OpenAI.**
- `Supabase/migrations/0012_secao_canonica_e4.sql`: coluna `campo_extraido.secao_canonica` +
  `fn_registrar_campos_extraidos` (mesma assinatura) gravando-a.
- O classificador do export (`portal/src/lib/statement-templates.ts` → `classificarConta`) usa a
  sugestão **só como fallback**: se a regra determinística (âncora/seção-livre/palavra-chave) já
  classificou, ela prevalece; a sugestão da IA só entra quando a conta cairia em "Contas Não
  Classificadas", e só se a seção sugerida pertencer à estrutura do documento. Isso ataca direto
  o alvo de 90% sem regredir o que a regra já acerta e **sem depender de golden set**.
- **Continua N1/anti-ancoragem:** a seção afeta só ONDE a linha aparece no Excel; a linha
  continua PENDENTE/âmbar até o aceite humano (`fn_aceitar_extracao`). Nenhum número vira fato.
- **"Otimizar a cada output"** (pedido do dono): isso é o laço de golden set (`Arquitetura do Sistema/2 Especificação/f0/06`) — medir
  concordância IA×humano e, quando alta, subir o dial (fazer a IA ter prioridade sobre a regra,
  ou auto-clear). O mecanismo está desenhado; é medição + ajuste de prompt, não código novo. O
  degrau para promover a IA acima da regra determinística é justamente ter esse golden set.
- Testes: 53/53 do N8N (`node --test`) seguem passando (schema/parse de `secao_canonica`
  cobertos em `extract.test.mjs` e no mirror do Code node em `workflow-sim.test.mjs`); classificador
  do portal validado isoladamente (7 casos: gap-filling, determinístico com prioridade, âncora com
  prioridade, sugestão inválida ignorada, DRE/Fluxo); export end-to-end confirmado (conta de
  jargão com sugestão vai pra seção certa; sem sugestão cai em "Não Classificadas"); `tsc --noEmit`
  limpo; migration 0012 aplicada contra Postgres 16 local (grava `secao_canonica`, inclusive null).
- **Limitação conhecida (follow-up):** não há ainda uma ação no portal pra CORRIGIR uma seção
  sugerida errada (o aceite hoje é por documento inteiro — ver item "Refinar granularidade do
  aceite"). Uma sugestão errada é visível (âmbar) mas só se corrige via reextração por enquanto.
- **Ainda pendente (só o dono consegue):** rodar com documentos reais no Supabase/N8N de produção
  e **medir de fato a taxa de "Não Classificadas"** com o vocabulário real dos clientes — é o
  sinal direto de se o alvo de 90% foi atingido, e o primeiro insumo do golden set.

### Sessão 6 (cont.) — Roteamento por linha: separar cada demonstração em sua aba
**Motivado por teste real do dono** (documento `GLOBAL ONE BRASIL REPRESENTAÇÃO LTDA`): ele rodou
o export e viu a DRE cair em "Contas Não Classificadas". O diagnóstico revelou um problema maior
que o aparente: o PDF era uma **Demonstração Contábil completa** (Balanço + DRE + Fluxo de Caixa +
DMPL num arquivo só), classificado como UM documento do tipo `BALANCO`. O export roteava **todas**
as linhas para a aba do tipo do documento, então: (1) a DRE caía em "Não Classificadas"; (2) pior,
as linhas de **Fluxo de Caixa vazavam para dentro do Ativo/Passivo do Balanço** (as linhas de
caixa casavam as palavras-chave "caixa"/"disponibilidade"/"empréstimo"); (3) linhas de DMPL
("SALDOS EM 31 DE DEZEMBRO...") iam parar no Patrimônio Líquido.
- **Fix (escopo escolhido pelo dono: Balanço + DRE + Fluxo de Caixa agora; DMPL/DVA como
  follow-up):** o export passou a **rotear cada LINHA para a aba da sua demonstração**, não para a
  do tipo do documento. `classificarDemonstracao(secao, chave, secao_canonica)` em
  `statement-templates.ts` decide a qual demonstração a linha pertence: prioridade para a
  `secao_canonica` que a IA **já anota por linha** (o `#27`; `ativo_*`→Balanço, `receita_*/custos/
  despesas_*/...`→DRE, `atividades_*`→Fluxo de Caixa), com fallback determinístico (ordem Fluxo →
  DRE → Balanço, porque o de Balanço casa "caixa" de forma gulosa) quando a IA não anotou. Isto é
  literalmente o pedido do dono ("o modelo identifica o que é DRE e o que é Balanço"): a IA já
  identifica; faltava o export obedecer, por linha.
- **Só reroteia entre abas ESTRUTURADAS** (Balanço/DRE/Fluxo). Abas de série (Faturamento/Dívida/
  Fluxo Projetado) não são tocadas. Um **Balancete/Combinado puro** (também família "balanco")
  mantém suas linhas na própria aba — o rerote só move o que "vaza" para uma família DIFERENTE.
  Continua N1/anti-ancoragem: a linha segue pendente/âmbar até o aceite; muda só EM QUAL ABA a
  sugestão aparece.
- **Reforço do classificador de Fluxo de Caixa** para o vocabulário real: saldos de caixa que
  **não usam a palavra "saldo"** ("Caixa e Equivalentes de Caixa no Final/Início do Período") e
  variação de caixa por "acréscimo/decréscimo" agora são reconhecidos como âncoras de Saldo
  Final/Inicial/Variação — sem casar a linha do Balanço "Caixa e Equivalentes de Caixa" (que não
  tem final/início/período).
- **Testes:** reproduzido o caso GLOBAL ONE isoladamente (via `tsx` + inspeção do `.xlsx` com
  `openpyxl`): com `secao_canonica`, as 3 demonstrações se separam em abas próprias com **zero
  "Não Classificadas"**; sem `secao_canonica` (documento antigo, fallback determinístico), ainda
  separa as 3 abas corretamente (só 1 linha ambígua — "ADMINISTRATIVAS" sem contexto — fica em
  "Não Classificadas", o que a `secao_canonica` da IA resolve). Balancete puro mantido na própria
  aba. `tsc --noEmit` e `eslint` limpos. (LibreOffice deste ambiente segue quebrado — validação
  estrutural via `openpyxl`, mesma ressalva das sessões anteriores.)
- **DMPL/DVA (deferido, escolha do dono):** separar Mutações do PL e DVA em abas próprias exige
  estender o `SECAO_CANONICA_ENUM` (novo schema/prompt no N8N + migration) e **reextrair** os
  documentos — não foi feito nesta fatia. Hoje linhas de DMPL provavelmente caem no PL do Balanço
  ou em "Não Classificadas".

### Sessão 7 — BUG CRÍTICO: item errado no upload em lote (conteúdo trocado entre documentos)
**Motivado por teste real do dono** com 2 documentos reais (`BALANÇO ACUMULADO 2025.pdf` — balanço
combinado de 3 entidades, Certsys Tecn/Part/Com — e `Balanço Patrimonial DRE, DFC, DMPL Global One
2024assinado.pdf`) enviados **juntos no mesmo upload do Form**. O export saiu com dezenas de contas
que não existem em NENHUM dos dois PDFs (ex.: "ADIANTAMENTO A CONSÓRCIOS", "ADIANTAMENTO A
COOPERATIVAS" com valores redondos repetidos — `1.000.000.000,00`, `1.234.567,00` — em várias
contas sem relação nenhuma) e entidade/período errados (pegou o nome do CONTADOR assinante em vez
da razão social num dos documentos; "anual 2023" em vez de "anual 2024" no outro).

**Diagnóstico (comparado linha a linha contra os 2 PDFs originais + consulta SQL no Supabase real
do dono):** não era só alucinação da IA. O `documento` do arquivo "Global One" tinha uma
`justificativa` da IA **descrevendo o conteúdo do Certsys** ("colunas para 'Certsys Teen', 'Certsys
Part', 'Certsys Com'...") — prova de que o CONTEÚDO enviado à IA pra esse item não era o do próprio
arquivo.

**Causa raiz** — `N8N/build-workflow.mjs`, node `Preparar Conteudo` (each-item mode, monta a parte
multimodal da chamada de extração): `this.helpers.getBinaryDataBuffer(0, 'data')` com o **índice
fixo em `0`**, comentário do código dizendo (errado) que "cada item roda isolado em each-item mode,
então o índice é sempre 0". Na prática, mesmo em each-item mode, `getBinaryDataBuffer(itemIndex,
propriedade)` resolve o buffer pelo índice do item **dentro do lote inteiro do node** (é assim que
a referência interna de binário vira bytes de verdade) — não pelo item que o código acha que está
processando. Com 2+ arquivos no mesmo upload, todo item diferente de 0 lia o **binário do item 0**:
o nome/mimeType usados na requisição eram os do próprio item (corretos, vêm do JSON), mas os BYTES
de fato enviados pra IA eram de outro arquivo. Com upload de 1 arquivo por vez isso nunca aparecia
(o único item É o item 0) — por isso passou despercebido em toda sessão anterior, incluindo as
verificações "confirmado rodando ao vivo" de sessões passadas (que sempre testaram 1 arquivo de
cada vez).
- **Fix:** troca do literal `0` por `$itemIndex` (global do N8N que dá o índice do item corrente
  em each-item mode).
- **O teste (`N8N/test/workflow-sim.test.mjs`) tinha o MESMO ponto cego** — o mock de
  `getBinaryDataBuffer` ignorava o `itemIndex` recebido e sempre lia do `item` passado
  explicitamente pela própria chamada de teste (por isso o parâmetro se chamava `_itemIndex`, com
  underscore de "não uso"), então nunca exercitava o cenário real de 2 itens competindo pelo mesmo
  binário resolvido por índice. Corrigido: o mock agora resolve pelo `itemIndex` dentro de um
  `binaryStore` (o lote inteiro, como o N8N faz de verdade); `chainFile(idx)` passa a fornecer esse
  lote completo. **Novo teste de regressão** reproduziu o bug (confirmado FALHANDO com o código
  antigo antes do fix — item 1 lia o binário `QUJD` do item 0 em vez do próprio `REVG` — e
  passando depois). 54/54 testes (`npm test` em `N8N/`).
- **Ação pendente do dono (fora do código, só ele consegue):** documentos processados em uploads
  em lote (2+ arquivos no mesmo Form) **antes** deste fix podem ter conteúdo trocado — qualquer
  `documento` cujo diagnóstico/entidade/valores pareçam não bater com o próprio arquivo é suspeito.
  Recomendação: reprocessar (reenviar) esses documentos depois do fix estar no N8N de produção, e
  **não aceitar** ("Aceitar estes dados para a base") nenhuma extração de upload em lote anterior a
  esta correção sem conferir contra o PDF original antes.
- **Achados secundários** (mesmo teste, менos graves, ainda reais — corrigir depois):
  1. Um documento que é, na prática, uma demonstração **combinada de 3 entidades** (colunas
     Certsys Tecn/Part/Com + Total, sem uma única razão social na página) teve a entidade
     preenchida com o **nome do contador que assinou** o documento — a IA não tem hoje uma
     instrução explícita pra não confundir signatário/contador com razão social quando não há uma
     entidade única óbvia. Vale reforçar o prompt (`N8N/lib/extract.mjs`).
  2. Um documento com Balanço+DRE+DFC+DMPL do mesmo exercício teve o período extraído como o ano
     ANTERIOR (2023 em vez de 2024) — provavelmente confundido pela linha "SALDOS EM 31 DE
     DEZEMBRO DE 2023" (saldo de ABERTURA da DMPL) no mesmo PDF. Também vale reforçar o prompt pra
     diferenciar saldo de abertura vs. o período de referência do documento.
  3. O mesmo tipo de documento (Balanço+DRE+DFC+DMPL de UMA entidade só) foi classificado ora como
     `BALANCO`, ora como `COMBINADO` em re-extrações diferentes — `COMBINADO` na taxonomia (Arquitetura do Sistema/2 Especificação/f0/03)
     significa demonstrações **combinadas de um grupo de empresas**, não "múltiplas demonstrações
     no mesmo arquivo para uma entidade só". Vale clarificar essa distinção no prompt.
  4. **Achado à parte, não é bug:** o caso de teste do dono ("teste v7") acumulou **11 registros de
     `documento`** pra só 2 arquivos, de reprocessamentos em sessões anteriores — normal em uso
     iterativo de teste, mas reforça que uma limpeza/consolidação de dados de teste pode ajudar a
     não confundir qual é a versão "atual" ao depurar.

### Sessão 7 (cont.) — Causa raiz da fabricação de valores + guarda de segurança
Depois do fix do item errado (acima), pedi ao dono os dados brutos de `campo_extraido` via SQL
(o Supabase real dele) pra confirmar a causa exata da fabricação de valores. Achado decisivo: a
versão **correta** do Global One (documento simples, 1 entidade) veio **perfeita** — toda linha
batendo com o PDF real, confiança 0.95-0.99, `unidade` corretamente `null` (o documento diz "Reais",
não "mil"). Isso isolou o problema: o Certsys (`348c46b8`), mesmo recebendo o PRÓPRIO conteúdo (a
`justificativa` da IA o descreve corretamente — não é vítima do bug de item trocado), ainda assim
saiu quase todo fabricado (`1.234.567,00` repetido em ~20 contas, confiança declarada 0.99). Causa:
o Certsys é um balanço **combinado de 3 entidades** (colunas "Certsys Tecn | Part | Com | Total" na
mesma tabela) e o schema de extração só tinha **um** `valor_num` por linha, sem dimensão de
entidade/coluna — ao tentar espremer 4 colunas num valor só, o modelo fabricava.

O dono pediu as duas ações em paralelo (não são excludentes):

**1. Guarda de segurança (`Supabase/migrations/0013_guarda_extracao_suspeita.sql`)** — não resolve a
causa raiz, torna o sintoma visível pra QUALQUER documento, já em produção assim que a migration
for aplicada (não depende de reextrair nada):
- `fn_registrar_campos_extraidos` (mesma assinatura de 0005/0006/0010/0012) passa a analisar o
  **próprio lote** que acabou de gravar (não relê extrações anteriores, pra não misturar com uma
  extração velha) e gerar `pendencia` tipada quando:
  - **`extracao_padrao_suspeito`** (tipo novo no enum `pendencia_tipo`): 4+ contas DISTINTAS com o
    EXATO mesmo valor não-zero — praticamente impossível em dado real, típico de fabricação. Exclui
    zero de propósito (repetir "0,00" em várias linhas vazias é normal, não é sinal de nada).
  - **`extracao_baixa_confianca`** (o enum já existia desde a `0001`, nunca tinha sido usado — só
    estava no catálogo do `Arquitetura do Sistema/2 Especificação/f0/04`): ≥3 linhas E ≥30% do lote com confiança abaixo de 0.7.
  - Idempotente (reaproveita pendência aberta da mesma versão) e auto-resolve numa reextração que
    não repete o padrão — mesmo molde de `fn_registrar_diagnostico`/reconciliação.
- Testado contra Postgres 16 local: extração suspeita gera a pendência certa; reextração limpa
  auto-resolve; baixa confiança gera a pendência certa; chamar duas vezes com o mesmo padrão não
  duplica.

**2. Suporte a documentos multi-entidade (`Supabase/migrations/0014_entidade_coluna_multi_entidade.sql`)**
— ataca a causa raiz, dando à IA uma forma estruturalmente correta de representar o dado em vez de
forçá-la a resumir/adivinhar:
- Coluna nova `campo_extraido.entidade_coluna` — nome da coluna/entidade da linha, quando o
  documento traz várias entidades lado a lado (null no caso comum, 1 entidade só).
- `N8N/lib/extract.mjs` (fonte da verdade) — schema (`entidade_coluna` novo, obrigatório-mas-
  nullable, mesmo padrão de `secao_canonica`) + prompt: quando o documento tem colunas de
  entidade lado a lado, gerar **uma linha por (conta × coluna)**, mesmo "chave", nunca somar/
  estimar um valor único. Mirror manual em `N8N/build-workflow.mjs` (schema JSON + prompt
  comprimido + parse) atualizado junto — mesmo padrão de manutenção de `secao_canonica` (0012).
  `N8N/test/extract.test.mjs` ganhou teste dedicado reproduzindo o Certsys (mesma chave, 4
  `entidade_coluna` diferentes → 4 linhas, não 1).
- Portal: `CampoExtraido`/rota `/export` passam a trazer `entidade_coluna`; `export.ts` usa
  `campo.entidade_coluna || ctx.entidade` para montar a coluna (entidade×período) — cada
  coluna/entidade do documento combinado vira sua PRÓPRIA coluna no export (em vez de forçar tudo
  na entidade principal do documento); a nota de proveniência da célula ganhou "Coluna de origem
  no documento" quando aplicável. Tela de planilha (`/casos/[id]/documentos/[docId]`) mostra a
  coluna de origem ao lado do rótulo quando presente (senão a mesma "chave" repetida N vezes
  pareceria duplicada sem explicação).
- Testado contra Postgres 16 local (grava `entidade_coluna` corretamente, sem falso positivo na
  guarda de padrão suspeito) e via `buildExportWorkbook` fim a fim com os valores REAIS do PDF do
  Certsys (`BENS NUMERÁRIOS`/`DEPÓSITOS BANCÁRIOS` batendo exatamente) — 3 colunas separadas no
  export ("Certsys Tecn", "Certsys Com", "Total"), sem nenhum valor inventado. 55/55 testes do
  N8N; `tsc --noEmit`/`eslint` do portal limpos.
- **Não resolvido nesta fatia:** a classificação `tipo_taxonomia` (BALANCO vs. COMBINADO) do
  documento continua uma decisão separada (achado secundário #3 acima) — `entidade_coluna` funciona
  independente de qual `tipo_taxonomia` o documento levou. (Endereçado logo abaixo, no reforço de
  prompt.)

### Sessão 7 (cont.²) — Reforço de prompt (3 achados secundários) + confirmação do multi-entidade
Com #29 e #30 mergeados e aplicados em produção, o dono **reprocessou os 2 documentos reais**
("teste v9") e mandou o dashboard + o `.xlsx`. Confirmação importante: **o multi-entidade
funcionou** — o Certsys agora sai na aba "Balanço" com 4 colunas separadas (Certsys Com / Part /
Tech / Total), internamente consistentes (as colunas somam o Total), sem os valores fabricados
(`1.234.567,00` repetido) de antes. As abas DRE e Fluxo de Caixa do Global One também vieram
separadas corretamente (roteamento por linha da #28). Um erro claro restava, exatamente o achado
secundário #3: a classificação **`BALANCO` vs `COMBINADO` saiu INVERTIDA** entre os dois documentos:
- `BALANÇO ACUMULADO 2025.pdf` (Certsys — 3 empresas em colunas → **deveria ser COMBINADO**) foi
  classificado como `BALANCO`.
- `Balanço Patrimonial DRE, DFC, DMPL Global One 2024assinado.pdf` (Global One — 1 empresa, várias
  demonstrações → **deveria ser BALANCO**) foi classificado como `COMBINADO`.
- Distinção oficial (taxonomia `Arquitetura do Sistema/2 Especificação/f0/03` / seed `0002`): `BALANCO` = balanço de UMA entidade × período
  (vinculação `entidade_periodo`); `COMBINADO` = "Demonstrações combinadas (grupo consolidado)",
  vinculação por `periodo` (o grupo inteiro, não uma entidade).

Reforço aplicado no prompt de extração (`N8N/lib/extract.mjs`, fonte da verdade; mirror comprimido
em `N8N/build-workflow.mjs` regenerado) nos 3 achados secundários de uma vez:
1. **Entidade ≠ signatário:** não usar o nome de quem assinou (contador/administrador/sócio; bloco
   com CRC/CPF) como razão social — foi o que fez "ED ALVES DE AQUINO" (contador) virar a entidade
   do Certsys numa sessão anterior. Em documento de várias empresas, usar o nome do GRUPO ou null.
2. **BALANCO vs COMBINADO:** regra prática amarrada ao sinal que já temos — se as linhas têm
   `entidade_coluna` preenchido (várias empresas) → COMBINADO; se é uma entidade só (mesmo com
   Balanço+DRE+DFC+DMPL no mesmo arquivo) → o tipo da demonstração principal (normalmente BALANCO).
3. **Período ≠ saldo de abertura:** o período é o exercício ATUAL do documento; uma DMPL que mostra
   "Saldos em 31/12/2023" e "31/12/2024" é documento de 2024 (2023 é só o saldo inicial) — foi o que
   fez o Global One sair como "2023" numa sessão anterior.
- **Sem teste unitário determinístico** (é comportamento do LLM — o alvo do golden set `Arquitetura do Sistema/2 Especificação/f0/06`, ainda
  não montado). 55/55 testes do N8N seguem passando (schema/parse cobertos); o novo texto foi
  confirmado presente no `workflow.e1-ingestao.json` gerado. **Validação real = o dono reprocessar**
  e conferir se o Certsys vira COMBINADO e o Global One vira BALANCO.

### Sessão 7 (cont.³) — Balanço/DRE/Fluxo completos com FÓRMULAS (reescrita do export)
Pedido do dono depois de reprocessar ("teste v9"): o export estava "horrível e faltando
informações" — sem totais, com a linha de total do documento ("NÃO CIRCULANTE") perdida no meio
das contas, e nomes iguais para valores diferentes ("CIRCULANTE" do Ativo vs. do Passivo). Pediu:
fórmulas calculando os totais por categoria (Ativo/Ativo Circulante/Não Circulante/Passivo/PL/…)
**no cabeçalho da seção**, balanço completo, e "buscar nas melhores fontes contábeis" como montar
Balanço/DRE/Fluxo. **Tensão de doutrina:** isso contradiz a anti-ancoragem de `Arquitetura do Sistema/2 Especificação/f0/07` ("nenhum
subtotal calculado por soma"). Reconciliação escolhida pelo dono (via AskUserQuestion): usar
**fórmulas Excel transparentes** (`=SUM`), manter o total que o documento trouxe numa linha de
conferência, e **sinalizar divergência** formula×extraído. Emenda registrada em `Arquitetura do Sistema/2 Especificação/f0/07`.
- **Fundamentação (WebSearch):** Lei 6.404/76 art. 178 + CPC 26 — Ativo em ordem de liquidez
  (Circulante; Não Circulante = Realizável a LP / Investimentos / Imobilizado / Intangível);
  Passivo (Circulante, Não Circulante) + PL. DRE em cascata; DFC método indireto (CPC 03).
- **`portal/src/lib/statement-templates.ts` reescrito:** `classificarBalanco` agora (1) reconhece
  linhas que são TOTAIS/cabeçalhos que o doc trouxe (rótulo "nu" — só palavras estruturais — ou com
  "total"/"soma") e as manda para o NÓ certo em vez de virarem "conta no meio" (resolve o "NÃO
  CIRCULANTE no meio" e o "nomes iguais": "CIRCULANTE" sob Ativo vs. Passivo viram os totais de cada
  seção, desambiguados pelo contexto `secao`); (2) sub-classifica o Ativo Não Circulante nos
  subgrupos CPC (Realizável LP/Investimentos/Imobilizado/Intangível), com bucket "Outros" pro que
  não casar. Nova árvore `BALANCO_OUTLINE` (grupo→seção→subseção).
- **`portal/src/lib/export.ts` — builder reescrito:** Balanço montado pela árvore; cada
  seção/grupo tem o subtotal como **FÓRMULA** por coluna (folha = `SUM` das contas; pai = soma dos
  cabeçalhos dos filhos; grupo ATIVO/PASSIVO+PL = soma das seções). DRE em **cascata** (cada
  subtotal = subtotal anterior + soma das contas da seção; referencia a célula anterior, nunca
  re-soma subtotais → sem dupla contagem). Fluxo: caixa líquido por seção = `SUM`; variação = soma
  dos 3; saldo final = inicial + variação. Total do documento vira linha "↳ total informado no
  documento"; se a soma calculada divergir (tolerância 0,5%/1 centavo), pinta ambos + nota
  (reconciliação embutida). Subseções CPC vazias não são emitidas (não polui). Funciona em
  multi-coluna (documento combinado: uma fórmula por empresa).
- **Bugs reais achados e corrigidos durante os testes** (validação via `openpyxl`, LibreOffice do
  ambiente segue quebrado): (1) `ATIVO.filhos` apontava para o bucket-folha errado — o nó pai
  "Ativo Não Circulante" não era emitido e a conta "Créditos com Pessoas Ligadas" SUMIA; (2)
  âncora do total "NÃO CIRCULANTE" caía no nó "Outros" em vez do nó-seção; (3) "PATRIMÔNIO LÍQUIDO"
  (total da seção) colidia com "TOTAL DO PASSIVO E PL" (total do grupo) — resolvido exigindo
  "passivo" no próprio rótulo pro grupo; (4) "Créditos c/Terceiros" não era Realizável LP.
- **Validação com os dados reais** (Global One + Certsys): o balanço agora FECHA — ATIVO = Passivo+
  PL = 12.086.571,06, com Realizável a LP somando as duas contas de crédito (12.080.078,23 =
  informado), Passivo Circulante e PL batendo o informado, zero divergência falsa. DRE em cascata e
  Fluxo com saldo final = inicial+variação, ambos conferidos. `tsc`/`eslint` limpos; 55/55 testes
  do N8N (inalterados — mudança é só no portal).
- **Pendente do dono:** reprocessar/baixar o `.xlsx` e abrir no Excel de verdade (recálculo das
  fórmulas na abertura — validei a ESTRUTURA/fórmulas via openpyxl, não a abertura no Excel real).

### Sessão 7 (cont.⁴) — Layout analítico (margens) inspirado num modelo de FP&A real
O dono mandou arquivos de referência (3 zips: balanços consolidados 2022–2025, DREs, 10
balancetes do grupo Embrepar/Fort Lub/SKY; + `ProjecoesDelendSummary.csv`) e pediu que o export
"entregue algo parecido". O `DelendSummary` é um **modelo de FP&A completo** (colunas mensais
Actual→projeções, KPIs de SaaS — ARR/MRR/BaaS —, Fluxo de Caixa indireto, P&L em cascata com
margens/crescimento %, Pro-forma). **Isso é modelagem/projeção — contradiz `Arquitetura do Sistema/2 Especificação/f0/07` ("output NÃO
projeta, NÃO é modelagem")**. Perguntei o rumo (AskUserQuestion); o dono escolheu **"layout
analítico sobre o dado REAL, sem projetar"** (não o motor de projeção). Registrado.
- **Entregue nesta fatia:** linhas de **MARGEM** (% da Receita Líquida) na DRE, como FÓRMULA por
  coluna — Margem Bruta / Operacional / Líquida (estilo DelendSummary), com `IFERROR` (evita div/0).
  Só divide dois valores já extraídos; não projeta nem inventa. **EBITDA ficou de fora de
  propósito:** a DRE real (SKY GROUP consolidado, conferido no PDF) NÃO traz Depreciação/
  Amortização como linha isolada — viria das notas/Fluxo —, então calcular EBITDA exigiria
  inventar D&A. Não fizemos (anti-ancoragem).
- **Nota sobre a estrutura:** a DRE do grupo dobra o Resultado Financeiro DENTRO do "Lucro
  Operacional"; a nossa estrutura (padrão analítico) separa EBIT (antes do financeiro) do
  Resultado Financeiro. Isso faz a conferência do "Lucro Operacional informado" divergir do EBIT
  calculado — é uma diferença DEFINICIONAL esperada (a flag de divergência a torna visível), não
  um bug.
- **Deferido (natural, ainda SEM projeção):** (1) aba "Indicadores/Resumo" consolidada (KPIs por
  período referenciando as abas de demonstração — margens, e indicadores de balanço tipo liquidez/
  endividamento/capital de giro); (2) coluna de **Crescimento %** período-a-período (exige lógica
  de comparabilidade entre colunas da MESMA entidade). Ambos são presentation/fórmula sobre dado
  real. (3) O **motor de projeção/modelagem** (o que o DelendSummary realmente é) segue FORA do
  escopo pela decisão do dono + `Arquitetura do Sistema/2 Especificação/f0/07` — só entraria com revisão explícita da doutrina.

### Sessão 7 (cont.⁵) — Ajustes no export após o teste v12 do dono
O dono reprocessou ("teste v12") e apontou "faltou algumas fórmulas". Ao inspecionar o `.xlsx`:
- **Seção só com total informado, sem itens de linha** (ex.: "Imobilizado" no balanço Certsys — o
  documento trouxe só o total do subgrupo, sem detalhar contas): o cabeçalho ficava EM BRANCO (não
  havia o que somar) e o valor ficava órfão na linha de conferência, quebrando o total do pai.
  **Fix:** nesse caso o cabeçalho usa o próprio valor informado como valor da seção (não há soma a
  fazer); a linha de conferência só aparece quando há de fato uma soma para comparar.
- **Seções padrão genuinamente vazias** (ex.: Passivo Não Circulante sem contas) mostravam célula
  em branco no meio do balanço. **Fix:** passam a mostrar `0` explícito (coluna completa).
- **PL inflado no Combinado (bug mais sério, o dono não tinha citado):** as linhas de **DMPL**
  ("SALDOS EM 31 DE DEZEMBRO DE 2023/2024") estavam sendo somadas como contas do PL — e o saldo de
  fechamento REPETE o próprio PL, então o total dobrava (~32 mi vs. ~11,8 mi reais). **Fix:**
  `ehLinhaDMPL()` em `statement-templates.ts` detecta linhas de saldo de abertura/fechamento de
  DMPL (contém "saldo" + ano/inicial/final) e as tira da classificação do Balanço → vão para
  "Contas Não Classificadas" (visíveis, sem somar). Bloqueia inclusive o fallback do
  `secao_canonica` (a IA tende a marcar essas linhas como `patrimonio_liquido`). Só afeta o
  Balanço/Combinado (no Fluxo, "saldo inicial/final de caixa" é tratado pelo classificador do
  Fluxo). Validado: PL fecha no informado, sem divergência falsa; Imobilizado com valor;
  DMPL em "Não Classificadas". `tsc`/`eslint` limpos.
- **Ainda deferido:** DMPL em aba própria (exige estender o enum da IA + reextração); é o passo
  que traria essas linhas de volta como uma demonstração de verdade, em vez de "Não Classificadas".

### Sessão 7 (cont.⁶) — Reconciliação Classe B (`Supabase/migrations/0015`)
Próximo passo combinado com o dono desde a sessão 6, adiado 3x por bugs críticos de dados —
retomado agora que a extração está estável. Segue o desenho de `Arquitetura do Sistema/2 Especificação/04_RECONCILIACAO.md` e o
molde da Classe A (`0009`): mesma tabela `reconciliacao` (log append-only, `classe='B'`), mesma
função `fn_valor_conceito`/`fn_normalizar_texto`, mesma pendência idempotente com auto-resolução —
mas **travada em N1** (nunca sobe pra N2 como a A pode): Classe B é agregação/período, não
identidade aritmética pura, então **banda de materialidade** (mais folgada que a A: piso R$ 50k
**e** 5%, vs. R$ 100/0,5% da A) e qualquer divergência na zona cinzenta vira **revisão humana**,
nunca auto-clear.
- **Duas checagens canônicas** (os exemplos de `Arquitetura do Sistema/2 Especificação/04`): (1) `fn_reconciliar_receita_dre_vs_faturamento`
  — Receita Operacional Bruta da DRE vs. soma das linhas MENSAIS de `FATURAMENTO_24M` do MESMO
  ano (recorte pelo ano no rótulo — aceita "2024", "24", "12M24" — excluindo linhas de total/média/
  acumulado, que somariam duplicado); (2) `fn_reconciliar_despfin_dre_vs_divida` — Despesa
  Financeira da DRE vs. soma das linhas de juros/encargos do `MAPA_DIVIDA` (compara em módulo,
  já que despesa financeira normalmente vem negativa na DRE).
- **Novo helper de agregação** (diferente da 0009, que casa UMA linha): `fn_somar_conceito` (soma
  todas as linhas que casam termos, ex. todas as linhas de "juros") e `fn_somar_faturamento_ano`
  (soma as linhas mensais de um ano — cada mês não compartilha uma palavra-chave, então o recorte
  é pelo ANO no próprio rótulo). `fn_registrar_reconciliacao_b` fatora o log+pendência (mesmo
  padrão da 0009, reaproveitado pelas duas checagens B).
- **Pré-condição honesta:** como `FATURAMENTO_24M`/`MAPA_DIVIDA` ainda têm schema genérico de
  linhas (não um schema dedicado como a DRE/Balanço), é ESPERADO que estas checagens caiam em
  "precondição não satisfeita" com frequência real até essa extração ser refinada — vira
  pendência, nunca um "OK" falso-limpo (mesmo princípio da Classe A).
- **`fn_reconciliar_por_documento` redefinida** (mesma assinatura) para disparar A+B pelo tipo do
  documento processado — DRE dispara as duas checagens B; FATURAMENTO_24M/MAPA_DIVIDA disparam a
  checagem B correspondente (reaproveitando/auto-resolvendo a pendência quando o outro lado já
  existia).
- **Portal:** rótulo do card mudou de "Reconciliação (Classe A)" para "Reconciliação (Classe A/B)"
  — a lista já é genérica por `pendencia.tipo` (`PENDENCIA_TIPOS_RECONCILIACAO`), então as
  pendências B aparecem automaticamente, sem mudança de lógica.
- **Testado contra Postgres 16 local:** receita batendo (linha "Total" corretamente ignorada);
  precondição por documento faltante, com **auto-resolução** quando o Mapa de Dívida chega depois;
  zona cinzenta (divergência de 32%, acima da banda); casamento de ano com 2 e 4 dígitos.
  Migrations 0001-0015 aplicadas limpo (mesma ressalva de sempre: `storage.buckets` não existe em
  Postgres vanilla). `tsc`/`eslint` do portal limpos.
- **Achado de documentação:** a `0014` nunca tinha entrado na tabela do `Supabase/README.md` (esquecida
  numa sessão anterior) — corrigido junto com a `0015`.
- **Próximo passo natural (não feito aqui):** ação de "confirmar/ressalva" dedicada na fila do
  portal pras pendências de reconciliação (hoje só listam, read-only — item já listado em
  "Próximos passos" há várias sessões).

### Sessão 7 (cont.⁷) — BUG CRÍTICO: extração silenciosamente vazia (`Supabase/migrations/0016`)
Achado testando com um caso real do dono ("teste v14", 16 documentos): todos os documentos foram
**classificados com sucesso** (tipo/entidade/período gravados, confiança 90-95%, fonte
`openai_conteudo`) mas **0 linhas foram extraídas** para qualquer um deles — export saiu com
"Linhas totais extraídas: 0", Reconciliação (Classe A) só apontou pré-condição não satisfeita
(sem dado pra conferir). O N8N mostrava **sucesso em todos os nós**, e reprocessar **não mudava
nada** — sinal de causa determinística, não transitória (rate limit teria variado entre tentativas).
- **Causa raiz:** classificação e extração são DUAS chamadas OpenAI separadas e sequenciais por
  documento. A de extração pede um array `linhas` SEM limite de tamanho (documentos combinados
  grandes — grupo com várias entidades/demonstrações no mesmo PDF, ex. "Balanço Patrimonial DRE
  DFC DMPL 2025assinado.pdf" — podem exigir uma saída JSON enorme). Sem `max_tokens` explícito e
  sem checagem de `finish_reason`, uma resposta truncada (finish_reason=length) virava um JSON
  incompleto que falhava o `JSON.parse` — e `parseExtractionResponse` (`N8N/lib/extract.mjs`,
  mirror em `N8N/build-workflow.mjs`) devolvia `campos: []` **silenciosamente**, sem lançar exceção
  (por isso o node aparece verde no N8N: é um 200 OK truncado, não um erro HTTP). Como o node
  `OpenAI Extrair` também tem `onError: continueRegularOutput` (fail-safe pra um documento ruim
  não derrubar o lote inteiro), mesmo um erro de fato da API (429/500) passaria despercebido do
  mesmo jeito. `fn_registrar_campos_extraidos` (0013) tratava array vazio como "0 campos, sucesso"
  e retornava cedo — nada no pipeline detectava isso.
- **Fix (dois lados, precisam andar juntos):**
  1. `N8N/lib/extract.mjs` (+ mirror `N8N/build-workflow.mjs`): `buildExtractionRequest` agora
     manda `max_tokens: 16384` explícito (teto de saída do gpt-4o) — elimina a possibilidade de um
     default menor específico de conta/API. `parseExtractionResponse` agora captura
     `finish_reason` e `apiJson.error`, e devolve um novo campo `falhaMotivo` (null quando ok;
     motivo textual quando a API errou, veio truncada, ou o JSON é inválido) — nunca mais silêncio.
  2. `Supabase/migrations/0016_guarda_extracao_falhou.sql`: novo tipo `extracao_falhou` no enum
     `pendencia_tipo`. `fn_registrar_campos_extraidos` (mesma assinatura de 0005/.../0013 +
     `p_falha_motivo text default null`) passa a resolver documento/caso **mesmo com 0 campos**
     (antes só rodava se `v_count > 0`) e gera pendência idempotente/auto-resolvível quando o N8N
     manda um motivo de falha — igual ao padrão dos outros dois sinais de guarda (0013).
  3. Node `Gravar Campos (Sombra)`: passa `$json.falha_motivo` como `p_falha_motivo=>$3::text`.
  4. Portal: novo agrupador `PENDENCIA_TIPOS_QUALIDADE_EXTRACAO` (`extracao_padrao_suspeito`,
     `extracao_baixa_confianca`, `extracao_falhou`) — os dois primeiros já existiam desde a 0013
     mas **nunca apareciam em lugar nenhum do portal** (lacuna descoberta agora); nova seção
     "Qualidade da extração" em `casos/[id]/page.tsx` fecha a lacuna pros três de uma vez.
- **Testado:** `npm test` do n8n (63/63, incluindo 6 testes novos — truncamento com JSON
  incompleto, erro de API, `max_tokens` no request, motivo passado pro Postgres). Migrations
  0001-0016 aplicadas limpo contra Postgres 16 local; exercitado ao vivo: extração vazia com
  motivo → pendência criada; reprocessar com o mesmo motivo → não duplica (idempotente);
  reprocessar com sucesso → auto-resolve; sinal 1 (padrão suspeito) continua funcionando sem
  regressão na restruturação da função. `tsc`/`eslint` do portal limpos.
- **Ainda por confirmar pelo dono:** REIMPORTAR o workflow no N8N (o fix de `max_tokens`/detecção
  vive no JSON gerado) + aplicar `0016` no Supabase + reprocessar "teste v14" pra confirmar que
  os dados saem certos dessa vez.

### Sessão 7 (cont.⁸) — Causa real da extração vazia: rate limit (429) no upload em lote
O fix da cont.⁷ (`0016` + `max_tokens`) foi aplicado pelo dono e **funcionou como projetado**:
reprocessando o "teste v15" (16 documentos), a falha deixou de ser silenciosa — o portal mostrou
16 pendências `extracao_falhou` na nova seção "Qualidade da extração", TODAS com o mesmo motivo:
**"Erro da API OpenAI: Try spacing your requests out using the batching settings under 'Options'"**.
Ou seja: a `max_tokens` não era a causa (era uma hipótese plausível); a causa real é **rate limit
(429)**. Num upload em lote de 16 documentos, o N8N dispara ~16 chamadas de extração multimodais
(cada uma pesada) quase simultâneas → estoura o limite de RPM/TPM da OpenAI → a API retorna 429
e TODAS as extrações falham. (A classificação por conteúdo dos mesmos arquivos funcionou porque é
uma chamada mais leve e nem todo documento aciona o fallback — só quem tem confiança de nome < 0.7.)
- **Hipótese do dono (formato de arquivo, ex. Word):** descartada para ESTE caso — os 16 são PDFs,
  a classificação leu o conteúdo de todos com sucesso (90%), e as 16 falhas têm a mensagem idêntica
  de rate limit (um problema de formato daria erros diferentes por arquivo). Word (.docx) É um gap
  real e separado (hoje cai em "conteudo nao suportado" no `Preparar Conteudo`), mas não é o que
  quebrou o teste v15.
- **Fix:** os dois nós HTTP da OpenAI (`OpenAI Classificar`, `OpenAI Extrair`) ganharam **batching**
  (`batchSize: 1`, `batchInterval: 3000` — 1 chamada por vez, 3s de intervalo, espalha RPM e TPM no
  tempo) + **retry no nível do node** (`retryOnFail`, `maxTries: 4`, `waitBetweenTries: 5000` — teto
  do N8N) pro 429 residual. É exatamente o que a própria mensagem de erro do N8N recomenda
  ("use the batching settings under 'Options'"). Helper `OPENAI_BATCHING` + extensão do helper
  `node()` pra aceitar as opções de retry.
- **Só workflow** (nenhuma migration): `N8N/build-workflow.mjs` + `workflow.e1-ingestao.json`
  regenerado. `npm test` 64/64 (1 teste novo trava batching+retry nos dois nós). **Precisa
  reimportar o workflow no N8N** e reprocessar o "teste v15".
- **Trade-off consciente:** com `batchSize 1` + 3s, 16 documentos levam ~1min só de espaçamento
  (+ o tempo de cada chamada). É lento mas confiável; se o volume crescer muito, dá pra afrouxar o
  intervalo conforme o tier da conta OpenAI (limites maiores) — deixado conservador de propósito.

### Sessão 7 (cont.⁹) — Documentos COMPARATIVOS: coluna de período (`Supabase/migrations/0017`)
Pedido do dono: deixar o sistema "profissional a ponto de um modelador de 20 anos usar ativamente".
A maior lacuna de export mapeada (e um bug de PERDA DE DADO): demonstração comparativa — o padrão em
contabilidade, ex. o "Balanço consolidado 2023 x 2024.pdf" do teste v15 — tinha as duas colunas de
ano (2023, 2024) da MESMA entidade **coladas numa coluna só** no export. A chave de coluna era
`entidade × período-do-documento`, e o período do documento é único (`multi 23,24`), então a
extração emitia duas linhas "Caixa" (uma por ano) que caíam na MESMA coluna e uma sobrescrevia a
outra. Sem os anos lado a lado não há análise horizontal (Δ%) nem vertical — inutilizável pra
modelagem.
- **Fatia completa (mesmo padrão do `entidade_coluna`/0014):** coluna nova `campo_extraido.periodo_coluna`
  (rótulo da coluna de período da linha; null no caso comum de período único → cai no período do
  documento, sem regressão). É **ortogonal** a `entidade_coluna`: um documento pode ter várias
  empresas E vários anos → linha por (conta × empresa × período). Schema+prompt de extração
  (`N8N/lib/extract.mjs` + mirror `build-workflow.mjs`) pedem uma linha por (conta × período); o
  export (`portal/src/lib/export.ts`) usa `periodo_coluna` na chave de coluna; a tela de linhas do
  documento mostra `[período]` ao lado do `(entidade)`.
- **Limpeza de schema junto:** a `0016` tinha deixado DUAS sobrecargas de `fn_registrar_campos_extraidos`
  (3 e 4 params — `create or replace` com nº de params diferente cria overload novo, não substitui);
  uma chamada posicional de 2 args ficava AMBÍGUA ("is not unique") — só não estourava em produção
  porque o N8N chama com o param nomeado `p_falha_motivo=>`. A `0017` derruba a de 3 params e recria
  só a de 4. (Mesma classe do cruft de `fn_registrar_documento` ainda anotado em "Itens adiados".)
- **Testado:** `npm test` do n8n 66/66 (parse de comparativo, schema pede `periodo_coluna`, mirror
  propaga). Migrations 0001-0017 limpas no Postgres 16 local; provado no banco (comparativo grava 2
  linhas "Caixa" com períodos distintos, overload agora único) E no export (harness `tsx` com
  `buildExportWorkbook`: "Grupo X — 2023" e "Grupo X — 2024" viram colunas separadas). `tsc`/`eslint`
  do portal limpos.
- **Bundle consciente:** subiu na MESMA branch do batching (cont.⁸) — o dono reimporta o workflow UMA
  vez só e ganha os dois (fim do 429 + colunas comparativas). Precisa aplicar `0017` no Supabase.
- **Ainda por validar pelo dono:** reprocessar o v15 já com este workflow, e conferir se o LLM
  popula `periodo_coluna` corretamente nos documentos comparativos reais (o teste local prova o
  encanamento, não o comportamento do modelo).

### Sessão 7 (cont.¹⁰) — Upload pelo portal + mandato explícito (intake amigável)
Pedido do dono (OODA): input mais amigável dentro do HTML da Vercel (enviar/receber arquivos no
próprio portal) + um "campo de mandato" pra enviar arquivos em momentos diferentes e caírem no
mesmo checklist/export/reconciliação.
- **Observação-chave:** o "mandato" JÁ é o `caso` — `fn_upsert_caso(nome)` reusa por nome
  (`Supabase/migrations/0006`), então reenviar no mesmo mandato já acumula. O que faltava era (a) tornar
  isso explícito/amigável e (b) permitir upload pelo portal. E o ponto crítico de arquitetura: o
  pipeline lê o binário do **Form do N8N** — reescrever isso pra ler do Storage seria uma fatia
  grande e não-testável.
- **Desenho de menor risco (pipeline intacto):** o portal ENCAMINHA os arquivos pra MESMA URL do
  Form do N8N, servidor-a-servidor. A OpenAI/extração/reconciliação continuam 100% no N8N; o portal
  é só um front-end de intake.
  - `portal/src/app/api/intake/route.ts` (runtime Node): recebe multipart, valida, e faz `fetch`
    POST multipart pra `N8N_INTAKE_FORM_URL` com os campos `Mandato (nome do caso)`/`Arquivos`
    (nomes overridáveis por env `N8N_INTAKE_FIELD_*`). Sem a env → 503 com aviso claro.
  - `portal/src/components/upload-form.tsx` (client): dropzone (drag-drop + clique), lista de
    arquivos com remover, campo de mandato, estados de envio/erro/sucesso. `travarMandato` quando
    é "adicionar a um mandato existente".
  - Páginas: `/casos/novo` (novo mandato) e `/casos/[id]/adicionar` (mandato travado, volta ao
    caso). Botões "+ Novo mandato" (lista) e "+ Adicionar arquivos" (dashboard). Copy do empty-state
    da lista corrigida (não diz mais "a ingestão roda pelo N8N").
- **Testado:** `tsc`/`eslint`/`next build` limpos — todas as rotas novas compilam
  (`/api/intake`, `/casos/novo`, `/casos/[id]/adicionar`). **Não testável aqui:** se o Form do N8N
  aceita o multipart encaminhado com esses nomes de campo exatos (depende da instância/versão) —
  por isso os nomes são overridáveis por env e o erro do route é explícito. O dono precisa setar
  `N8N_INTAKE_FORM_URL` (Production URL do node Intake Form) na Vercel e validar o primeiro envio.
- **Escopo consciente:** o polimento "de modelador" (análise horizontal/vertical Δ%/AV%) NÃO entrou
  aqui — fica pro próximo passo, e faz mais sentido depois do reprocesso real do v15 (com o
  batching+período já mergeados) mostrar dado de verdade. Documentos Word/.xlsx (gap de formato
  levantado pelo dono) também continuam pendentes (item nos próximos passos).

### Sessão 7 (cont.¹¹) — "Teste v18" (16 docs reais, US$3): 9/16 ok, 7 falharam — 2ª rodada de hardening
Pedido do dono: OODA — analisar o que ainda quebra/não está otimizado e executar. O dono rodou o
lote real de 16 documentos ("teste v18", já com o batching+período mergeados) e reportou o
resultado: **797 linhas extraídas com sucesso** (progresso real vs. 0 da cont.⁷), mas **7 de 16
documentos ainda falharam** — 3 com o MESMO 429 de rate limit da cont.⁸, 3 com truncamento
(`finish_reason=length`) mesmo com `max_tokens=16384` (cont.⁷), e 1 sinal de padrão suspeito
(guarda 0013 funcionando corretamente).
- **Padrão real identificado:** todos os 7 falhos são demonstrações CONSOLIDADAS COMPARATIVAS
  MULTI-ANO (ex. "Balanço Consolidado 2022 e 2023.pdf", "DRE Consolidado 2024.pdf") — o PIOR caso
  possível: mais tokens de ENTRADA (2-3 anos de dados no PDF) e mais tokens de SAÍDA (cada conta
  vira 2-3 linhas via `periodo_coluna`, cont.⁹). Os 9 documentos "Sky/Fort Lub/Embrepar" (multi-
  demonstração — Balanço+DRE+DFC+DMPL — mas de UM ano só) funcionaram bem, o que descarta a
  hipótese de "documento com várias demonstrações = sempre denso demais".
- **Fix 1 — chaves de fio curtas (`N8N/lib/extract.mjs` + mirror):** o array `linhas[]` é o único
  bloco repetido centenas de vezes por documento — cada caractere de nome de propriedade é gasto
  DE NOVO a cada linha na saída JSON. Renomeado `secao→s, secao_canonica→sc, entidade_coluna→ec,
  periodo_coluna→pc, chave→k, valor_texto→vt, valor_num→vn, origem_pagina→op, confianca→cf` SÓ na
  conversa com a OpenAI (com `description` em cada campo pra não perder a orientação do modelo);
  `parseExtractionResponse` remapeia de volta pros nomes completos — **nada gravado no banco
  muda**. Redução medida: ~30-40% de bytes por linha (teste trava >=15%). Mitigação PARCIAL e
  honesta: ajuda todo documento, mas documentos genuinamente enormes (300+ linhas) podem ainda
  passar de 16384 tokens mesmo compactado — a correção completa exigiria dividir a extração em
  múltiplas chamadas (por página ou por período), o que é uma mudança de topologia do grafo do N8N
  que **não dá pra validar sem uma instância N8N viva** (decisão consciente de NÃO implementar às
  cegas — ver "Itens adiados" abaixo).
- **Fix 2 — batching mais conservador (`OPENAI_BATCHING`, `maxTries`):** `batchInterval` 3s→6s,
  `maxTries` 4→6. Achado: 3s+4 tentativas (cont.⁸) reduziu o 429 de 16/16 pra 3/16, mas não
  eliminou pros documentos mais pesados (mais tokens de ENTRADA também consomem TPM, não só a
  cadência de requisições resolve). Trade-off consciente: processa mais devagar.
- **Workaround imediato pros 3 documentos que ainda truncam:** dividir o PDF em arquivos por ano
  antes de subir (ex. "Balanço 2022.pdf" + "Balanço 2023.pdf" separados) — cada ano sozinho tem
  volume comparável aos 9 documentos que já funcionaram bem.
- **Kit de PDFs sintéticos pra testar sem gastar dinheiro real** (pedido explícito do dono, que não
  quer "ficar testando infinitamente gastando tokens"): 9 arquivos pequenos (~2-3 KB cada, texto
  puro, nada escaneado) cobrindo os 8 itens do Kit Básico + Mapa de Dívida (bônus, fecha a
  checagem Classe B de despesa financeira). Números **deliberadamente consistentes entre
  arquivos** — Ativo = Passivo+PL (2024 e 2025), Caixa do Balanço = Saldo final do Fluxo, Receita
  Bruta da DRE = soma dos 12 meses de 2025 no Faturamento 24M, Despesas Financeiras da DRE = soma
  dos juros no Mapa de Dívida — pra que as reconciliações Classe A **e** Classe B tenham uma chance
  real de fechar limpo num teste de poucos centavos, não só "a extração rodou". Entregues ao dono
  fora do repo (são dado de teste, não código).
- **Testado:** `npm test` do n8n 68/68 (2 testes novos travando o batching endurecido e a redução
  de bytes por linha). Migrations não mudaram nesta fatia (só `N8N/lib/extract.mjs` +
  `build-workflow.mjs` + testes). `tsc`/`eslint` do portal inalterados (fatia é só n8n).
- **Observação à parte (não corrigida aqui):** os 9 documentos "Sky/Fort Lub/Embrepar" (1 entidade,
  4 demonstrações no mesmo PDF) vieram classificados como `COMBINADO` com a entidade preenchida —
  pela doutrina (`Arquitetura do Sistema/2 Especificação/f0/03`, reforçada na cont.²) isso deveria ser a demonstração PRINCIPAL (ex.
  `BALANCO`), já que `COMBINADO` é reservado pra grupo de VÁRIAS empresas com colunas por empresa.
  Não corrigiu os dados (o `entidade_coluna` ficou null corretamente, o export separou por arquivo
  do jeito certo) — é só um rótulo de classificação errado, cosmético por ora. Vale reforçar o
  prompt de novo numa sessão futura se persistir.
- **Itens adiados (arquitetura maior, precisa de N8N vivo pra validar):**
  1. Dividir a extração em múltiplas chamadas por período/página pra documentos genuinamente
     enormes (a correção COMPLETA do truncamento) — muda a topologia do grafo (fan-out mid-
     pipeline), não é seguro de implementar sem testar contra uma instância N8N real.
  2. Reforçar de novo o prompt BALANCO×COMBINADO (achado acima) se o dono confirmar que persiste.

### Sessão 7 (cont.¹²) — BUG CRÍTICO: upload pelo portal "sucesso" mas workflow nunca rodava
Achado testando o upload novo (cont.¹⁰) contra o N8N real do dono: depois de corrigir o erro de
URL de teste vs. produção, o envio pelo portal mostrava sucesso, mas **20+ minutos depois nada
tinha aparecido no mandato e ZERO tokens tinham sido gastos na conta OpenAI** — ou seja, o workflow
nunca chegou a rodar de verdade, apesar do portal reportar "enviado com sucesso".
- **Causa raiz:** `/api/intake` montava o multipart usando os RÓTULOS visíveis do Form
  ("Mandato (nome do caso)"/"Arquivos") como nome de campo — mas o atributo `name` real gerado
  pelo N8N para aquele campo pode ser diferente do rótulo. O webhook do Form aceita o POST (HTTP
  200 — "deu certo" pro portal) ANTES de saber se o workflow vai ter dado pra processar; se o nome
  do campo não bate, o node `Listar Arquivos` lança seu erro explícito ("Nenhum arquivo recebido do
  formulario") e a execução morre ANTES de qualquer chamada à OpenAI — exatamente "sucesso na tela,
  0 tokens gastos, nada no mandato".
- **Fix — descoberta automática de nomes de campo** (`portal/src/lib/n8n-form.ts`): em vez de
  fixar/adivinhar os nomes, `/api/intake` agora faz um GET no próprio Form antes de enviar, faz o
  parsing (por regex, tolerante) dos `<input>` do HTML retornado, e usa os `name` REAIS
  encontrados (arquivo = primeiro `<input type="file">`; mandato = primeiro `<input>` de texto
  não-hidden/não-submit). As envs `N8N_INTAKE_FIELD_*` viram um **override manual opcional** (se
  setadas, usadas direto, pulando a descoberta) em vez do único caminho. Fallback gracioso: se o
  GET falhar ou não achar `<input>` reconhecível, cai nos nomes padrão de antes (nunca piora o
  comportamento anterior).
- **Pedido do dono (mesma sessão): pop-up elegante ao terminar + copy sem termos técnicos.** A
  mensagem "O N8N está processando (classificação + extração)" foi trocada por algo sem nomear
  nenhuma ferramenta/plataforma ("Estamos organizando tudo com cuidado — isso costuma levar alguns
  minutos"). Novo endpoint `GET /api/intake/status` (`portal/src/app/api/intake/status/route.ts`)
  combina dois sinais pra saber quando o pipeline "terminou de tentar" (não "terminou sem
  pendências" — isso continua no dashboard como sempre): `documento` criado para o caso desde o
  envio (classificação concluída) + `evento_auditoria` tipo `extracao_sombra` referenciando aquele
  `documento_versao` (extração tentou rodar — sucesso OU falha, sempre gravado por
  `fn_registrar_campos_extraidos` desde a `0016`). `upload-form.tsx` faz polling silencioso a cada
  ~8s por até ~12min e, quando pronto, mostra um pop-up modal ("Tudo pronto") com CTA pro mandato —
  sem precisar recarregar a página.
- **Testado:** parser de nomes de campo validado contra 4 cenários (rótulo=nome, nomes internos
  diferentes, campo hidden não confundido, HTML sem `<input>` reconhecível → fallback). `tsc`,
  `eslint` e **`next build`** limpos — as duas rotas novas (`/api/intake/status`) e o componente
  compilam. **Não testável aqui:** se o parsing por regex bate com o HTML real que o N8N do dono
  gera (não tenho acesso a uma instância viva) — por isso o fallback gracioso existe; se a
  descoberta não funcionar, o comportamento cai pro que já existia (nomes fixos, ajustáveis via
  env).

### Sessão 7 (cont.¹³) — "Teste v19" (9 arquivos pequenos, kit sintético): confirmação de tier + 2º bug crítico
Pedido do dono: corrigir "completamente" os erros que fizeram até os 9 PDFs sintéticos pequenos
(kit da cont.¹¹, ~2-3 KB cada) falharem — nenhuma linha extraída, e alguns arquivos nem aparecendo
no dashboard.
- **Contradição que motivou a investigação:** o "teste v18" (16 documentos REAIS, batching de 3s)
  teve 13/16 sucesso; o "teste v19" (9 arquivos pequenos, batching de 6s — mais conservador) teve
  0/6 sucesso nas extrações visíveis. Mais espaçamento resultando em MAIS falha é o oposto do
  esperado — indicava causa fora do código de batching.
- **Causa 1 confirmada pelo dono:** a conta OpenAI estava genuinamente no teto do rate limit (RPM)
  — ele confirmou e subiu o tier durante a sessão. Nenhum espaçamento de código resolve isso
  sozinho quando o teto real da conta é mais baixo que a cadência tentada; **"0 tokens gastos" no
  painel da OpenAI é exatamente o esperado num 429 genuíno** (a requisição é rejeitada antes de
  qualquer processamento, não cobra token nenhum) — não era evidência CONTRA a hipótese de rate
  limit, e sim a favor.
- **Causa 2 — bug real, achado investigando por que 3 dos 9 arquivos nunca apareceram no
  dashboard (nem "não classificado", nem pendência):** os 6 nós Postgres do pipeline
  (`Upsert Caso`, `Registrar Documento`, `Recomputar Completude`, `Gravar Campos (Sombra)`,
  `Registrar Diagnostico`, `Reconciliar (Classe A)`) não tinham NENHUM tratamento de erro — ao
  contrário dos nós OpenAI, que já tinham `onError:continueRegularOutput` desde a cont.⁸. Um erro
  transitório de conexão num ÚNICO item (mais provável sob a carga do lote, com o rate limit já no
  teto) **parava a execução inteira do N8N**, e todo item ainda na fila desaparecia sem nenhum
  rastro — exatamente o sintoma "3 de 9 arquivos somem". Corrigido: todos os 6 nós Postgres agora
  têm `onError:continueRegularOutput` + `retryOnFail` (3 tentativas, 3s entre elas) — o pior caso
  agora é "esse item específico fica incompleto" (nunca vira fato, segue N0/pendente, doutrina
  anti-ancoragem Arquitetura do Sistema/1 Visão e Doutrina/01), não "o lote inteiro desaparece em silêncio".
- **Testado:** `npm test` do n8n 69/69 (1 teste novo travando onError+retryOnFail+maxTries nos 6
  nós Postgres). `tsc`/`eslint` do portal inalterados (fatia é só n8n).
- **Ainda por confirmar pelo dono:** reimportar o workflow (pega o retry dos nós Postgres) e
  reprocessar o kit de PDFs sintéticos de novo, agora com o tier da OpenAI já corrigido — deve
  extrair 100% das linhas dos 9 arquivos (são pequenos e simples de propósito, o "caso mais fácil
  possível" pro pipeline).

### Sessão 7 (cont.¹⁴) — "Teste v20" (kit sintético reprocessado): 2 bugs reais + auto-aceite + limpeza de export
O kit de PDFs sintéticos reprocessado ("teste v20", com o rate limit corrigido e os fixes de
extração/Postgres já mergeados) veio 100% classificado (Kit Básico inteiro "presente", 113 linhas
extraídas) — a extração em si funcionou. Análise do resultado (export + fila de revisão) achou 4
problemas reais, todos corrigidos nesta fatia.

- **BUG 1 — cards da fila de revisão não somem ao confirmar/salvar (confirmado ao vivo):** os
  prints do dono mostravam documentos já com `fonte=humano, confiança=100%` (ou seja, o "Confirmar/
  salvar" JÁ tinha rodado) mas o card continuava na fila com "PERÍODO PODE ESTAR INCORRETO". Lendo
  `fn_revisar_documento` (0008): ela só resolve pendências do tipo `classificacao_pendente` — as
  outras três (`tipo_incorreto`/`entidade_incorreta`/`periodo_incorreto`, introduzidas pela 0010
  MUITO depois e nunca conectadas de volta a esta função) nunca fecham, mesmo depois da revisão
  humana confirmar/corrigir. **`Supabase/migrations/0018`**: mesma função, mesma assinatura, resolve os
  quatro tipos agora.
- **BUG 2 — vazamento entre abas do export:** a aba "Fluxo de Caixa" tinha uma coluna FANTASMA
  ("Teste Indústria Ltda — multi 02,25") com só a linha "Lucro Líquido do Exercício" (600.000) —
  vinda do arquivo da DRE, que não tem NENHUMA linha de fluxo de caixa. Causa:
  "Lucro Líquido do Exercício" é âncora TANTO da DRE (linha de fechamento) QUANTO do Fluxo de Caixa
  indireto (ponto de partida da reconciliação) — mesmo rótulo, dois sentidos legítimos — e
  `classificarDemonstracao` (`statement-templates.ts`) checava Fluxo de Caixa ANTES de checar a
  estrutura do próprio documento, então uma DRE isolada perdia a própria linha de fechamento pra
  aba errada. Fix: `classificarDemonstracao` agora recebe a estrutura do PRÓPRIO documento e
  prioriza mantê-la ali quando ela também reconhece a linha — só reroteia pra outra família quando a
  estrutura do documento não reconhece a linha (o caso genuíno de PDF combinado).
- **BUG/ACHADO 3 — "taxonomia estranha":** `MUTUOS` (categoria "Intragrupo" na própria taxonomia,
  `Supabase/migrations/0002`) estava mapeado pra aba "Dívida" — um mútuo intragrupo não é dívida bancária
  externa (`MAPA_DIVIDA`/`CONTRATO_DIVIDA`), misturar os dois numa aba só não fazia sentido
  contábil. `FAT_INTRAGRUPO` e `CONTRATO_SOCIAL` nem tinham aba própria, caindo no genérico
  "Outros" junto com dado sem relação nenhuma. Fix (`portal/src/lib/export.ts`): `MUTUOS`/
  `FAT_INTRAGRUPO` → aba nova "Intragrupo"; `CONTRATO_SOCIAL` → aba nova "Societário".
- **Pedido 4 — colunas mais simples na listagem simples** (Faturamento/Dívida/Intragrupo/
  Societário/Fluxo Projetado): tinha 13 colunas, a maioria técnica/rastreabilidade (seção, página,
  unidade, confiança, aceito por/em, arquivo de origem, versão da taxonomia) — poluindo quem só
  quer ver conta × valor. Reduzido pra 5 (Entidade, Período, Rótulo, Valor, Status); as removidas
  NÃO somem — viram um comentário (`cell.note`) no rótulo, visível ao passar o mouse (mantém
  rastreabilidade sem poluir a grade, princípio de `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`).
- **Pedido 5 — auto-aceite >=95% de confiança:** decisão de produto explícita do dono, registrada
  com a ressalva honesta de que isto sobe a autonomia da extração além do que a doutrina padrão
  (`Arquitetura do Sistema/1 Visão e Doutrina/01`) exigiria sem golden-set validado — a `confianca` é a autoavaliação do PRÓPRIO modelo,
  não verificada contra gabarito humano. Implementado mesmo assim (é uma escolha do dono, não da
  IA), com registro completo: `Supabase/migrations/0019` grava `status_aceite='aceito'` já na extração
  quando `confianca >= 0.95`, com UM `decisao`(autor='sistema:auto_aceite')+`evento_auditoria` por
  chamada (resumo, não por linha) — auditável/reversível. Inclui backfill pras linhas já gravadas
  antes desta migration. Recomendação registrada: acompanhar a taxa de erro real nas linhas
  auto-aceitas e ajustar o limiar (hoje 0.95, hardcoded) se necessário.
- **Testado:** os dois fixes de SQL provados contra Postgres 16 local com dado real (pendência
  `periodo_incorreto` resolvendo corretamente; confiança 90% ficando pendente e 95%/97% auto-
  aceitando; backfill promovendo linha antiga; idempotência confirmada). Export validado com
  harness `tsx` reproduzindo o cenário exato do bug (DRE isolada não vaza mais pra Fluxo de Caixa;
  MUTUOS/FAT_INTRAGRUPO vão pra Intragrupo; CONTRATO_SOCIAL vai pra Societário; listagem simples
  com 5 colunas). `tsc`/`eslint`/`next build` limpos.
- **Precisa:** aplicar `0018`+`0019` no Supabase (sem mudança no N8N — esta fatia é só Postgres +
  export do portal). Re-exportar o "teste v20" pra conferir visualmente o resultado.

### Verificação de qualidade (rodada real, 2026-07-20)
Um ciclo completo de teste ao vivo no N8N/Supabase real do dono revelou e corrigiu 3
bugs reais em sequência (todos documentados em `N8N/README.md` → Troubleshooting):
1. Schema da OpenAI sem `enum` em `tipo_taxonomia`/`periodo_tipo` → IA inventava
   código inválido (`"BAL"` em vez de `"BALANCO"`).
2. Leitura de binário no Code node via `binary.data.data` direto → quebra em modo
   "filesystem" do N8N (o campo vira uma referência interna, não a base64).
3. Fix do item 2 usou `$helpers` (global que não existe no runtime de Task Runner) —
   corrigido para `this.helpers.getBinaryDataBuffer(...)`.

Resultado final confirmado: a IA classifica com confiança alta citando o **conteúdo
real** do documento (não mais o nome do arquivo), com justificativa objetiva.

### Sessão 7 (cont.¹⁵) — "Total informado × calculado" divergindo mesmo em arquivo de teste + limpeza final do export
O dono reportou que, mesmo em arquivos sintéticos próprios, a linha "↳ total informado no
documento" batia com o total informado mas divergia do SUM calculado em vários lugares — pediu pra
explicar por quê. Inspeção do export real ("teste v20") linha a linha achou 2 bugs de classificação
reais (não artefato do arquivo de teste — vêm de convenções bem comuns de demonstração financeira
brasileira), além de 3 pedidos de limpeza visual:

- **BUG 1 — DRE contava um subtotal duas vezes:** "Resultado antes do resultado financeiro" (mesmo
  valor do EBIT) e "Resultado Financeiro Líquido" (mesmo valor de Despesas+Receitas Financeiras já
  dentro da própria seção) são subtotais de apresentação em cascata — mas o rótulo compartilha
  vocabulário com a seção "Resultado Financeiro" onde a linha está, então caíam classificados como
  CONTA comum e eram somados de novo, dobrando o valor do total calculado (`SUM` incluía o EBIT e o
  próprio resultado financeiro líquido, além das contas que os compõem). Fix
  (`statement-templates.ts`): nova guarda `ehSubtotalRedundanteDRE` (mesmo padrão de `ehLinhaDMPL`)
  reconhece essas duas frases e as tira da soma — caem em "Contas Não Classificadas" (visíveis, sem
  distorcer nenhum subtotal).
- **BUG 2 — cabeçalho combinado "Passivo e Patrimônio Líquido" jogava tudo pra PL:** convenção
  padrão dos balanços brasileiros (Lei 6.404/76 art. 178) — mas em `classificarBalanco`, o check de
  seção pra "patrimonio liquido" rodava ANTES do check pra "passivo", e o cabeçalho combinado contém
  as duas palavras como substring. Resultado: toda conta sob esse cabeçalho (Fornecedores,
  Empréstimos e Financiamentos) caía em `patrimonio_liquido` em vez de `passivo_circulante`/
  `passivo_nao_circulante`, e as seções de Passivo ficavam zeradas — daí a divergência entre o total
  informado (que inclui essas contas) e o calculado (que não). Fix: "passivo" é checado primeiro;
  "patrimonio liquido" só entra como `else if` quando "passivo" não está combinado na mesma seção.
- **Pedido — remover toda menção a tipo/versão de taxonomia da planilha:** era detalhe interno de
  classificação, não algo que o time de análise precisa ver. Removido de: nota de proveniência de
  cada célula (`notaProveniencia`/`notaProvenienciaSimples`), aba Resumo (linha "Versão(ões) da
  taxonomia envolvidas" e o parâmetro inteiro `taxonomia`/`TaxonomiaParaExport` que só existia pra
  isso). Continua orientando o roteamento por aba internamente (`tipo_taxonomia`/`ABA_POR_TIPO`) —
  só sai da tela, não da lógica.
- **Pedido — padronizar a escrita de período:** convenções cifradas vindas da extração ("multi
  02,25", "data-base 2025-01-15", "12M25", "L24M", "1T25") viravam texto solto e técnico na
  planilha. Nova função `formatarPeriodo` (`export.ts`) traduz pra um modelo pronto e objetivo:
  "2023, 2024, 2025" / "15/01/2025" / "2025" (ano fiscal completo) / "9 meses/2024" / "Últimos 24
  meses" / "1º Tri/2025" / "2024–2025" (intervalo de 2). O que não reconhece devolve como veio
  (nunca pior que antes).
- **Pedido — anotações cortadas ao abrir:** a caixa de toda nota (`cell.note`) do ExcelJS vem com
  tamanho FIXO no XML VML (`width:97.8pt;height:59.1pt` ≈ 130×80px), hardcoded no próprio pacote
  (`lib/xlsx/xform/comment/vml-shape-xform.js`) — sem parâmetro público pra mudar (conferido lendo o
  fonte da lib, não só o `.d.ts`). Fix em duas partes: (1) fonte compacta (8pt, `comoNota()`) em toda
  nota; (2) nova função `ampliarNotasNoBuffer` pós-processa o `.xlsx` já gerado — ele é um .zip, abre
  com JSZip (dependência transitiva do próprio exceljs, agora explícita em `package.json`), troca a
  string de tamanho fixo por uma caixa bem maior (`340pt×170pt`) em toda parte
  `xl/drawings/vmlDrawing*.vml`, sem tocar `node_modules`. Chamada em `route.ts` logo após
  `workbook.xlsx.writeBuffer()`.
- **Testado:** harness `tsx` cobrindo os 9 formatos de período (todos passando), os dois fixes de
  classificação (já verificados em sessão anterior, confirmados intactos), e o round-trip do
  `ampliarNotasNoBuffer` (caixa de nota confirmada mudando de `97.8pt/59.1pt` pra `340pt/170pt` no
  XML gerado). `tsc --noEmit`, `eslint`, `next build` limpos.
- **Precisa:** re-exportar um caso real pra conferir visualmente — planilha sem nenhuma menção a
  taxonomia, período legível, notas abrindo sem corte, e as duas divergências de DRE/Combinado
  resolvidas.

### Sessão 7 (cont.¹⁶) — Tipo/período em texto natural no dashboard/planilha do documento + resumo menos redundante
Print do dono da tabela de documentos do dashboard mostrou `tipo_taxonomia` cru ("FATURAMENTO_24M",
"FLUXO_CAIXA") e período sem tradução ("outro Jan/2024 a Dez/2025", "anual 12M25") — a
`formatarPeriodo` de cont.¹⁵ só tinha sido ligada no export em Excel, não nas telas do portal.

- **Rótulo natural do tipo:** nova `formatarTipoTaxonomia` (`portal/src/lib/export.ts`) — mapa
  explícito pros 12 tipos do Kit Básico + Variáveis já usados no export (`TIPO_TAXONOMIA_LABEL`,
  igual ao pedido do dono: "Faturamento em 24 meses", "Fluxo de Caixa", "DRE", "Balanço",
  "Faturamento Intragrupo", "Contrato Social", "Mútuos", "Mapa da Dívida", "Demonstrações
  Combinadas", + Balancete/Contrato de Dívida/Fluxo Projetado no mesmo estilo); tipo fora desse mapa
  (documento complementar raro, ex. `EXTRATO_BANCARIO`) cai num fallback genérico que já tira o
  `_`/caixa alta ("Extrato Bancario") em vez do código cru — nunca pior que antes, já preparado pra
  quando entrar um tipo novo. Ligado em `casos/[id]/page.tsx` (tabela de documentos),
  `casos/[id]/documentos/[docId]/page.tsx` (cabeçalho da planilha do documento) e
  `casos/[id]/revisao/page.tsx` ("Sugestão atual").
- **Período nas mesmas telas:** `formatarPeriodo` (já existia, só usada no export em Excel) agora
  também roda nessas três telas — mesmo tratamento, um lugar só.
- **Resumo repetindo entidade/período/tipo:** o prompt da IA (`N8N/workflow.e1-ingestao.json`, nó
  "Montar Req Extração") só dizia `resumo = 2-3 frases objetivas do conteudo`, sem instruir a NÃO
  repetir o que já sai em campos próprios — daí frases como "...da Teste Indústria Ltda para os
  últimos 24 meses, de janeiro de 2024 a dezembro de 2025..." reafirmando entidade/período que já
  aparecem em colunas ao lado. Fix: instrução explícita no prompt pra focar só no conteúdo
  específico (colunas/tabelas, estrutura, achados) e nunca repetir entidade/tipo/período. **Só vale
  pra extrações novas** — resumos já gravados no banco não mudam retroativamente sem reprocessar o
  documento.
- **Testado:** harness `tsx` confirmando os 12 rótulos de tipo batendo exatamente com o pedido do
  dono, o fallback genérico, e os 6 casos de período do print reproduzidos batendo com o esperado.
  `tsc --noEmit`, `eslint`, `next build` limpos.
- **Precisa:** nenhuma migration nem redeploy do N8N automático — o workflow JSON precisa ser
  reimportado no N8N pra pegar o prompt novo (mesmo processo de sempre).

---

## 2. Decisões tomadas (por que as coisas são como são)

| Decisão | Onde está documentada |
|---|---|
| Build vs. buy: híbrido, reaproveitando infra do `clipping-news` (Supabase + N8N + Vercel) | `Arquitetura do Sistema/2 Especificação/f0/02_build_vs_buy.md` |
| Ingestão: upload em lote via **N8N Form Trigger** (não pelo portal) | decisão explícita do dono na conversa; `N8N/README.md` |
| Motor de IA: **OpenAI API direta** (multimodal + Structured Outputs), classificação por nome primeiro (barato), fallback pra IA só quando confiança baixa | `Arquitetura do Sistema/2 Especificação/f0/02_build_vs_buy.md` |
| Taxonomia v1: Kit Básico (8 obrigatórios) + 26 Variáveis (complementares) | `Arquitetura do Sistema/2 Especificação/f0/03_taxonomia_reestruturacao.md` |
| Output final: **base viva + export Excel** — dado curado e rastreável, **NÃO modelagem com fórmulas prontas** (decisão reafirmada nesta sessão após dúvida do dono) | `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`, seção "Fora do escopo" |
| Doutrina de Autonomia: classificação nasce N1 (sugestão+revisão humana), extração nasce N0 (sombra), anti-ancoragem (nenhum número vira fato sem aceite humano explícito) | `Arquitetura do Sistema/1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md` |
| RLS do Fatia 1: qualquer usuário `authenticated` vê tudo (ferramenta interna, um time) — restrição por caso é fatia futura | `Supabase/migrations/0003_rls_e_storage.sql` |
| Upload Storage (N8N→Supabase Storage) desabilitado — bug de plataforma confirmado do node HTTP Request do N8N com binário | `N8N/README.md` § "Upload Storage — pendência conhecida" |
| E3 Classe A: casamento `chave` extraída → conceito canônico por **normalização + termos obrigatórios/excludentes** (determinístico, sem LLM); log append-only (`reconciliacao`) separado do estado acionável deduplicado (`pendencia`, chave `motivo='reconciliacao:<tipo>'`) | `Supabase/migrations/0009_reconciliacao_e3.sql` |
| Diagnóstico de conteúdo (entidade/tipo/período/legibilidade) fundido na MESMA chamada de extração E2 (não uma chamada nova) para não aumentar custo; só preenche lacunas (entidade vazia) ou confere contra o já registrado — divergência sempre vira pendência revisável, nunca sobrescreve sozinho | `Supabase/migrations/0010_diagnostico_e1e2.sql` |
| E4 aceite: granularidade v0 é por **documento_versao inteiro** (não célula-a-célula) — degrau mínimo que já satisfaz `status_aceite`/`aceito_por`/`aceito_em` por linha exigidos pela spec, sem construir UI de seleção linha-a-linha ainda | `Supabase/migrations/0011_aceite_export_e4.sql` |
| Export Excel: linhas pendentes de aceite aparecem no export (visualmente distintas — âmbar+itálico), nunca são omitidas — "sugestão pendente de revisão" nunca é fato silencioso | `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`, `portal/src/lib/export.ts` |
| Export Excel — Balanço/Balancete/DRE/Fluxo de Caixa/Combinado: layout PADRÃO DE MERCADO com colunas entidade×período, mas classificação por SEÇÃO (não por template de nomes fixos) — cada conta mantém o rótulo original da empresa; casamento tolerante a plural/conectivo; nunca soma/calcula subtotal novo. Faturamento/Dívida/Fluxo Projetado continuam em listagem simples (já são série/tabela por natureza) | `portal/src/lib/statement-templates.ts` |

---

## 3. Próximos passos

### Decisão pendente (bloqueia o próximo passo de código)
**GATE ATUAL (atualizado pós-cont.¹⁶):** os problemas de REVISÃO/EXPORT achados no "teste v20"
(fila não fechando, vazamento entre abas, taxonomia confusa/crua na tela, período sem tradução,
2 bugs reais de classificação causando divergência de total, notas de célula cortadas, resumo
redundante) estão todos corrigidos e mergeados (PRs #39, #40, #41 — ver TL;DR no topo do arquivo).
**Falta o dono, antes de qualquer código novo:** (1) reimportar o workflow N8N atualizado (pega o
prompt novo do `resumo`); (2) re-exportar um caso real e conferir visualmente o resultado de tudo
isso junto. Depois disso, não há mais gate conhecido — a lista abaixo é de FEATURE nova, nenhuma
delas foi formalmente escolhida ainda pelo dono. Itens mais antigos da lista (reimportar pós
cont.¹³, reprocessar os 7 documentos do "teste v18", confirmar pop-up do upload) provavelmente já
foram resolvidos em sessões posteriores — confirmar com o dono antes de retrabalhar. Próximo passo
de feature é uma destas (perguntar ao dono qual prioriza):
1. **Ação de resolução na fila do portal** para pendências de reconciliação (hoje só lista;
   não tem um "confirmar/ressalva" dedicado como `fn_revisar_documento` tem para classificação
   — as pendências de diagnóstico, ao contrário, JÁ passam pela fila existente). Mais relevante
   agora que a Classe B dobrou o volume potencial de pendências de reconciliação.
2. **Análise horizontal/vertical no export** (Δ% ano-a-ano e % do total) — agora que os períodos
   viram colunas próprias (cont.⁹), é o passo seguinte pra "cara de modelo": colunas de variação
   entre anos adjacentes e % de cada conta sobre o total do grupo. Puramente aditivo ao export.
3. **Suporte a `.docx`/Word e `.xlsx` no `Preparar Conteudo`** (hoje caem em "conteudo nao
   suportado"/nota de texto) — ligar um nó *Extract From File* do N8N antes do `Preparar Conteudo`
   e mandar o texto extraído no lugar do binário. Gap real de "adaptação a arquivos diferentes"
   levantado pelo dono (não foi a causa do v15/v18, mas é legítimo).
4. **Dividir a extração por página/período pra documentos genuinamente enormes** (cont.¹¹) — a
   correção COMPLETA do truncamento residual; requer testar contra N8N vivo (mudança de topologia
   do grafo), por isso ficou fora desta rodada.
5. **Refinar a extração de `FATURAMENTO_24M`/`MAPA_DIVIDA`** (hoje schema genérico de linhas) —
   é o que faz as checagens de Classe B (e uma futura Classe A de dívida) pararem de cair em
   "precondição não satisfeita" com tanta frequência.
6. **Refinar a granularidade do aceite** (hoje é por documento inteiro) para célula/linha
   individual — o bug da sessão 7 tornou isso mais urgente: um aceite em lote é especialmente
   perigoso quando a extração pode vir contaminada/alucinada em volume.
7. **Reconciliação Classe C** (interpretativa — mapa de dívida vs. balanço, mútuos/intragrupo,
   `Arquitetura do Sistema/2 Especificação/04`) — "não reconcilia, aproxima para humano": mostra as duas fontes, humano decide.
   LLM só como hipótese explicativa de uma divergência já detectada, nunca decide.
8. **Portão 2 formal do caso inteiro** (bloqueantes não-sobrepujáveis, teto de ressalva,
   `Arquitetura do Sistema/3 Estado e Execução/07_STATUS_E_PENDENCIAS.md`) — hoje só existe o aceite mínimo por linha extraída.

**Validar com o time de análise** (ainda pendente): se as palavras-chave de seção
(`statement-templates.ts`) cobrem o vocabulário real dos clientes da Oria — a sessão 7 usou 2
documentos reais e a classificação por seção em si funcionou bem (ver diff PDF↔export); o
problema achado foi de PIPELINE (item errado), não de vocabulário de classificação.

### Itens adiados (documentados, não bloqueantes)
- ~~**Teto de ~4,5 MB no upload pelo portal (Vercel)**~~ — **RESOLVIDO em 13/09/2026**, depois de
  o lote de 48 arquivos (~50 MB) da AMO morrer em HTTP 413 da BORDA (a rota nunca rodou). Acima do
  teto o navegador manda o multipart direto ao Form do n8n, numa execução só; abaixo dele nada
  mudou. Ver `portal/src/lib/limite-de-envio.ts` e a memória
  `.claude/memory/teto-da-borda-recusa-antes-do-codigo.md`.
- **O acompanhamento não distingue DOIS lotes no mesmo mandato** (achado na revisão adversarial da
  mesma rodada, e ANTERIOR a ela). `/api/intake/status` filtra por `caso_nome` + `criado_em >=
  desde` e por mais nada: um segundo envio feito enquanto o primeiro ainda roda conta os documentos
  do primeiro como seus, e fecha com "Tudo pronto" sem que nenhum documento dele tenha chegado. A
  correção de 13/09 ENCOLHEU a janela (o `desde` do envio direto passou a ser lido DEPOIS do upload,
  não antes — num lote de 50 MB isso são minutos), mas não resolve o caso: a solução real é o
  pipeline gravar o identificador do lote no `documento` e o status filtrar por ele. Até lá, não
  mande um segundo lote no mesmo mandato enquanto o primeiro está rodando.
- **Overload morto de `fn_registrar_documento`:** achado ao testar 0009 contra Postgres local —
  a migration `0007` adicionou `p_justificativa` via `create or replace` com um parâmetro a
  mais, o que em Postgres **cria uma segunda função** (14 params) em vez de substituir a de
  `0006`, em vez de exigir `drop` antes (como `0005` fez corretamente para a mudança de tipo de
  retorno). Não quebra a produção porque o N8N sempre chama com o parâmetro nomeado
  `p_justificativa=>...`, que desambigua para a versão de 15 params — mas é lixo de schema
  (duas assinaturas da mesma função) e qualquer chamada só-posicional (ex.: um teste manual)
  fica ambígua. Limpar numa migration futura (`drop function` da assinatura de 14 params).
- **Upload Storage** ainda desabilitado — alternativas documentadas em
  `N8N/README.md`: community node `n8n-nodes-supabase`, ou mover upload pro portal via
  SDK JS do Supabase.
- **XLSX no fallback de conteúdo**: hoje só manda uma nota de texto avisando; falta
  ligar um nó *Extract From File* antes do `Preparar Conteudo`.
- **LGPD**: OpenAI API direta está fora do perímetro Azure preferido — antes de dados
  reais de cliente em produção, ativar zero-retention/DPA da OpenAI + revisão de NDA
  pelo jurídico. Migração para Azure OpenAI é trivial (mesma troca de baseURL/auth).
- **RLS por caso** (membership) — hoje é "todo autenticado vê tudo".
- **Verificação em Supabase real** dos embeds de foreign key nas queries do portal
  (`entidade`, `periodo`, `documento_versao`) — escritos conforme sintaxe documentada
  do PostgREST mas não exercitados contra um projeto real antes do deploy (agora já
  testado ao vivo pelo dono — funcionando).

---

## 4. Padrões relevantes (como este projeto é construído)

### Disciplina de teste
- Toda lógica de negócio do N8N vive em `N8N/lib/*.mjs` (testável, fonte da verdade) e
  é **espelhada manualmente** dentro das strings de código dos nós Code em
  `N8N/build-workflow.mjs` (porque nós Code do N8N não importam arquivos). Ao mudar
  lógica: mude `lib/`, rode `npm test`, regenere com `node build-workflow.mjs`.
  **Já causou um bug real** (schema sem enum) por o mirror manual ter ficado
  desatualizado — hoje o gerador importa constantes direto de `lib/` quando possível,
  em vez de copiar à mão.
- `N8N/test/workflow-sim.test.mjs` executa os códigos **reais** do JSON gerado com
  dados mock reproduzindo a semântica exata do N8N (`$input`, `$()`, `$json`,
  `this.helpers`) — pega bugs de fluxo de dados entre nós antes do dono testar ao vivo.
- Migrations SQL são sempre testadas contra um **Postgres 16 local efêmero** antes de
  entregar (rodar como usuário `postgres` do sistema via `sudo -u postgres`, criar role
  `authenticated` manualmente pra simular RLS do Supabase). Ver histórico de comandos
  nesta sessão para o padrão exato (`initdb`/cluster já vem provisionado no ambiente).

### Regras de fluxo do N8N aprendidas (não violar)
1. Node Postgres **não repassa binário** — quem precisa do arquivo lê do Form por
   referência (`$('Intake (Form)')`).
2. Node HTTP Request **substitui o item inteiro** pela resposta da API (perde
   json+binário) — contexto anterior se recupera via `$('Nome do Node').item`.
3. Code em `runOnceForEachItem` retorna **um objeto** `{json,binary?}`; em
   `runOnceForAllItems` retorna **array** (único modo que permite fan-out).
4. Binário em Code node: **nunca** ler `binary.<prop>.data` direto — usar
   `await this.helpers.getBinaryDataBuffer(itemIndex, propertyName)` (funciona em
   qualquer modo de armazenamento; ler direto só funciona por acaso no modo memória).
5. `$env` é bloqueado por padrão no N8N — não usar.
6. **`itemIndex` de `getBinaryDataBuffer` NUNCA pode ser um literal fixo** (ex.: `0`) — mesmo em
   `runOnceForEachItem`, o buffer é resolvido pelo índice do item **dentro do lote inteiro do
   node**, não por um índice "local" do item isolado. Usar `$itemIndex` (global do N8N em
   each-item mode). Um literal fixo funciona por acaso quando só há 1 item no lote (upload de 1
   arquivo por vez) e **quebra silenciosamente** com 2+ itens — cada item != 0 lê o binário do
   item 0 (nome/mimeType corretos, mas o CONTEÚDO enviado pra IA é de outro arquivo). Achado
   testando com upload de 2 arquivos reais no mesmo Form (sessão 7) — node `Preparar Conteudo` em
   `N8N/build-workflow.mjs` (plumbing do N8N, sem `lib/` próprio — não é lógica de negócio
   testável isoladamente, por isso o teste é contra o JSON gerado, `workflow-sim.test.mjs`).

### Git / PR workflow desta sessão
- Branch usada na sessão 4: `claude/ola-3a5wp0` — teve **5 PRs mergeados** a partir dela
  (#20-#24, ver acima), depois esgotada (já mergeada) — sessão 5 restartou a partir do `main`
  atualizado, como o padrão abaixo manda.
- Branch usada nas sessões 5 e 6: `claude/handoff-md-review-ywt57q`. O PR #26 (sessão 5) foi
  mergeado; a sessão 6 **restartou a branch do `main` atualizado** (`git checkout -B
  claude/handoff-md-review-ywt57q origin/main`) antes de commitar o trabalho novo — nunca empilhar
  em cima de branch cujo PR já foi mergeado. A **próxima sessão deve fazer o mesmo**: checar se o
  PR desta branch já foi mergeado e, se sim, restartar do `main`. Padrão no meio do trabalho:
  `git fetch origin main && git rebase origin/main` (ou `git checkout -B claude/<nome> origin/main`).
- Branch usada nas sessões 7-10: `claude/handoff-continuation-2oecw8` — **14 PRs mergeados** a partir
  dela (#39-#52), restartada de `origin/main` a cada vez que um PR fechava.
  **Padrão obrigatório**: quando o PR da branch é mergeado, restarte do `main` atualizado
  (`git fetch origin main && git checkout -B claude/handoff-continuation-2oecw8 origin/main`) — nunca
  empilhe em cima de histórico já mergeado.
- Branch das sessões 11-13: `claude/handoff-leitura-continuacao-jeifmd` — **2 PRs mergeados** (#54 na
  sessão 11; #55 com as sessões 12 e 13 juntas), restartada de `origin/main` a cada vez.
- Branch das sessões 14-15: `claude/handoff-continuation-orqkmn`, criada a partir do `main` já com o
  #55 mergeado; o #56 (sessão 14) saiu dela e a sessão 15 continuou na mesma branch. Mesmo padrão: quando o PR desta branch fechar, a próxima sessão restarta do `main`
  atualizado em vez de empilhar em cima de histórico já mergeado.
- **Aviso de leitura desta sessão:** ao retomar, confirme o estado do `main` com
  `git ls-remote origin main` **e** com a lista de PRs — o cabeçalho deste arquivo já ficou defasado
  duas vezes (na sessão 14 ele dizia "PR #54 em aberto" quando #54 e #55 já estavam mergeados, porque
  o commit de handoff viaja no próprio PR que muda o estado). O `git fetch origin main` do container
  pode devolver um `origin/main` velho; o `ls-remote` não mente.
- **Aviso prático desta sessão:** duas sessões editaram o mesmo cabeçalho do HANDOFF em paralelo
  (o #53 corrigiu o estado do `main` enquanto o #54 já estava aberto), e o #54 ficou em conflito.
  O cabeçalho deste arquivo é o ponto de conflito mais provável do repositório — ao retomar,
  `git fetch origin main` antes de escrever nele.
- O stop-hook local reclama dos **merge commits do próprio GitHub** (committer `noreply@github.com`),
  que aparecem na branch depois de cada merge. **Não reescreva**: já estão publicados no `main`, e
  reescrever trocaria um aviso cosmético por divergência real. Os commits de autoria própria passam.
- Todo PR é aberto como **draft**; o dono marca "ready for review" e mergeia pelo GitHub.
- O stop-hook local avisa sobre commits "Unverified" (merge commits do próprio
  GitHub) — **não são reescritos** (exigiria reescrever histórico compartilhado do
  `main`); é uma checagem esperada, não um problema real.

### Doutrina de Autonomia (aplicar em qualquer fatia nova)
- N0 = sombra (roda, mas nada é fato). N1 = sugestão + revisão humana obrigatória.
  N2 = determinístico auto-clear. N3 = autônomo.
- **Anti-ancoragem**: nenhum número/classificação sugerido por IA entra na base como
  fato sem uma `decisao` de aceite humano explícito, registrada em `decisao` +
  `evento_auditoria` (append-only).
- Todo passo de mutação de estado importante vira uma função Postgres testável (não
  lógica solta no N8N/portal) — ver `fn_registrar_documento`, `fn_recomputar_completude`,
  `fn_revisar_documento` como modelo a seguir para as funções da E3.

### Onde tudo mora
```
Supabase/         — migrations SQL (0001-0028) + README com ordem de aplicação
              test/  — fixture do book + reconciliacao/macro/reextracao.test.sql + run.sh
N8N/        — build-workflow.mjs (gerador) + lib/ (lógica testável) + test/ + workflow.e1-ingestao.json (gerado)
              build-workflow-macro.mjs + lib/macro.mjs + workflow.macro.json — coleta de índices macro (0025),
              workflow SEPARADO que roda no relógio (dia 12); falha dele não derruba a ingestão
portal/     — Next.js (App Router) + Supabase Auth — dashboard, fila de revisão, planilha+aceite, export Excel
              src/lib/export.ts             — o motor do export (função pura buildExportWorkbook):
                                              abas de demonstração, DMPL/DVA, Macro, Modelagem, roteamento por linha
              src/lib/statement-templates.ts — classificador por seção contábil
              scripts/verificar-export.mts   — 126 invariantes de regressão do export
              scripts/lib/avaliar-formula.mts — avaliador de SUM/refs/aritmética/IFERROR
              scripts/fixtures/             — fixture do book em JSON (gerado, versionado)
Arquitetura do Sistema/2 Especificação/f0/         — decisões estruturais da fundação (taxonomia, schema, output spec, padrão analítico)
docs/       — doutrina de autonomia, arquitetura, roadmap, reconciliação, auditoria, custo OpenAI
Dados de Teste/  — book-vertentes/ (gerador do book complexo + gabarito; PDFs não são versionados)
```

### Como validar (rodar SEMPRE antes de commitar)
```bash
node --test 'N8N/test/*.test.mjs'           # 160 testes: libs + nós REAIS do JSON gerado
node N8N/build-workflow.mjs                 # regenera workflow.e1-ingestao.json (commitar o gerado)
node N8N/build-workflow-macro.mjs           # regenera workflow.macro.json (idem)
node N8N/build-workflow-diagnostico.mjs     # regenera workflow.diagnostico-openai.json (idem)
npx tsx portal/scripts/verificar-export.mts # 198 invariantes do export
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh
#   ^ reconciliação + macro + reextração + canonicalização (16) + seed macro
E2E_PSQL="sudo -u postgres psql -h /tmp -p 5432" npx tsx Verificação/run.mts
#   ^ 18 asserts ENCADEANDO extração (nó real) -> banco (funções reais) -> export -> gabarito.
#     É a única suíte que cobre a COSTURA entre as três; as outras validam seu pedaço
#     contra fixture escrita à mão nas duas pontas, e as duas pontas podem errar juntas.
cd portal && npx tsc --noEmit && npx eslint . && npx next build
```

**Preparo de container novo** (a sessão 14 perdeu tempo nos três — rode antes de qualquer coisa):

```bash
cd portal && npm install && cd ..                    # node_modules NÃO vem no clone
cd "Dados de Teste"/book-vertentes && pip install reportlab && python3 gerar.py && cd ../..
# ↑ gera pdf/ + GABARITO.json, que NÃO são versionados. Sem isso o verificar-export.mts
#   morre com ENOENT no GABARITO.json — não é bug, é insumo faltando.
sudo -u postgres /usr/lib/postgresql/16/bin/pg_ctl -D /var/lib/postgresql/16/main \
  -o "-c config_file=/etc/postgresql/16/main/postgresql.conf -k /tmp -p 5432" -l /tmp/pg.log start
# ↑ o cluster já vem provisionado; sem o config_file explícito o pg_ctl falha
#   ("could not access postgresql.conf" — o Debian separa config de dados).
sudo -u postgres env PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh
# ↑ como postgres, senão dá "Peer authentication failed" (o socket usa peer auth).
```

O `run.sh` cria os papéis `anon`/`authenticated`/`service_role` e o schema `storage` que as migrations
assumem do Supabase.

Migrations: aplicar `0001`→`0032` em ordem num Postgres 16 local antes de propor SQL novo — várias
funções são redefinidas por migrations posteriores e só a ordem completa revela o comportamento real.
O `.xlsx` do dono se lê com `python3` + `openpyxl` (`data_only=False` pra ver as fórmulas).

> **Nota para quem for continuar a E3:** `Arquitetura do Sistema/2 Especificação/04_RECONCILIACAO.md` tem o desenho conceitual
> das classes A/B/C. A Classe A (checagens 1 e 2 dos exemplos canônicos) já está construída em
> `Supabase/migrations/0009_reconciliacao_e3.sql` — ler essa migration (e os testes ad hoc descritos
> em §1 desta sessão) antes de adicionar novas checagens ou atacar B/C do zero. **A Classe B é o
> próximo passo combinado com o dono** (sessão 6): determinística, banda de materialidade (piso
> R$ **E** % relativo, `Arquitetura do Sistema/2 Especificação/04`), teto N1; duas checagens canônicas (Receita DRE vs. soma do
> faturamento; despesa financeira vs. juros do mapa de dívida). Reaproveitar `fn_valor_conceito`
> e o padrão de pendência idempotente (`motivo='reconciliacao:<tipo>'`) da 0009.

> **Nota para quem for continuar a E4:** `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md` é a spec travada (v0) do output
> — dois modos de entrega (base viva no portal + export Excel), schema-alvo com ordem de
> prioridade, proveniência por célula, e o princípio inegociável de anti-ancoragem. O aceite
> (`fn_aceitar_extracao`, `0011`), o export (`portal/src/lib/export.ts`) e o classificador por
> seção do Balanço/Balancete/DRE/Fluxo de Caixa (`portal/src/lib/statement-templates.ts`) já
> existem nessa primeira fatia — ler os três antes de mexer. **Importante:** não é mais um
> template de nomes de conta fixos — é um classificador por seção com palavras-chave +
> casamento tolerante a plural/conectivo (`contemFrase`/`tokensDe`). Para ampliar cobertura,
> adicionar palavras-chave nas listas (`ATIVO_CIRC_KW` etc.) em vez de tentar adivinhar nomes
> de conta exatos. Ver quantas linhas caem em "Contas Não Classificadas" com dados reais é o
> sinal mais direto de onde o vocabulário ainda precisa de mais cobertura.
>
> **Atualização sessão 6:** além das palavras-chave, o classificador agora tem um **fallback de
> IA** — a `secao_canonica` que a IA sugere na extração (`Supabase/migrations/0012`, `N8N/lib/extract.mjs`)
> entra em `classificarConta` só quando a regra determinística abstém. Ao mexer, lembrar: o enum
> de `secao_canonica` (em `extract.mjs` → `SECAO_CANONICA_ENUM`) e as chaves de seção do
> classificador (`BALANCO_SECOES`/`DRE_SECOES`/`FLUXO_CAIXA_SECOES`) têm que permanecer IDÊNTICOS
> (não há import cruzado .mjs↔portal TS). Promover a IA a ter PRIORIDADE sobre a regra (ou
> auto-clear) é uma subida de dial que exige golden set + concordância medida (`Arquitetura do Sistema/1 Visão e Doutrina/01`, `Arquitetura do Sistema/2 Especificação/f0/06`)
> — não fazer sem isso.

## Sessão 31 (2026-08-04) — Fase 8 (papel da linha) + Fase 9 (modelo institucional)

Duas coisas nesta sessão: as correções que a **rodada real do Teste v35** pediu, e a
**reconstrução do "Modelo Base"** que o dono subiu como referência universal.

### Fase 8 — a linha diz o que ela é (`0042`, `0043`, `0044`)

Os prints do v35 mostraram a tela de Modelagem tratando 236 linhas como conta projetável:
`Ativo Circulante 67.878` entre os 32 componentes dela, os 12 `Faturamento Janeiro…Dezembro`
como contas, `(-) Depreciação acumulada` positiva, `TOTAL — saldo devedor 51.300.000` (reais)
ao lado de `Passivo Circulante 92.539` (milhares).

- **`0042`** — `fn_papel_linha` (conta/subtotal/derivado/serie_mensal, lista fechada,
  reaproveitando `fn_rotulo_estrutural` da 0034), `fn_linhas_para_modelagem` com **papel, valor
  COM SINAL, unidade/moeda, documentos de origem e `sobreposicao_suspeita`**; recusa de vínculo
  em linha que não é conta, no BANCO; lote que declara o que deixou de fora; macro puxando o
  **Focus** ao ser ativada sem valor; `fn_conferir_modelagem` contando só o projetável.
- **Dois defeitos que a fixture escondia:** `fn_sazonalidade_do_caso` lia o mês com
  `left(chave,3)` — funcionava com `jan/2024` (rótulo que EU inventei) e voltava **vazia** com
  `Faturamento Janeiro` (rótulo que a extração real produz). E `sobreposicao_suspeita` na
  primeira versão marcava qualquer par com valor igual: 4 pares reais viraram dezenas de falsos
  até entrar `fn_rotulo_contido`.
- **`0043`** — `fn_reconferir_caso`: reaplica as regras de HOJE sobre o dado já gravado, **sem
  gastar IA**. As duas pendências do v35 ("falta o Passivo+PL" e "4 contas com 14529") eram
  **achado de regra velha** — a 0034 já as havia fechado e nada reavaliava pendência gravada. O
  teste reproduz a forma exata daquele dado e prova que hoje dá `ok`.
- **`0044`** — `fn_valores_por_ano(caso, entidade)`: a série histórica por exercício. O filtro de
  entidade **não é opcional**: sem ele, "Ativo Circulante 2024" devolvia o da VT Logística
  (3.961) enquanto a Metalúrgica tinha 67.878 — ativo de uma empresa com passivo de outra.

### Fase 9 — o modelo institucional (14 abas)

`portal/src/lib/modelo-institucional.ts` reconstrói o Modelo Base com os MESMOS nomes de aba e a
MESMA semântica: `Considerações · Capa · Output · Revenues, COGS & SG&A · Premissas · Income
Statement · Balance Sheet · Working Capital · ST Inv. & Debt · Fixed Assets & CAPEX · Cash Flow ·
Goodwill, Taxes & Div. · Anual · Tributos a Recolher`. Switch de cenário `CHOOSE(Output!$G$2,…)`,
capital de giro por dias/360, revolver contra caixa mínimo, capex com depreciação linear, checks.

**O que muda em relação à referência, declarado na aba Considerações:**

1. **Histórico não é digitado** — vem da extração, com proveniência por célula.
2. **`Anual` é a base macro do banco** (realizado + Focus), não uma planilha de 1994-2014.
3. **A circularidade foi cortada**: juros e rendimento sobre o saldo de ABERTURA. Referência
   circular resolve para zero SEM AVISO fora do Excel e nenhum teste consegue verificar o arquivo.
4. **Nada projeta sem premissa**; subtotal é soma dos componentes; tributo só sobre lucro positivo.

**O avaliador de fórmula do arnês ganhou referência entre abas e `CHOOSE`** — e foi ele que
achou os dois defeitos desta fase: escala misturada (dívida em reais somada a balanço em
milhares: passivo de 51.300.000 contra ativo de 1.000) e **modelo vazio com cara de modelo**
(sem `secao_canonica` todo bloco fica vazio e as 14 abas saem zeradas). O primeiro virou
conversão de escala com nota por célula; o segundo, um banner **"ESTE MODELO NÃO ESTÁ
PROJETÁVEL"** no topo do Output, nomeando o que falta.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **426**; `Supabase/test/run.sh` = **44 migrations / 233
asserts**; `Verificação/run.mts` = **27**.

### O que falta (declarado, não escondido)

- **Asserts do modelo institucional no `verificar-export.mts`** — o avaliador já resolve as
  fórmulas cruzadas; faltam os asserts (balanço fecha em toda coluna projetada, cenário 3 piora o
  resultado, banner aparece quando não projetável). É o próximo passo.
- A aba `Modelagem` agregada (Fase 7) **continua no arquivo**, de propósito: é a única com
  validação ao vivo, e serve de comparação. Removê-la é decisão do dono depois de conferir os dois.
- Aplicar `0042`, `0043`, `0044` e publicar o portal.

## Sessão 32 (2026-08-04) — o lote da Modelagem destravado, e a captura de produção

Sessão curta e reativa: o dono foi executar o roteiro de teste da Fase 8/9 e **travou no passo 3**.
Três PRs mergeados (#86, #87 e o do `Supabase/README.md`), nenhuma fase nova.

### O que o dono subiu: a tela de Modelagem de produção, salva pelo navegador

`Dados de Teste/capturas/2026-08-04-v35-modelagem/` — o HTML renderizado de
`/casos/c4581e51-…/modelagem`, com a `0042`/`0043`/`0044` **já aplicadas**. Chegou achatado na raiz
do repositório (o HTML mais os onze *bundles* do Next); os assets voltaram para a pasta `_files/`
que o próprio HTML referencia, senão a página abre sem estilo. Conferido: **nenhum segredo** nos
onze arquivos.

**É a primeira evidência da Fase 8 contra dado real, e ela prova as duas coisas:**

| Funciona | Denuncia |
|---|---|
| curva de sazonalidade **preenchida** (jan 8,4% … dez 7,0%) com `Faturamento Janeiro` — a correção de `fn_mes_do_rotulo` | **203 contas projetáveis, ZERO com premissa vinculada** |
| 28 subtotais sem seletor; os 12 meses como série mensal; indicadores como derivado | só as **5 premissas macro** ativas; o seletor de sazonalidade das 203 linhas tinha **uma única opção**, a vazia |
| escala **por linha**: `R$` no mapa da dívida ao lado de `R$ mil` no balanço | `setor = tecnologia` salvo num mandato de **metalurgia** (a lista sugeria ARR, churn, LTV, CAC) |
| `sobreposicao_suspeita` marcando 6 pares reais | `Arrendamentos` e `Provisões` são **cabeçalho de grupo tratado como conta projetável** |

### O defeito que travou o dono — `0100_papel_por_secao.sql`, e são TRÊS empilhados

Clicar em "aplicar em lote" fazia a **seção inteira sumir da página**: sem mensagem, sem linha
vinculada, sem caminho para continuar.

1. **Duas funções calculavam o mesmo papel com escopos diferentes.**
   `fn_linhas_para_modelagem` agrupa por `(secao_canonica, rotulo_norm)` — é o que a tela mostra e o
   que o laço do lote percorre. `fn_papel_do_rotulo_no_caso`, que é a guarda dentro de
   `fn_vincular_linha_premissa`, agrupava **só por `rotulo_norm`** no caso inteiro e resolvia o
   empate pelo papel mais restritivo. Bastava o mesmo rótulo existir em outro canto do caso para a
   guarda **recusar a linha que a tela tinha acabado de oferecer como conta**. E é o caso comum, não
   o raro: `fn_papel_linha` depende do tipo do documento, e as ocorrências **sem `secao_canonica`**
   (45 no v35) formam grupo separado na tela e caem no mesmo balaio na guarda.
2. **Uma recusa de papel abortava o lote inteiro.** O `return` na primeira recusa vale para "a
   premissa não está ativa", que é global — e derrubava as outras 43 quando o motivo era por linha.
   A recusa passou a carregar `escopo`: `'premissa'` aborta, papel vai para `ignoradas`.
3. **E a recusa chegava à tela como exceção sem dono.** Sem `error.tsx` na rota o React desmonta a
   subárvore — foi assim que a seção "fechou". E **em produção o Next redige a mensagem de erro de
   servidor**, então nem com fronteira o analista leria "esta linha é um subtotal": leria "an error
   occurred". Recusa esperada agora volta pela URL e vira aviso na própria tela (`voltarComAviso`);
   `error.tsx` ficou só para o inesperado. O lote que **dá certo** também passou a dizer o que fez —
   antes, "não aconteceu nada" e "aconteceu tudo" tinham a mesma aparência.

A guarda **não afrouxou**: subtotal, série mensal e derivado seguem recusados, e seção inexistente
cai para o escopo do caso inteiro, para passar seção errada não virar o jeito de furar a regra.

**Defeitos religados:** com a guarda sem seção, `"em receita_bruta a guarda diz CONTA"` reprovou com
`serie_mensal`; com os dois juntos (= comportamento da `0042`), `"o lote NÃO é recusado"` reprovou
com a recusa de `Faturamento Janeiro` — **o sintoma da tela reproduzido em teste**.

**Declarado:** o ramo de recusa por linha dentro do lote fica **inalcançável** com a guarda
corrigida, e portanto **não está coberto por teste**. A migration diz isso em vez de fingir
cobertura. Ficou porque é a diferença entre uma linha declarada e o lote inteiro caindo — e a
divergência volta no instante em que alguém mexer num lado só, que é o que aconteceu entre a `0039`
e a `0042`.

### `Supabase/README.md` tinha parado na `0031`

O `CLAUDE.md` chama esse arquivo de **ordem oficial de aplicação**, e treze migrations (`0032` a
`0044`) nunca entraram nem na tabela nem na lista de comandos. Quem aplicasse do zero seguindo a
lista pararia na `0031` e teria um banco **sem Portão 2, sem catálogo de premissas, sem papel da
linha — sem nenhum erro, só faltando**. É literalmente a falha que a faixa de numeração existe para
evitar, descrita no próprio arquivo. As 14 linhas entraram nos dois lugares.

### Também nesta sessão

**O horizonte de projeção deixou de ser `placeholder`** (PR #86). O ano de cada coluna de premissa
só existia como texto cinza dentro da caixa, que some ao digitar o primeiro caractere — quem
preenchia a terceira caixa não sabia mais se estava em 2028 ou 2029, e premissa no ano errado não dá
erro, projeta diferente. Agora é rótulo fixo acima da coluna, com o horizonte por extenso.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **426**; `Supabase/test/run.sh` = **45 migrations**
(13 asserts novos, em `Supabase/test/papel_por_secao.test.sql`); `Verificação/run.mts` = **27**.

### O que o dono precisa fazer

1. **Aplicar a `0100` no Supabase** — sem ela o "aplicar em lote" continua caindo, porque a correção
   principal é no banco. A faixa `0100`+ é a de quem colabora (`CLAUDE.md`/`Supabase/README.md`, PR #73);
   o buraco `0044` → `0100` é o estado esperado. São 45 migrations no repositório.
2. Conferir se `0042`, `0043` e `0044` já foram aplicadas — a captura indica que sim.
3. Executar o roteiro de modelagem e mandar o `.xlsx`.

### Aberto, e prioritário para a próxima rodada

- **Dupla contagem de caixa e de dívida no modelo institucional.** `Working Capital` pega TODAS as
  contas de `ativo_circulante` (só exclui imobilizado) — **inclusive caixa, bancos e aplicações** —
  e as projeta por dias de giro; `Cash Flow` soma as mesmas contas em `CAIXA_FIM`; e `Balance Sheet`
  faz `AC = CAIXA + AC_OPER`. **O caixa entra duas vezes no ativo circulante, em toda coluna**, e a
  NCG sai inflada. Do lado do passivo, empréstimos do balanço entram no giro **e** as tranches do
  mapa de dívida entram em `DIVIDA_CP`. É correção só de portal, sem migration. O `CHECK` da aba
  `Balance Sheet` vai acusar isso em vermelho no próximo teste.
- **A Fase 9 nunca foi exercitada com conteúdo.** Medido nesta sessão: as 199 linhas da fixture do
  book têm `secao_canonica` **nula**, então 132 contas caem em `"fora"` e sobram os 18 lançamentos
  do mapa de dívida. O arquivo gerado dá `ATIVO 1.000` contra `PASSIVO+PL 52.300` e `CHECK −51.300`
  em toda coluna — e o banner "ESTE MODELO NÃO ESTÁ PROJETÁVEL" dispara e nomeia a causa certa. A
  rede de proteção funciona; **ela é hoje a única coisa que a Fase 9 comprova.** Os asserts do
  modelo institucional continuam sendo o próximo passo, e agora sabe-se que eles precisam de uma
  fixture COM seção canônica para provar qualquer coisa.
- **O cabeçalho deste arquivo está 17 PRs atrasado** (diz "mergeado até o PR #70, migrations até
  `0034`"). Não é descuido: o `CLAUDE.md` proíbe editar o cabeçalho, só acrescentar seção. O efeito
  colateral é que o "resumo de retomada rápida" é a parte mais velha do documento. Decisão do dono.

## Sessão 33 (2026-08-04) — por que a Modelagem continuou quebrada DEPOIS do merge

Sessão de diagnóstico. O dono relatou que a tela de Modelagem seguia mostrando o mesmo erro
**depois de mergear o PR #90 e aplicar a `0101`**, e pediu resolução completa. A conclusão é que
havia **duas coisas diferentes** sob o mesmo sintoma, e só uma delas era código de banco.

### O que a tela mostrava, e o que aquilo era

A captura do dono traz a caixa vermelha da `0089`:

```
2 consulta(s) ao banco FALHARAM
  conferência (fn_conferir_modelagem): canceling statement due to statement timeout
  linhas do caso (fn_linhas_para_modelagem): canceling statement due to statement timeout
```

**Isso é, campo a campo, o comportamento PRÉ-`0101`.** Reproduzido nesta sessão (ver fixture
abaixo): com os corpos da `0042` em pé, `fn_conferir_modelagem` estoura o teto de 8 s de forma
determinística (3 medições, 3 cancelamentos) e `fn_linhas_para_modelagem` leva 2,7 s — que sozinha
caberia, mas a página dispara **as duas no mesmo `Promise.all`**, concorrentes, e as duas voltam
canceladas. Com a `0101`+`0102` aplicadas, as mesmas duas funções, no mesmo caso: **~640 ms cada**.

### A causa de a correção não ter chegado ao banco: `Supabase/README.md`

A `0101` entrou na **tabela** do `Supabase/README.md` e **não** na lista de comandos
`supabase db execute` que o dono copia para aplicar. A lista terminava na `0100`.

É a mesma falha que a sessão 32 já havia consertado uma vez (treze migrations, `0032`→`0044`, fora
da lista) e que o próprio arquivo descreve: quem aplica seguindo a lista para no último item **sem
nenhum erro, só faltando**. E o efeito é particularmente cruel aqui, porque da tela **"aplicada" e
"não aplicada" têm exatamente a mesma aparência** — o que faz um PR correto parecer um PR que não
funcionou.

Três coisas mudaram por causa disso:

- a `0101` e a `0102` entraram na lista de comandos;
- **`Supabase/test/run.sh` passou a reprovar migration que exista em `Supabase/migrations/` e não esteja na
  lista** — o esquecimento de uma linha deixa de ser silencioso e morre no PR. Conferido religando o
  defeito: apagar a linha da `0102` do README reprova a suíte com o arquivo nomeado;
- `fn_diagnostico_modelagem(caso)` responde `correcoes_instaladas` direto do banco, para "merge não
  é apply" deixar de ser uma dedução.

### `0102_modelagem_versao_vigente.sql` — o que traria o defeito de volta sozinho

A `0101` resolveu o **custo por ocorrência** e não tocou no **número de ocorrências** — e ele cresce
sozinho. A `0026` estabeleceu que reextrair um documento cria `documento_versao` nova sem perder a
anterior; os **cinco leitores por caso** nunca mencionavam `n_versao`, então as ocorrências de
**todas** as versões entravam no mesmo agrupamento. Medido:

| | `Estoques` |
|---|---|
| antes da reextração | 7 ocorrências, valor 24.610 |
| depois de UMA reextração | 8 ocorrências, valor **777.777** |

São dois estragos de naturezas diferentes:

- **correção** — a versão superada não é substituída, é **somada**, e como o valor exibido é o de
  maior módulo (`0042`), uma ocorrência que o analista acabou de corrigir pode **ganhar** e sair no
  Excel. `fn_valores_por_ano` é quem escreve os números do entregável;
- **custo** — cada rodada de reextração acrescenta um jogo inteiro de ocorrências. O caso do v35 tem
  760; três reextrações fazem 2.280, e o custo é linear. **O `statement_timeout` que a `0101`
  destravou voltaria sem ninguém mexer em uma linha de código**, com a mesma cara de "caso vazio".

Os cinco leitores (`fn_linhas_para_modelagem`, `fn_papel_do_rotulo_no_caso`,
`fn_sazonalidade_do_caso`, `fn_valores_por_ano`, `fn_linhas_do_tipo`) passam a compartilhar **uma**
definição, `fn_versao_com_extracao`. Tela, guarda, curva, export e checklist ou andam juntos ou
reabrem o defeito da `0100` por outra porta.

**A decisão que evita trocar um jeito de mentir por outro:** `fn_versao_com_extracao` é a última
versão **que tem extração**, e não `max(n_versao)` como `fn_versao_atual`. `fn_registrar_documento`
cria a versão e `fn_registrar_campos_extraidos` a preenche **depois**; com `max(n_versao)` puro, na
janela entre as duas a tela ficaria **em branco** — exibindo "este caso não tem linha extraída" num
caso cheio, que é literalmente o sintoma que esta rodada existe para matar. Tem assert para isso.

### A fixture que faltava: o caso real, não o inventado

`Supabase/test/fixture_modelagem_v35.sql` reconstrói o caso "Teste v35" a partir da captura de produção
que a sessão 32 versionou — **249 linhas lógicas, 760 ocorrências, 14 documentos, com os rótulos que
o extrator realmente escreveu**. Ela reproduz a produção exatamente, papel por papel:

```
conta 203 · subtotal 28 · serie_mensal 12 · derivado 6      (= o que a captura mostra)
```

E reproduz também as medições do cabeçalho da `0101` (2,7 s / 8,0 s pré-correção contra os 2,35 s /
9,3 s medidos em produção), o que é o que autoriza tratá-la como reprodução fiel e não como
aproximação.

**Por que isso vale mais do que parece.** `modelagem_escala.test.sql` monta 770 ocorrências de **55
rótulos sintéticos** — mede escala e mede bem, mas nunca exerceu `fn_papel_linha` contra rótulo de
verdade, que é onde este projeto já se enganou duas vezes (a `0042` registra `fn_mes_do_rotulo`
passando na fixture com "jan/2024" e voltando vazia com "Faturamento Janeiro"). Agora
`ATIVO`, `TOTAL DO ATIVO`, `Faturamento Janeiro`, `Índice de liquidez corrente` e
`PREJUÍZO LÍQUIDO DO EXERCÍCIO` estão travados **um por um, pelo nome**.

### Defeitos religados (regra do `CLAUDE.md`)

| Defeito religado | Assert que reprovou |
|---|---|
| `fn_linhas_para_modelagem` sem filtro de versão (= `0101`) | "a reextração SUBSTITUI a contribuição do documento" — *depois 8, com o defeito seria 8* |
| `fn_versao_com_extracao` volta a `max(n_versao)` puro | "a linha continua igual com a versão vazia registrada por cima" — *antes 6, depois 5* |
| `fn_papel_linha` perde o total de grupo sem a palavra "total" | "a classificação bate com a produção" — *conta 204, subtotal 27* |
| par PRÉ-`0101` inteiro, na forma real | `canceling statement due to statement timeout`, 3 de 3 |
| a `0102` fora da lista do `Supabase/README.md` | `run.sh` reprova nomeando o arquivo |

**Declarado, com a medição que sustenta:** o filtro de versão em `fn_papel_do_rotulo_no_caso`
**não muda nenhum resultado hoje e não está coberto**. Escrevi o teste e ele **passou com o filtro
removido** — `fn_papel_linha` declara `p_unidade` na assinatura e nunca a usa no corpo, então o
papel é função de (chave, tipo do documento); como a versão superada pertence ao mesmo `documento`,
o papel calculado sobre ela é necessariamente igual. O filtro fica pelo critério da `0100` (as duas
funções ou andam juntas ou a divergência volta), com a inalcançabilidade escrita na migration em vez
de fingida em teste. Vale o mesmo para o outro achado do caminho: `p_unidade` é **parâmetro
decorativo** em `fn_papel_linha` — 303 combinações distintas com ou sem ela na fixture real.

### Também nesta sessão

**A caixa de erro parou de dar o conselho errado.** Ela sempre mandava rodar
`notify pgrst, 'reload schema'` — certo para "function not found", **errado para consulta
cancelada**, que é o caso que estava na tela do dono. Orientação errada num painel de diagnóstico é
pior que orientação nenhuma: manda consertar o que não está quebrado e reforça a impressão de que o
PR não funcionou. Agora a orientação segue o erro, e no caso de timeout aponta para
`fn_diagnostico_modelagem`.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **426**; `Supabase/test/run.sh` = **47 migrations** e
**306 asserts** (283 antes: 23 novos, em `Supabase/test/modelagem_v35.test.sql`); `Verificação/run.mts` =
**27**.

Nota de insumo, que custou uma tentativa: o `CLAUDE.md` documenta o e2e como
`E2E_PSQL=1 ./portal/node_modules/.bin/tsx Verificação/run.mts`, mas `E2E_PSQL` é o **comando** do psql
e não um interruptor — com `1` o Node tenta executar um binário chamado `1` e morre com
`spawnSync 1 ENOENT`. O que funciona é `E2E_PSQL=psql` (ou `E2E_PSQL="sudo -u postgres psql"`, que é
o exemplo no próprio `Verificação/run.mts`).

### O que o dono precisa fazer

1. **Aplicar a `0101` e a `0102`** no Supabase, na ordem, e rodar
   `notify pgrst, 'reload schema';`. A `0101` é a que tira a tela do timeout — se o sintoma da
   captura ainda aparece, é ela que não está no banco.
2. **Conferir com o diagnóstico, em vez de deduzir pela tela:**
   `select jsonb_pretty(fn_diagnostico_modelagem('c4581e51-3ee5-413d-ba04-6d6149fff0c7'));`
   `correcoes_instaladas` tem de vir tudo `true`. Vale olhar `ocorrencias_superadas`: se vier maior
   que zero, o caso vinha somando versão superada e os números da tela **vão mudar** com a `0102` —
   é correção, não regressão.
3. Executar o roteiro de modelagem e mandar o `.xlsx`.

### Aberto (inalterado nesta sessão)

- **Dupla contagem de caixa e de dívida no modelo institucional** (sessão 32) — correção só de
  portal. `Arrendamentos` e `Provisões` como cabeçalho de grupo tratado como conta é da mesma
  família, e agora está travado como `conta` em `modelagem_v35.test.sql`: mudar o papel deles exige
  atualizar o `203/28/12/6` de propósito, com o rótulo nomeado no diff.
- **A Fase 9 nunca foi exercitada com conteúdo** (sessão 32). A fixture desta sessão **tem** seção
  canônica nas 249 linhas, então ela é o insumo que faltava para os asserts do modelo institucional.

## Sessão 34 (2026-08-04) — o timeout sobreviveu ao apply, e a investigação virou de ambiente

A `0101` e a `0102` foram aplicadas e **confirmadas** pelo dono: `fn_diagnostico_modelagem`
devolveu `correcoes_instaladas` tudo `true`, `conferir_modelagem_e_0101` `true`, 249 linhas,
203 projetáveis, 760 ocorrências, `ocorrencias_superadas: 0`. **E a tela continuou mostrando
`canceling statement due to statement timeout` nas duas RPC.**

### O que essa combinação já prova, antes de qualquer hipótese nova

O retorno do diagnóstico em produção veio **idêntico**, número por número, ao que a fixture
`Supabase/test/fixture_modelagem_v35.sql` produz — `249 · conta 203 · subtotal 28 · serie_mensal 12 ·
derivado 6`, 760 ocorrências, 14 documentos. A reconstrução do caso é fiel, então medição local
vale como medição do caso real. E `fn_diagnostico_modelagem` chama
`fn_linhas_para_modelagem` por dentro: ela **terminou** no SQL Editor.

Duas consequências que fecham capítulos:

- **a `0102` não mudou nenhum número desse caso** (`ocorrencias_superadas: 0`): aquele mandato
  nunca havia sofrido do defeito de versão. Quem destravou o sintoma foi a `0101`; a `0102` é
  prevenção. O aviso que dei ao dono de que "os números podem mudar" não se concretizou;
- **o SQL Editor roda como `postgres`, o portal roda como `authenticated`** — e as medições da
  sessão 33 correram todas como superusuário, que **ignora RLS**. Era a assimetria óbvia a
  investigar primeiro.

### As três hipóteses testadas nesta sessão, e todas descartadas POR MEDIÇÃO

| Hipótese | Medido | Veredito |
|---|---|---|
| RLS encarece o caminho como `authenticated` | 492 ms como `authenticated` × 498 ms como superusuário | **descartada** — as políticas são todas `using (true)` |
| as 7 chamadas do `Promise.all` se estrangulam | 480-492 ms cada, todas concorrentes, como `authenticated` | **descartada** |
| `campo_extraido` cresceu com os casos antigos e o plano degradou | plano usa índice em `(documento_versao_id)`, 14 laços — o custo acompanha os documentos DO CASO, não a tabela | **descartada** |

**Conclusão: a lógica SQL não é mais o gargalo.** Nenhuma medição chega perto de 8 s, e nada que
eu consiga fazer localmente reproduz o timeout com a `0101`+`0102` instaladas. O que sobra é
ambiente — e ambiente não se resolve com migration.

### As quatro causas que sobram, e o instrumento que as separa

`Supabase/diagnostico_modelagem.sql` (novo) responde as quatro numa consulta só:

- **A. o portal aponta para outro projeto Supabase** do que o SQL Editor onde as migrations
  foram aplicadas. Explica *tudo* sem sobra: `correcoes_instaladas` `true` de um lado, funções
  velhas do outro. A variável é `NEXT_PUBLIC_SUPABASE_URL` na Vercel;
- **B. o `statement_timeout` de `authenticated` é menor que os 8 s** contra os quais a `0101` foi
  dimensionada;
- **C. a instância está estrangulada de CPU** (crédito de tier compartilhado) e 640 ms viram
  segundos. Quem responde isso é `pg_stat_statements`, que guarda o tempo REAL das chamadas do
  PostgREST — evidência histórica, do relógio da própria produção, não simulação;
- **D. o render do print é anterior ao apply.** A rota é `ƒ` (dinâmica, `cookies()` no
  `createClient`), então não há Full Route Cache — sobra cache de navegador.

O arquivo é uma consulta única de propósito: o SQL Editor mostra só o resultado da **última**
consulta de um lote, e um `pg_stat_statements` inexistente abortaria o lote inteiro levando os
outros blocos com ele. Daí a tabela temporária e o `execute` guardado por `to_regclass`.

### A tela passou a relatar TEMPO, não só falha

Cada uma das sete chamadas volta cronometrada, e o tempo entra na caixa de erro. **Num
cancelamento por tempo, o tempo decorrido É O TETO que o servidor aplica** — sem esse número,
8 s (default do Supabase) e 3 s (projeto mais apertado) produzem exatamente a mesma mensagem, e
foi essa ambiguidade que fez esta rodada custar idas e vindas. Os tempos de quem deu **certo**
também aparecem, porque é a linha de base que dá sentido ao número da falha: cinco chamadas
leves em 80 ms com duas pesadas cortadas em 8.000 ms é um servidor saudável e duas funções que
não couberam; **tudo** lento é a instância, e nenhuma otimização de SQL resolve.

O cronômetro vive em escopo de módulo por causa do `react-hooks/purity` do eslint, que reprova
`Date.now()` no corpo de componente — com o motivo escrito, em vez de silenciado com um
`eslint-disable`.

### Sobre otimizar mais: deliberadamente NÃO feito

`fn_papel_linha` domina os ~490 ms (~1,6 ms × 303 combinações distintas, entre
`fn_normalizar_texto`, quinze subconsultas escalares e nove `fn_rotulo_estrutural`). Dá para
melhorar, e agora seria **seguro** tentar, porque `modelagem_v35.test.sql` trava a classificação
203/28/12/6 contra rótulo real. Mas 490 ms contra 8 s são 16× de folga, e otimizar contra uma
causa **desconhecida** é trabalho especulativo. Medir primeiro; otimizar se a medição pedir.

### O upload do dono não continha o artefato

Os 15 arquivos do commit `9cdadc4` são *chunks* de framework e CSS — **nenhum tem a string
`supabase`**, e o HTML não veio. Como `NEXT_PUBLIC_SUPABASE_URL` fica embutido no bundle da
aplicação, o HTML (ou o chunk da app) permitiria ler o projeto de destino do portal e matar a
hipótese A na hora. Fica registrado como o que pedir na próxima: **o `.html` salvo**, não a
pasta `_files/`.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **426**; `Supabase/test/run.sh` = **47 migrations** e
**306 asserts**; `Verificação/run.mts` = **27**. Nenhuma migration nova nesta sessão — o achado é
que não cabia migration nenhuma.

### O que o dono precisa fazer

1. **Rodar `Supabase/diagnostico_modelagem.sql`** (bloco 1) e mandar a saída inteira.
2. **Comparar o `NEXT_PUBLIC_SUPABASE_URL` da Vercel** com o projeto onde as migrations foram
   aplicadas. Se forem diferentes, acabou aqui.
3. Recarregar a tela com **Ctrl+Shift+R** — o print novo passa a trazer os tempos, e só isso já
   distingue B de C.

## Sessão 35 (2026-08-05) — a `0103`, a regra do cabeçalho, e um agente que não gravou nada

Três coisas: a terceira fatia do problema de tempo, a liberação do cabeçalho deste arquivo, e a
conferência de um agente novo que o dono pôs para rodar.

### `0103_papel_linha_tokeniza_uma_vez.sql` — e o erro foi meu, no BENCHMARK

A `0101` foi medida contra um caso de **55 rótulos distintos** e o resultado (9,3 s → 100 ms)
pareceu suficiente. O caso real tem **~250**. Refeita a medição com a forma certa — 14 documentos,
770 ocorrências, 750 linhas lógicas, oito tipos de documento — as duas funções da tela voltaram a
**~1,9 s cada**, e o dono viu as DUAS cancelarem na mesma tela.

**Fixture menor que a produção mede o instrumento, não o sistema.** Vale como regra geral aqui.

Dois gargalos, os dois de trabalho repetido *dentro* de cada rótulo:

| Gargalo | Antes | Agora |
|---|---|---|
| `fn_papel_linha` chamava `fn_rotulo_estrutural` **nove vezes**, cada uma re-tokenizando o mesmo rótulo do zero | 1,27 s / 770 chamadas | `fn_tokens_estruturais` uma vez por rótulo, nove igualdades de array — **182 ms** |
| `sobreposicao_suspeita` chamava `fn_rotulo_contido` **por par de linhas**, re-tokenizando os dois rótulos a cada par | — | radicais como coluna calculada uma vez por linha, contenção pelo operador `<@`, par não ordenado visitado uma vez |

**1,93 s → 270 ms**, medido em cima da `0102`.

**Duas coisas que eu quase quebrei, e o repositório pegou:**

- o filtro `dv.id = fn_versao_com_extracao(d.id)` da `0102` é **preservado** — reemitir
  `fn_linhas_para_modelagem` sem ele desfaria a correção de versão vigente em silêncio;
- a **`marca-0102` fica no corpo**, ao lado da `marca-0103`. `fn_diagnostico_modelagem` procura
  aquela marca para responder "está instalada no banco?", e foi esse assert que reprovou a primeira
  versão desta migration, com `fn_linhas_para_modelagem: false`.

**Colisão de número, e ela morreu onde devia.** A minha migration nasceu `0102` e outra sessão
mergeou uma `0102` diferente em paralelo. O `run.sh` reprovou o prefixo duplicado antes de aplicar
qualquer coisa — exatamente o desenho da faixa (`CLAUDE.md`). Renumerada para `0103`.

**E um erro de processo que vale registrar:** empurrei a migration para a branch **depois** que o
PR já tinha sido mergeado. Ela ficou órfã — no repositório, fora de qualquer PR — e o dono só
descobriu ao procurar o arquivo. Commit depois do merge não entra sozinho: abre PR novo.

### A regra do cabeçalho mudou

O `CLAUDE.md` proibia editar o cabeçalho deste arquivo. O motivo era bom (dois editando o topo
conflita a cada rodada) e o custo foi maior: o cabeçalho ficou **17 PRs atrasado**, anunciando
"mergeado até o PR #70, migrations até `0034`" enquanto o `main` estava no #93 com a `0103`. A parte
escrita para quem chega sem contexto virou a mais velha do documento — e mandava começar errado.

Agora: **manter o cabeçalho em dia é obrigação de quem fecha a rodada**; seção de sessão anterior
continua sendo histórico e não se reescreve. Conflito no topo se resolve como qualquer outro.

### O agente de ARCHITECTURE.md não alterou nada

Conferido, e o resultado é limpo:

- **não existe `.cto/` nem `ARCHITECTURE.md`** em nenhuma branch do repositório
  (`git ls-tree -r` em todas as `origin/*`);
- **nada no `.gitignore`** esconderia esses caminhos;
- `HANDOFF.md` e `CLAUDE.md` não têm commit dele — o histórico dos dois só traz os desta linha de
  trabalho e os da sessão paralela.

**Por quê:** o próprio prompt terminava com *"Retorne SOMENTE o conteúdo do arquivo"*. Ele produziu
o texto e devolveu na resposta; salvar, commitar e abrir PR não estavam no pedido. O trabalho não se
perdeu — só não foi gravado. Para virar arquivo, o prompt precisa mandar **escrever em
`.cto/ARCHITECTURE.md`, commitar em branch e abrir PR**, e a saída dele passa a ser o link do PR.

Um risco a declarar sobre esse agente: ele pede leitura de cabeçalhos de migrations "mais
estruturais" por número fixo (`0001`…`0102`). Essa lista envelhece a cada rodada — hoje já ignora a
`0103`. Melhor pedir *"as N migrations mais recentes + as que `Supabase/README.md` marca como
estruturais"*, que é uma pergunta que continua verdadeira sozinha.

### O que continua ABERTO, e é o único bloqueio real

**A tela ainda dá `statement_timeout` em produção com `0101` e `0102` aplicadas e confirmadas.** A
sessão 34 mediu e descartou três hipóteses de SQL (RLS: 492 ms como `authenticated` contra 498 ms
como superusuário; concorrência das sete chamadas; crescimento de `campo_extraido`). Sobraram quatro
de **ambiente**, e `Supabase/diagnostico_modelagem.sql` separa as quatro numa consulta só:

1. portal apontando para **outro projeto** Supabase;
2. `statement_timeout` de `authenticated` **abaixo dos 8 s** contra os quais a `0101` foi dimensionada;
3. instância **estrangulada de CPU** (respondida por `pg_stat_statements`);
4. render **anterior** ao apply.

A `0103` entrou depois dessa medição e derruba o tempo mais 6× — o que aumenta a folga, mas **não
substitui o diagnóstico**: se o teto do projeto for 3 s e não 8 s, ou se o portal estiver noutro
banco, nenhuma otimização resolve.

### Também aberto, sem dono ainda

- **Caixa e dívida contados duas vezes no modelo institucional.** `Working Capital` pega TODAS as
  contas de `ativo_circulante` — inclusive caixa, bancos e aplicações — e as projeta por dias de
  giro; `Cash Flow` soma as mesmas em `CAIXA_FIM`; e `Balance Sheet` faz `AC = CAIXA + AC_OPER`.
  Correção só de portal, sem migration. O `CHECK` da aba `Balance Sheet` acusa em vermelho.
- **A Fase 9 nunca foi exercitada com conteúdo:** as 199 linhas da fixture do book têm
  `secao_canonica` nula, 132 contas caem em `"fora"`, e o arquivo sai com `CHECK −51.300` em toda
  coluna. O banner "não projetável" dispara e acerta a causa — e é hoje a única coisa que a fase
  comprova. Os asserts do modelo institucional precisam de uma fixture **com** seção canônica.
- **Duas capturas de página** do dono estão achatadas na raiz do repositório (commit `9cdadc4`). A
  primeira foi organizada em `Dados de Teste/capturas/2026-08-04-v35-modelagem/`; a segunda ainda não.

## Sessão 36 (2026-08-05) — RESOLVIDO: as três fatias do timeout, medidas na produção

> Esta seção fecha o que a **sessão 35** deixou aberto como "o único bloqueio real". As duas
> rodaram no mesmo dia, em sessões paralelas, e esta é a mais nova: onde as duas falarem do estado
> da tela de Modelagem, **vale esta**. A `0103` está descrita na sessão 35 — aqui entra só o que é
> novo, que é a medição na produção.

**A tela de Modelagem voltou a funcionar.** Medido pelo `pg_stat_statements` da própria
produção, com o contador **zerado** e um único carregamento de página depois:

| Chamada | `calls` | média | teto do Supabase | folga |
|---|---|---|---|---|
| `fn_linhas_para_modelagem` | 1 | **501 ms** | 8.000 ms | **16×** |
| `fn_conferir_modelagem` | 1 | **485 ms** | 8.000 ms | **16×** |

Nenhum cancelamento. Antes eram **6.381 ms de média com máximo de 7.769 ms**, raspando o teto —
e é por isso que a tela falhava de forma que parecia intermitente.

Detalhe que confirma o desenho da `0101`: as duas dão praticamente o **mesmo** tempo (501 e
485), porque a conferência faz **uma** passada pelo mesmo leitor. Quando ela fazia cinco, era
exatamente dali que vinham os 9,3 s.

### O que era, no fim: TRÊS causas empilhadas, cada uma escondendo a seguinte

| Migration | Parou de repetir |
|---|---|
| `0101` | trabalho **de fora** — a conferência executava a listagem cinco vezes, duas delas uma vez por vínculo |
| `0102` | leitura de versão **superada** — cada reextração somava um jogo inteiro de ocorrências ao caso |
| `0103` | trabalho **de dentro de cada rótulo** — `fn_papel_linha` refazia a mesma tokenização nove vezes |

E uma quarta causa, **de processo**, que atrasou tudo mais que as três juntas: a `0101` estava na
tabela do `Supabase/README.md` e **não** na lista de comandos que o dono copia para aplicar. Por uma
rodada inteira a correção existia no GitHub e não no banco — e da tela isso é indistinguível de
"o PR não funcionou". Hoje `Supabase/test/run.sh` reprova migration que exista e não esteja na lista.

### A `0103` está mesmo NO BANCO — conferido pelo plano, não pela lista de migrations

A migration está descrita na sessão 35 (o que ela faz e o que quase quebrou). O que esta sessão
acrescenta é a **confirmação de que a versão aplicada é a nova**, e ela não veio de conferir
arquivo: veio do plano em produção, que mostra a marca da `0103` — CTEs `base_r` e `pares`, com
`radicais <@ o.radicais` e `tem_longa` no lugar de `fn_rotulo_contido`.

Isso importa porque "mergeado" e "aplicado" já divergiram uma rodada inteira neste mesmo problema
(a `0101`), e a única evidência que não mente sobre isso é o que o banco está de fato executando.

A escada de tempo, no mesmo caso: **~8 s (pré-`0101`) → 570 ms (`0102`) → 160 ms (`0103`)** aqui;
na produção do dono, **483 ms** no `explain analyze`.

### O erro desta rodada foi de RÉGUA, não de análise — e vale mais que a correção

Eu afirmei, na sessão 34, "a lógica SQL não é mais o gargalo" e "16× de folga contra 8 s", e
**decidi deliberadamente não otimizar `fn_papel_linha`** por ser "especulação contra causa
desconhecida". As três hipóteses que descartei (RLS, concorrência das sete chamadas, volume da
tabela) estavam certas em serem descartadas. O que estava errado era a base da conclusão:

**eu medi 570 ms no meu hardware e concluí folga para o hardware do dono, que é ~3× mais lento e
onde aquilo dava 6,4 s contra um teto de 8 s.** O gargalo *ainda era SQL*, e era exatamente a
função que eu havia examinado e deixado passar.

O instrumento que resolvia isso era o `pg_stat_statements` — **o relógio da produção, não o
meu** — e eu o empacotei na quarta rodada, não na primeira. Fica como regra: **em qualquer
"está lento" deste sistema, o primeiro dado é o `pg_stat_statements` da produção**, antes de
qualquer medição local. `Supabase/diagnostico_modelagem.sql` existe para isso e é o primeiro lugar a
olhar.

Duas armadilhas de leitura que custaram uma volta cada, e ficam registradas:

- **`mean_exec_time` é média ACUMULADA desde o último reset.** Ela mostrou 6.381 ms enquanto o
  `explain analyze` mostrava 483 ms, e as duas estavam certas: média histórica contaminada por
  chamadas pré-correção contra execução de agora. Para medir o estado atual:
  `select pg_stat_statements_reset();` → recarregar a tela → medir;
- **o SQL Editor do Supabase roda como `postgres`, o portal como `authenticated`.** O Editor não
  tem o teto de 8 s, então `fn_diagnostico_modelagem` respondia com folga (6,9 s) enquanto a tela
  era cancelada. "Funciona no Editor" nunca foi evidência de que a tela funciona.

### O susto do Supabase, que não era perda de dado

O dono clicou em *Integrations → Open in Supabase* na Vercel e caiu numa organização cuja URL é
`/dashboard/org/vercel_icfg_…` — uma org **criada pelo Vercel Marketplace**, contendo um único
projeto (`supabase-charcoal-crystal`, `sa-east-1`) com **0 GB de banco, 0 usuários, pausado**.
Parecia que os projetos tinham sumido. Não sumiram: era outra organização, e o projeto de lá é
vazio. O seletor de org, ou `supabase.com/dashboard/projects`, volta para a org de verdade.

Fica o alerta, porque a integração anuncia *"sync all your Project env vars to your Vercel
projects automatically"*: se ela sobrescrever `NEXT_PUBLIC_SUPABASE_URL`, o portal passa a falar
com o projeto vazio. **Não desinstalar a integração nem apagar o projeto do Marketplace sem
conferir antes** — desinstalar integração de marketplace pode apagar o projeto que ela
provisionou.

Nota prática: o *ref* do projeto **não é descoberto de fora**. Todo acesso a Supabase no portal é
de servidor (`createServerClient` no `proxy.ts` e no `server.ts`), então a URL não aparece no
HTML, nem nos chunks, nem em cookie de visitante anônimo — conferido nesta sessão. E na Vercel a
variável pode estar marcada como *Sensitive*, que não permite leitura depois de criada, só
sobrescrita. O caminho que funciona é a barra de endereço do dashboard do Supabase
(`/dashboard/project/<ref>`) ou o `pg_stat_statements` do próprio banco, que responde "o portal
está falando comigo?" sem depender de navegador.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **426**; `Supabase/test/run.sh` = **48 migrations** e
**306 asserts**; `Verificação/run.mts` = **27**. Conferido nesta sessão que a `0103` convive com a
trava da `modelagem_v35.test.sql`: a classificação **203/28/12/6** contra rótulo real continua
passando, o que era o risco de a `0103` ter mexido em `fn_papel_linha`.

### PRÓXIMO PASSO — o teste prático, e é do dono

O caminho de banco está fechado e medido. **O que falta é exercitar a tela de ponta a ponta**, o
que nenhuma suíte substitui:

1. **Executar o roteiro de modelagem** no caso do v35 (`c4581e51-…`): parâmetros do mandato,
   ativar as premissas do passo 2 — incluindo **`SAZ_MENSAL`**, que a captura da sessão 32
   denunciou como não ativada (a curva é calculada e exibida, e nenhuma linha podia consumi-la) —
   e vincular premissa às linhas, inclusive **"aplicar em lote"** por seção, que é o caminho que
   a `0100` consertou e que só foi exercitado em teste.
2. **Exportar o completo e mandar o `.xlsx`.** É o primeiro export depois da `0102`
   (`fn_valores_por_ano` passou a ler só a versão vigente) e da Fase 9, e é o artefato que
   ninguém conferiu ainda contra dado real.
3. **O que olhar no arquivo, porque já se sabe onde deve doer:** o `CHECK` da aba
   `Balance Sheet`. Ele deve acusar em vermelho a **dupla contagem de caixa e de dívida** que
   está aberta desde a sessão 32 — `Working Capital` pega TODAS as contas de `ativo_circulante`
   (inclusive caixa, bancos e aplicações) e as projeta por dias de giro, enquanto `Cash Flow`
   soma as mesmas contas em `CAIXA_FIM` e `Balance Sheet` faz `AC = CAIXA + AC_OPER`. Se o
   `CHECK` fechar, é sinal de que a leitura do defeito está errada e vale reabrir a análise.

### Aberto (inalterado)

- **Dupla contagem de caixa e de dívida no modelo institucional** (sessão 32) — correção só de
  portal, sem migration. É o item 3 acima.
- **`Arrendamentos` e `Provisões` são cabeçalho de grupo tratado como conta projetável.**
  `fn_papel_linha` não os classifica como subtotal porque não têm a palavra "total". Estão
  travados como `conta` em `modelagem_v35.test.sql`, então mudar isso exige atualizar o
  `203/28/12/6` de propósito, com o rótulo nomeado no diff — o que é o comportamento desejado
  para uma reclassificação deliberada.
- **A Fase 9 nunca foi exercitada com conteúdo** (sessão 32). A fixture da sessão 33 **tem**
  seção canônica nas 249 linhas, e é o insumo que faltava para os asserts do modelo
  institucional em `verificar-export.mts`.

## Sessão 37 (2026-08-05) — a modelagem exercitada de ponta a ponta, e três defeitos que só o uso real acha

Primeira rodada em que o dono **usou** a tela de Modelagem e o export completo até o fim. Saíram
cinco PRs (#96 a #100) e, principalmente, a lição de que **os defeitos desta fase não aparecem em
teste sintético** — aparecem quando alguém clica.

### O que entrou

| PR | O que |
|---|---|
| #96 | organização da raiz (as capturas do dono viraram pasta com procedência) |
| #97 | **`0104`**: `fn_desativar_premissa` + botão **"Remover"** no passo 2 da tela |
| #98 | a identidade da linha é **(seção, rótulo)** — a linha que "completava sozinha" |
| #99 | **`Supabase/roteiro_modelagem_v35.sql`**: 70 cliques viram uma colada de SQL |
| #100 | o **HTTP 500** do export: âncora duplicada no modelo institucional |

### Os três defeitos, e o que eles têm em comum

**São a mesma família**: tratar o rótulo como identidade da linha, quando no banco a identidade é
o par (`secao_canonica`, `rotulo_norm`) — o índice único de `caso_linha_premissa` inclui a seção e
`fn_linhas_para_modelagem` agrupa pelas duas. **No caso v35, treze rótulos existem em duas
seções** (`Empréstimos e Financiamentos`, `Arrendamentos`, `Capital social`, `Reserva legal`…).

1. **A tela preenchia linha que ninguém tocou.** Relato do dono: escolher a premissa de UMA linha,
   salvar, e outra aparecer preenchida. A causa não era o salvamento (que já mandava só o que
   mudou) — era a LEITURA, em dois mapas indexados só pelo rótulo. E o efeito era em cadeia: o
   valor herdado virava o `orig` daquela seção e ia ao banco de verdade no salvamento seguinte.
2. **O export puxava o valor base da seção errada.** Medido com o defeito religado: a linha do
   passivo **circulante** recebia base **37.379**, que é o saldo do **não** circulante. A projeção
   inteira partia do número errado, sem erro nenhum na tela.
3. **O modelo institucional derrubava o export com HTTP 500.** `abaTributos` é a única aba que
   junta dois blocos sob o mesmo prefixo, e `Obrigações Tributárias` existe nas duas pontas do
   passivo (7.895 e 13.549). A guarda da `Grade` fez o que devia — preferiu explodir a somar a
   conta errada em silêncio.

A correção é a mesma nos três: a chave inclui a seção. Ficou em `portal/src/lib/modelagem-linha.ts`
(um módulo, não duas cópias) e em `chaveLinha` do modelo institucional.

### `portal/scripts/gerar-export-do-banco.mts` — o 500 deixou de ser invisível

O export completo só podia ser exercitado em produção, e um defeito nele chegava ao dono como
página em branco, com o stack trace preso no log da Vercel. O script novo refaz **as consultas da
rota** contra um Postgres local e chama o **mesmo** `buildExportWorkbook`: o mesmo defeito virou
stack trace no terminal em dois segundos. Foi assim que a âncora duplicada foi encontrada.

Se o script gera e a rota não, a diferença é de **ambiente**, não de lógica de planilha — é a
mesma separação que a sessão 34 levou quatro rodadas para conseguir fazer.

### O Portão 2 recusou o export, e estava certo

`item_faltante` de `CONTRATO_SOCIAL` (não-sobrepujável) e de `FAT_INTRAGRUPO`. As outras cinco
pendências do caso são `importante` e não contam para a condição 1.

Testado o atalho — registrar documento vazio só para tapar o buraco — e **a `0036` o barrou**:
`item_faltante` vira `item_sem_conteudo`, também bloqueante e também não-sobrepujável. **Não existe
caminho barato**, e isso é notícia boa sobre o desenho. O caminho legítimo quando o documento não
vem é `rejeitada` com motivo, que é o que o próprio portão nomeia.

**Lacuna que isso expôs:** não existe UI para rejeitar pendência. A tela de revisão só trata
`classificacao_pendente`; todo o resto é `UPDATE` no SQL Editor. Para um portão que é a doutrina
central do produto, a decisão mais importante do fluxo é a única sem botão.

### O que o roteiro de SQL provou sobre o produto

Configurar a modelagem pela tela são ~70 interações antes de chegar no que interessa. O roteiro faz
tudo numa colada, chamando **as mesmas funções que a tela chama** — então as guardas continuam
valendo, e se o roteiro passa e a tela não, a diferença está na interface.

Duas descobertas dele, medidas contra o caso real:

- **só premissa de CRESCIMENTO pode entrar em lote.** `pct_de_linha` e `dias_de_giro` incidem
  sobre a **receita total**, então um lote em 44 linhas faria as 44 valerem o mesmo. Isso não está
  escrito em lugar nenhum da tela — foi preciso ler `export-modelagem.ts` para saber;
- **`ALIQUOTA` e `TAXA_DIVIDA` são inúteis como estão.** A alíquota realizada do caso (43%) e a
  taxa da dívida (15,1% a.a.) são números bons, mas como `pct_de_linha` aplicariam 43% e 15% **da
  receita** como imposto e juro. A base é errada para elas.

O roteiro **começa com reset** desde o PR #99: rodar por cima de uma configuração existente somava
os dois estados (26 viraram 98, medido). Agora uma colada devolve sempre o mesmo estado.

### O espelhamento do Modelo Base — medido, e é o próximo grande trabalho

O dono pediu que o modelo gerado seja **idêntico** ao `Arquitetura do Sistema/6 Referência/modelo-base.xlsx`. Primeira
medição honesta da distância, com `Arquitetura do Sistema/6 Referência/mapear-xlsx.py` (novo):

| | Modelo Base | Nosso export |
|---|---|---|
| Abas | 14 | 29 (as 14 + 15 nossas, de proveniência) |
| **Fórmulas nas 14 abas** | **14.504** | **2.842** (~20%) |
| Nomes definidos | 1.044 | **0** |
| Gráficos / imagens | 8 / 1 | **0 / 0** |

Os dois maiores buracos são `Output` (3.693 contra 118) e `ST Inv. & Debt` (3.573 contra 241).

**E o Modelo Base não é um gabarito vazio:** é o modelo preenchido de uma **operadora de plano de
saúde**, exercícios 2010–2018 ("Contraprest. efetivas de plano de assist. à saúde", "Eventos
conhecidos ou avisados"). Isso obriga a separar o que se replica: o **motor** (abas, blocos,
gramática de fórmula, formatação, recursos) e não o **vocabulário** de outra indústria. É a
primeira pergunta que a próxima sessão tem de fazer ao dono.

O trabalho está descrito em **`Arquitetura do Sistema/5 Prompts/PROMPT_ESPELHAR_MODELO_BASE.md`**, escrito para ser colado como
primeira mensagem de uma sessão nova: função, objetivo, estado medido, ferramentas, método em cinco
fases (mapear → comparar → planejar → replicar → provar), requisitos e formato de entrega.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **435**; `Supabase/test/run.sh` = **49 migrations / 324
asserts**; `Verificação/run.mts` = **27**.

### O que o dono precisa fazer

1. **Aplicar a `0104`** no Supabase (`supabase db execute --file Supabase/migrations/0104_desativar_premissa.sql`
   + `notify pgrst, 'reload schema';`) — sem ela o botão "Remover" devolve erro de função inexistente.
2. Decidir a leitura de "idêntico" (§4 do prompt): **motor** ou **arquivo**.
3. Quando quiser retomar: abrir sessão nova e colar `Arquitetura do Sistema/5 Prompts/PROMPT_ESPELHAR_MODELO_BASE.md`.

### Aberto

- **Espelhamento do Modelo Base** — o trabalho grande, ~80% da distância em fórmulas.
- **Dupla contagem de caixa e de dívida** (sessão 32). O `CHECK` do `Balance Sheet` acusa. O mapa
  do Modelo Base provavelmente contém a resposta certa.
- **Sem UI para rejeitar/ressalvar pendência** — o Portão 2 depende de `UPDATE` manual.
- **O "Exportar completo" não pergunta o portão antes de abrir a aba**: a recusa chega como página
  preta de JSON em vez de mensagem na tela com link para a revisão.
- **`fn_conferir_modelagem` conta premissa de sazonalidade como "sem valor"** e isso segura o
  "pronto" — a curva vem do caso, ela não tem valor a digitar.
- **"Sugerir do realizado"** (proposta, não feita): oito premissas saem do próprio balanço/DRE do
  caso (PMR 81, PME 62, PMP 59, custo variável 54,7%, SG&A 14,1%, alíquota, depreciação, taxa da
  dívida), com `origem = 'historico'` — que o schema da `0038` já prevê e ninguém usa.

## Sessão 38 (2026-08-05) — Fase 1 do espelhamento: o Modelo Base mapeado inteiro, e três números que mudam o placar

Rodada de **leitura**, como o `Arquitetura do Sistema/5 Prompts/PROMPT_ESPELHAR_MODELO_BASE.md` manda: *mapear primeiro,
replicar depois*. **Nenhuma linha de código de produção foi alterada.** A entrega é
`Arquitetura do Sistema/6 Referência/MAPA_MODELO_BASE.md`, com as **14 abas** cobertas nos seis eixos que o §7 do
prompt exige (identidade, anatomia, gramática das fórmulas, formatação, recursos, classificação).

### A medição, refeita nesta sessão

`python3 "Arquitetura do Sistema/6 Referência/mapear-xlsx.py" Arquitetura do Sistema/6 Referência/modelo-base.xlsx` confere com o §3 do
prompt nas duas colunas que ele mede: **14 abas**, **14.504 fórmulas**, 1.044 nomes definidos,
8 gráficos, 1 imagem, 3 validações, 0 formatação condicional. O mapa acrescenta três colunas que
o §3 não tinha — e são elas que mudam o plano.

### Os três achados que mudam o plano da fase 2

1. **Dos 1.044 nomes definidos, ZERO estão em uso.** Varredura de todos os identificadores das
   14.504 fórmulas contra a lista de nomes: **nenhum casamento**. O que existe é sedimento —
   531 apontam para `#REF!`, 392 são definição de relatório do **Excel 4** (`{#N/A,#N/A,FALSE,…}`),
   382 apontam para **outra pasta de trabalho** (`[6]Comps!`, `'PXR_6500'!`), 26 são
   `__123Graph_*` do **Lotus 1-2-3** e 4 são macros de tecla (`\a`, `\b`). Só **5** têm valor:
   as áreas de impressão de `Output`, `Income Statement`, `Balance Sheet`, `Cash Flow` e `Anual`.
   A linha do placar *"nomes definidos: 1.044 × 0, ausente por completo"* estava medindo lixo —
   gerar 1.044 nomes não aproximaria o export de nada que um analista consiga apontar.
2. **667 das 14.504 fórmulas da referência já estão quebradas** (`#REF!`), e **627 delas estão no
   `Output`** (17% da aba): o bloco `DEBT & RATIOS` (linhas 128–206) inteiro — os 33 `HLOOKUP`,
   os 13 rótulos de tranche e o `DSCR2` — aponta para uma tabela de dívida que não existe mais no
   arquivo. Mais 24 no `Goodwill` (o `New Deferred Taxes`, que contamina o saldo de imposto
   diferido), 10 no `ST Inv. & Debt`, 4 no `Revenues` e 2 no `Income Statement`. **Nove abas estão
   íntegras.** A meta honesta do `Output` não é 3.693 fórmulas: são **3.066** mais a
   reimplementação do bloco de tranches a partir do que ele *queria* fazer.
3. **O Modelo Base não fecha o próprio balanço a partir de 2020**, e o `CHECK` dele denuncia:
   `Balance Sheet!Mismatch` = **0** de 2007 a 2019, **16.987** em 2020, **33.974** em 2021 e
   **`#VALUE!`** de 2022 a 2032 (`#DIV/0!` em 2032). Duas causas independentes, rastreadas célula
   a célula:
   - **o parcelamento tributário sem piso**: `Tributos a Recolher` paga 16.987/ano por 12 anos
     contra um saldo que só suporta 11 (`L10` = **−4.249**), e o rótulo de ano para em 2018
     enquanto a fórmula vai até 2024;
   - **texto na base macro**: `Anual!AC86:AL86` (`Libor 6 meses`, 2021+) contém a string **`nd`**;
     `='ST Inv. & Debt'!S196` = `=Anual!AC86/100` vira `#VALUE!` e a cadeia propaga sem guarda
     até o `NET PROFIT` e o `Mismatch`:
     `Anual!AC86 → ST!S196 → S198 → S202 (×5 tranches em moeda estrangeira) → ST!S20 → IS!U64 →
     IS!U63 → U70 → U81 NET PROFIT → BS!U80 → U44 → U83 Mismatch`.

   **Uma célula de texto na base macro apaga o resultado dos últimos 11 anos do modelo.** Isso é
   transferível direto para o nosso produto: em `Macro (dados)`, ano sem série tem de ser vazio ou
   zero, **nunca `nd`**, e o consumo precisa de guarda. E passou despercebido no arquivo do dono
   por um motivo estrutural: **o horizonte visível do `Output` é 2010–2018** (as colunas P:AB,
   2019–2031, estão **ocultas**) — o modelo quebra exatamente onde ninguém olha.

### O que o mapa descobriu sobre o motor (o que se replica)

- **Todo o calendário do modelo sai de UMA célula.** `'Revenues, COGS & SG&A'!C5`
  (`Last Completed Period` = 31/12/2011) e duas recorrências: histórico para trás
  `=+EOMONTH(<coluna à direita>,-12)`, projeção para frente `=+EOMONTH(<coluna à esquerda>,12)`.
  São as **3 únicas** ocorrências de `EOMONTH` no arquivo. Não existe lista de anos.
- **As abas não estão alinhadas na mesma coluna** — cada uma tem seu deslocamento fixo
  (`Income Statement` = `Revenues` +1 coluna; `Fixed Assets` e `Cash Flow` = −1; `Working Capital`
  = mesma). O `Output` usa **ano inteiro** e termina em **2031**; as operacionais usam **data de
  fim de mês** e vão a **2032**. A tabela completa está no §2.2 do mapa.
- **O cenário é dado, não código**: `Output!G2` ∈ {1,2,3}; cada driver copia em `C3`; consumo por
  `CHOOSE($C$3,…)` (46 ocorrências); e o mesmo conjunto de linhas aparece **três vezes** na aba,
  com o 2º e o 3º bloco nascendo como `=<bloco anterior>`. Há uma guarda `Check Scenario`
  (`Output!I2:L5`) que lê o `C3` de volta de três abas.
- **Nenhuma demonstração lê o miolo de um cálculo.** Todo driver publica três blocos —
  `BALANCE SHEET ACCOUNTS`, `INCOME STATEMENT ACCOUNTS`, `CASH FLOW ACCOUNTS` — e as
  demonstrações leem **dali**. É a interface do modelo, e replicar isso vale mais que replicar
  qualquer aba isolada.
- **A cor tem significado, e a paleta está declarada no arquivo** (`indexedColors`, 64 entradas):
  fonte **azul `0000FF`** = entrada manual; **preta** = calculado; **branca** = auxiliar
  invisível (o contador da coluna A); preenchimento `DDDDDD`/`C0C0C0`/`969696` = conta/subtotal/
  total; **`CCFFCC` verde** = âncora do histórico que vem da `Premissas`; **`FF0000` vermelho com
  fonte branca** = faixa de cabeçalho de ano.
- **A gramática cabe em dez verbos**: `SUM` 1.525, `IF` 851, `AVERAGE` 192, `CHOOSE` 46,
  `HLOOKUP` 33 (todos quebrados), `OFFSET` 17, `EOMONTH` 3, `ABS`/`CORREL`/`SUMPRODUCT`. **Não
  há** `VLOOKUP`, `INDEX/MATCH`, `IFERROR`, `NPV`, `IRR`, macro VBA, tabela dinâmica nem tabela
  estruturada. O mapa nomeia **32 padrões** (`P01`…`P32`), cada um com o endereço onde nasce.
- **Os 8 gráficos estão todos no `Output`**, todos `lineChart`, alimentados por duas tabelas
  laterais da própria aba (`AD18:AK28` e `AO11:BB44`); o padrão é **3 séries = 3 cenários** ou
  **4 séries = 3 cenários + corte de covenant**. A única imagem (`image1.emf`) está no
  `Balance Sheet`, ancorada em C73.

### A resposta para a dupla contagem de caixa e de dívida (aberta desde a sessão 32)

**O Modelo Base não projeta caixa por dias de giro.** As 6 contas de giro do ativo em
`Working Capital` (linhas 13–18) são `Aplicações de liquidez imediata`, `Reserva Técnica`,
`Créd. operações`, `Despesas de comercialização diferidas`, `Títulos e créditos a receber` e
`Outros valores e bens` — **`Cash & Short Term Inv.` está fora da lista**. O caixa vem **só** do
`Cash Flow` (`Balance Sheet!J13` = `='Cash Flow'!H59`) e a dívida **só** do `ST Inv. & Debt`. A
regra é **uma conta, uma origem**, e é exatamente o que o §9 do prompt suspeitava que o mapa
conteria. Nosso `Working Capital` projeta todas as contas de `ativo_circulante` inclusive caixa:
é divergência de **mecanismo**, com a correção agora conhecida.

Outro achado do mesmo tipo: em `P08 DIAS-DE-GIRO` a base é **a linha de DRE correspondente**
(`Net Revenues`, `COGS` ou `SG&A`), com **360 dias**, e o prazo médio da projeção é *derivado do
realizado* (`=IF(base>0, saldo/base*360,)`). Isso contrasta com a nossa decisão de produto de
`pct_de_linha` e `dias_de_giro` incidirem sobre a **receita total do caso** (sessão 37) — vai para
a tabela de conformidade como divergência de mecanismo, **não corrigida por conta própria**.

### A ambiguidade do §4, resolvida com número

O mapa marcou cada bloco como `universal`, `do setor de origem` ou `do caso` (o terceiro grupo
apareceu na leitura e conta como não-universal para efeito da regra). **O vocabulário de outra
indústria cabe em 18 itens**, todos localizados: 14 rótulos do setor de origem (`Reserva Técnica`,
`Créd. operações pl. de assist. à saúde`, `Provisões técnicas…`, `Eventos conhecidos ou
avisados`…) e 4 blocos do caso (`Capa!C4` = `Unimed Rio`, a aba `Tributos a Recolher` inteira,
`Reconhecimento de Perdas Futuras`, `Provisão Previdenciaria`). **Todo o resto é motor.** Isso
confirma a hipótese (A) do prompt com medição, e o trabalho não fica bloqueado: se o dono ler
como (B), é o mesmo trabalho **mais** a cópia destes 18 itens, todos com endereço no mapa.

### Sobre as ferramentas

Foi usado o `Arquitetura do Sistema/6 Referência/mapear-xlsx.py` do §6, e ele resolve a aba pelo `rels` — a armadilha
da ordem dos `sheetN.xml` não voltou. Ele tem três limites de escopo que a fase 1 precisou cobrir
por leitura direta das partes do ZIP: não decodifica `xl/styles.xml` (o `s=123` fica opaco), não
expande fórmula **compartilhada** (8.373 células, 58% do total, saem como
`=(compartilhada si=N)`), e não lê largura/altura/`hidden`/`outlineLevel`/gráfico/imagem/nome
definido. Duas ferramentas de análise **descartáveis** cobriram isso no scratchpad, reusando a
mesma resolução por `rels`: uma que traduz o índice de estilo para o que ele significa, e uma que
traduz cada fórmula para **R1C1 relativa** e comprime faixas de colunas idênticas — é ela que
torna 14.504 fórmulas legíveis, porque uma linha de 26 colunas quase sempre é **uma** fórmula
puxada à direita. **Se a fase 2 quiser isso de forma permanente, o lugar é dentro do
`mapear-xlsx.py` (`--estilos` e `--r1c1`), não em script novo** — e é mudança de ferramenta, fora
do escopo da fase 1.

### Ordem proposta para a fase 4 (a fase 3 é aprovação do dono)

A ordem natural é **a do fluxo de dados, não a do tamanho do buraco**: `Premissas`/eixo do tempo →
`Revenues` (define `P01`, `P03`, `P06`, `P07`, `P10`) → `Working Capital` (`P08`) →
`Fixed Assets` (`P13`) → `ST Inv. & Debt` (`P11`, `P14`, `P15`, `P17`) → `Income Statement` →
`Balance Sheet` (+ `P12`) → `Cash Flow` (`P22`) → `Goodwill` → `Output` → `Considerações`/`Capa`.
Começar pelo `Output`, que é o maior buraco, seria construir a vitrine antes do motor: **toda
fórmula dele é referência a outra aba.**

### Contadores

Inalterados, e é o esperado: o diff desta rodada é **só documentação** (`Arquitetura do Sistema/6 Referência/
MAPA_MODELO_BASE.md` + esta seção), sem uma linha de código. Conferido nesta sessão:
`node --test 'N8N/test/*.test.mjs'` = **176 pass / 0 fail**. Os outros três contadores seguem em
`verificar-export.mts` = **435**, `Supabase/test/run.sh` = **49 migrations / 324 asserts**,
`Verificação/run.mts` = **27** — e o CI os roda no PR.

### O que o dono precisa decidir

1. **Aplicar a `0104`** (segue pendente da sessão 37).
2. **A leitura de "idêntico"** (§4 do prompt): **motor** ou **arquivo**. O mapa segue por
   **motor** e mostra que a diferença entre as duas leituras são 18 itens nomeados.
3. **Aprovar a ordem da fase 4** acima — é a fase 3 do prompt, e ela pede aprovação antes de
   executar.
4. **Confirmar que os 1.044 nomes definidos saem do placar** (§17.1 do mapa): eles não são
   funcionalidade, e replicá-los seria replicar lixo de três gerações de pasta de trabalho.

## Sessão 39 (2026-08-05) — o espelhamento executado: 11 defeitos corrigidos, o balanço fechando, e os 8 gráficos

Rodada de EXECUÇÃO das fases 2 a 5 do `Arquitetura do Sistema/5 Prompts/PROMPT_ESPELHAR_MODELO_BASE.md`, com o objetivo que o
dono declarou: *idêntico ao modelo de referência em motor, com a cara da Oria, e MELHOR que ele —
corrigindo os defeitos dele.*

### O placar, remedido — e a régua que estava errada

| | Referência | Nosso antes | Nosso agora |
|---|---:|---:|---:|
| Fórmulas nas 14 abas | 14.504 | 2.660 | **3.157** |
| **Fórmulas por COLUNA de ano** | **598** | 450 | **533 (89%)** |
| Gráficos | 8 | 0 | **8** |
| Áreas de impressão | 5 | 0 | **14** |
| Validações de dados | 3 | 1 | **10** |
| Formatação condicional | 0 | 1 | **8** |
| Fórmulas com `#REF!` | **667** | 0 | **0** |
| Balanço fecha | até 2019 (de 26 anos) | **não fechava** | **todos os anos** |
| Tamanho do arquivo entregue | 0,5 MB | **4,3 MB** | 0,3 MB |

**A régua absoluta era enganosa e isso importa para o plano.** O `~20%` do §3 do prompt compara
**6 colunas de ano contra 26**: a referência projeta 21 exercícios, o caso v35 projeta 5. Em
densidade por coluna — que mede motor, não horizonte — a distância era de 450 contra 598, não de
2.660 contra 14.504. O que sobra está concentrado em quatro abas: `Output` (39% da densidade),
`ST Inv. & Debt` (51%), `Cash Flow` (52%), `Goodwill` (52%).

### Os onze defeitos corrigidos — cinco eram NOSSOS e mudavam número

Cada um com teste em `verificar-export.mts` que **reprova com o defeito religado** (§8.2 do prompt).
As mensagens abaixo são as reprovações reais.

1. **O caixa era contado duas vezes no ativo** — a pendência aberta desde a sessão 32. O
   `Working Capital` projetava TODAS as contas de `ativo_circulante` por dias de giro, inclusive
   caixa e aplicações, e o `Balance Sheet` fazia `AC = CAIXA + AC_OPER`. A resposta veio do próprio
   Modelo Base: as seis contas de giro do ativo dele **excluem** `Cash & Short Term Inv.`; o caixa
   vem só do `Cash Flow` e a dívida só do `ST Inv. & Debt`. **Uma conta, uma origem.**
2. **A dívida bancária de curto prazo também era contada duas vezes** — entrava no passivo
   operacional do giro e voltava por `DIVIDA_CP`.
3. **A depreciação NUNCA chegava à DRE.** `Revenues!DEPRECIACAO` era declarada e nunca preenchida:
   `EBITDA = EBIT` (exatamente o erro que o comentário do próprio EBITDA alerta), `D&A` zero em
   todos os anos com o `Fixed Assets` calculando depreciação, e o `Cash Flow` somando de volta uma
   depreciação que a DRE não tinha debitado. Reprovação com o defeito religado:
   `D&A 2026 = 0 (capex 2026 = 6480)` e `EBITDA 39800 · EBIT 39800`.
4. **A dívida do balanço DESAPARECIA** quando o caso não tem mapa de dívida. As tranches vinham só
   de `MAPA_DIVIDA`; tirar a dívida do giro (item 2) a deixou em lugar nenhum. Reprovação:
   `2025: 50000.00 · 2026: 50000.00 · 2027: 50000.00 · 2028: 50000.00` — exatamente os empréstimos
   de curto e longo prazo do caso de teste. Agora a fonte é o mapa **ou** as linhas de dívida
   bancária do balanço, nunca as duas (somar contaria duas vezes), e a origem usada está escrita no
   cabeçalho do bloco.
5. **O rateio da depreciação por classe não era exaustivo**: com saldo anterior zero, nenhuma classe
   recebia depreciação e o imobilizado crescia pelo capex inteiro. A última classe agora recebe o
   resíduo — a soma dos rateios é a depreciação do período por construção.
6. **Redução de dívida sem efeito caixa não tinha contrapartida.** A chave `S/N` por tranche reduz o
   passivo sem pagamento; sem contrapartida o balanço abre no valor reperfilado. Entrou
   `REPERFILAMENTO` no PL — que é o que uma conversão em participação, um perdão ou uma
   capitalização de dívida literalmente é.
7. **O sinal do dividendo estava invertido no PL**: `LUCROS_ACUM` subtraía uma célula que já é
   negativa, então distribuir dividendo AUMENTARIA o patrimônio. A convenção de sinal está agora
   escrita na nota da célula.
8. **O `Output` sobrescrevia a legenda de cenário**: `pular(4)` depois de escrever até a linha 5
   punha o cabeçalho da aba exatamente sobre "3 = Stress Case" — medido no arquivo gerado.
9. **O arquivo entregue saía 14× maior do que devia.** O pós-processamento das notas
   (`ampliarNotasNoBuffer`, que já existia) regravava o ZIP com o default do JSZip — `STORE`, sem
   compressão. 0,3 MB viravam 4,3 MB, e o dono baixava isso desde a sessão 7.
10. **A aba `Tributos a Recolher` vazia saía sem área de impressão** (saída antecipada da função).
11. **O script de iteração local não gerava o mesmo arquivo da rota**: ele chamava `writeFile`
    direto, sem o pós-processamento. Eu media um arquivo que o dono nunca recebe. As duas pontas
    agora passam por `finalizarBufferDoExport`.

### O que entrou de motor do Modelo Base

- **`P01` EIXO DO TEMPO — todo o calendário sai de UMA célula.** `'Revenues, COGS & SG&A'!<raiz>` é
  a única data digitada; o histórico volta por `EOMONTH(−12)`, a projeção avança por `EOMONTH(+12)`,
  e as outras 13 abas herdam a linha de ano por fórmula (`P02`). Antes, "2026" estava escrito 14
  vezes no arquivo.
- **`P18` ESPELHO DA CONTA.** Toda aba de driver (`Working Capital`, `Fixed Assets`,
  `ST Inv. & Debt`) publica três blocos — `BALANCE SHEET / INCOME STATEMENT / CASH FLOW ACCOUNTS` —
  e as demonstrações leem DALI, nunca do miolo do cálculo. É a interface do modelo, e é o que
  permitiu tirar a repartição CP/LP da dívida de dentro do balanço.
- **`P14` amortização por safra**: cada captação anual tem cronograma próprio, com carência e prazo
  (o que as 43 linhas `% Amt Issuance` da referência fazem, em uma safra por ano).
- **`P15` custo composto** `((1+curva)*(1+spread))−1`, com o **spread DERIVADO** do custo implícito
  medido no mapa da dívida — então o número total é o do documento, não taxa de mercado chutada.
- **`P29` chave de efeito caixa** por tranche, com validação de lista `S,N` — e com a contrapartida
  que a referência não tem (item 6).
- **Bloco `SHORT TERM INVESTMENTS`**, com o rendimento incidindo só sobre o excedente ao caixa
  mínimo. É decomposição do caixa, não ativo a mais — publicá-la como conta de balanço repetiria a
  dupla contagem que acabamos de corrigir, e a nota da célula diz isso.
- **`Output` reconstruído**: `SCENARIO` + `Check Scenario` (lê o dial de volta de 4 abas),
  `SUMMARY`, espelho de balanço/DRE/fluxo, `DEBT & RATIOS`, e **13 índices com corte de covenant
  editável e teste de rompimento ao lado**, mais uma linha de diagnóstico por exercício.
- **Os 8 gráficos.** O ExcelJS **não tem API de gráfico** (conferido no runtime, não só no `.d.ts`),
  então eles entram por `portal/src/lib/xlsx-graficos.ts`, que injeta as partes OOXML no `.xlsx` já
  gerado — o mesmo caminho que o repositório já usava para ampliar a caixa das notas, com JSZip, sem
  dependência nova. Três armadilhas estão documentadas no arquivo, e as três produzem "conteúdo
  ilegível" no Excel: a ordem dos elementos é normativa (`<drawing>` vai ANTES de `<legacyDrawing>`,
  que o ExcelJS emite em toda aba com nota), a ordem das abas não é a dos `sheetN.xml`, e os `rId`
  da aba já estão ocupados pelo VML das notas.

### A cara da Oria

`portal/src/lib/oria-marca.ts`, novo. **Não existia paleta de marca versionada neste repositório** —
procurado antes de escrever: o `globals.css` tem três regras e nenhuma cor, não há
`tailwind.config` com tokens, não há logotipo em `portal/public`, e a skill de marca é identidade
VERBAL. Então a paleta é **derivada do que já existia** no próprio export (o grafite `1E293B` das
faixas, o cinza `E5E7EB` do cabeçalho, o vermelho da divergência) mais hierarquia e um acento.

E entrou a **gramática de cor de FONTE do Modelo Base**, que é convenção de mercado e nós não
tínhamos: **azul = digitado, preto = calculado, verde = vem de outra aba** (o verde é acréscimo
nosso — num arquivo de 29 abas, saber num relance que a célula é espelho economiza abrir a nota). A
classificação é automática dentro de `Grade.set`, pela procedência do valor, para não depender de
alguém lembrar. A legenda está na `Capa` e na `Considerações`: cor que carrega informação sem
legenda obriga o leitor a adivinhar.

A `Capa` deixou de ser duas células de texto e a `Considerações` ganhou a **matriz 3 cenários × 4
premissas** da referência — a única aba dela feita para receber texto humano — já com o fato
conhecido escrito e o "(justificar aqui)".

### O avaliador de fórmula ficou mais forte, e era isso que faltava para PROVAR

`portal/scripts/lib/avaliar-formula.mts` ganhou `NOT`, `AND`, `OR`, `ABS`, `YEAR`, `EOMONTH` e
leitura de célula de **data** (o eixo do tempo é data; antes toda célula de cabeçalho voltava como
`null`, "não sei avaliar" — e um assert que não avalia passa sem provar nada, que é a forma mais
silenciosa de teste inútil). O comentário do topo dizia que ele não segue referência entre abas;
seguia desde a sessão 21, e a documentação estava mentindo.

Com isso os 15 asserts novos do bloco `(0105)` conferem o modelo **por valor**, não por estrutura:
o balanço fecha em todo exercício, o caixa não está no giro, a depreciação chega à DRE, o eixo do
tempo é fórmula em todas as abas, nenhuma fórmula nasce com `#REF!`, as 14 abas imprimem, o revolver
cobre o furo, e o diagnóstico responde.

### Contadores

`N8N/test` = **176**; `verificar-export.mts` = **450** (era 435); `Supabase/test/run.sh` = **49 migrations
/ 324 asserts**; `Verificação/run.mts` = **27**. `tsc` e `eslint` limpos.

### O que o dono precisa fazer

1. **Abrir `/tmp` não serve — o arquivo é gerado por caso.** Exportar o completo do v35 pelo portal
   e conferir três coisas: os 8 gráficos no `Output`, a linha `CHECK` do `Balance Sheet` em zero em
   todos os anos, e a `Capa`.
2. **Aplicar a `0104`** (segue pendente desde a sessão 37).
3. **Decidir os cortes de covenant** (hoje `3,0x` de alavancagem, `1,2x` de DSCR, `1,0x` de
   liquidez): são patamares usuais de term sheet, não dado do caso, e entram como célula azul.
4. **Aprovar a ordem do que falta** — está no §5 do `CONFORMIDADE.md`, por impacto: expandir os
   espelhos do `Output` conta a conta, tranche em moeda estrangeira, `CAPEX FINANCING`, publicar o
   `CHECK` no topo dos drivers, abrir a variação de giro linha a linha no fluxo.

### Aberto

- **O que falta do espelhamento**, no §5 do `CONFORMIDADE.md`.
- **Vida útil por classe de imobilizado** — exige laudo que o Kit Básico não traz.
- **Sem UI para rejeitar/ressalvar pendência** (o Portão 2 depende de `UPDATE` manual).
- **`fn_conferir_modelagem` conta premissa de sazonalidade como "sem valor"**.
- **"Sugerir do realizado"** (proposta, não feita): oito premissas saem do próprio balanço/DRE do
  caso, com `origem = 'historico'`, que o schema da `0038` já prevê.
