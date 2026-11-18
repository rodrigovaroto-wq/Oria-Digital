# Leitor — leitura determinística de arquivos oficiais e tabulares

Lê arquivos cujo formato é conhecido, **sem IA**: SPED, XML fiscal (NF-e, NFS-e, CT-e), eSocial,
EFD-Reinf, CNAB 150/240/400, OFX, CSV e XLSX volumosos e o zip que o contador manda. Para cada arquivo devolve um
**envelope**: o que é, de quem, de quando, quantos registros o arquivo **declara** ter e quantos
foram **lidos**. Arquivo truncado, versão de leiaute desconhecida ou entrada de zip recusada
aparecem na saída com o motivo, nunca como leitura bem-sucedida.

A especificação é a [`Espec. 12 — Fontes oficiais e captação`](../Arquitetura%20do%20Sistema/2%20Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md);
o aging e o mapeamento de colunas vêm do [`PLANO_MVP_2026-11.md`](../Arquitetura%20do%20Sistema/3%20Estado%20e%20Execução/PLANO_MVP_2026-11.md) (MB1–MB4).

## Uso

```bash
node Leitor/ler.mjs <arquivo>...
```

```bash
LEITOR_PSQL="psql '<url>'" node Leitor/ler.mjs --caso <uuid> [--documento <uuid>] <arquivo>...
```

A primeira forma imprime o envelope de cada arquivo em JSON. A segunda o registra na tabela
`arquivo_oficial`. O comando sai com código 1 se algum arquivo não ficou `lido`.

**Ainda não está no fluxo de produção:** o n8n não chama o leitor. Onde ele vai rodar (serviço,
contêiner ou nó do n8n) está em aberto; a medição dessa decisão está em
[`medicao-n8n/README.md`](medicao-n8n/README.md).

## Módulos (`lib/`)

| Arquivo | Responsabilidade |
|---|---|
| `envelope.mjs` | o envelope de um arquivo oficial (identificação, contagem declarada × lida) |
| `familia.mjs` | descobre a família do arquivo pelos bytes, não pela extensão |
| `leiautes.mjs` | registro de leiautes suportados, versão por versão |
| `campos.mjs` | particularidades de formato que erram em silêncio (sinal, decimal, datas) |
| `resumo.mjs` | o resumo que vai ao banco no lugar do arquivo bruto |
| `zip.mjs` | abre o zip em fluxo e por posição, com limites contra zip-bomb e afins |
| `sha256.mjs` | hash incremental em JS puro (o mesmo no CLI e no navegador) |
| `tabela.mjs` | leitor tabular em fluxo: CSV e XLSX de até milhões de linhas |
| `mapeamento.mjs` | o que cada coluna de contas a receber/pagar significa |
| `aging.mjs` | o aging da carteira numa data-base |
| `arquivo.mjs` | adaptador do disco para fluxo (a única parte que depende do Node) |

O mesmo código de `lib/` roda no navegador do analista: o arquivo é lido na máquina dele e só o
resumo sai dela.

## Testes

```bash
node --test 'Leitor/test/*.test.mjs'
```

Os arquivos de entrada vêm de geradores sintéticos ([`Dados de Teste/fontes-oficiais/`](../Dados%20de%20Teste/fontes-oficiais/)
e [`Dados de Teste/volume/`](../Dados%20de%20Teste/volume/)). Eles provam a coerência do leitor,
não que ele lê um arquivo real: isso só se mede com arquivo real.
