# O leitor dentro do n8n aguenta um SPED de 10 milhões de linhas? — medição de 13/10/2026

**A pergunta (sessão 108).** O dono decidiu que o leitor roda no mesmo PikaPods do n8n. Como o
PikaPods só roda os apps do catálogo, isso quer dizer que ele roda **dentro do n8n, num nó Code**.
O dono pediu a garantia de que um SPED com pelo menos 10 milhões de linhas passa por esse caminho.

**A resposta, medida:**
- **Pelo caminho de hoje, não passa.** O caminho de hoje é o binário inteiro com `getBinaryDataBuffer`, o que o `Preparar Conteudo` faz. Com 3 milhões de linhas, ele **derruba o n8n inteiro**.
- **Por fatias de Range HTTP, passa.** As 10 milhões de linhas foram contadas e gravadas no Postgres com a memória plana.

O que esta medição NÃO cobre está no fim do arquivo, e são as condições da garantia.

## Ambiente

- n8n **2.30.7**, a versão de produção citada no `N8N/README.md`, instalado do npm e rodando com `n8n start`.
- Configuração padrão: SQLite, task runner JS interno e binário em `filesystem`.
- Node 22.22, 4 núcleos, 16 GB de RAM.
- Postgres 16 local, com tabela comum (logada, com chave primária).
- O "Storage" é `servir-range.mjs`, um servidor HTTP com `Range`.

O arquivo de teste é uma ECD sintética (`gerar-grande.mjs`):
- tem o cabeçalho do gerador de `Dados de Teste/fontes-oficiais`;
- tem N linhas `I250` de ~118 bytes, com acento;
- os `9900` e o `9999` são coerentes;
- 10M de linhas = **1,19 GB**.

O leitor do repositório (`Leitor/ler.mjs`) dá `lido` nos dois tamanhos, então o arquivo é coerente.

## Os números

"Pico" é a RSS máxima amostrada a cada 0,5 s (`medir.sh`). "Heap 384/192" quer dizer
`NODE_OPTIONS=--max-old-space-size=384` no processo principal e `N8N_RUNNERS_MAX_OLD_SPACE_SIZE=192`
no runner, que é como fica um pod de ~1 GB.

| Caminho | Linhas | Heap | Resultado | Tempo | Pico principal + runner |
|---|---|---|---|---|---|
| CLI fora do n8n (`ler.mjs`, em fluxo) | 10M | padrão | `lido`, 10.000.010 = 9999 | 14,8 s | 86 MB |
| **Binário inteiro** (`no-binario-inteiro.js`) | 1M | padrão | ok, mas 45 s só no `getBinaryDataBuffer` | 46 s | 3.900 + 3.818 MB |
| **Binário inteiro** | 3M | padrão | **o n8n CAI**: `FATAL ERROR: invalid table size Allocation failed - JavaScript heap out of memory` | — | — |
| **Binário inteiro** | 1M | 384/192 | **o n8n CAI**, mesmo erro | — | — |
| Fatias de 16 MB como texto UTF-8 | 10M | padrão | contagem certa, **acento perdido** | 38 s | 905 + 625 MB |
| Fatias de 4 MB como bytes (`no-fatias-envelope.js`) | 10M | padrão | contagem certa, acento certo | 114 s | 1.032 + 554 MB |
| Fatias de 4 MB como bytes | 10M | **384/192** | contagem certa, acento certo | 116 s | 548 + 368 MB |
| **Carga no Postgres** (`no-planejar.js` + sub-workflow `no-ler-fatia.js`, fatia de 32 MB) | 1M | 384/192 | 1.000.010 linhas gravadas | 20 s | 590 + 381 MB |
| **Carga no Postgres** | **10M** | **384/192** | **10.000.010 linhas gravadas** em 36 fatias; zero perdida ou duplicada na emenda (`count(distinct (fatia_ini, ordem))` = total); 10.000.000 com `LANÇAMENTO` intacto; 1,95 GB de tabela | **222 s** | **563 + 386 MB** |

Ociosos, os dois processos ocupam ~456 + ~137 MB. A carga de 10M acrescenta **menos de 400 MB**
ao que o n8n já ocupa parado, e o pico do 10M é o mesmo do 1M.

## Por que o binário inteiro cai

O stack do `FATAL ERROR` passa por `JSObject::AddDataElement` / `KeyedStoreIC_Slow`. Para entregar
o binário ao task runner, o n8n o transforma num objeto JS **byte a byte**: 117 MB de arquivo
viraram ~3,9 GB no processo principal. A mesma serialização aparece nas fatias, onde o corpo chega
ao runner como `{type:'Buffer', data:[...]}`. É por isso que a fatia de bytes é de **4 MB**.

O processo que cai é o **principal**, não o runner. Com ele cai o n8n inteiro, com todas as
execuções em curso, igual ao 502 de `.claude/memory/n8n-nao-aguenta-baixar-execucao-grande.md`.

## Por que a carga usa sub-workflow

Num laço dentro da mesma execução, o n8n guarda a saída de cada volta no `runData` até o fim. Com
10M, isso dá 1,2 GB de texto em memória. A execução filha devolve só `{linhas}` e solta o resto
quando termina. É o que mantém o pico do 10M igual ao do 1M. Por isso o sub-workflow roda com
`saveDataSuccessExecution: none`: salvar 32 MB por fatia no banco do n8n seria a mesma conta pelo
outro lado.

## Para repetir

```bash
npm install n8n@2.30.7                      # numa pasta fora do repositório
node Leitor/medicao-n8n/gerar-grande.mjs 10 /tmp/ecd_10M.txt
node Leitor/medicao-n8n/servir-range.mjs /tmp &          # o "Storage", porta 8099
node Leitor/medicao-n8n/montar.mjs /tmp/wf              # os 4 workflows
# a tabela e a função da carga (ver no-ler-fatia.js): linha_sped + fn_carregar(bigint, text)
n8n import:credentials ... ; n8n import:workflow --input=/tmp/wf/<id>.json ; n8n publish:workflow --id=<id>
NODE_OPTIONS=--max-old-space-size=384 N8N_RUNNERS_MAX_OLD_SPACE_SIZE=192 n8n start
Leitor/medicao-n8n/medir.sh "http://localhost:5678/webhook/carregar?arq=ecd_10M.txt&mb=32"
```

A função usada na carga (só da medição; a de verdade nasce na onda 1, por migration):

```sql
create table linha_sped (id bigserial primary key, fatia_ini bigint, ordem int, reg text, conteudo text);
create function fn_carregar(p_ini bigint, p_txt text) returns int language sql as $$
  with ins as (insert into linha_sped (fatia_ini, ordem, reg, conteudo)
               select p_ini, o::int, substr(l, 2, 4), l
                 from regexp_split_to_table(p_txt, E'\r?\n') with ordinality as t(l, o) where l <> ''
               returning 1)
  select count(*)::int from ins $$;
```

## O que NÃO foi medido: as condições da garantia

A garantia vale para este n8n, nesta máquina. Em produção ela depende de cinco coisas que daqui
não dá para ver:

1. **A RAM e a CPU do plano do PikaPods.**
   - Medido: o n8n parado ocupa ~600 MB, e a carga de 10M sobe para ~950 MB com o heap limitado.
   - Num plano de 1 GB não sobra margem. Com 2 GB sobra.
   - A CPU do PikaPods é compartilhada. Aqui a carga levou 222 s em 4 núcleos, e lá pode levar várias vezes isso.
   - Cada tarefa do runner é uma fatia de 32 MB, alguns segundos de trabalho, muito abaixo do teto de 300 s (`N8N_RUNNERS_TASK_TIMEOUT`).
2. **O Supabase Storage aceitar `Range` e um arquivo de 1,2 GB.**
   - O plano gratuito limita o arquivo a 50 MB.
   - Arquivo grande pede envio resumível (TUS), e não o envio simples. É a peça 2 da Espec. 12 §11.
   - **Hoje nenhum arquivo acima de ~4,5 MB chega ao n8n pelo portal**, porque a borda da Vercel recusa antes.
3. **O tempo de cada `insert` no Supabase.**
   - Local: ~6 s por fatia de 32 MB (~280 mil linhas).
   - Pela rede e com o `statement_timeout` do papel da credencial do n8n, a fatia pode ter de ser menor.
   - Medir contra produção antes da onda 1.
4. **O espaço em disco do banco.** Uma ECD de 10M de linhas ocupa ~2 GB de tabela, sem índice extra.
5. **Arquivo real.** O arquivo é sintético, e a linha real pode ser maior (regra 4). O desenho não depende do tamanho da linha, mas o tempo depende.

**E uma consequência imediata, independente da F2T:** o `Preparar Conteudo` usa
`getBinaryDataBuffer` em todo arquivo. Um SPED de 3 milhões de linhas que chegue ao n8n por
qualquer caminho que não seja o portal (o formulário do n8n direto, por exemplo) **derruba a
instância**. A rota da F2T tem de decidir a família **antes** de pegar o binário.

## A alternativa medida: ler no navegador e guardar só o que importa (13/10/2026, mesma sessão)

O dono respondeu às condições acima: o PikaPods subiu para 2 GB. Pagar o Supabase para guardar o
arquivo é o último recurso. E 2 GB de banco por ECD é demais: guardar a linha bruta não é
necessário se o que as reconciliações usam for guardado.

**O que as reconciliações usam (Espec. 12 §1).**
- S1 usa o `J150` e o `L300`.
- S2 usa o `I155` com o `I050`.
- S5 usa o `E110`, o `M200` e o `M600`.
- S6 usa o `M300`.
- Nenhuma usa o lançamento um a um (`I200`/`I250`), que é ~75% das linhas de uma ECD.
- O mesmo vale para o item de nota (`C170`) da EFD: a S3 usa o `C190`.

**A medição.** O arquivo vem de `gerar-ecd-realista.mjs`, uma ECD de 10.000.180 linhas (929 MB) com
a composição de uma real:
- 2.000 contas;
- 24.000 `I155`;
- `J100` e `J150`;
- 7,48M de `I250`.

`navegador-leitor.js` roda num Chromium de verdade (`navegador-medir.mjs`, Playwright). Ele lê o
`File` em fluxo, sem o arquivo sair da máquina, e:
- calcula o SHA-256 incremental, **idêntico ao `sha256sum`**, que é a identidade da `0206`;
- confere o 9999 e o 9900;
- guarda os registros-chave na íntegra, com o número da linha;
- soma os `I250` por conta e mês (débito, crédito, quantidade, primeira linha).

| | 10M de linhas |
|---|---|
| Tempo | **22,9 s** |
| Pico de memória do JS | **59 MB** (RSS do navegador inteiro: 529 MB) |
| 9999 / 9900 | 10.000.180 = 10.000.180 / bate |
| Registros-chave guardados na íntegra | 26.211 linhas |
| `I250` somados | 7.480.476 (= `grep -c '^|I250|'`) em 18.000 grupos conta × mês |
| **O que viaja e é gravado** | **3,4 MB** de JSON, **745 KB** comprimido. Contra 1,95 GB da carga bruta: ~570× menos |

O que isso resolve:
- **Não precisa de Storage**: o arquivo não sai do computador do analista.
- **Não passa pela borda da Vercel**: 745 KB < 4,5 MB.
- **Não passa pelo n8n**, então não derruba a instância.
- **O banco guarda MB, e não GB.**
- O CLI (`Leitor/ler.mjs`) continua sendo o caminho para a máquina do robô de captação (P5, D12.5).

O que custa:
1. **O lançamento individual não fica guardado.** Só a soma por conta e mês fica. Uma análise
   futura que precise do lançamento (parte relacionada, lançamento manual no fechamento) exige
   reenviar o arquivo. O hash prova que é o mesmo arquivo.
2. **O resumo é calculado no navegador, então o servidor tem de reconferir o que dá para
   reconferir** (fronteira de confiança). Exemplos:
   - a soma das quantidades agregadas = a contagem do `I250` = o 9900 declarado;
   - saldo inicial + débitos − créditos = saldo final em cada `I155`.
3. **O arquivo é sintético** (regra 4): o tamanho do resumo de uma ECD real depende do número de
   contas, e não do número de linhas.

### O leitor do repositório no navegador (não o protótipo)

O número acima (22,9 s, 59 MB) é do protótipo `navegador-leitor.js`. Depois disso, o próprio
`Leitor/lib/envelope.mjs` passou a rodar no navegador (`lerEnvelopeDeFluxo` + `resumo.mjs`).
`navegador-igual-ao-cli.mjs` serve o repositório por HTTP, importa o módulo num Chromium real,
lê o arquivo com `File.stream()` e compara o resultado com o do CLI (`arquivo.mjs`):

| Arquivo | Igual ao CLI | Hash = `sha256sum` | Tempo no navegador | Pico de heap JS | Resumo |
|---|---|---|---|---|---|
| ECD realista de 10.000.180 linhas (929 MB), contas de 16 caracteres | sim | sim | 37,5 s | **61 MB** | 18.000 grupos, 26.196 linhas na íntegra, 4,7 MB |
| ECD com bytes 0x80–0x9F no nome (o "–" e o "€" do cp1252) | sim | sim | 0,07 s | — | — |

As contas têm 16 caracteres de propósito. A partir de 13, o V8 guarda um recorte de string como
referência à fatia de ~64 KB de onde ele veio. Por isso o `resumo.mjs` copia a conta e a linha
que guarda, e o pico ficou igual ao do protótipo.

O caminho de volta do cp1252 só roda no navegador, e por isso foi checado nos dois sentidos.
Com `desfazerCp1252` desligado, o mesmo arquivo saiu "AÇÚCAR – €" no navegador, diferente do CLI,
e o script terminou com 1.
