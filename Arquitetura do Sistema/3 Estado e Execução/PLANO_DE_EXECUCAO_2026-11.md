# Plano de execução — de 02/11/2026 até a aplicação completa

**Data:** 30/10/2026, sessão 114 · **Base:** `main` em `62c8b55` (PR #265 mergeado) · **Banco de
produção:** `0216` aplicada e conferida nesta sessão (catálogo inteiro 287/287 presente).

**Objetivo do dono, nas palavras dele (30/10/2026):** *garantir que o sistema consegue captar e rodar
todos os dados com um grau de confiança alto. Sem prazo, mas o mais rápido possível.* Nenhum cliente
roda no sistema até ele estar pronto para isso. Hoje só o dono usa o portal, e a confiabilidade do
sistema como um todo é baixa.

**Ordem decidida pelo dono (30/10/2026):** **(d)** estabilidade e completude da extração →
**(f)** portal → **(g)** área do cliente e multiempresa → **(e)** conta canônica (F4) →
**(c)** fontes oficiais, onda 1 (F2T) → **(b)** aceite financeiro → **(a)** fechar o perímetro (F1).
Mais duas coisas que entram **agora**: o n8n passa a rotear pelo `caso_id` em vez do nome do
mandato, e as pendências conhecidas do portal.

**Restrições do dono:**
- **Custo:** até **US$ 5 por book**.
- **Fatias:** uma fatia por sessão. O detalhe abaixo cobre **6 semanas**. O que vem depois está
  mapeado por fase, com esforço estimado.
- **Merge, deploy, republicação e aplicação em produção:** a sessão faz, mas **só quando o dono
  pede ou autoriza**. Nenhuma fatia termina num deploy por conta própria.
- **Sonar:** os achados vêm do dono. A sessão não consulta o Sonar.
- **Vistoria em navegador:** autorizada com três usuários de teste (Sócio, Analista, Leitura).

> **Premissa deste plano, para o dono corrigir:** **5 sessões por semana**, 30 fatias em 6 semanas.
> Com outro ritmo, a ordem não muda; muda só a data em que cada fatia acontece.

---

## 1. Onde estamos, medido em 30/10/2026 (não lembrado)

**Banco de produção.** `fn_instalacao_conferir()`: 287 de 287 requisitos presentes; a `0216` com 48
de 48. Um único usuário em `auth.users`, que virou Sócio. Nenhuma policy de `authenticated` com
`using (true)` (eram todas, desde a `0003`); 136 policies agora checam o mandato. `postgres` e
`service_role` têm `rolbypassrls = true`: o n8n continua gravando.

**A extração nos dois últimos lotes de documentos reais** (`lote_execucao` de produção):

| Lote | Documentos | Com falha | Cobertura da régua | Custo |
|---|---|---|---|---|
| Fw Valtra (05/10) | 15 | **5 (33%)** | 0,78 | US$ 1,10 |
| KRAUSPENHAR E HARTMANN (30/09) | 7 | **5 (71%)** | 0,57 | US$ 0,42 |
| Sintético Vertentes (30/09) | 14 | 2 (14%) | 0,94 | US$ 0,05 |
| AMO teste 00 (16–17/09) | 65 + 45 | 10 + 1 | **1,31 e 1,43** | US$ 0,52 |

**O que isso diz:**
1. **Documento real falha em um terço a dois terços dos casos.** As pendências abertas nesses lotes
   nomeiam as causas: extração INCOMPLETA por "conta(s) descartada(s) por desalinhamento" de coluna
   (balancete e DRE multi-coluna), seções que não fecham com as próprias linhas (28 de 112 num
   documento do Valtra), período e entidade atribuídos errado, e um padrão suspeito de valor
   repetido (fabricação).
2. **A régua de cobertura não é confiável:** valor acima de 1 (até 2,25 em setembro) significa
   que ela conta errado. Ela não serve de medida enquanto isso não for corrigido.
3. **Há um defeito de execução no n8n:** `Maximum call stack size exceeded` em "Juntar Extração de
   Conteúdo" (3 vezes, última em 17/09).
4. **Custo não é o gargalo:** o lote real mais caro custou US$ 1,10, abaixo do teto de US$ 5. A
   confiança é o gargalo.

**Configurado nesta sessão (30/10):**
- Na Vercel, `N8N_INTAKE_SEGREDO` (produção e preview, marcado como sensível).
- No Supabase Auth, Site URL `https://tratamento-dados-financeiros.vercel.app` e Redirect URLs
  `/auth/confirmar**` para produção, para os previews do time `oria4` e para `localhost:3000`.

**NÃO foi possível nesta sessão:**
- **Variable do n8n:** a licença não tem `feat:variables` (resposta 403 da API).
- **Modelo do e-mail de recuperação:** o plano gratuito do Supabase não permite mudá-lo sem SMTP
  próprio (resposta 400). Efeito: o link de recuperação usa PKCE e **só abre no mesmo navegador que
  pediu**.

---

## 2. O que "confiança alta" quer dizer neste plano (proposta, para o dono aprovar)

Sem número, "confiança alta" não fecha nunca. Proposta de critério para o fim da etapa (d), medido
no **corpus de regressão** (seção 3, fatia P4):

| Medida | Hoje | Alvo |
|---|---|---|
| Documentos com extração falha ou incompleta, em documento real | 33–71% | **≤ 5%**, e **cada um** com causa nomeada |
| Falha silenciosa (documento sem linha e sem pendência) | não medida | **0** |
| Linhas do documento com destino declarado (conta, cabeçalho ou descarte com motivo) | indecidível hoje | **≥ 99,9%** |
| Seções que fecham com as próprias linhas, ou com divergência declarada | 84 de 112 num documento | **100% declaradas** |
| Régua de cobertura | 0,57 a 2,25 | **entre 0,98 e 1,02**, ou divergência explicada |
| Custo por book | até US$ 1,10 | **≤ US$ 5**, medido por `medir-custo-book.mjs` |
| Lote com falha parcial | reprocessa tudo | **retoma só o que falhou** |

---

## 3. As 6 semanas, fatia por fatia

Cada fatia segue o `/rodada`: medir antes, achar a causa, corrigir, medir depois. Invariante novo é
**medido não-vazio** (regra 2), e todo diff passa pelo `revisor-defeito-silencioso`. "Pronto" é o
critério que fecha a fatia. Sem ele cumprido, a fatia não fecha.

### Semana 1 (02 a 06/11) — fechar o que está no ar, rotear por `caso_id`, medir a base

| # | Fatia | Pronto quando |
|---|---|---|
| **P1** | **Fechar o deploy da Fase 5.** Com o segredo já no PikaPods (pendência D1 do dono): redeploy do portal, republicação da ingestão, conferir `multipleFiles` em "Arquivos", envio ponta a ponta de um book sintético pelo portal | Um lote sintético entra com o token do portal, e o n8n **recusa** token adulterado e token vencido (medido) |
| **P2** | **Três usuários de teste e vistoria por papel.** Criar Sócio, Analista e Leitura; percorrer com Playwright todas as telas autenticadas no preview; registrar cada defeito com captura | Matriz papel × tela, com o que cada papel vê e faz, medida. A lista de defeitos alimenta a semana 4 |
| **P3** | **O n8n roteia por `caso_id`.** O token assinado passa a carregar o `caso_id`; o "Upsert Caso" busca por id; o nome vira só exibição | Renomear um mandato não quebra o envio; o invariante reprova com o roteamento antigo (medido) |
| **P4** | **Linha de base da F3 e corpus de regressão.** Três books sintéticos mais os documentos reais já no banco (Valtra, Krauspenhar, AMO). Script que mede, por documento: falhou, incompleto, linhas, descartadas por desalinhamento, seções que não fecham. Corrigir a régua de cobertura acima de 1 | Número de base publicado por documento; a régua dá entre 0 e 1 no corpus inteiro, ou diz por que não |
| **P5** | **`Maximum call stack size exceeded` em "Juntar Extração de Conteúdo".** Causa raiz, com o documento que provoca o erro | O documento que estourava passa, e um teste reprova com o código antigo |

### Semana 2 (09 a 13/11) — (d) F3: a extração para de perder documento

| # | Fatia | Pronto quando |
|---|---|---|
| **P6** | **Desalinhamento de colunas** (balancete e DRE multi-coluna, a maior causa de INCOMPLETA no Krauspenhar e no Valtra). Causa raiz no fatiamento ou no contrato da resposta | As contas descartadas por desalinhamento no corpus caem a zero, ou cada uma com motivo |
| **P7** | **Fila de reprocesso.** Lote com falha parcial retoma só os documentos que falharam, sem pagar de novo o que já foi extraído | Aceite técnico da F3: retomar um lote com 1 falha custa 1 documento, não o lote inteiro |
| **P8** | **Retentativa classificada e fallback de provedor.** Separar erro transitório (rede, 429, 5xx) de definitivo; o transitório tenta de novo e, esgotado, cai no provedor alternativo; cada tentativa registra rodou, falhou ou caiu | Uma falha simulada do provedor principal termina no alternativo, e fica registrada |
| **P9** | **Período e entidade atribuídos errado** (`precondicao_nao_satisfeita` "sem período par", `periodo_incorreto`, `entidade_incorreta`). Causa raiz na atribuição, não na guarda | No corpus, as pendências falsas desse tipo somem e as verdadeiras continuam abrindo (controle positivo) |
| **P10** | **Rodada de regressão paga** sobre o corpus (precisa da autorização D6 do dono). Comparar com P4 | Tabela antes × depois por documento; custo de cada book ≤ US$ 5 |

### Semana 3 (16 a 20/11) — (d) F3b: nenhuma linha faltando, nenhuma inventada

Detalhe em `PLANO_LINHA_A_LINHA.md`. Esta é a parte que transforma "extraiu tudo" de estatística em
aritmética.

| # | Fatia | Pronto quando |
|---|---|---|
| **P11** | **A coordenada.** Texto numerado ao lado do PDF; `ln` obrigatório no schema da linha | Toda linha extraída do corpus cita a linha do texto de onde veio |
| **P12** | **A bijeção.** O modelo declara `descartadas` com motivo; buraco, duplicação e origem inventada viram pendência BLOQUEANTE com o número da linha | Os 3 documentos do araucária acusam o buraco nomeado (97−68, 150−102, 20−13) |
| **P13** | **A literalidade.** `vt` cobrado como o `tr` dos fatos: trecho literal da linha citada | Valor sem trecho literal correspondente abre pendência; a guarda reprova com valor inventado (medido) |
| **P14** | **Re-perguntar só o buraco.** "Leia só as linhas 23 a 51", no máximo 1 re-pergunta por documento | O buraco do corpus fecha a um custo proporcional ao buraco, e o teto é respeitado |
| **P15** | **Cada guarda medida não-vazia e portão da etapa (d).** Rodada de regressão final; o padrão suspeito de fabricação e as seções que não fecham reavaliados com a bijeção | A tabela da seção 2 está no alvo, ou cada desvio está explicado. **Fim da etapa (d)** |

### Semana 4 (23 a 27/11) — (f) portal: os erros que impedem o uso

| # | Fatia | Pronto quando |
|---|---|---|
| **P16** | **Defeitos da vistoria de P2, lote 1** (os que bloqueiam o uso) | Cada defeito do lote reproduzido antes e conferido depois no navegador |
| **P17** | **Lote 2**, mais o tooltip que vaza o resumo no modo discrição e a paginação de `fn_membros_da_equipe` | Modo discrição sem vazamento medido; equipe pagina acima de 1.000 |
| **P18** | **Novo mandato com Produto e Responsável** (migration e tela) | Os dois campos gravam, aparecem na lista de mandatos e respeitam a RLS |
| **P19** | **`aprovado_em` e "Tempo até aprovar"**; teste para as funções puras sem teste (`escolherRecentes`, `iniciaisDoEmail`, `passosDaTrilha`, `etapaDoMandato`, `mensagemDeLogin`) e para o ramo da `0215` sem assert | O indicador mede o tempo de aprovação, não o de ingestão; cada teste novo reprova com a função quebrada |
| **P20** | **Recuperação de senha ponta a ponta e vistoria final por papel** (os 3 usuários), `viewport-fit=cover` no celular | Recuperação conferida no navegador; matriz papel × tela sem defeito aberto. **Fim da etapa (f)** |

### Semana 5 (30/11 a 04/12) — (g) área do cliente e multiempresa

Hoje esses dois itens estão **arquivados** no `REDESENHO_DO_PORTAL.md`. A ordem do dono os traz para cá.
A regra que vale: **tela que sugere separação de acesso que o banco não garante é pior que nenhuma
tela.** Por isso o banco vem antes da tela.

| # | Fatia | Pronto quando |
|---|---|---|
| **P21** | **Desenho** (prompt `01` de `5 Prompts/`): organização acima do caso, papel Cliente, o que o cliente vê (subir documento contra o Kit Básico e ver o andamento) e o que nunca vê (pendência, premissa, nota interna). Decisões D9–D11 do dono | Documento de desenho aprovado pelo dono |
| **P22** | **Migration da organização** e RLS por organização sobre a RLS por mandato da `0216` | Usuário da organização A não lê nem escreve nada da B, em nenhuma tabela e nenhum bucket (medido) |
| **P23** | **Papel Cliente** e superfície externa isolada no banco: views ou funções que só devolvem o que o cliente pode ver | Cliente não alcança pendência, premissa, nota nem outro mandato, nem por API direta (medido) |
| **P24** | **Telas da área do cliente** (envio contra o Kit Básico, andamento) | Vistoria com um usuário Cliente de teste |
| **P25** | **Revisão de segurança** (`/security-review`) e teste de vazamento entre organizações e entre papéis | Nenhum achado alto aberto. **Fim da etapa (g)** |

> **Risco declarado:** a etapa (g) estava estimada em G (4–6 sessões) sem a multiempresa completa.
> Se P22 mostrar que a multiempresa exige mais, ela se divide e a área do cliente vai primeiro.

### Semana 6 (07 a 11/12) — (e) F4: conta canônica, primeira metade

A F4 é a maior intervenção do roadmap (esforço GG, mais de 6 sessões). Nesta semana entra a fundação.
O resto está na seção 4.

| # | Fatia | Pronto quando |
|---|---|---|
| **P26** | **Catálogo `conta_canonica`** com hierarquia (`pai`), natureza e seção, semeado da taxonomia atual | Toda seção canônica dos 3 books tem conta canônica; nenhuma conta sem pai, exceto as raízes |
| **P27** | **`fato_financeiro` acima de `campo_extraido`**, que não muda. A resolução da conta quando é heurística abre pendência | 0 fato sem identidade no corpus; heurística sempre com pendência |
| **P28** | **Subtotal = Σ folhas** em todo documento dos books, e 0 duplicidade subtotal + filho | Aceite financeiro da F4 nos 3 books, ou divergência declarada |
| **P29** | **Primeira reconciliação migrada**, com os dois caminhos rodando em paralelo | As duas versões dão o mesmo resultado no corpus |
| **P30** | **Portão das 6 semanas:** regerar a prontidão, atualizar este plano e o roadmap com o medido | Plano das semanas 7 em diante revisado com números, não com estimativa |

---

## 4. Da semana 7 ao fim da aplicação (mapeado, sem fatia ainda)

Esforço em sessões, **ordem de grandeza** (P ≤ 1 · M = 2–3 · G = 4–6 · GG > 6). Cada fase é
fatiada quando chega a vez dela, contra o estado medido naquele dia.

| Ordem | Fase | O que entrega | Sessões | Depende de |
|---|---|---|---|---|
| 1 | **(e) F4, segunda metade** | As outras 9 reconciliações migradas para a conta canônica; o caminho antigo sai | ~6 | P26–P29 |
| 2 | **(c) F2T onda 1, com dado sintético** | Gerador sintético de ECD e ECF que fecha no BP (padrão `book-distress`); o leitor lê 100% dos registros; S1, S6 e o segmento (`Y540`). A onda com dado real espera os 3 ECDs reais | ~4 | F1 (CNPJ por entidade), P11 |
| 3 | **(b) Aceite financeiro, nos books de teste** | Sem cliente real, o aceite usa os 3 books como gabarito (o COMBINADO do `book-canastra` no lugar do COMBINADO do cliente): ≥95% dos documentos com linha e toda diferença explicada | ~2 | etapa (d) |
| 4 | **(a) F1, fechar o perímetro** | Perímetro declarado pela tela nos mandatos de teste; decisões 1.7, ressalva e fusão (D2–D4 do dono) aplicadas | ~2 | decisões do dono |
| 5 | **F5 — lineage** | "De onde veio este número" por SQL; a nota do Excel vira render | ~3 | F4 |
| 6 | **F6 — reconciliação sobre identidade e intercompany** | Eliminação intragrupo como fato próprio. **DATA GATE** | ~3 | F4, F5 |
| 7 | **F2T ondas 2 a 5 e captação** | OFX e CNAB; EFD e XML fiscal; eSocial; logística; cofre e robô. A etapa jurídica (P3, RIPD) vem antes de qualquer coleta | ~22 | F6, D7 e D8 do dono |
| 8 | **F7 — motor de cálculo** | Aritmética da projeção no sistema, com paridade com o Excel. **MODEL GATE** | ~8 | DATA GATE |
| 9 | **F8 — cenários e alavancas** | **STRATEGY GATE** | ~5 | F7 |
| 10 | **F9, F10, F11 em paralelo** | Estrutura de capital, liquidez e 13 semanas, diagnóstico analítico | ~13 | F7 |
| 11 | **F12 → F13 → F14** | Valuation, recovery (**CREDITOR GATE**), reestruturação | ~13 | F9 |
| 12 | **F15 → F16** | Camada de apresentação e deck. **PRESENTATION GATE** | ~4 | CREDITOR GATE |
| — | **F17 — hardening, contínuo** | Uma linha por semana: Sonar (achados vindos do dono), teste de restauração, proteção do `main`, registro de leitura | distribuído | — |

**Total depois da semana 6: cerca de 85 sessões, ~17 semanas no ritmo de 5 por semana.** Com as 6
semanas detalhadas, a aplicação completa fica em torno de **23 semanas**, ou seja, **meados de abril
de 2027**. É estimativa de ordem de grandeza: a etapa (d) é a que mais pode mover esse número,
para cima ou para baixo.

---

## 5. Pendências do dono (decisões e ações que só ele faz)

| # | Pendência | Bloqueia | Desde |
|---|---|---|---|
| **D1** | **Pôr `N8N_INTAKE_SEGREDO` e `N8N_BLOCK_ENV_ACCESS_IN_NODE=false` nas variáveis do n8n no PikaPods**, com o mesmo valor da Vercel. A licença do n8n não tem Variables, então o `$env` é o único caminho | P1: sem isso, o n8n recusa todo envio | 30/10 |
| **D2** | Controle familiar conta como controle comum? (fatia 1.7) | (a) | 15/10 |
| **D3** | Pendência "aceita com ressalva" deve segurar o fechamento do perímetro? (hoje não segura) | (a) | 15/10 |
| **D4** | `caso_pergunta` na fusão de entidades (FK `NO ACTION`: hoje a fusão falha alto) | (a) | 15/10 |
| **D5** | B3, a autonomia: dois estágios rodam em N2 `declarada` sem concordância medida | Etapa (d) declarar confiança alta | 20/08 |
| **D6** | Autorizar as rodadas pagas de regressão (P10, P15; cada book ≤ US$ 5) | P10, P15 | — |
| **D7** | Atualizar o secret `N8N_API_KEY` do GitHub (a Action de republicação dá 401) | Republicar pela Action | 15/10 |
| **D8** | SMTP próprio no Supabase, para o e-mail de recuperação abrir em qualquer aparelho e sair em português | P20 sem a limitação | 30/10 |
| **D9** | Área do cliente: o cliente envia só contra o Kit Básico ou qualquer documento? Vê o andamento por item ou só o percentual? | P21 | — |
| **D10** | Multiempresa: escopo da primeira versão (uma organização por usuário ou várias) | P21 | — |
| **D11** | Papel Cliente: quem convida e quem revoga (Sócio da Oria, ou o próprio cliente para a equipe dele) | P21 | — |
| **D12** | Cortes de covenant (hoje 3,0x de alavancagem, 1,2x de DSCR, 1,0x de liquidez) | Book de comitê | sessão 38 |
| **D13** | Integra Contador (D12.3, aguarda cotação) e a etapa jurídica da F2T (termo, RIPD, procuração só de consulta) | F2T captação | 13/10 |
| **D14** | Os 3 ECDs reais anonimizados para a onda 1 da F2T com dado real | F2T onda 1 real | 13/10 |
| **D15** | Aprovar o critério de "confiança alta" da seção 2 | Portão da etapa (d) | 30/10 |
