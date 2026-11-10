# Reimportar o workflow no n8n — o que conferir, nó a nó

Feito para a reimportação de **11/09/2026**, que troca DUAS coisas ao mesmo tempo:
o provedor de IA (Google → OpenAI `gpt-5.6-luna`) e a topologia (roteamento por
formato, 7 nós novos). Rodar sem reimportar roda o Gemini contra a conta sem
billing — ou seja, repete as 72 falhas do "Teste 00".

## Antes de tudo: NUNCA faça PUT do JSON direto

O JSON do repositório **não tem** os ids da sua instalação nem alguns toggles.
Publicar direto perde `onError` em 23 nós, `retryOnFail` em 11 e o `multipleFiles`
do formulário. Use sempre o par de scripts:

```bash
curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
  | node N8N/preparar-republicacao.mjs > publicar.json

curl -X PUT -H "X-N8N-API-KEY: $N8N_API_KEY" -H 'Content-Type: application/json' \
  "$N8N_URL/api/v1/workflows/$ID" --data-binary @publicar.json

curl -s -H "X-N8N-API-KEY: $N8N_API_KEY" "$N8N_URL/api/v1/workflows/$ID" \
  | node N8N/conferir-publicado.mjs
```

O terceiro comando é o que vale: ele compara o publicado contra o repositório e
lista o que não bate, **inclusive `disabled`/`onError`/`retryOnFail` e o nome de
cada credencial**. Se ele disser "ok", o resto deste arquivo é conferência dupla.

## Os cinco pontos que o script NÃO cobre

1. **`multipleFiles` no campo de arquivo do formulário.** É o pior toggle perdido:
   sem ele o intake aceita **um documento por vez**, e o sintoma só aparece quando
   alguém tenta subir 190. Confira no editor, no nó `Intake (Form)`.
2. **A credencial da OpenAI.** O JSON aponta para uma credencial Header Auth
   chamada exatamente **`OpenAI API`**. Se a sua tem outro nome, ou o nome muda ou
   o JSON não acha. São **4 nós** usando credencial.
3. **O teto de gasto na conta OpenAI.** É configuração de conta, não de código, e
   **conta nova começa sem teto nenhum**. Ponha US$ 5. É a única defesa que um bug
   do próprio código não fura.
4. **O `Roteador de Formato`** (nó novo): confira que tem as 6 condições de
   mimetype **mais a saída de sobra** (fallback). Sem o fallback, formato
   desconhecido some.
5. **Rode o diagnóstico antes do lote.** O workflow `Diagnostico da conta OpenAI`
   faz uma chamada de 1 token e um GET no catálogo. Ele responde, de graça, as
   duas perguntas que nenhum teste daqui responde: a conta aceita o modelo, e o
   `gpt-5.6-luna` está mesmo disponível para ela.

## A tabela completa — todo nó, como ele deve ficar

`onError = continueRegularOutput` significa "se falhar, não derruba o lote".
Nó sem `onError` é proposital: ali falhar **tem** de parar.

| Nó | Tipo | onError | retryOnFail | disabled |
|---|---|---|---|---|
| Intake (Form) | formTrigger | — | — | — |
| Upsert Caso (Postgres) | postgres | continueRegularOutput | sim | — |
| Listar Arquivos | code | — | — | — |
| Classificar Nome | code | continueRegularOutput | — | — |
| Orcamento do Lote | code | — | — | — |
| Lote cabe? | if | — | — | — |
| Registrar Recusa | postgres | continueRegularOutput | sim | — |
| Abortar Lote | code | — | — | — |
| Extrair Texto | extractFromFile | continueRegularOutput | — | — |
| Preparar Conteudo | code | continueRegularOutput | — | — |
| Roteador de Formato | switch | — | — | — |
| Extrair CSV | extractFromFile | continueRegularOutput | — | — |
| Copiar Como ZIP | code | continueRegularOutput | — | — |
| Ler Abas do XLSX | compression | continueRegularOutput | — | — |
| Expandir Abas | code | — | — | — |
| Extrair XLSX | extractFromFile | continueRegularOutput | — | `options.sheetName` = expressão `$json.aba_nome` |
| Extrair XLS | extractFromFile | continueRegularOutput | — | — |
| Extrair XML | extractFromFile | continueRegularOutput | — | — |
| Juntar Extracao de Conteudo | merge | — | — | — |
| Recompor Conteudo Extraido | code | — | — | — |
| Medir Documento | code | continueRegularOutput | — | — |
| Upload Storage | httpRequest | — | — | SIM |
| Precisa Fallback? | if | — | — | — |
| Montar Req Classif | code | continueRegularOutput | — | — |
| IA Classificar | httpRequest | continueRegularOutput | sim | — |
| Parse Classif | code | continueRegularOutput | — | — |
| Juntar Ramos | merge | — | — | — |
| Registrar Documento | postgres | continueRegularOutput | sim | — |
| Recomputar Completude | postgres | continueRegularOutput | sim | — |
| Recompor Contexto | code | continueRegularOutput | — | — |
| Extracao ja feita? | if | — | — | — |
| Juntar Extraidos | merge | — | — | — |
| Montar Req Extracao | code | continueRegularOutput | — | — |
| Fatiar Extracao | code | continueRegularOutput | — | — |
| IA Extrair | httpRequest | continueRegularOutput | sim | — |
| Parse Extracao | code | continueRegularOutput | — | — |
| Juntar Blocos | code | continueRegularOutput | — | — |
| Gravar Campos (Sombra) | postgres | continueRegularOutput | sim | — |
| Registrar Diagnostico | postgres | continueRegularOutput | sim | — |
| Reconciliar (Classe A) | postgres | continueRegularOutput | sim | — |
| Reconciliar Lote | postgres | continueRegularOutput | sim | — |
| Resumo de Custo | code | continueRegularOutput | — | — |
| Gravar Uso do Lote | postgres | continueRegularOutput | sim | — |
| Abrir Lote | postgres | continueRegularOutput | sim | — |
| Conferir Lote | postgres | continueRegularOutput | sim | — |

## Depois de publicar

- `node N8N/conferir-publicado.mjs` tem de dizer **ok**.
- Rode o workflow de diagnóstico (1 token).
- Só então um lote real.

## O que ainda não foi visto rodar na sua instância

Duas coisas vêm da documentação do n8n, não de observação:

1. **`Extract From File` devolve uma linha por item** de planilha. O nó
   `Recompor Conteudo Extraido` reagrupa por documento contando com isso.
2. **`pairedItem` atravessa o Merge de 7 entradas.** Se não atravessar, o
   documento perde o contexto a caminho do banco.

Ambas são cobertas por teste no repositório, mas **teste mede o JSON, não a sua
instância**. No primeiro lote com planilha, confira no banco que cada arquivo
virou o seu próprio documento, com `caso_id` preenchido.
