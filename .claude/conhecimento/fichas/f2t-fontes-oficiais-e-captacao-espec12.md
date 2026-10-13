---
id: f2t-fontes-oficiais-e-captacao-espec12
tipo: doutrina
toca:
  - Arquitetura do Sistema/2 Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
  - N8N/lib/formato.mjs
ancora: N8N/lib/formato.mjs#detectarFormato
ancora_sha: 339d8072ad42
substitui: []
---

# F2T — fontes oficiais (SPED, eSocial, logística, CNAB, OFX, CNAE) e captação: Espec. 12 e decisões D12.x

Termos de busca: SPED, EFD, ECD, ECF, Reinf, eSocial, CT-e, MDF-e, CNAB, OFX, CNAE, F2T, captação,
NF-e, NFS-e, Espec. 12.

**Estado (13/10/2026): só planejamento.** Não há migration, workflow nem teste desta fase, e nada foi
medido em produção. Por isso esta ficha não tem `prova`: não existe suíte que reprove a violação, e
inventar uma seria a falsa afirmação que o `INSTRUCOES.md` proíbe.

## O que a F2T é, e por que não é a F2

A F2 dá consumidor aos tipos que já chegam pela extração por IA. A F2T é um segundo caminho de entrada,
determinístico e sem IA, para arquivos de leiaute oficial (SPED, eSocial, XML fiscal e de transporte,
CNAB, OFX), mais a captação automática deles. O escopo está na Espec. 12; a ordem e as dependências estão
no roadmap, fase F2T.

## Fatos medidos (não supostos)

- `SPED`, `EXTRATO_BANCARIO`, `AGING_AP` e `AGING_AR` são `sem_consumidor` na `0187`. Zero SPED em produção.
- `buscar.mjs` dá NADA ENCONTRADO para `esocial`, `cnae`, `ofx` e `cnab` (853 nós). Termo novo no
  projeto: quem for mexer nisso começa por esta ficha.
- `detectarFormato` (`N8N/lib/formato.mjs`) decide pelos BYTES: PDF, imagem, xlsx, XML (declaração
  `<?xml` no início), texto delimitado (`;` `,` tab `|`), HTML e zip. Zip que não é planilha vira
  `desconhecido` ("o pipeline não extrai este formato"), então zip com vários arquivos não abre.
  **O roteador reconhece a FORMA do arquivo, não a família fiscal**: SPED, NF-e, eSocial, CNAB e OFX não
  são identificados. Essa identificação é o que a F2T acrescenta.
- Correção de texto pendente: o commit `c0d54eb` diz que o roteador reconhece "texto e zip SÓ como
  xlsx/docx". Isso está errado (a medição acima é a correta). A G5 da Espec. 12 deve ser corrigida na
  próxima rodada da especificação.

## Decisões do dono (13/10/2026) que não se desfazem sem nova decisão

- **D12.4 = D6 da Espec. 11.** A mesma decisão tem numeração diferente em duas especificações. Antes de
  citar ou decidir um "D" de uma delas, conferir a outra. Resposta: sem Open Finance; o extrato vem por
  arquivo (OFX, depois CNAB E).
- **D12.10:** o Simples Nacional e as declarações estaduais ficam fora. Sem fonte fiscal independente, a
  receita é conferida só contra o declarado. O efeito fica escrito no caso (regra 1).
- **D12.9:** o leitor é um serviço próprio em Node, fora do n8n, gravando em lote. O merge do n8n estoura
  com ~125-150 mil itens (roadmap, 17/09/2026), abaixo de um ano de XML ou extrato.
- **D12.3 (Integra Contador) continua ABERTA:** cotar antes, com o SERPRO. Não bloqueia a etapa 1 nem a
  onda 1. Os demais D12.1-D12.11 estão tomados.

## Os [A CONFIRMAR] sem responsável (G27)

ReceitaNet BX para procurador; serviços do Integra; eSocial para procurador; API do Portal Único com
certificado; cronograma da reforma tributária (G8). Cada um com quem verifica e como, na G27.
