# Dados de Teste

Tudo aqui é **sintético ou capturado de propósito**, e cada pasta diz qual dos dois. Os books são
gerados por código: o gerador escreve o PDF/XLSX **e** a verdade (`METRICAS.json`, as linhas que
ele escreveu), e as suítes comparam o que o sistema leu com essa verdade.

## Books sintéticos

| Pasta | Grupo fictício | Para que serve |
|---|---|---|
| [`book-vertentes/`](book-vertentes/) | Grupo Vertentes | book de referência: 14 documentos em dificuldade financeira severa; é o insumo do teste de ponta a ponta (`Verificação/run.mts`) e da fixture do banco |
| [`book-canastra/`](book-canastra/) | Grupo Canastra | 38 documentos, 6 empresas, 3 exercícios: os documentos **difíceis** (régua de cobertura, custo do book) |
| [`book-distress/`](book-distress/) | Grupo Piraquara | 14 documentos de distress: passivo a descoberto e covenant rompido; o gerador confere 16 identidades contábeis por `assert` |
| [`book-espelho/`](book-espelho/) | Serra do Espelho | 7 PDFs e 4 planilhas com a **forma** dos documentos reais que falharam (planilha de duas abas, por exemplo) |
| [`volume/`](volume/) | — | contas a receber, contas a pagar e OFX com 10 mil a 1 milhão de linhas, para o leitor tabular e o aging |
| [`fontes-oficiais/`](fontes-oficiais/) | — | SPED, XML fiscal, CNAB e OFX fictícios para o leitor de arquivos oficiais |
| [`comum/`](comum/) | — | código compartilhado pelos geradores (a contagem de verdade das linhas de conta) |

Gerar (o `PYTHONPATH=.` é obrigatório):

```bash
cd "Dados de Teste/book-vertentes" && PYTHONPATH=. python3 gerar.py
```

Os PDFs e XLSX gerados não são versionados; o CI os gera em toda passada. Dependências e a ordem
completa estão em [`.claude/COMANDOS-CANONICOS.md`](../.claude/COMANDOS-CANONICOS.md).

## Capturas de produção

| Pasta | O que é |
|---|---|
| [`capturas/2026-08-04-v35-modelagem/`](capturas/2026-08-04-v35-modelagem/) | a tela de Modelagem salva pelo navegador, para comparar layout |
| [`capturas/2026-08-31-texto-extraido-n8n/`](capturas/2026-08-31-texto-extraido-n8n/) | o texto que o nó `Extrair Texto` produziu em produção para 20 documentos do Canastra |
| [`capturas/2026-09-01-texto-extraido-araucaria/`](capturas/2026-09-01-texto-extraido-araucaria/) | o mesmo para 2 dos 190 documentos de uma rodada real |

Cada captura tem um README com a origem e o que ela prova e não prova.
