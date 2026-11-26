# Fase A — Fontes públicas grátis (prioridade em vigor)

**Detalhe da primeira fase da prioridade definida pelo dono em 24/11/2026.** O plano único continua
sendo o [`PLANO_DE_EXECUCAO.md`](PLANO_DE_EXECUCAO.md) (K1): ele diz a ordem; este arquivo diz o
passo a passo da Fase A. **A1 e A2 estão feitas e em produção** (25/11/2026; medidas no Andamento do plano único e no `ESTADO.md`, sessão 138). A3 em andamento: fontes 1 a 3 no repositório (sessão 139); republicação e 1ª execução em produção NÃO CONFERIDAS; fontes 4 a 9 não feitas. A4 e A5 não construídas.

## 1. A ordem que o dono definiu

```
Fase A  Fontes públicas grátis ──► todas as APIs conectadas e visíveis no portal
Fase B  Book confiável ───────────► extrato conciliado, página de cada número, Registrato e SPED lidos
Fase C  Conferência e análises ───► contabilidade × fontes, mapa da dívida, caixa 13 semanas, juro × mercado
```

- **Por que esta ordem:** são as partes que a Oria constrói sozinha, com dado que já existe e grátis,
  sem esperar parceiro, contrato ou demo. Depois delas entram as três plataformas prontas (Direct
  Data, JUDIT, Serasa) e o restante do plano.
- **Os agentes de IA vêm depois das três fases.** A pergunta "o MVP fica sem agentes?" foi feita ao
  dono em 24/11/2026 e **não teve resposta explícita**; o que ele decidiu foi a ordem A → B → C.
  Registrar só a ordem até ele confirmar o resto.
- **A Fase 0 não some.** Os itens P1 da Fase 0 (backup, n8n com chave restrita, extração em N1,
  contrato com a IA, RIPD) continuam exigidos antes do **primeiro mandato real** (portão G0). A
  Fase A puxa só a cópia de segurança para o começo (A1).

## 2. Decisões do dono (24/11/2026) — registrar na v0.1.7 do registro

| # | Decisão | Efeito na Fase A |
|---|---|---|
| 1 | Ordem A → B → C como prioridade | Este arquivo |
| 2 | Cadastro CNPJ pelo **espelho gratuito** (BrasilAPI), marcado como **não oficial** | A base oficial da Receita fica **pendente** ([pendências](../08_pendencias_e_riscos/PENDENCIAS_RISCOS_E_QUESTOES_FUTURAS.md)) |
| 3 | Listas pequenas baixadas inteiras; **PGFN e PEP por consulta** | A PGFN entra na A4; o PEP é de pessoa física e fica fora da Fase A |
| 4 | Consultar os sócios **mesmo sem autorização registrada**, mas **por enquanto só a empresa** | A Fase A consulta só CNPJ. **Conflito a resolver antes de consultar pessoa física:** a decisão contradiz a N-C7b e a regra R5 da Espec. 13 ("nada de PF sem autorização; a recusa é no banco") e o item 1.B7 do plano. Precisa de decisão registrada e conversa com o advogado |
| 5 | Cópia de segurança agora, **pequena e rápida** | A1, a versão mínima dos itens 0.2 e 0.3 |
| 6 | ANBIMA, CCEE e FipeZAP são **fontes oficiais** (24/11, ao revisar a A2) | `oficial = verdadeiro` no catálogo; só a BrasilAPI fica "não oficial" |
| 7 | O 404 da fonte que quer dizer "não existe" é tratado **na A4**, fonte por fonte | Até lá todo 404 grava "falhou"; na A4, cada fonte de empresa mede o seu 404 e preenche `http_inexistente` |
| 8 | **Toda fonte tem prazo de validade**, à prova de falhas (24/11) | O banco recusa fonte sem prazo. Prazo = até a próxima publicação: o publicado pela fonte; senão, o da cadência (diária 1, semanal 7, mensal 30, trimestral 90, semestral 180, anual 365 dias); cadência desconhecida ou variável = **1 dia** (vence cedo, nunca parece nova estando velha). A origem do prazo fica gravada; A3 e A4 trocam o mínimo pelo real ao conectar cada fonte |

## 3. O que o teste de 24/11/2026 mostrou

Cada API foi chamada deste ambiente de desenvolvimento. "Não respondeu" pode ser bloqueio só daqui:
conferir no ambiente de produção antes de concluir que a fonte caiu.

| Situação | Fontes |
|---|---|
| **Já existe no sistema** | BCB/SGS (IPCA, IGP-M, INPC, Selic, CDI, câmbio) e Focus, com agendamento diário (`0025`, `N8N/lib/macro.mjs`, `N8N/workflow.macro.json`). **Execução em produção não conferida** |
| **Respondeu, sem chave** | BCB juros por modalidade (Olinda), IBGE/SIDRA, CVM dados abertos, IPEADATA, Comex Stat, ANBIMA (curva de juros), BrasilAPI (CNPJ), downloads da CGU (CEIS, CNEP), PGFN (página de dados abertos), IBAMA, lista do MTE (trabalho escravo) |
| **Pede chave gratuita** | API da CGU (401) e DataJud (401). A Fase A não precisa de nenhuma das duas: a CGU entra pelo download e o DataJud fica fora (ver §6) |
| **Não respondeu daqui** | CAGED (FTP do PDET) e ANEEL |

## 4. Dois tipos de fonte

| Tipo | Quando roda | Onde roda | Por quê |
|---|---|---|---|
| **Mercado** (séries do BCB, IBGE, CVM…) | Agendado, todo dia ou todo mês | n8n, como o macro de hoje | Não leva nenhum dado de cliente |
| **Empresa** (cadastro, sanções, dívida ativa…) | Ao criar o caso e pelo botão "Atualizar" | **Servidor do portal** (Vercel, São Paulo) | O CNPJ do cliente é dado do mandato, e a decisão H2 proíbe mandato real novo no n8n atual |

## 5. O roteiro, em 5 fatias

Cada fatia segue as sete regras do `CLAUDE.md`: uma fatia por commit, invariante **medido não-vazio**,
o porquê com o número, e um sinal positivo de que rodou (regra 7: fonte que não rodou não pode
parecer fonte que rodou e não achou nada).

### A1 · Cópia de segurança mínima (itens 0.2 e 0.3, versão enxuta)

- **O que é:** uma rotina no GitHub Actions, uma vez por dia, que copia o banco e os arquivos do
  Storage, criptografa e guarda como artefato do próprio GitHub por 30 dias. Nenhum fornecedor novo.
- **Armadilha conhecida:** o papel usado no `pg_dump` precisa enxergar todas as linhas. Um papel só
  de leitura, sem passar pela RLS, gera um arquivo **vazio sem erro**. A rotina compara a contagem
  de linhas de 5 tabelas-chave no arquivo com a do banco e falha se não bater.
- **Teste de restauração, uma vez:** restaurar o arquivo no Postgres do CI e rodar a sonda.
- **O dono faz:** cadastrar dois segredos no GitHub (a conexão do banco e a senha da criptografia).
- **Pronto quando:** uma restauração funciona do zero e as contagens batem.
- **Limite conhecido:** 30 dias de histórico e perda máxima de 1 dia. É a regra provisória da H1-1;
  a definitiva (perda de minutos, volta em 4 h) é o item 0.12.

### A2 · Base comum no banco

- **O que é:** três tabelas novas (desenho da Espec. 13 §3 e da Espec. 15 §7):
  - `fonte_externa` (o catálogo): nome, de onde vem, se é oficial, frequência, quando vence;
  - `consulta_externa`: cada consulta, com fonte, alvo, data, validade, custo (zero aqui) e
    **resultado em quatro estados**: encontrado, nada encontrado, falhou, não consultado;
  - `fato_externo`: o dado achado, ligado à consulta que o trouxe.
- **Regras no banco, não na tela:** consulta de fonte fora do catálogo é recusada; "falhou" nunca
  vira "nada encontrado"; toda tabela nova com RLS por mandato e o próprio GRANT (`0214`); sonda
  sabe que elas existem.
- **Pronto quando:** um teste SQL com uma API derrubada grava "falhou" (desligar a regra faz o teste
  reprovar, com o número de asserts no commit).

### A3 · Dados de mercado (agendados) — itens 1.C1 a 1.C5

Uma fonte por commit, nesta ordem (as primeiras servem à Fase C):

| Ordem | Fonte | O que traz | Para que serve |
|---|---|---|---|
| 1 | Conferir o macro em produção | Último dado gravado de cada série | Saber se o que existe roda |
| 2 | BCB juros por modalidade | Taxa média por tipo de empréstimo PJ | Fase C: juro de cada contrato × mercado |
| 3 | BCB/SGS: INCC, IBC-Br, crédito e inadimplência PJ, câmbio de outras moedas | Séries mensais | Premissas e cenário |
| 4 | IBGE/SIDRA | PIB, produção e vendas por setor, emprego | Empresa × setor |
| 5 | CVM | Cadastro e demonstrações das companhias abertas | Pares do setor |
| 6 | ANBIMA | Curva de juros | Despesa financeira projetada |
| 7 | IPEADATA, Comex Stat | Risco-país, exportação e importação por produto | Cenário e exposição externa |
| 8 | CAGED | Emprego por setor | Conferir o acesso em produção antes |
| 9 | Setoriais do slide 6: ANEEL/CCEE, ANTT/ANP, SUSEP, FipeZAP | Indicadores do setor | A decisão K6 pede todas no piloto |

- **Tamanho:** o banco está no plano gratuito (500 MB). Antes da CVM, medir o tamanho do banco e
  guardar só os campos usados. Se não couber, a decisão volta ao dono.
- **Pronto quando:** cada fonte aparece no catálogo com a data da última atualização; derrubar uma
  fonte aparece como "falhou", nunca como "sem dado".

**Estado (25/11/2026, sessões 139 e 140):**

- Fonte 1 (macro em produção): **medida.** O macro rodava mensal (dia 12); execuções em 12/10 e 12/11; último mês gravado: SELIC/CDI 2026-11, CÂMBIO_USD/IGPM 2026-10, IPCA/INPC 2026-09.
- Fonte 2 (juros PJ por modalidade): **feita e em produção** (sessão 139: `f102a92`, 0304; execução 10048 com 19 séries de juros). A taxa banco a banco da Olinda fica para depois (decisão do dono).
- Fonte 3 (SGS): **parcial** (`5e5c1d4`): IBC-Br, crédito e inadimplência PJ, euro PTAX. Ficaram de fora o INCC (nome não confirmado) e a série 7458 (parou em 2025).
- Fonte 4 (IBGE/SIDRA setorial): **feita e em produção** (sessão 140: `7e2b1f8`, `f5147ab`). 6 séries: PIB por setor, PIM-PF, PMC (total e por atividade), PMS, ocupados por grupamento. Uma consulta `ibge_sidra` por série; dados só em `fato_externo`. Medido pela sessão 140 em produção: macro republicado com 34 nós; execução 10052 `success`, 43 consultas `encontrado` (7 de `ibge_sidra`), 202 fatos setoriais. Sem migration.
- Fontes 5 a 9: **não feitas.** A CVM (fonte 5) só começa depois de medir o banco (113 MB em 25/11).
- **Agenda conferida em produção (26/11/2026, 09:30 UTC):** execução 10071 do workflow `UGhv57BU3YNukVxV`, `mode: trigger` (agenda, não webhook), `success`, de 09:00:47 a 09:01:03 UTC. Desde 08:55 UTC: 43 consultas, todas `encontrado` (12 `bcb_sgs`, 19 `bcb_juros_modalidade`, 5 `bcb_focus`, 7 `ibge_sidra`), nenhuma `falhou`; 267 fatos novos, 202 com `agregado`, `mes_final` e `otica`. Bate com o critério do passo 1.
- **Falta para a A3 fechar:** as fontes 5 a 9.

**Próximos 2 passos (definidos em 25/11/2026, sessão 140):**

| Passo | O que | Critério de pronto | Quem |
|---|---|---|---|
| **1. Conferir a agenda** — **FEITO 26/11** (execução 10071, ver acima) | A 1ª execução AGENDADA do macro (26/11, 06h = 09:00 UTC), já com a fonte 4. Conferida agendada para 26/11 às 09:30 UTC | 43 consultas `encontrado` desde 08:55 UTC (12 `bcb_sgs`, 19 `bcb_juros_modalidade`, 5 `bcb_focus`, 7 `ibge_sidra`); ~267 fatos novos (202 setoriais); a execução no n8n veio da agenda, não de webhook. Se não bater: diagnóstico antes de qualquer fonte nova | Claude (conferida); dono: nada |
| **2. Fonte 5 — CVM (pares do setor)** | Cadastro e demonstrações das companhias abertas. Antes do código, medir o banco e o dono decidir o recorte | Catálogo `cvm_dados_abertos` com url e cadência de publicação; uma consulta por ARQUIVO baixado, com `registros_lidos` > 0 (fonte de lista); "falhou" visível; o tamanho do banco medido antes e depois | Dono decide o recorte; Claude implementa |

**Medido para o passo 2 (25/11/2026, dados abertos da CVM):**

- Cadastro: 2.680 linhas, 1,5 MB. Uma companhia aparece uma vez por mercado (bolsa, balcão): são 2.533 CNPJ únicos, 655 ativos.
- DFP 2025: 12,9 MB zipado, **1.192.514 linhas** somando todos os CSV (consolidado e individual; BPA, BPP, DRE, DRA, DFC, DMPL, DVA; dois exercícios). Só o exercício ÚLTIMO: 595.476. Recortes menores, para comparação: consolidado em BPA, BPP, DRE e DFC_MI, 443 companhias e 244.012 linhas (dois exercícios); contas até o nível 3, só o último exercício, 43.387.
- ~~Só as contas até o nível 3 (ex.: `1.01.01`), no último exercício: 43 mil linhas por ano.~~ **Corrigido em 26/11:** 43.387 é a interseção (consolidado, BPA/BPP/DRE/DFC_MI, nível ≤ 3, último exercício). Nível ≤ 3 no consolidado inteiro, último exercício, são 147.444.
- ITR 2026: 29,5 MB zipado. Medido na tabela abaixo.

**Medido em 25/11/2026, 22h UTC (sessão 141): linhas e bytes reais por linha.** Arquivos baixados com `last-modified` de 22/11/2026 (DFP 2025, 12.898.422 B; ITR 2026, 29.511.192 B). Linhas contadas nos CSV de demonstração (sem `composicao_capital` e `parecer`, por isso a DFP dá 1.187.317 e não os 1.192.514 acima). O ITR 2026 traz três trimestres (31/03, 30/06, 30/09) e 650 CNPJ; a DFP, 672. Bytes por linha medidos carregando os dados INTEIROS num Postgres 16 local (produção é 17.6; o formato em disco de heap e `jsonb` é o mesmo), com índice:

- formato `fato_externo` (chave + um JSON por linha + PK uuid + índice por consulta): **611 a 620 B/linha**. Conferência em produção: os 1.198 fatos de hoje têm 581 B/linha com índice (JSON menor).
- tabela enxuta, colunas tipadas + índice (cnpj, data, conta): **152 a 189 B/linha**.
- banco de produção: 113 MB (118.705.299 B em 26/11, 09:30 UTC), 387 MB livres no teto de 500 MB.

| Recorte (último exercício) | Linhas DFP 2025 | Linhas ITR 2026 | MB/ano em `fato_externo` | MB/ano em tabela enxuta |
|---|---|---|---|---|
| Inteira (consolidado e individual, 7 demonstrações) | 595.476 | 1.685.112 | 350 + 993 = **1.343** | 93 + 261 = **354** |
| (a) Consolidado, todas as demonstrações | 260.890 | 728.120 | 153 + 431 = **584** | 42 + 118 = **160** |
| (b) Consolidado, BPA, BPP, DRE, DFC_MI | 122.006 | 368.099 | 71 + 215 = **286** | 22 + 65 = **87** |
| (c) Consolidado, contas até nível 3 | 147.444 | 413.479 | 87 + 245 = **332** | 23 + 63 = **86** |
| (b) ∩ (c) | 43.387 | 143.643 | ~115 (DERIVADO) | ~35 (DERIVADO) |

As quatro primeiras linhas são tabelas carregadas e medidas; a última é linhas × B/linha medido, sem carga. O exercício PENÚLTIMO não entra em nenhuma: repete o ÚLTIMO do ano anterior. Leitura: a decisão (1) não cabe em formato nenhum; com ITR, só cabe em tabela enxuta e com recorte. **Aguarda o dono:** o recorte e o lugar (tabela própria ou `fato_externo`). Recomendação: (b) em tabela própria, 87 MB/ano.

**DECIDIDO pelo dono em 25/11/2026:** (1) **DFP inteira**; (2) **ITR entra**; (3) **gravar pela proposta**: baixar só quando o arquivo da CVM mudar e registrar a consulta mesmo quando nada mudou.

**⚠ A decisão (1) PRECISA SER REVISTA pelo dono antes de gravar** (achado da revisão final do PR #318, conferido em 25/11). Quando a decisão foi tomada, o número na mesa era 244 mil linhas, que é só um recorte. A DFP inteira de 2025 tem **1,19 milhão de linhas**; só o último exercício, 595 mil. A cerca de 400 B por linha (ESTIMADO, o tamanho real por linha não foi medido), dá cerca de 240 MB por ano só com o último exercício, antes do ITR, contra 387 MB livres. Não cabe com o ITR. O primeiro passo da fonte 5 é medir o tamanho real por linha e as linhas do ITR, e levar ao dono três recortes com o número medido: (a) só consolidado, último exercício; (b) consolidado e só BPA, BPP, DRE e DFC; (c) contas até o nível 3.

**O que estava em decisão** (registro):

1. **Recorte.** (Número da época, SUPERADO: tomava 244 mil linhas, que é o consolidado de 4 demonstrações, como a DFP inteira; ver o aviso acima.) A DFP inteira são 244 mil linhas por ano. A cerca de 400 B por linha com índice, dá cerca de 100 MB por ano: não cabe nos 387 MB livres junto com o ITR. Contas até o nível 3, consolidado, último exercício, são 43 mil linhas, cerca de 17 MB por ano (ESTIMADO).
2. **ITR (trimestral) entra ou não.** Medir as linhas antes de decidir.
3. **Forma de gravar.** A CVM publica por ano e por trimestre. Regravar todo dia, como o macro faz, multiplicaria o volume. A proposta é baixar só quando o arquivo mudar (o `last-modified` medido é de 22/11/2026) e registrar a consulta mesmo quando nada mudou. Decidir também se os dados vão para `fato_externo`, que é imutável e guarda um JSON por linha, ou para uma tabela própria e enxuta.

### A4 · Dados da empresa (sob demanda, só CNPJ) — item 1.H2, parte da empresa

| Fonte | Como | Observação |
|---|---|---|
| Cadastro, CNAE, situação e quadro de sócios | BrasilAPI, uma consulta por CNPJ | **Marcada "não oficial"** (decisão 2). Os nomes dos sócios vêm junto e ficam guardados, mas **não são consultados** em outra fonte nesta fase |
| Sanções (CEIS, CNEP) | Download diário da lista inteira da CGU; procura pelo CNPJ | Lista pequena (decisão 3) |
| Trabalho escravo (MTE) | Lista semestral inteira; procura pelo CNPJ | Lista pequena |
| IBAMA (autos e embargos) | Medir o tamanho primeiro. Pequeno: baixar inteiro. Grande: ler em fluxo e guardar só os CNPJs do caso | — |
| PGFN (dívida ativa) | Por consulta (decisão 3). **A fonte por CNPJ ainda não foi achada:** se só houver o arquivo trimestral, ler em fluxo e guardar só os CNPJs do caso, sem guardar o arquivo | Descobrir isso é o primeiro passo da fatia |

- **Onde roda:** no servidor do portal, ao criar o caso e no botão "Atualizar dados públicos".
- **Pronto quando:** num caso de teste com 3 empresas, cada empresa tem uma linha por fonte,
  inclusive a vazia; com a BrasilAPI fora do ar, a linha diz "falhou".
- **Primeiro passo de cada fonte (decisão 7):** medir o que ela devolve para um CNPJ que não existe.
  Se for um 404 documentado, preencher `http_inexistente` no catálogo e o teste prova que ele vira
  "nada encontrado"; qualquer outro 404 continua "falhou".

### A5 · No portal e no Excel — item 1.C4 e parte do 1.H5

- **Painel "Fontes públicas"** (equipe): cada fonte com última atualização, estado e próxima rodada.
  Vencida aparece vencida.
- **Aba nova do mandato, "Dados públicos":** por empresa, cada fonte com o resultado (achou, não
  achou, falhou, não consultou), a data e o link. Selo "não oficial" no cadastro da BrasilAPI.
- **No Excel:** uma aba de fontes externas, com cada dado, a data e a origem. Atenção ao risco já
  conhecido de deslocar endereços de célula ao inserir linhas (memória `splicerows-desloca-enderecos`).
- **Pronto quando:** um mandato de teste mostra tudo isso no navegador, sem número sem fonte, e a
  suíte do export passa.

### Ordem e paralelismo

```
A1 ─┐
A2 ─┴─► A3 (n8n) ─┐
        A4 (portal)┴─► A5 (portal e Excel)
```

- A1 e A2 andam juntas: arquivos diferentes.
- A3 e A4 andam juntas depois da A2: uma mexe no n8n, a outra no portal.
- A5 fecha a fase.
- **Especialistas:** `migrations-postgres` (A2 e as tabelas da A4), `n8n-workflow` (A3),
  `portal-export` (A4 e A5), `suites-invariantes` (cada invariante), `revisor-defeito-silencioso`
  (todo diff, nunca o autor), `estado-e-handoff` (fecha cada fatia).

## 6. O que fica fora da Fase A, e por quê

| Fica fora | Por quê | Quando volta |
|---|---|---|
| Base oficial da Receita (CNPJ) | Vários GB; não cabe no plano gratuito | Pendente, depois da infraestrutura (0.12) |
| Sócios pessoa física (PEP, sanções por CPF) | Decisão 4: por enquanto só a empresa; conflito com a N-C7b a resolver | Depois da decisão registrada |
| DataJud | Só consulta por número de processo; a descoberta de processos vem da JUDIT | Junto com a JUDIT |
| Painel Receita | Exige o login gov.br da própria empresa | Fase do kickoff com o cliente |
| B3 (cotações históricas) | Arquivo grande e sem uso definido no book | Quando houver uso |
| Preço de commodities (Banco Mundial) | Opcional na planilha de captação | Depois da Fase C |

## 7. Portão da Fase A (pronto quando)

1. A cópia de segurança roda todo dia e uma restauração foi feita.
2. Todas as fontes da A3 e da A4 estão no catálogo, com data e estado.
3. Num caso de teste, cada empresa tem uma linha por fonte, inclusive vazia, e uma API derrubada
   aparece como "falhou".
4. O portal mostra o painel de fontes e a aba "Dados públicos"; o Excel mostra a origem de cada dado
   externo.
5. Cada invariante novo foi medido não-vazio, com o número no commit.

## 8. Riscos

- **A BrasilAPI é mantida pela comunidade.** Pode atrasar em relação à Receita ou sair do ar. Mostrar
  a data da base de origem e tratar a queda como "falhou".
- **Consultar a BrasilAPI revela a terceiros quais CNPJs a Oria pesquisa.** Baixo, mas existe.
- **Fonte pública muda de endereço sem aviso.** Já aconteceu com a Receita e com o Comex Stat (27/10).
  Por isso o estado "falhou" é obrigatório desde a A2.
- **Espaço no banco gratuito.** Medir antes de cada carga grande.
