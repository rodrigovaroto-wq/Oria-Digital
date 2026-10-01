# Camada N8N — Fatia 1 (E1 — Ingestão + E2 — Extração-sombra + E3 — Reconciliação Classe A)

O N8N é o **orquestrador stateless** (Arquitetura do Sistema/1 Visão e Doutrina/02, trava de stack nº 1): recebe o upload em lote,
classifica cada arquivo e chama as funções do Postgres (`Supabase/migrations/0004-0010`) que cuidam
do estado. A ingestão é feita **pelo próprio N8N** (Form Trigger) — sem Vercel nesta fatia.


## Reportar erro — ligue o Error Workflow (passo do dono, uma vez)

O `workflow.erros.json` transforma **qualquer** falha do pipeline numa linha de
`execucao_falha`, que é o que o portal lê para parar de dizer "estamos organizando tudo com
cuidado" sobre um processamento que já morreu.

1. importar `N8N/workflow.erros.json`;
2. abrir o **Intake Oria — E1** → menu ⋯ → **Settings** → **Error Workflow** → escolher
   *Oria SARF — Reportar Erros*;
3. salvar.

Sem esse passo, só a recusa de orçamento chega ao portal (ela tem ramo próprio no workflow
principal); as outras falhas continuam visíveis apenas na aba de execuções do n8n.

A credencial de Postgres do workflow de erros é a mesma do principal (`Supabase Postgres`) —
o `id: REPLACE` do JSON é substituído pelo n8n na importação, como nos outros.

## O que roda (fluxo do `workflow.e1-ingestao.json`)

```
Intake (Form: nome do mandato + upload de N arquivos)
  → Upsert Caso ............. fn_upsert_caso(nome) → caso_id   [Postgres: NÃO repassa binário]
  → Listar Arquivos ......... fan-out: 1 item por arquivo (binário lido do FORM, chave 'data')
  → Classificar Nome ........ nome + regras → {tipo, período, assinado, confiança} [preserva binário]
  → Preparar Conteudo ....... parte multimodal p/ pdf/imagem (real); placeholder p/
       │                      csv/xlsx/xls/xml, até o extrator nativo confirmar [preserva binário]
       ├─→ Upload Storage ... POST no bucket privado (RAMO LATERAL — nada depende da saída)
       └─→ Roteador de Formato (Switch) ... 1 documento → EXATAMENTE 1 extrator, por content_mime
             ├─ pdf   → Extrair Texto ........ camada de texto do PDF, na instância, sem IA/custo
             ├─ imagem → (direto — já vai como image_url)
             ├─ csv   → Extrair CSV .......... n8n-nodes-base.extractFromFile, operation csv
             ├─ xlsx  → Extrair XLSX ......... idem, operation xlsx (Office Open XML, MODERNO)
             ├─ xls   → Extrair XLS .......... idem, operation xls (OLE binário, ANTIGO)
             ├─ xml   → Extrair XML .......... idem, operation text (lê o binário como texto cru)
             └─ outros → (direto — mantém "conteudo nao suportado" + pendência)
                   ↓ (Merge, 7 ramos)
             → Recompor Conteudo Extraido .. reagrupa linhas de planilha por documento
             │                    (itemMatching), monta o content_part real, e converge
             │                    tudo em 1 item por documento antes de:
             → Medir Documento .. conta as linhas com número e as PÁGINAS (a régua do
             │                    fatiamento, da cobertura e do teto de gasto) e RECOMPÕE o
             │                    contexto lendo o `Preparar Conteudo`
             → Orcamento do Lote → Lote cabe? ... o TETO DE GASTO, decidido com o documento
             │     │                             já medido (linhas e blocos exatos) e ainda
             │     │                             antes da primeira chamada à IA
             │     └─ não cabe → Registrar Recusa → Abortar Lote
             └─→ Precisa Fallback? ... confiança < 0.7 ou tipo desconhecido?
                   ├─ sim → Montar Req Classif → IA Classificar → Parse (recompõe contexto)
                   └─ não → direto
  → Registrar Documento ..... fn_registrar_documento(...) → {documento_id, documento_versao_id,
        │                     reaproveitou_extracao}
        ├─ Recomputar Completude ... fn_recomputar_completude(caso_id) → Portão 1 + status
        └─ Recompor Contexto → Extracao ja feita? ... o mesmo arquivo já foi extraído com o
              │                  MESMO prompt+modelo+esquema, e aquela extração tem linha?
              ├─ sim → Juntar Extraidos (não paga a extração de novo — Supabase/migrations/0118)
              └─ não → [E2] Montar Req Extracao → Fatiar Extracao (1 doc → N blocos que CABEM
                    no teto de saída) → IA Extrair → Parse → Juntar Blocos (N → 1 doc +
                    guarda de cobertura) → Gravar Campos (Sombra, N0)
                    → [Diagnóstico] Registrar Diagnostico ... fn_registrar_diagnostico(...)
                          → Juntar Extraidos
                                → [E3] Reconciliar (Classe A) ... fn_reconciliar_por_documento(...)
                                      → Resumo de Custo ..... o custo REAL do lote, num painel só
                                            → Gravar Uso do Lote → Conferir Lote
```

> **O TETO DE GASTO MUDOU DE LUGAR (18/08) e isso é o que mais se nota no canvas.** Ele decidia
> entre `Classificar Nome` e `Preparar Conteudo`, onde só existiam o nome do arquivo e os bytes —
> e estimava por TAMANHO, com margem de 1,8× que recusava lote que cabia, sem saber quantos blocos
> a extração gastaria. Agora ele decide depois do `Medir Documento`: linhas com número e número de
> blocos são exatos, e continua sendo antes de qualquer gasto (o `Extrair Texto` é local e o
> `Upload Storage` é ramo lateral). Lote sem camada de texto em algum documento cai na conta por
> byte, como antes.

> **As três camadas contra o truncamento e a extração pela metade** (`N8N/lib/cobertura.mjs`):
> `Extrair Texto` mede o documento antes de qualquer chamada; `Fatiar Extracao` garante que nenhum
> pedido passe de 60% do teto de saída do modelo (16.384 tokens), com o TEXTO da primeira e da última
> linha da faixa como âncora; `Juntar Blocos` remonta o documento e **abre pendência quando o que
> voltou é muito menor que o que o documento tem**. O `Extrair Texto` tem `onError: continue` — PDF
> escaneado (sem camada de texto) segue como imagem e as duas outras camadas se calam para ele.
>
> **`Resumo de Custo` é onde se lê quanto o lote custou.** Último nó do canvas, terminal: custo total,
> quanto foi extração e quanto foi classificação, o que o `Orcamento do Lote` havia estimado, tokens de
> entrada/saída/cache e **tokens de saída por linha extraída** (o número que recalibra o estimador).
> Ele existe porque o custo por documento já saía no `Parse Extracao` desde sempre, e saber o do LOTE
> exigia abrir um painel por documento e somar à mão.

Autonomia (Arquitetura do Sistema/1 Visão e Doutrina/01): classificação nasce em **N1** (sugestão; humano confirma na fila de
revisão); **extração (E2) nasce em N0 (sombra)** — registra para medir, não decide, não entra
em base sem aceite humano (anti-ancoragem); **diagnóstico de conteúdo (E1/E2) nasce em N1** —
a MESMA chamada da extração agora também busca entidade, confere tipo/período do nome contra
o conteúdo real e avalia a legibilidade real do arquivo (`Supabase/migrations/0010_diagnostico_e1e2.sql`)
— roda **sempre** (não só no fallback de baixa confiança), preenche entidade quando ainda vazia,
mas só CONFERE tipo/período/legibilidade já registrados: divergência vira `pendencia` tipada
(nunca corrige sozinho); **reconciliação Classe A (E3) nasce em N1** — checagens aritméticas
determinísticas (`Supabase/migrations/0009_reconciliacao_e3.sql`, `Arquitetura do Sistema/2 Especificação/04_RECONCILIACAO.md`) geram
`pendencia` tipada quando divergem (ou quando falta pré-condição), nunca escrevem um número
como fato aceito.

## Regras de fluxo do N8N (aprendidas em teste real — a topologia depende delas)

1. **Node Postgres não repassa binário** — a saída são as linhas da query. Por isso `Listar
   Arquivos` lê os arquivos por referência direta ao Form (`$('Intake (Form)')`), não do
   `$input`.
2. **Node que SUBSTITUI o item exige que o SEGUINTE recomponha o contexto.** Vale para o
   *HTTP Request* (troca o item pela resposta da API) e para o `Extract From File` (escreve o
   resultado do PDF no `json` e **não repassa o binário**). Duas saídas legítimas: ser **ramo
   lateral** (`Upload Storage` — ninguém lê a saída), ou ter um consumidor que recompõe por
   `$('Nome do Node').item` (`Parse Classif`, `Parse Extracao`, `Medir Documento`).
3. **`$('Nó').item` só resolve para nó ANCESTRAL.** Ramo irmão não resolve — e o sintoma é o
   dado voltar vazio **em silêncio**, não um erro.
   > As duas regras acima custaram duas execuções em 13/08, na sequência. Primeiro o
   > `Extrair Texto` foi posto no meio da corrente e levou junto `caso_id` — o banco recusou 35
   > documentos com *"null value in column caso_id violates not-null constraint"*. Depois ele
   > virou ramo IRMÃO, parou de derrubar o lote e parou também de ser lido: a medição voltou
   > vazia (`celulas_nos_documentos: 0`) e as camadas 2 e 3 ficaram desligadas sem ninguém notar.
   > A forma certa é a de hoje: ele entra na corrente DEPOIS do `Preparar Conteudo` (onde o
   > binário ainda existe e o `content_part` já leva o arquivo em base64 no json), e o
   > `Medir Documento` logo atrás recompõe o contexto lendo um ancestral. Dois testes em
   > `workflow-sim.test.mjs` travam as duas regras.
4. **Modos dos nós Code:** seis rodam "Run Once for All Items", cada um porque a pergunta dele é
   do LOTE e não do item — `Listar Arquivos` (fan-out, 1 item → N), `Orcamento do Lote` (só o lote
   inteiro diz se ele cabe no teto), `Abortar Lote`, `Fatiar Extracao` (1 documento → N blocos),
   `Juntar Blocos` (N blocos → 1 documento) e `Resumo de Custo` (quanto custou o lote). Os
   demais são "Run Once for Each Item" (1:1; usam `$input.item`; retornam **objeto único**
   `{json,...}` — array nesse modo dá o erro `A 'json' property isn't an object`). Um teste em
   `workflow-sim.test.mjs` reprova quem puser um nó no modo errado, com a lista das exceções.
5. **Code que repassa arquivo devolve `binary` explicitamente** — retornar só `{json}`
   descarta o binário (`Classificar Nome` e `Preparar Conteudo` preservam).
6. **Posição de nó no canvas NÃO se escreve à mão.** Os quatro geradores chamam
   `posicionar(nodes, connections)` (`N8N/layout.mjs`) e o desenho sai do próprio grafo:
   uma coluna por camada (caminho mais longo desde a entrada, então toda linha anda para a
   direita), o filho de maior alcance herda a faixa do pai (o tronco fica reto), o ramo curto
   desce para a primeira faixa livre, e aresta que pula colunas ganha **corredor reservado** —
   nada é posicionado no caminho dela.
   > Coordenada escolhida a olho, nó a nó, ao longo de 40 sessões, entregou o canvas que o dono
   > viu na tela em 17/08: `Fatiar Extracao` desenhado por cima do `IA Extrair`,
   > `Juntar Blocos` por cima do `Gravar Campos (Sombra)`, o tronco pulando entre y=140 e y=560,
   > e a linha do `false` do fallback atravessando por dentro dos três nós da classificação por
   > conteúdo. Quem acrescentar um nó agora declara **só a conexão**. Quatro invariantes em
   > `test/layout.test.mjs` conferem o JSON commitado dos quatro workflows: nó não se sobrepõe a
   > nó, conexão não volta para trás, linha reta não atravessa nó, e tudo cai na grade de 20px.

## Como usar

1. **Aplicar as migrations do banco** (`Supabase/README.md`) — em caso de dúvida sobre o estado das
   funções, rodar a `0006` (reset idempotente).
2. **Importar como workflow NOVO**: Workflows → Add workflow → *Import from File* →
   `N8N/workflow.e1-ingestao.json`.
   > ⚠️ **Não cole/importe por cima de um workflow existente.** Se o canvas já tiver nodes com
   > os mesmos nomes, o N8N renomeia os novos com sufixo (ex.: `Intake (Form)1`) — e os códigos
   > referenciam nodes **pelo nome exato** (`$('Intake (Form)')`), então o sufixo quebra tudo.
   > Antes de reimportar, **apague ou arquive o workflow antigo**.
3. **Configurar credenciais** nos **6 nós Postgres** e **variáveis de ambiente** (ver abaixo).
4. **Conferir os Query Parameters** dos 6 nós Postgres (o import pode não preenchê-los — tabela
   no Troubleshooting).
5. Abrir a URL do **Form Trigger**, informar o nome do mandato e subir os arquivos.
6. Conferir no banco: `caso`, `documento`, `checklist_item_status`, `pendencia`,
   `evento_auditoria`, `campo_extraido`, `reconciliacao` populados; status do caso avançando
   conforme a completude.

> **Testar sem gastar dinheiro real com documentos reais:** existe um kit de 9 PDFs sintéticos
> (~2-3 KB cada, texto puro, cobrindo os 8 itens do Kit Básico + Mapa de Dívida como bônus)
> entregue ao dono fora do repo (não são código, são dado de teste — sessão 7 cont.¹¹). Os números
> são deliberadamente consistentes entre arquivos (Ativo=Passivo+PL, Caixa do Balanço=Saldo final
> do Fluxo, Receita da DRE=soma do Faturamento, Despesa Financeira=soma dos juros do Mapa de
> Dívida), então as reconciliações Classe A **e** Classe B têm uma chance real de fechar limpo num
> teste de poucos centavos — não só "a extração rodou".

## Troubleshooting conhecido (achados testando no N8N real)

**`No output data returned` no Listar Arquivos:** o node lia o binário do `$input` (= saída do
Postgres, que não repassa binário) → lista vazia. Corrigido: lê do Form por referência. Se o
Form realmente não entregar arquivos, o node agora **lança erro explícito** em vez de parar em
silêncio.

**Erro `there is no parameter $1` num node Postgres:** o campo **"Query Parameters"** (em
Options) não veio preenchido do import. Abra o node → **"+ Add option"** → **"Query
Parameters"** → cole a expressão correspondente:

| Node | Query Parameters |
|---|---|
| Upsert Caso (Postgres) | `={{ [$json["Mandato (nome do caso)"]] }}` |
| Registrar Documento | `={{ [$json.caso_id, $json.entidade \|\| null, $json.periodo_tipo \|\| null, $json.periodo_ref \|\| null, $json.tipo_taxonomia \|\| null, $json.confianca, $json.fonte, 'supabase_storage', $json.caso_id + '/' + $json.nome_original, $json.nome_original, $json.assinado, null, 'ok', $json.justificativa \|\| null] }}` (14º parâmetro = justificativa; a query usa `p_justificativa=>$14` para pular o `p_threshold` que fica no default) |
| Recomputar Completude | `={{ $('Upsert Caso (Postgres)').first().json.caso_id }}` |
| Gravar Campos (Sombra) | `={{ [$json.documento_versao_id, JSON.stringify($json.campos), $json.falha_motivo \|\| null] }}` (3º parâmetro nomeado `p_falha_motivo=>$3` — motivo textual quando a extração falhou/veio truncada, null quando ok) |
| Registrar Diagnostico | `={{ [$('Registrar Documento').item.json.r.documento_id, $('Parse Extracao').item.json.documento_versao_id, $('Parse Extracao').item.json.diagnostico.entidade, $('Parse Extracao').item.json.diagnostico.tipo_confirma, $('Parse Extracao').item.json.diagnostico.tipo_sugerido, $('Parse Extracao').item.json.diagnostico.periodo_tipo, $('Parse Extracao').item.json.diagnostico.periodo_referencia, $('Parse Extracao').item.json.diagnostico.legibilidade, $('Parse Extracao').item.json.diagnostico.nota_legibilidade, $('Parse Extracao').item.json.diagnostico.resumo, $('Parse Extracao').item.json.diagnostico.justificativa] }}` |
| Reconciliar (Classe A) | `={{ [$('Registrar Documento').item.json.r.documento_id] }}` |

**Erro `function fn_upsert_caso(unknown) does not exist`:** o driver do N8N envia o parâmetro
sem tipo; a resolução falha sem cast. As queries já vêm com `::tipo` em cada `$N`.

**Erro `function fn_upsert_caso(text) does not exist` (com o cast!):** as funções no banco
estão com assinatura divergente (aplicações parciais/repetidas das migrations). Rodar
`Supabase/migrations/0006_reset_funcoes.sql` — derruba qualquer versão e recria do zero (idempotente).

**Nodes com sufixo `1` no nome (`Upsert Caso (Postgres)1`):** o workflow foi importado/colado
por cima de outro. As referências `$('Nome')` quebram. Apagar o antigo e reimportar limpo.

**"Corrigimos isso, mas o erro é o mesmo" — como saber se o workflow importado é o do repositório.**
Aconteceu em 12/08/2026: o lote foi recusado com uma mensagem que o código em `main` não produzia
havia cinco dias, e a hipótese "o n8n está com a versão velha" ficou uma rodada inteira sem prova. A
partir da v3 do orçamento (13/08/2026) dá para ler da tela, em dois lugares:

- a mensagem de recusa começa com **`[orçamento v3 (2026-08-13)]`**;
- a saída do nó `Orcamento do Lote` traz **`orcamento_versao`** mesmo quando o lote PASSA.

Se a versão não aparecer, o workflow importado é anterior a 13/08 — reimportar. **Merge no
repositório não reimporta nada**, e da tela código novo e código velho recusam igual.

**Erro `access to env vars denied` (num node Code ou expressão):** o N8N bloqueia `$env` por
padrão (`N8N_BLOCK_ENV_ACCESS_IN_NODE`). O workflow atual **não usa `$env`** — se esse erro
aparecer, é versão antiga: reimportar, ou trocar manualmente `($env.OPENAI_MODEL||'gpt-4o')` →
`'gpt-4o'` nos nós `Montar Req *` e configurar credenciais nos nós HTTP (ver seção
Credenciais).

**Erro `Credentials not found` nos nós OpenAI:** a Authentication está em *Predefined
Credential Type → OpenAI* mas a credencial não existe (ou é do tipo errado). Corrigido: os
nós vêm configurados como *Generic Credential Type → Header Auth* — criar a credencial Header
Auth (Authorization / Bearer sk-...) e selecionar.

**Erro `Bad request` no Upload Storage com a credencial da OpenAI selecionada:** a credencial
de Header Auth escolhida no node era a da OpenAI (manda a chave errada para o Supabase). Criar
uma credencial Header Auth **separada** para o Supabase (ver Credenciais acima).

**Documentos classificados com sucesso (tipo/entidade/período/confiança ok) mas 0 linhas
extraídas — export sai com "Linhas totais extraídas: 0", todos os nós do N8N em verde, e
reprocessar não muda nada:** achado em produção (sessão 7 cont.⁷, "teste v14") — a chamada de
extração (`IA Extrair`) veio truncada (`finish_reason=length`, teto de tokens de saída
estourado por um documento combinado grande) ou com erro de API, mas `onError:
continueRegularOutput` faz o node aparecer verde mesmo assim, e o JSON incompleto falhava o
parse silenciosamente. Corrigido (`Supabase/migrations/0016`): `max_tokens` explícito na chamada +
detecção de truncamento/erro → gera pendência `extracao_falhou` (visível no portal, seção
"Qualidade da extração") em vez de silêncio. **Se você já tem casos com este sintoma: reimporte
o workflow (pega o `max_tokens`/detecção novos), aplique `0016`, e reprocesse** — a pendência só
aparece em processamentos NOVOS (não é retroativa aos `campo_extraido` já gravados vazios).

**Pendência `extracao_falhou` com motivo "Erro da API OpenAI: Try spacing your requests out using
the batching settings" em VÁRIOS/TODOS os documentos de um upload em lote:** é **rate limit (429)**
da OpenAI — o N8N disparou muitas chamadas de extração quase simultâneas e a API throttlou (achado
sessão 7 cont.⁸, "teste v15": 16 documentos, 16 falhas idênticas). **Não é problema de formato de
arquivo** (se fosse, os erros seriam diferentes por arquivo, e a classificação — que lê o mesmo
conteúdo — teria falhado também). Corrigido: os nós `IA Classificar`/`IA Extrair` vêm com
**batching** (1 chamada por vez, 6s de intervalo — era 3s, endurecido na cont.¹¹) + **retry** (6
tentativas — era 4 — 5s entre elas) — 1 chamada por vez espalha RPM/TPM no tempo. Se persistir
mesmo com batching, sua conta pode estar num tier de limite muito baixo. O número a ajustar NÃO é
o `batchInterval` do nó: são `tpm`/`rpm` do provedor em `N8N/lib/provedor.mjs`, de onde o intervalo
é DERIVADO (`node N8N/build-workflow.mjs` depois). Editar o nó à mão faz o teste de cadência e o
workflow discordarem no primeiro rebuild. **Reimporte o workflow** para pegar o batching. Trade-off: um lote de N documentos fica ~N×6s mais lento, mas
confiável.

**Documentos CONSOLIDADOS COMPARATIVOS MULTI-ANO (ex. "Balanço Consolidado 2022 e 2023.pdf") ainda
dão 429 ou truncam mesmo com o batching endurecido:** achado em produção (sessão 7 cont.¹¹, "teste
v18" — 16 documentos reais, 7 falharam, TODOS desse tipo). É o pior caso possível: mais tokens de
ENTRADA (2-3 anos de dados no PDF) e mais tokens de SAÍDA (cada conta vira 2-3 linhas via
`periodo_coluna`, cont.⁹) — documentos de UM ano só ou multi-demonstração-mas-um-ano funcionam bem.
Duas mitigações já aplicadas (batching mais conservador + chaves de fio curtas no schema de
extração, que cortam ~30-40% dos bytes de saída por linha) reduzem o problema mas **não eliminam
pros casos mais extremos**. Workaround imediato: **divida o PDF em arquivos por ano antes de
subir** (ex. "Balanço 2022.pdf" + "Balanço 2023.pdf" separados) — cada ano sozinho fica num volume
comparável ao que já funciona. A correção completa (dividir a extração em várias chamadas por
página/período automaticamente) precisa de uma mudança de topologia do grafo do N8N e só pode ser
validada contra uma instância viva — ver "Itens adiados" em `HANDOFF.md` (cont.¹¹).

**429 persiste em TODOS os documentos, mesmo pequenos e simples (ex. um PDF de 2-3 KB), mesmo com
batching:** confirmado em produção (sessão 7 cont.¹³, "teste v19") que a causa raiz pode ser o
**tier de rate limit da própria conta** estar no teto — nenhum espaçamento de código resolve isso
sozinho. Confira no console do provedor (OpenAI: Settings → Limits; Google: as cotas do projeto) o
RPM/TPM do modelo em uso; se estiver baixo, suba o tier (ou adicione forma de pagamento, se a conta
for nova/trial), e ajuste `tpm`/`rpm` em `N8N/lib/provedor.mjs` para o valor real — subir o tier e
não contar isso ao código deixa o lote lento à toa.

Atalho: `IA_API_KEY=... node N8N/diagnosticar-ia.mjs` faz uma chamada de 1 token e diz a causa
classificada pelo MESMO código que a pendência usa. Quem não usa terminal importa
`N8N/workflow.diagnostico-ia.json` e clica.

**Alguns arquivos do upload em lote NUNCA aparecem no dashboard (nem "não classificado", nem
pendência nenhuma) — simplesmente somem:** achado em produção (sessão 7 cont.¹³, "teste v19": 9
arquivos enviados, só 6 apareceram). Causa: os nós Postgres (`Registrar Documento`, `Gravar Campos
(Sombra)`, etc.) não tinham tratamento de erro — um erro transitório de conexão num ÚNICO item
(mais provável sob carga, com o rate limit já no teto) **parava a execução inteira**, e todo item
ainda na fila desaparecia sem nenhum rastro. Corrigido: todos os nós Postgres agora têm
`onError: continueRegularOutput` + `retryOnFail` (3 tentativas) — um erro vira, no pior caso, um
item incompleto (nunca fato, doutrina anti-ancoragem), não o lote inteiro sumindo. **Reimporte o
workflow** para pegar essa correção.

**Erro `The resource you are requesting could not be found` no Upload Storage:** a URL está
apontando para o **painel** do Supabase (`supabase.com/dashboard/...`) em vez da **API**
(`<ref>.supabase.co/storage/v1/...`). Ver seção Credenciais acima.

**Erro `Bad request - please check your parameters` no Upload Storage mesmo com URL e
credencial corretas:** falta o header **`apikey`**. O gateway do Supabase exige esse header
**além** do `Authorization` (a credencial Header Auth só injeta um dos dois) — sem ele,
rejeita antes de processar o upload. Adicionar um header `apikey` com a mesma service role key
(já vem como campo no node, com placeholder para editar).

**Erro `Converting circular structure to JSON` / `_httpMessage closes the circle` ao rodar o
workflow inteiro (não ao testar node a node):** **não é bug nosso** — é um problema de longa
data do próprio node HTTP Request do N8N ao lidar com dados binários em certas configurações
(GitHub `n8n-io/n8n#3089`, `#10096`). Confirmado via console do navegador: é o **editor do
N8N** travando ao tentar serializar os dados de execução dos nodes HTTP, não uma falha de rede
com o Supabase/OpenAI. Limpar o cache de execução e recarregar a página **não resolve** — é
reproduzível. Ver seção "Upload Storage — pendência conhecida" abaixo.

**Erro `401 - "Your authentication token is not from a valid issuer"` (`invalid_issuer`) nos
nós `IA Classificar`/`IA Extrair`:** a credencial Header Auth selecionada no node não é
a chave da OpenAI (`sk-...`) — é um **JWT** (token de 3 partes com um campo `iss`), tipicamente
a chave `anon`/`service_role` do **Supabase** selecionada por engano (o inverso do bug já visto
no Upload Storage). Corrigir: no node, abrir a credencial Header Auth e conferir que o valor é
`Bearer sk-...` da OpenAI — criar uma credencial separada da do Supabase se ainda não existir.

**Documento com nome sugestivo (ex.: "BALANÇO ACUMULADO 2025.pdf") classificado com
`tipo_taxonomia` inválido (ex.: `"BAL"` em vez de `"BALANCO"`) → `insert or update on table
"documento" violates foreign key constraint "documento_tipo_taxonomia_fkey"` no Registrar
Documento:** bug real encontrado testando com documento real (2026-07-20) — o schema JSON
enviado à OpenAI (nó `Montar Req Classif`) **não travava `tipo_taxonomia`/`periodo_tipo` num
`enum`** (era só `{type:'string'}`), então a IA ficou livre para inventar abreviações (`"BAL"`)
em vez de usar exatamente um código da taxonomia — e até confundir `periodo_tipo` com a
referência (`"12M25"` em vez de `"anual"`). Corrigido em `N8N/build-workflow.mjs`: o enum de
`tipo_taxonomia` agora é **importado diretamente** de `codigosConhecidos()`
(`lib/ia.mjs`), não copiado à mão — e há um teste (`workflow-sim.test.mjs`) que trava essa
regressão. **Reimporte o workflow atualizado** (o node `Montar Req Classif` mudou) para pegar o
fix; nenhum dado ficou corrompido no banco porque o `insert` falhou e reverteu (a
constraint fez o trabalho dela).

**IA classifica com confiança "razoável" mas a `justificativa` só repete o nome do arquivo
(nunca cita cabeçalho, colunas, estrutura do documento) — sinal de que o PDF NÃO chegou de
verdade na OpenAI:** bug real encontrado testando com documento real (2026-07-20), no mesmo
caso do item acima já corrigido. O node `Preparar Conteudo` lia `binary.data.data` **direto**
assumindo que esse campo sempre é a string base64 do arquivo — o que só é verdade quando o N8N
guarda binário em **modo memória** (o default). Se a instância está configurada em modo
**filesystem** ou **S3** (`N8N_DEFAULT_BINARY_DATA_MODE`), esse campo vira uma **referência
interna** (ex.: `"filesystem-v2"`), não a base64 — e a OpenAI recebe um `file_data` inválido
**sem erro nenhum** (só devolve uma classificação vaga baseada só no texto do nome do arquivo,
porque não conseguiu ler nada do PDF). Corrigido em `N8N/build-workflow.mjs` (nó `Preparar
Conteudo`): agora usa `await this.helpers.getBinaryDataBuffer(0, 'data')`, que resolve o
binário corretamente em **qualquer** modo — é a forma documentada/correta de ler binário num
Code node, nunca ler o campo `.data` direto.

> **Correção de rota (mesmo dia):** a primeira versão deste fix usava o global `$helpers`, que
> não existe no runtime de **Task Runner** do N8N (padrão em instalações self-hosted recentes —
> confirmado pelo erro `ReferenceError: $helpers is not defined` testando ao vivo, N8N 2.30.7).
> A forma correta, confirmada na doc oficial do N8N (cookbook "Get the binary data buffer"), é
> `this.helpers.getBinaryDataBuffer(itemIndex, propertyName)` — `this`, não um global `$helpers`.

**Reimporte o workflow atualizado** (o node `Preparar Conteudo` mudou) e reteste; para
confirmar que resolveu, a `justificativa` da IA deve passar a citar algo específico do conteúdo
(cabeçalho, rótulos de linha, estrutura de colunas), não só repetir o nome do arquivo.

## Upload Storage — pendência conhecida (node desabilitado)

O node **`Upload Storage` vem desabilitado por padrão** neste workflow (2026-07-17) por causa
do bug de plataforma acima. Como ele é um **ramo lateral** (nenhum outro node depende da sua
saída — ver teste `workflow-sim.test.mjs`), desabilitá-lo **não afeta** classificação,
extração, completude nem pendências — só significa que a cópia do arquivo não é enviada ao
Supabase Storage por enquanto (os arquivos originais continuam disponíveis onde foram
enviados no Form).

**Duas alternativas para resolver, fora do HTTP Request genérico do N8N:**

1. **Community node `n8n-nodes-supabase`** — node dedicado com operação de upload para
   Storage, usando a lib oficial do Supabase por baixo (evita o bug do HTTP Request com
   binário). Instalar em **Settings → Community Nodes → Install → `n8n-nodes-supabase`**
   (funciona em instâncias self-hosted, incluindo PikaPods, sem precisar de acesso ao
   servidor). Depois de instalado, trocar o node `Upload Storage` por ele, apontando para o
   mesmo bucket `documentos`.
2. **Mover o upload para o portal Vercel** (fatia futura) — usar o SDK oficial do Supabase em
   JavaScript (`@supabase/supabase-js`) direto no backend do portal, que não tem as
   limitações do node HTTP Request do N8N. Fica natural já que o portal também vai lidar com
   upload em lote na fatia seguinte.

**Para reabilitar** depois de adotar uma das alternativas: em `build-workflow.mjs`, localizar
o node `Upload Storage` e trocar/remover `disabled: true` (ou substituir o node inteiro pelo
community node, se for esse o caminho).

## Republicar sem perder o comportamento — e conferir depois

**Duas republicações seguidas (26 e 27/08) perderam a mesma família de coisas**, e a
segunda perdeu a pior: o `multipleFiles: true` do campo de arquivo do formulário — sem
ele o intake aceita **um documento por vez**, e os books têm 38 e 190. Junto foram-se
`onError` em 23 nós e `retryOnFail`/`maxTries`/`waitBetweenTries` em 11.

Corrigir à mão é abrir 23 nós e mexer na aba *Settings* de cada um. Em um comando:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
  | node N8N/preparar-republicacao.mjs > publicar.json

curl -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
  "$N8N_URL/api/v1/workflows/$ID" --data-binary @publicar.json
```

Ele parte do JSON do **repositório** (a autoridade sobre o que o workflow faz e como
falha) e traz do **publicado** só o que é da instalação: o `id` de cada credencial, o
`path` do formulário (sobrescrevê-lo troca a URL pública do intake), o `id` de cada nó
e as `settings` — onde mora o `errorWorkflow`. O relatório sai pelo *erro*, listando as
credenciais que continuam em `REPLACE` e se o nó delas está ligado.

## Depois de publicar, CONFIRA o que ficou publicado

```bash
# no editor do n8n: … → Download, salva o JSON; depois:
node N8N/conferir-publicado.mjs < ~/Downloads/workflow.json

# ou, com acesso à API REST, sem passar por arquivo nenhum:
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
  | node N8N/conferir-publicado.mjs
```

O JSON entra pela **entrada padrão**, não como caminho de arquivo: assim quem
abre o arquivo é o shell, com as permissões de quem digitou, e o conferidor não
toca em caminho nenhum além do arquivo do próprio repositório.

**Isto existe porque uma conferência já passou verde estando errada.** Em 26/08/2026 a
republicação foi declarada *"33 de 33 nós byte a byte iguais ao repositório"* — e era verdade, e era
insuficiente: ela comparava `parameters`, e **toda a configuração de falha de um nó do n8n mora fora
de `parameters`**. O que tinha se perdido, medido dois dias depois contra o workflow vivo:

| O que sumiu | Em quantos nós | O que isso custa |
|---|---:|---|
| `onError: continueRegularOutput` | 23 | qualquer falha passa a **matar o lote inteiro** em vez de seguir |
| `retryOnFail` / `maxTries` / `waitBetweenTries` | 11 | uma oscilação do provedor no `IA Extrair` (6 tentativas) mata o lote na primeira |
| `disabled: true` do `Upload Storage` | 1 | o ramo lateral desabilitado desde 17/07 **voltou a executar**, com credencial `REPLACE`, e derrubou o primeiro lote no primeiro nó |

O conferidor compara o nó inteiro — o que ele faz, **como ele falha**, e **se ele está ligado** — e
ignora de propósito o que pertence à instalação e não ao repositório: o `id` e o `name` da
credencial, o `path` do formulário (sobrescrevê-lo troca a URL pública do intake) e a `position`.
O que ele cobra no lugar é o contrapositivo, que é o útil: **um nó HABILITADO com o `REPLACE` do
repositório ainda na credencial não vai rodar.**

## Credenciais (configurar no N8N — o workflow NÃO usa variáveis de ambiente)

> O N8N **bloqueia `$env` por padrão** em nós Code e expressões (erro *"access to env vars
> denied"*). Por isso o workflow usa só **credenciais nativas** + 1 edição de URL:

- **Postgres (Supabase, Session Pooler)** — credencial nos **6 nós Postgres** (Upsert Caso,
  Registrar Documento, Recomputar Completude, Gravar Campos, Registrar Diagnostico, Reconciliar
  (Classe A)). Reaproveitar do `clipping-news`.
  Pegadinhas herdadas: usar o **Session Pooler** (IPv4 + SSL), usuário com sufixo
  `.projectref`. O N8N usa conexão de serviço, que **ignora RLS** por design (é o orquestrador)
  — ver `Supabase/migrations/0003`.
- **Provedor de IA** — nos nós `IA Classificar` e `IA Extrair`. Authentication já vem como
  *Generic Credential Type → Header Auth*; o **nome da credencial e o header que ela preenche
  dependem do provedor ativo** (`N8N/lib/provedor.mjs`), e o JSON gerado já aponta para o nome
  certo:

  | Provedor ativo | Nome da credencial no n8n | Name | Value |
  |---|---|---|---|
  | **Google (Gemini)** — padrão desde 24/08/2026 | `Google AI (Gemini)` | `x-goog-api-key` | a chave, **sem prefixo nenhum** |
  | OpenAI | `OpenAI API` | `Authorization` | `Bearer sk-...` (a palavra `Bearer` + espaço) |

  A chave do Google sai de `aistudio.google.com/apikey`. Ela vai no **header**, nunca na URL
  como `?key=`: a URL do nó aparece na tela de execução e no log do n8n, e chave em URL é
  segredo em lugar de leitura.

  O modelo NÃO se troca no nó: ele é escrito pelo gerador a partir de `MODELOS_POR_PROVEDOR`
  (`N8N/lib/custo.mjs`), porque o orçamento depende do preço dele. Editar o nó à mão faz o
  guarda de US$ 3 passar a decidir com o preço do modelo errado.

  **Para voltar para a OpenAI:** `IA_PROVEDOR=openai node N8N/build-workflow.mjs`, reimportar o
  JSON, e criar/selecionar a credencial `OpenAI API`. Nenhuma linha de código muda.

  **Confira o id do modelo ANTES de rodar um lote** — é a única coisa deste sistema que nenhum
  teste prova, porque só a API do provedor valida a string, e errá-la faz TODA chamada voltar 404:

  ```
  IA_API_KEY=<sua-chave> node N8N/diagnosticar-ia.mjs --modelos
  ```

  É um GET no catálogo da conta: **zero token, zero custo**. Ele lista o que existe, marca o que o
  workflow usa e, se o configurado não estiver lá, sugere os ids mais parecidos. O mesmo comando
  sem `--modelos` faz uma chamada de 1 token e diagnostica crédito/cota/cadência.

  **SEM TERMINAL, é a mesma coisa em dois cliques:** importe `N8N/workflow.diagnostico-ia.json`,
  selecione a credencial nos **dois** nós HTTP dele (`Listar Modelos` e `IA (1 token)`) e execute.
  Ele lista o catálogo, confere se o modelo configurado está lá — nomeando os parecidos quando não
  está — e só então faz a chamada de 1 token para separar crédito de cota de cadência. Não grava
  nada em banco nenhum.

### Testar sem pôr crédito — o que dá e o que NÃO dá

O Google tem um **nível gratuito** da API do Gemini (chave do `aistudio.google.com/apikey`, sem
cartão). Ele serve para provar a costura inteira — credencial, formato do corpo, leitura do PDF,
schema, gravação no banco, export — sem gastar nada.

> ⚠️ **NÃO USE DOCUMENTO REAL DE CLIENTE NO NÍVEL GRATUITO.** A diferença entre o gratuito e o pago
> não é só cota: no gratuito o provedor usa o conteúdo enviado para melhorar os produtos dele, e no
> pago não. Documento de mandato é dado de cliente sob NDA — ver `Arquitetura do Sistema/2 Especificação/10_DADOS_RETENCAO_E_LGPD.md`.
> **Confirme os termos vigentes no console antes de decidir**, e enquanto isso rode só o material
> sintético.

O material sintético existe e é o certo para esta prova: `Dados de Teste/book-canastra` (38 PDFs, 6
empresas, 3 exercícios, com `GABARITO.json` para comparar) e `Dados de Teste/book-vertentes` (14). Gere
com `cd "Dados de Teste"/book-canastra && PYTHONPATH=. python3 gerar.py`.

**O que o nível gratuito NÃO substitui:** ele não é o **B1** do `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md`. O B1
existe justamente porque toda suíte prova a ingestão sobre extração FIEL — PDF gerado por
`reportlab`, texto limpo, layout conhecido —, e scan torto, carimbo, coluna deslocada e escala mista
estão fora do alcance dela por construção. Rodar o book sintético no Gemini prova que **a troca de
provedor funciona**; não prova que o sistema lê documento de verdade.

**A cadência já está dimensionada para o nível de entrada:** 8s entre chamadas em cada um dos dois
nós, derivado de 15 chamadas/minuto contando que um documento mal nomeado faz duas. Se a sua cota
for outra, o número a mexer é `tpm`/`rpm` em `N8N/lib/provedor.mjs` — não o `batchInterval` do nó.
- **Upload Storage** — duas configurações no node:
  1. **URL:** já vem com a ref real do projeto (`mrcabcaotblleojxnsxc`), gravada no
     `build-workflow.mjs` — ela é a URL pública da API, a mesma do
     `NEXT_PUBLIC_SUPABASE_URL` do portal, e não é segredo. **Atenção** ao trocar de projeto: é a URL da
     **API** (`https://<ref>.supabase.co/storage/v1/object/documentos/...`), **não** a URL do
     painel (`https://supabase.com/dashboard/project/<ref>/...`, que é só para humanos no
     navegador). A ref aparece em ambas as URLs; confirme também em Settings → API → Project URL.
  2. **Credencial:** Authentication já vem como *Generic → Header Auth*; criar credencial
     **Header Auth NOVA** (não reaproveitar a do provedor de IA!) com Name=`Authorization`,
     Value=`Bearer <service role key>` — pegue em Settings → API → `service_role` (a chave
     secreta, não a `anon`).
  3. **Header `apikey`:** o gateway do Supabase exige esse header **além** do `Authorization`
     (a credencial só injeta um). No campo **Headers** do node, junto ao `x-upsert` já
     presente, colar a **mesma service role key** no header `apikey` (o valor já vem com um
     placeholder `COLE_A_SERVICE_ROLE_KEY_AQUI` para editar). Sem ele, a API responde `400
     Bad Request` mesmo com URL e credencial corretas.
- **Sem a credencial/URL do Upload**, o node falha (e para a execução — falha explícita de
  propósito: linha no banco apontando para arquivo inexistente seria um "falso-limpo"). Para
  um dry-run sem storage, **desative** o node Upload Storage.
- **Sem a credencial do provedor**, os nós de IA falham mas **não derrubam o workflow**
  (`onError: continue`): o parse produz confiança 0 → pendência de classificação / extração
  vazia (fail-safe coerente com a doutrina).

## Fallback de classificação por conteúdo — como funciona

Quando o classificador por nome não tem confiança, a chamada leva o **conteúdo real do
arquivo** (montado no `Preparar Conteudo` + roteado por `Roteador de Formato`, que rodam
para todos):
- **PDF** → parte `file` (base64) — o modelo lê texto + páginas.
- **Imagem** (scan/foto PNG/JPG) → parte `image_url` (base64).
- **CSV / XLSX / XLS** → roteados (por `content_mime`, no `Roteador de Formato`, um Switch
  nativo) para o extrator certo — `Extrair CSV`/`Extrair XLSX`/`Extrair XLS`, todos
  `n8n-nodes-base.extractFromFile` com a `operation` que bate com o formato (XLS é o
  formato ANTIGO — OLE binário, pré-2007 —, XLSX é o MODERNO — Office Open XML,
  pós-2007). `Recompor Conteudo Extraido` reagrupa as linhas devolvidas (o extrator nativo
  entrega uma por item) em um item por documento e monta o texto com `spreadsheetToText`
  (`N8N/lib/spreadsheet.mjs`) — a mesma função que a lib usa, embutida por `toString()`
  como todo o resto.
- **XML** → `Extrair XML` (`extractFromFile`, operação `text`) lê o binário como texto
  cru, mandado como está — não estruturado em linhas, mas legível pelo modelo.
- Qualquer outro mimetype → sem extrator; `Preparar Conteudo` mantém a nota
  "conteudo nao suportado" e a pendência (regra 1: nunca inventa suporte que não existe).
- Saída sempre via **Structured Outputs** (JSON Schema estrito). Continua **N1**: sugestão
  para revisão humana.

**⚠️ NÃO CONFIRMADO CONTRA O N8N DO DONO** (mesma categoria da nota sobre `retryOnFail`
mais abaixo): o comportamento "uma linha por item" do `Extract From File` em planilha, e a
propagação de `itemMatching` através do Merge que junta os 7 ramos do roteador, são o que a
documentação do n8n descreve — não o que foi visto rodar na instância real. `Recompor
Conteudo Extraido` nunca agrupa às cegas quando o rastro falha (isola a linha, não funde
documentos), mas o que falta confirmar ao vivo: subir **2 ou mais planilhas no mesmo
lote** e checar no banco que cada uma virou o SEU PRÓPRIO documento, com as próprias
linhas — não uma mistura.

## Diagnóstico de conteúdo (E1/E2) — como funciona

Diferente do fallback de classificação acima (que só roda com confiança baixa), o diagnóstico
roda **para todo documento, sempre** — é a MESMA chamada que já fazia a extração linha a linha
(`Montar Req Extracao` → `IA Extrair` → `Parse Extracao`), só que agora o schema
(`N8N/lib/extract.mjs`) também pede um bloco `diagnostico`:

- **Entidade**: se visível no conteúdo. `fn_registrar_diagnostico` só preenche `documento.entidade_id`
  quando ainda está **vazio** — nunca sobrescreve uma entidade já registrada; se o conteúdo sugerir
  uma entidade **diferente** da já registrada, vira pendência `entidade_incorreta` (revisão humana).
- **Tipo/período**: a IA recebe a mesma dica que o classificador por nome já resolveu, mas agora
  confirma (ou não) contra o **conteúdo real**. Diverge → pendência `tipo_incorreto` /
  `periodo_incorreto`. Essas pendências caem na **mesma fila de revisão** da classificação
  (`fn_revisar_documento` já sabe corrigir tipo/entidade/período juntos).
- **Legibilidade real**: antes hardcoded `'ok'` em `documento_versao.legibilidade` — agora vem do
  diagnóstico (`ok`/`degradado`/`ilegivel`); `ilegivel` vira pendência `arquivo_ilegivel`.
- **Resumo + planilha organizada**: `documento.resumo` (2-3 frases) e cada linha extraída ganha
  `secao` (agrupador que espelha a estrutura do próprio documento — ex. "Ativo Circulante",
  "Passivo Não Circulante") — o portal agrupa por isso na tela "ver linhas" do documento.
- Tudo isso é **N1**: só sugere (via pendência) ou preenche uma lacuna que ainda não tinha valor
  nenhum. Nunca sobrescreve um valor já registrado sem passar por uma pendência revisável.

## Qualidade da classificação — ajustes feitos a partir de teste real (2026-07-17)

Testando com um documento real (`BALANÇO ACUMULADO 2025.pdf`), a classificação ficou incerta
(confiança 0.5, tipo `DESCONHECIDO`) mesmo o nome citando "Balanço" claramente. Três ajustes:

1. **Período mais flexível** (`N8N/lib/classifier.mjs`): reconhece agora ano isolado ("2025")
   e intervalo de anos ("2021-2025", "2021 a 2025" — expandido para a lista inteira, não só os
   extremos). Um ano isolado é tratado como sinal **fraco** (soma só +0.05 à confiança, contra
   +0.3 dos formatos estruturados) — de propósito: "tipo no nome + ano solto" não deve, sozinho,
   pular a verificação pela IA (ex.: `BALANCO` + `2025` fica em 0.65, abaixo do limiar 0.7).
2. **Merge de confiança nome-vs-IA** (`N8N/lib/merge.mjs`): quando o fallback roda, o resultado
   final fica com a **maior confiança** entre nome-do-arquivo e IA — não é mais sempre a IA que
   vence. Entidade e assinado da IA são sempre aproveitados (o nome nunca informa isso). Se a
   chamada à OpenAI falhar tecnicamente, o sistema não zera a confiança à toa — mantém o que o
   nome já sabia.
3. **Prompt menos conservador + justificativa objetiva** (`N8N/lib/ia.mjs`): antes, o
   prompt incentivava "se incerto, use DESCONHECIDO" — na prática, isso fazia o modelo desistir
   fácil demais. Agora ele é instruído a **sempre tentar um palpite específico** (reservando
   `DESCONHECIDO` só para documento genuinamente ilegível/não-financeiro), e o campo
   `justificativa` passou a ser obrigatório e objetivo (o que ele viu/não viu no documento).
   Essa justificativa agora **aparece na descrição da pendência** de classificação
   (`Supabase/migrations/0007`), então o humano revisando já vê o motivo, não só o número de confiança.

**Confirmado ao vivo (2026-07-20), depois de corrigir dois bugs à parte encontrados no caminho**
(enum ausente no schema da OpenAI — ver troubleshooting acima — e leitura de binário via
`this.helpers.getBinaryDataBuffer` em vez do campo `.data` direto): o mesmo documento
`BALANÇO ACUMULADO 2025.pdf` classificou com `tipo_taxonomia=BALANCO`, `confiança=0.9`,
`fonte=openai_conteudo`, e a justificativa passou a citar o **conteúdo real** do PDF:
> "O documento é intitulado 'BALANÇO PATRIMONIAL ACUMULADO 31 DE DEZEMBRO 2025', indicando que
> se trata de um balanço patrimonial. A data de referência é 2025, e o documento está assinado
> por um contador registrado, o que aumenta a confiança na classificação."

Os quatro itens do feedback original estão validados de ponta a ponta com documento real.

## ⚠️ Estado honesto desta entrega

- **Executado ponta a ponta no N8N real do dono (2026-07-17):** Upsert Caso → Listar Arquivos
  → Classificar Nome → Preparar Conteudo → (fallback por conteúdo) → Registrar Documento →
  Recomputar Completude → Extração E2 → Gravar Campos — **todos passaram** com um caso real
  (arquivos com nome/acento reais, ex. "BALANÇO ACUMULADO 2025.pdf").
- **Upload Storage: desabilitado** por um bug de plataforma do N8N (ver seção dedicada acima)
  — pendência de arquitetura, não de lógica.
- **Caminho determinístico (nome → registro → completude): completo, testado e validado ao
  vivo** — lógica com testes unitários, funções do banco exercitadas num Postgres real, e
  confirmado no N8N real.
- **Fluxo entre nós: simulado por teste** — `N8N/test/workflow-sim.test.mjs` executa os códigos
  **reais** do JSON gerado com a semântica de passagem de dados do N8N (Postgres sem binário,
  HTTP substituindo o item, referências `$('Node')`), nos dois ramos.
- **Fallback por conteúdo (PDF/imagem) e Extração E2 em N0/sombra: completos**, cobertos por
  testes de corpo/schema/parse e confirmados no N8N real.
- **Roteamento por formato (CSV/XLSX/XLS/XML) — construído e testado, NUNCA confirmado no
  N8N do dono.** `Roteador de Formato` (Switch) manda cada documento a UM extrator nativo
  (`Extrair CSV`/`Extrair XLSX`/`Extrair XLS`/`Extrair XML`), e `Recompor Conteudo Extraido`
  reagrupa por documento antes de `Medir Documento` — corrige a lacuna real que existia
  (XLSX/XLS/XML nunca eram extraídos; CSV era parseado à mão) e o fan-out cego que uma edição
  direta no editor introduziu (5 nós "Extract from..." em paralelo, todos recebendo o mesmo
  item, sem Switch nenhum decidindo). Testado por simulação (`workflow-sim.test.mjs`), com o
  invariante MEDIDO não-vazio: gerar o JSON com a topologia antiga faz 10 desses testes
  reprovar. **O que falta**: subir 2+ planilhas no MESMO lote no n8n real e confirmar no banco
  que cada uma virou o seu próprio documento — a propagação de `itemMatching` através do
  Merge de 7 ramos, e o comportamento "uma linha por item" do `Extract From File`, são o que a
  documentação do n8n descreve, não o que foi visto rodar aqui.
- **Diagnóstico de conteúdo (entidade/tipo/período/legibilidade/resumo/planilha) e Reconciliação
  Classe A (E3): construídos e testados** (testes unitários + simulação de fluxo + Postgres 16
  local efêmero) — **ainda não exercitados com documentos reais no N8N/Supabase do dono.**

## Fonte da verdade da lógica

`N8N/lib/*.mjs` são os módulos **testados** (`node --test` em `N8N/test/`). Os nós Code do
workflow **espelham** essa lógica (inline, porque nós Code não importam arquivos). Ao alterar a
lógica: mude `lib/`, rode os testes, e **regenere** com `node N8N/build-workflow.mjs` — o teste
`workflow-sim` valida o JSON regenerado.

**O que NÃO é mais espelhado à mão:** os enums da classificação (importados de `lib/ia.mjs`) e
o **prompt de extração** — `build-workflow.mjs` importa `SYSTEM_PROMPT` de `lib/extract.mjs` e o
embute literalmente (via `JSON.stringify`). Antes havia uma paráfrase manual do prompt no gerador,
e ela já tinha divergido da fonte: melhorias aplicadas em `lib/` não chegavam à produção até
alguém reescrever o mirror. Dois testes travam a propriedade (`workflow-sim.test.mjs`): o prompt do
JSON gerado é **idêntico** ao `SYSTEM_PROMPT`, e as instruções de escala/sinal/período canônico
estão presentes no texto que a OpenAI recebe. **Nunca voltar a parafrasear o prompt no gerador.**

## Estrutura

```
N8N/
├── lib/            # lógica testável: provedor, classifier, completude, ia, extract,
│                   #                  spreadsheet, taxonomia, normalize
├── test/           # node:test (simulação do workflow, layout do canvas, libs)
├── layout.mjs                # desenha o canvas a partir das conexões (os 4 geradores usam)
├── build-workflow.mjs        # gerador do workflow (JSON válido)
├── workflow.e1-ingestao.json # workflow importável no N8N (E1 + Diagnóstico + E2-sombra + E3)
└── README.md
```

## Próximas fatias

- **Resolver o Upload Storage** (community node `n8n-nodes-supabase` ou mover para o portal Vercel).
- **Confirmar o roteamento por formato ao vivo** (ver "Estado honesto" acima): subir 2+
  planilhas no mesmo lote no n8n do dono e checar no banco que cada uma virou o seu próprio
  documento.
- **Testar o diagnóstico + Classe A com documentos reais** do dono (maior risco de calibração:
  o vocabulário real do `secao`/`chave` pode variar mais do que os padrões cobertos hoje).
- **Reconciliação B/C** (aproximam para humano, não automatizam).
- **Refino da extração por tipo** (linhas esperadas de cada demonstração) — guiado pelo golden set.
- Portal Vercel: ação dedicada de "confirmar" para pendências de reconciliação (hoje só lista).
