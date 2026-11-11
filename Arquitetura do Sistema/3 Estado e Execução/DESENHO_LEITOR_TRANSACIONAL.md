# Desenho — Leitor transacional por código

**Data:** 11/11/2026 · **Conta:** Claude Oria 2 · **Status:** PROPOSTA, aguardando aprovação do dono.

## REVISÃO APÓS A PESQUISA (11/11/2026) — vale por cima do resto deste arquivo

Foram três pesquisas em fontes primárias: engine de leitura, infraestrutura e custo, IA só para a estrutura. O que mudou:

| Ponto | Antes | Agora | Por quê (fonte) |
|---|---|---|---|
| **Engine** | `exceljs` 4.4.0 em streaming | **DuckDB 2.0 LTS** pelo binding `@duckdb/node-api`: `read_csv` e `read_xlsx` (uma aba por chamada, `all_varchar=true`, `range` quando o cabeçalho não está na linha 1); grava no Postgres por `ATTACH` (o `INSERT` vira `COPY` binário) | exceljs sem release desde out/2023, 376–730 MB de pico com 1M linhas. DuckDB: MIT, LTS até out/2027, CSV com memória quase constante. duckdb.org/2026/10/21/announcing-duckdb-200 · duckdb.org/docs/2.0/core_extensions/excel.html |
| **Memória do xlsx** | "teto no sharedStrings" | Mantido e obrigatório. **Nenhuma** engine (DuckDB, calamine, exceljs, SheetJS, xlsx2csv) lê xlsx com memória constante: todas carregam a tabela de strings inteira (conferido no código de cada uma). Uma aba vai até 1.048.576 linhas, então 10M chegam como CSV ou como várias abas | support.microsoft.com, "Excel specifications and limits" |
| **Datas 1904 e células mescladas** | não previsto | O DuckDB **não** trata `date1904`: uma planilha nesse sistema sairia 1.462 dias deslocada sem erro nenhum. Também não preenche mescladas. O worker lê `xl/workbook.xml` e `<mergeCells>` do zip (`Leitor/lib/zip.mjs`), corrige 1904 em SQL e propaga as mescladas do cabeçalho e da coluna agrupadora | código do duckdb-excel (`read_xlsx.cpp`) |
| **Onde roda** | Fly.io sempre ligado (US$ 6/mês) | **Fly Machine em `gru`, ligada só quando há trabalho** (a máquina é iniciada pela API ao enfileirar e para quando a fila esvazia; centavos por mês). Alternativa: Cloud Run Jobs em `southamerica-east1` (vira zero sozinho, cabe no nível grátis, setup do GCP mais pesado). Fora: PikaPods (não aceita imagem própria), Render e Railway (sem região no Brasil), Lambda (15 min), Edge Functions (256 MB e 2 s de CPU), GitHub Actions (dado de cliente em runner nos EUA) | fly.io/pricing · cloud.google.com/run/pricing · docs.pikapods.com/faq/apps · supabase.com/docs/guides/functions/limits |
| **Plano do Supabase** | Pro só para os 10M | **Pro já** (US$ 25/mês, com a Micro coberta pelo crédito). No Free: arquivo até 50 MB (um CSV de 400 mil linhas tem ~50 MB), disco de 2 GB que fica somente leitura a 95%, e o projeto pausa após 1 semana parado. Para os 10M: compute Small (+US$ 5 líquido) e o **Spend Cap desligado** para o disco passar de 8 GB | supabase.com/pricing · supabase.com/docs/guides/platform/database-size |
| **Conexão de carga** | pooler de sessão | Confirmado: **pooler em modo session (5432)**, nunca o transaction (6543). O Supavisor 2.10 corrigiu COPY que "deixava o cliente pendurado" | supabase.com/docs/guides/database/connecting-to-postgres |
| **Acesso ao Storage** | chave `service_role` no worker | **URL assinada de curta duração** gerada por quem enfileira. O worker não recebe chave do Storage. As chaves legadas `service_role` serão descontinuadas até o fim de 2026 | supabase.com/docs/guides/api/api-keys |
| **Fila** | tabela própria + `for update skip locked` | Mantida a tabela própria: ela já carrega as colunas da regra 7. O pgmq (Supabase Queues) foi avaliado e serviria, mas seria uma segunda fonte de estado. O pg_cron varre leitura sem batimento | supabase.com/docs/guides/queues |
| **Destino de 10M** | tabela única, sem partição na v1 | Mantido na v1. Para 10M: carregar em tabela solta sem índice, criar índice e `CHECK`, depois `ATTACH PARTITION` por mandato; apagar um mandato vira `DROP` da partição | postgresql.org/docs/current/populate.html |
| **IA no mapeamento** | 1 chamada por aba com amostra | **Regras primeiro, IA só no que sobrar.** Cabeçalho por pontuação (estilo Pytheas: 95,6% dos arquivos certos, sem LLM); total por fórmula `SOMA` (prova) ou por soma conferida; "Valor" × "Saldo" resolvido pelo **teste do saldo corrido**. Visão comprimida para a IA: topo, meio, fim, candidatas a total com vizinhança k=4 (SheetCompressor), perfil por coluna e até 10 valores distintos (Magneto). **Duas chamadas** que precisam concordar nos campos críticos. Opção `indeterminada` em todo enum (escala para revisão em vez de chutar). **Template por assinatura de cabeçalho**: o mesmo ERP não chama a IA de novo, mas o template só se aplica se as guardas passarem e só é gravado depois de uma importação conciliada (padrão Flatfile/OneSchema/Osmos) | arxiv.org/abs/2407.09025 · arxiv.org/html/2412.08194 · vldb.org/pvldb/vol13/p2075 · flatfile.com/docs/plugins/automap |
| **Guardas** | G0–G4 | + saldo anterior + Σ movimento = saldo final (extrato/razão); exclusividade débito/crédito por linha; alvo único por coluna; concordância das duas chamadas; taxa de parse ≥ 99,5% (antes 98%) | — |

**Lacuna declarada:** nenhum benchmark publicado cobre planilha de ERP brasileiro. Os números de precisão acima são de outros domínios. O primeiro passo da F1 é medir a heurística sozinha nas planilhas reais da AMO antes de pôr a IA.

**Custo mensal:** (a) hoje, ~400 mil linhas: **~US$ 25** (Supabase Pro; worker ~US$ 0). (b) Meta de 10M: **~US$ 30–45** (Pro + Small + disco). Se consultas de FP&A sobre 10M ficarem lentas, a Large custa ~US$ 125/mês no total.

## Por que existe

A extração de hoje manda o conteúdo para a IA em blocos e grava contas em `campo_extraido`. Esse caminho não escala para lançamentos.

Medido em 11/11:
- O 2º lote da AMO ("Amobeleza teste 2", execução n8n 9653) tinha 68 documentos. O orçamento do lote o recusou ANTES de gastar: 1.828 chamadas de IA, ≈ US$ 160,89, contra o teto de US$ 3.
- A causa foram 6 planilhas de contas a pagar e a receber, linha a linha. Juntas têm ~389 mil linhas com número.
- O pod do n8n usa ~600 MB parado, mais ~50× o tamanho do arquivo (`N8N/lib/custo.mjs` ~l.620). Com 2 GB, ele caiu num lote de 80 MB (execução 9650, `crashed`). Hoje tem 4 GB.

## Decisões do dono (11/11)
1. **Meta:** ≥ 10 milhões de linhas sem quebrar. Quando a IA custar absurdamente, a extração é por código.
2. **Onde roda:** num serviço novo, fora do n8n. Ele lê do Storage em fluxo e grava em lote no Postgres. O n8n só enfileira.
3. **O que guarda:** cada lançamento e o resumo. Lançamento numa tabela própria, rastreável até a aba e a linha do arquivo. O book recebe o resumo calculado por SQL. A IA só mapeia as colunas: 1 chamada por aba.
4. **Prioridade:** agora, antes da P12.

## Arquitetura

```
portal ──► n8n: Form → Preparar → … → Medir Documento
                                         │
                              Separar Transacional (novo)
                     formato xlsx/csv nos BYTES  E  custo estimado ≥ US$ 0,50
                                         │
             sim ─► Registrar Documento ─► Enfileirar Leitura (ramo terminal, Postgres)
             não ─► caminho atual (IA)
                                         │
                       tabela leitura_transacional (fila)
                                         │
             worker Node (Fly.io gru, 1 GB) — polling a cada 10 s
             reservar → baixar do Storage (SHA-256 confere) → perfilar em fluxo
             → IA mapeia colunas (cabeçalho + 20 linhas + amostra de 30 + perfil)
             → guardas G1 → COPY em lotes de 250 mil → fn_concluir_leitura (G2, G3, resumo)
```

**O critério do desvio** é uma função pura, `N8N/lib/rota-transacional.mjs`, que reusa `estimativaDoDocumento` (`custo.mjs` ~l.1114). É a mesma conta do orçamento: uma segunda estimativa divergiria sem erro. O nome do arquivo nunca decide nada.

## Guardas (cada uma medida não-vazia, regra 2)
| Guarda | O que confere | Quando roda |
|---|---|---|
| G0 | SHA-256 do arquivo baixado = `documento_versao.hash` | antes de ler |
| G1 | Tipo das colunas: valor e data parseiam no formato declarado em ≥ 98%; datas plausíveis; natureza e status dentro das listas declaradas; a contraparte não é numérica | sobre o perfil, antes de gravar |
| G2 | Linhas rejeitadas ÷ lidas ≤ 0,5% | no fim da carga |
| G3 | Soma em centavos = total impresso no arquivo. Sem total, declara `sem_total_no_arquivo` e nunca "conferido" | no fim da carga |
| G4 | Zero linhas de dado reprova | no fim da carga |

Os limiares (98% e 0,5%) serão fixados com o número medido na AMO.

**Mapeamento duvidoso** vira leitura `reprovada`, nenhuma linha vigente, e uma pendência nova:
- `leitura_mapeamento_duvidoso`;
- `leitura_conferencia_falhou`.

Nunca vira `extracao_falhou`. Esse tipo devolveria o documento à IA pela fila da 0232.

## Dados (migrations 0272 em diante)
- **`leitura_transacional`** — a fila e o estado: pendente → reservada → perfilando → mapeando → carregando → conferindo → concluida | reprovada | falhou.
  - A regra 7 vira coluna: linhas lidas, gravadas, rejeitadas (por motivo e com exemplos), vazias e de total; soma; total impresso; controle.
  - Check: `concluida` só quando a aritmética fecha.
  - Há também a tabela por aba e `mapeamento_colunas` (versionado, com custo).
- **`lancamento_transacional`** — PK `(leitura_id, aba, linha)`. Colunas: datas, `valor_centavos`, natureza P/R, status L/A, contraparte, documento, parcela, entidade (texto do arquivo, sem vínculo fabricado).
  - Tamanho: ~2 GB para 10M de linhas, ~70 MB para a AMO.
  - Sem particionamento na v1.
- **`lancamento_transacional_resumo`** — calculado em `fn_concluir_leitura`: aging, top 50 contrapartes e entidade × mês.
  - É uma tabela pequena, e não uma view sobre 10M de linhas: o `statement_timeout` do `authenticated` é de 8 s (0101).
- **Papel `leitor_transacional`** com GRANT mínimo. O dono define a senha à mão.
- **`fn_saude_leitor()`** separa "worker parado há X min" de "fila vazia".

**Idempotência:** o mesmo arquivo cai na mesma `documento_versao` (0026), e o índice único parcial torna o enfileiramento um no-op. Se o worker cair no meio, `delete where leitura_id` e recarrega.

## Worker (`Transacional/`, diretório novo da Claude Oria 2)
- **Base:** Node 22, ESM. Lê xlsx com o `exceljs` 4.4.0 em modo fluxo, e csv com o `@fast-csv/parse`. Os dois já estão no lock do portal (degrau 5).
- **Escrita:** COPY pelo `psql` em processo filho, no mesmo padrão do `Leitor/ler.mjs`.
- **Reuso por import, sem editar:** `Leitor/lib/zip.mjs` e `Leitor/lib/campos.mjs`, da Claude Pessoal; `N8N/lib/provedor.mjs` e `N8N/lib/custo.mjs`. A suíte `Transacional/test` entra no CI e avisa se uma mudança neles quebrar o worker.
- **Memória:** teto de `--max-old-space-size=384` numa máquina de 1 GB.
  - **Prova:** pico de RSS com 10M ≤ 1,15 × pico com 1M, e < 512 MB.
  - **Exceção:** o `sharedStrings` do xlsx cresce com a quantidade de strings distintas. Acima de ~64 MB descomprimidos (a medir), a leitura é recusada com motivo: "exporte em CSV".
- **Hospedagem:** Fly.io, região `gru`, a mesma do Supabase (`sa-east-1`), por ≈ US$ 6/mês. A alternativa é o Render, de US$ 7 a US$ 25/mês. O PikaPods só roda apps de catálogo (a conferir).

## Fatias
| # | Entrega | Pronto quando |
|---|---|---|
| **F1** | Migration 0272 + `Transacional/ler.mjs` local (perfil, IA, G0–G4, COPY no `tdf_test`) | As 6 planilhas da AMO: a aritmética fecha em cada uma; a soma confere ou o arquivo é declarado sem total; ~389 mil linhas; resumo impresso; IA ≤ US$ 0,20; pico de RSS medido |
| **F2** | Escala: gerador + medição de 1M, 5M e 10M de linhas; teto do `sharedStrings` | Memória plana pelo critério acima; tempo de 10M registrado |
| **F3** | Worker em produção: fila, papel, GRANTs, sonda, Dockerfile, Fly | Leitura concluída em produção; `kill -9` no meio retoma sem duplicar; `fn_saude_leitor` acusa o worker desligado |
| **F4** | Desvio no n8n (arquivos ≤ 15 MiB) + republicação | O lote de 68 da AMO passa no orçamento (≤ US$ 3), e os 6 são desviados e concluídos |
| **F5** | `fn_resumo_transacional_do_caso` + especificação da aba do book (implementação da Claude Oria em `export.ts`) | Os totais da aba batem com o SQL |
| **F6** | Arquivos > 15 MiB: o portal envia direto ao Storage (TUS) e enfileira sem passar pelo n8n | 10M de linhas de ponta a ponta em produção. **Exige Supabase Pro** |
| F7 | Opcional: tela para revisar o mapeamento | — |

## O que o dono precisa saber e fazer
1. **Plano do Supabase.**
   - O repositório diz plano gratuito (`portal/README.md` ~l.236), e a API de gerenciamento não informou o plano.
   - O banco tem hoje **109 MB** (medido em 11/11). O teto do gratuito é 500 MB, então a AMO cabe (+70 MB).
   - **10M de linhas (~2 GB) só cabe no Pro**, por ~US$ 25/mês. O Storage gratuito também limita cada arquivo a 50 MB.
2. **Os originais das 6 planilhas não estão no bucket.**
   - O lote foi recusado antes do upload. Os 115 documentos que entraram têm original, mas estes 6 não.
   - A F1 precisa que o dono os mande. Pode ser por aqui, na sessão, ou por outro caminho.
3. **Na F3, o dono cria à mão:**
   - a conta e o app no Fly;
   - os segredos `DATABASE_URL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` e a chave da IA;
   - a senha do papel `leitor_transacional`;
   - o token do Fly no GitHub.

## Riscos e o que este desenho NÃO resolve
- **Versões do mesmo arquivo.** Os nomes da AMO sugerem versões ("…_V2", "… v2"). As duas seriam somadas no resumo do caso. A v1 resume por leitura e mostra lado a lado; a deduplicação entre arquivos fica para uma fatia futura.
- **Arquivos ≤ 15 MiB continuam caros na memória do n8n.** O n8n lê o arquivo inteiro antes de desviar. Isso dura até a F6.
- **Fora do escopo:** `xls` (BIFF) e PDF com lançamentos. Esses continuam na IA.
- **A chave `service_role` mora no worker,** com a mesma confiança do n8n.
- **O custo do mapeamento não aparece no `lote_execucao`.** Ele fica na leitura.
- **O aberto de CP e CR não é cruzado com o saldo de fornecedores e clientes do balanço.** É o próximo valor natural, da Claude Oria.
- **Ainda não medido:** vazão do COPY até `sa-east-1`, vazão do `exceljs`, limiares de G1 e G2.
