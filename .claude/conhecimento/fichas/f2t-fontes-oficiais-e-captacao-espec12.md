---
id: f2t-fontes-oficiais-e-captacao-espec12
tipo: doutrina
toca:
  - Arquitetura do Sistema/2 Especificação/12_FONTES_OFICIAIS_E_CAPTACAO.md
  - Arquitetura do Sistema/3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md
  - N8N/lib/formato.mjs
  - Leitor/lib/familia.mjs
  - Leitor/lib/envelope.mjs
  - Leitor/lib/zip.mjs
  - Leitor/ler.mjs
  - Supabase/migrations/0206_o_arquivo_oficial_lido_e_contado.sql
prova: Leitor/test/*.test.mjs
ancora: Leitor/lib/familia.mjs#detectarFamilia
ancora_sha: b98051c598ec
substitui: []
---

# F2T — fontes oficiais (SPED, eSocial, logística, CNAB, OFX, CNAE) e captação: Espec. 12 e decisões D12.x

Termos de busca: SPED, EFD, ECD, ECF, Reinf, eSocial, CT-e, MDF-e, CNAB, OFX, CNAE, F2T, captação,
NF-e, NFS-e, Espec. 12.

**Estado (13/10/2026, sessão 107): etapa 1 FEITA, sem ligação ao n8n.**
- O leitor (`Leitor/`) reconhece a família e lê o envelope em fluxo, conferindo a contagem declarada.
- O CLI (`Leitor/ler.mjs`) grava em `arquivo_oficial` (migration `0206`, escrita e **não aplicada em produção**).
- Prova: `Leitor/test/leitor.test.mjs` (32 testes, 26 guardas medidos não-vazios) e `Supabase/test/arquivo_oficial.test.sql` (65 asserts).
- O n8n ainda manda SPED e NF-e para a IA (nó Preparar Conteúdo, `buf.toString('utf-8')`).

**Sessão 108 (13/10/2026): o leitor NÃO vai para o n8n. Ele roda no navegador do analista.**
- Pelo n8n, um SPED de 3M de linhas derruba a instância (ficha `n8n-binario-grande-derruba-a-instancia`).
- Decisão do dono: o arquivo é lido no navegador, e só o RESUMO sai da máquina (`Leitor/lib/resumo.mjs`).
- O resumo da ECD guarda a íntegra dos registros pequenos e soma os I250 por conta, mês e IND_LCTO.
- `envelope.mjs` é o mesmo código no navegador e no CLI (`arquivo.mjs` só abre o disco como fluxo), e não usa `node:*` nem `Buffer`.
- Prova de igualdade num Chromium real: `Leitor/medicao-n8n/navegador-igual-ao-cli.mjs`.
- **Latin1 ≠ `TextDecoder('latin1')` no navegador:** pelo WHATWG, ali é windows-1252, e o 0x96 vira "–". `campos.mjs#latin1` desfaz isso.

## Armadilhas que a revisão independente achou (e que voltam em toda onda)

- **Identidade de escrituração não é CNPJ + período.** A ECD da SCP traz no 0000 o CNPJ do sócio ostensivo
  (COD_SCP no índice 18; na ECF, 15). O livro auxiliar (I010.IND_ESC A/Z) convive com o principal. Os dois
  entram na chave natural, senão um substitui o outro na vigência.
- **Memória e fluxo têm de quebrar linha igual** (`QUEBRA = /\r\n|\n|\r/`): o `readline` quebra em `\r`
  solto e `split('\n')` não. Toda entrada de zip passa pelo caminho em memória.
- **Contagem vazia é null, nunca 0** (`inteiro()` em `campos.mjs`): `Number('')` dá 0.
- **A vigência cobre só SPED retificado e reenvio.** NF-e cancelada (evento com chave própria),
  S-1200 retificador/S-3000 (Id próprio) e retorno CNAB duplicado (hash diferente) ficam para as ondas 3, 4 e 2.
- **Releitura:** o mesmo hash com status não lido ou `leitor_versao` diferente ATUALIZA a linha. Ao mudar
  um leiaute, suba `LEITOR_VERSAO` e releia.
- **Sonar:** os namespaces `http://` dos schemas oficiais levam NOSONAR(S5332). Parâmetro de opção com
  `null` como padrão vira "bug" S3403; use `''`.

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
- A mensagem do commit `c0d54eb` diz que o roteador reconhece "texto e zip SÓ como xlsx/docx". Está
  errada: a medição acima é a correta. A G5 da Espec. 12 já foi corrigida (sessão 106).

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
