# Product

## Platform

web

## Users

**Exclusivamente o time interno da Oria Partners** — analistas e sócios. Não há
tela de cadastro: contas são criadas pelo administrador direto no painel do
Supabase (Authentication → Users). O cliente assessorado **não acessa** o
portal, e credores ou terceiros tampouco.

**Isto é o HOJE, não o destino (decisão do dono, 27/10/2026).** Duas mudanças de
público estão decididas e ARQUIVADAS — nenhuma tela deve antecipá-las antes de o
banco garantir o isolamento (RLS por caso e papel, roadmap F17):

- **Outras casas vão assinar o portal** (multiempresa). Futuro, não agora.
- **O cliente vai acessar o mandato da própria empresa** para subir documentos e
  acompanhar o andamento. Futuro, não agora.

O registro completo está em `REDESENHO_DO_PORTAL.md`, § "Arquivado".

O usuário chega ao portal já sabendo de qual mandato precisa. O trabalho dele é
**conferir e liberar**: olhar o que a ingestão automática classificou e extraiu
dos documentos que o cliente enviou, corrigir o que está errado, aceitar o que
está certo, e levar o resultado para a análise em Excel.

Três cenas de uso confirmadas, em ordem de peso:

1. **Desktop, sessão longa** — sentado, monitor grande, horas conferindo linha
   por linha. É a cena principal: densidade de dado vence conforto de toque.
2. **Notebook em reunião ou na sede do cliente** — tela menor, às vezes virada
   para outra pessoa ou projetada. Consequência que o design precisa carregar:
   **a tela pode ser vista por quem não tem login.** Nada de nome de cliente ou
   valor exposto onde não precisa estar; legibilidade a distância importa.
3. **Consulta rápida no celular** — checar status e pendências entre reuniões.
   Não é onde a revisão acontece, mas precisa de uma leitura móvel decente.

Tablet não é cena de uso confirmada.

## Product Purpose

O portal é o **lado de leitura e revisão humana** de um sistema de *intake
governado e prontidão de dados* (`Arquitetura do Sistema/1 Visão e Doutrina/00_VISAO_E_ESCOPO.md`).

O problema de origem: a Oria recebe documentos financeiros de clientes contra um
checklist básico, e isso gera retrabalho, avanço prematuro com informação
incompleta e erro repetitivo. O sistema transforma essas submissões numa base
**organizada, validada, auditável, reconciliada e pronta** para a análise
avançar com segurança.

A ingestão em si (classificação, extração, reconciliação) roda **fora** do
portal, no n8n — por decisão explícita. O portal responde a quatro perguntas:

- **O que já chegou neste mandato?** (dashboard do caso: checklist do Kit
  Básico, documentos com tipo/entidade/período/confiança, pendências de
  reconciliação e de qualidade de arquivo)
- **O que precisa de mim agora?** (painel `/casos`: indicadores da mesa e a fila
  de pendências atravessando todos os mandatos, ordenada por severidade)
- **Isto aqui está certo?** (fila de revisão e planilha por documento — o
  humano confirma ou corrige classificação, entidade, tipo e período)
- **Posso levar isso para a análise?** (aceite por documento e export Excel no
  layout padrão de mercado das demonstrações)

Sucesso é o analista atravessar um mandato inteiro sem precisar abrir o arquivo
original para conferir, e sem que nada entre no Excel como fato sem alguém ter
dito que é fato.

## Positioning

**O sistema nunca inventa um número.** Esse é o mecanismo, e ele é estrutural,
não uma promessa de marketing:

- **Determinístico primeiro; LLM só na ambiguidade residual.**
- **Nenhum subtotal ou total é calculado por soma.** Uma linha de total só
  aparece no export se o próprio documento já a trouxe extraída — mesmo
  princípio de `fn_valor_conceito`: casamento determinístico, nunca um cálculo
  novo.
- **Sugestão pendente jamais vira fato silencioso.** Linha não aceita aparece no
  export (nunca some), mas em âmbar e itálico. É princípio inegociável de
  `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`.
- **Doutrina de Autonomia** (`Arquitetura do Sistema/1 Visão e Doutrina/01`): cada estágio do workflow nasce no seu
  nível de autonomia mínimo seguro (N0 sombra → N1 sugestão+revisão 100% → N2
  auto-clear → N3 amostragem) e só sobe com dado de calibração. O nível é estado
  do sistema no banco, não constante de código.
- **Recusa explícita de modelagem 100% automática.** Recorrente vs.
  não-recorrente, materialidade, divergência aceitável vs. bloqueante e
  premissas de modelagem continuam sendo julgamento humano, por decisão.
- **O rótulo original de cada empresa é preservado.** O classificador coloca a
  conta na seção certa do Balanço/DRE/Fluxo sem forçar um nome canônico; o que
  não é classificável com segurança vai para um bloco explícito "Contas Não
  Classificadas (revisar manualmente)" — nada desaparece nem é forçado para o
  lugar errado.

Isso espelha diretamente o que a Oria vende: *"a retomada da credibilidade é o
que viabiliza qualquer solução... análises verificáveis por todas as partes.
Credibilidade é o nosso principal ativo."* O portal é a máquina que produz a
base informacional única que o mandato promete ao credor e ao acionista.

## Operating Context

**Mandato = caso.** Reenviar arquivos com o mesmo nome de mandato acumula no
mesmo caso: mesmo checklist, mesmo export, mesma reconciliação
(`fn_upsert_caso`).

Fluxo real de uma sessão de trabalho:

1. **"+ Novo mandato"** ou **"+ Adicionar arquivos"** — o portal encaminha os
   arquivos servidor-a-servidor para o Form do n8n; o pipeline permanece 100%
   no n8n.
2. **Espera assíncrona.** Não há retorno síncrono do processamento. O portal
   acompanha em segundo plano e avisa "Tudo pronto" quando os arquivos
   terminaram de passar pelo pipeline. "Pronto" significa *terminou de tentar*,
   não *sem pendências*.
3. **Dashboard do mandato** — checklist do Kit Básico (verde = presente),
   documentos, pendências de Reconciliação (Classe A) e de Qualidade.
4. **Fila de revisão** — uma pendência por card
   (`classificacao_pendente`, `tipo_incorreto`, `entidade_incorreta`,
   `periodo_incorreto`), formulário pré-preenchido com a sugestão atual.
   Confirmar ou corrigir chama `fn_revisar_documento`; toda a lógica roda no
   Postgres, não no Next.
5. **Planilha do documento** — linhas extraídas agrupadas por seção, e o botão
   "Aceitar estes dados para a base" (`fn_aceitar_extracao`), que é o Portão 2
   mínimo.
6. **Export Excel** do caso inteiro, com proveniência (arquivo/página/
   confiança/status/versão da taxonomia) em comentário de célula.

**Navegação:** barra lateral retrátil onde *Novo mandato* é AÇÃO (fixa) e
*Mandatos* é LUGAR. Regra estabelecida: **nenhuma função da barra lateral se
repete no conteúdo.** Desde o redesenho (27/10/2026) a barra lista só os
mandatos RECENTES, não todos os ativos — a lista inteira é a tela Mandatos — e
**dentro do mandato as telas são abas fixas**, sempre as mesmas e na ordem do
trabalho (`REDESENHO_DO_PORTAL.md`).

**Fim de vida do mandato:** fechar ≠ excluir. `caso.status` diz onde o mandato
está no trabalho; `fechado_em` responde "ainda estamos nisso?".

**Vocabulário do domínio** (usar, nunca traduzir para genérico): mandato, caso,
Kit Básico, pendência, reconciliação, entidade, período, taxonomia, aceite,
linha extraída, proveniência.

**Vocabulário de ENGENHARIA não vai para a tela** (decisão do dono, 27/10/2026).
A regra acima protegia o termo de mercado, que o analista lê sem legenda; ela
também protegia, por acidente, nomes que só existem dentro do repositório. Na
tela, a partir daqui:

| No código e na doutrina | Na tela |
|---|---|
| Portão 2 / conferência final | **Aprovação** |
| Autonomia / dial de autonomia | **Qualidade da automação** |
| Perímetro | **Grupo econômico** |
| Entidade fantasma | **Empresa não identificada** |
| Painel | **Início** |

Os nomes da esquerda continuam valendo no banco, nas funções e nos documentos
de arquitetura — trocar ali é migration e não muda nada para quem usa.

## Capabilities and Constraints

- **Next.js 16 (App Router) + React 19 + Tailwind 4 + Supabase**, deploy na
  Vercel com `portal/` como Root Directory. `middleware.ts` virou `proxy.ts` no
  Next 16.
- **Teto de ~4,5 MB por requisição** na Serverless Function da Vercel — recusado
  na BORDA, antes de a rota rodar. Desde 13/09/2026 isto não é mais restrição de
  produto: acima do teto a própria tela manda o lote direto ao Form do n8n, numa
  execução só, e nada é pedido ao analista (ver `portal/src/lib/limite-de-envio.ts`).
  O que continua valendo é a consequência de desenho: **lote grande não devolve
  recibo de entrega** — a confirmação vem do acompanhamento pelo banco, nunca do
  status do envio.
- **Cota de egresso do Supabase é da organização, não do projeto** — 5 GB/mês
  divididos com outro projeto, e já houve incidente a 4,54 GB. Daí três regras
  de código que também são restrições de design: nomear colunas em vez de
  `select("*")`; filtrar e agregar no Postgres via RPC; **toda tela que pergunta
  em laço precisa desacelerar** (o polling pós-upload usa 8 s nos primeiros 2
  minutos e afrouxa para 30 s depois). Cadência de tela multiplica por centenas.
- **RLS por caso não existe ainda:** hoje é "qualquer autenticado vê tudo",
  decisão explícita da Fatia 1. Nenhuma tela deve sugerir separação de acesso
  que o banco não garante.
- **Sem tela de cadastro, sem recuperação de senha** — administração é no painel
  do Supabase.
- **`prefers-reduced-motion` é respeitado** e a abertura animada do painel toca
  uma vez por sessão do navegador, com qualquer gesto cortando.
- **Aceite é por documento inteiro** (v0). Aceite por linha/célula está
  explicitamente adiado.

## Brand Commitments

- **Oria Partners** — boutique independente de reestruturação financeira,
  turnaround e situações especiais, em São Paulo. Middle e large corporate e
  instituições financeiras.
- **O sextante é a marca.** `portal/public/logo-oria*.svg` é o original do dono
  com o fundo creme trocado por transparência, **sem redesenhar nada** — o SVG
  embute a arte original, porque vetorizar exigiria traçar e traçar é aproximar.
  Sextante no cabeçalho e no favicon; a lockup completa no login. A ilustração
  animada do painel é um vetor *próprio* inspirado no motivo — **a arte original
  não é tocada.**
- **Restrição visual vinculante, dada pelo dono nesta sessão:** o portal herda o
  mundo visual de `oriapartners.com` por inteiro, adaptado para trabalho — não
  como cópia do layout de marketing. Os valores medidos no site em produção:

  | Papel | Valor no site | Hex |
  |---|---|---|
  | Fundo / papel quente | `hsl(44 27% 95%)` | `#F6F4EF` |
  | Tinta / primária | `hsl(213 26% 9%)` | `#11161D` |
  | Acento | `hsl(11 59% 45%)` | `#B6482F` |
  | Acento suave | `hsl(14 67% 75%)` | `#EAA895` |
  | Borda / fio | `hsl(44 16% 79%)` | `#D2CDC1` |
  | Texto secundário | `hsl(60 2% 41%)` | `#6B6B66` |

  Tipografia do site: **Fraunces** (serifa de display, eixo óptico 9–144),
  **Inter Tight** (300–600), **JetBrains Mono** (400–500).

  O portal hoje **diverge**: paleta slate do Tailwind (`#0f172a`–`#f8fafc`),
  acento ciano `#0e7490`, corpo em fonte do sistema. Essa divergência é dívida
  reconhecida, não decisão.

- **Registro editorial do site**, disponível como referência: seções numeradas
  em `§ 01, ATUAÇÃO`, princípios em algarismos romanos (I–IV), sobriedade,
  ausência de exclamação e de superlativo.
- **Voz: português do Brasil, técnica e sóbria.** Precisão acima de entusiasmo.
  O produto é dado, não cartão de rede social — regra já escrita em
  `portal/src/app/globals.css`.
- **Discrição e confidencialidade** são compromisso público da firma ("todas as
  conversas e materiais compartilhados são tratados com absoluta
  confidencialidade") e, por causa da cena de uso 2, também um requisito de
  tela.

## Evidence on Hand

- `ESTADO.md` — onde o projeto está agora (migrations, suítes, CI, decisões de
  portal por data). `HANDOFF.md` — como chegou aqui, sessão a sessão.
- `Arquitetura do Sistema/1 Visão e Doutrina/00_VISAO_E_ESCOPO.md`, `Arquitetura do Sistema/1 Visão e Doutrina/01_DOUTRINA_DE_AUTONOMIA.md`,
  `Arquitetura do Sistema/2 Especificação/06_HUMAN_IN_THE_LOOP.md`, `Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md` — a doutrina do
  produto.
- `portal/README.md` — o registro mais completo do que cada tela faz e por quê.
- `portal/public/logo-oria*.svg`, `Logo Oria.jpg`,
  `Logo Oria - sextante apenas.jpg` — a marca.
- `oriapartners.com` — copy, paleta e tipografia de produção, medidos nesta
  sessão a partir de `assets/index-*.css` e `assets/index-*.js`.
- **Ausências que trabalho futuro não pode fabricar:** não há pesquisa com
  usuário, não há métrica de uso, não há nome real de cliente utilizável em
  tela ou exemplo. Os casos do site são anonimizados de propósito. Não existe
  benchmark de tempo de revisão.

## Product Principles

1. **Nada entra como fato sem alguém dizer que é fato.** Toda tela precisa
   deixar visível a diferença entre sugestão da máquina, correção humana e dado
   aceito. Quando essa distinção fica ambígua, é defeito.
2. **Diagnóstico antes de solução** — o princípio II da própria firma, aplicado
   à tela: mostrar a situação do mandato antes de oferecer o botão que a
   resolve.
3. **A tela responde "o que precisa de mim agora?", não "o que existe".** Foi
   por isso que a home deixou de ser a lista. Redundância entre navegação e
   conteúdo é erro, não conveniência.
4. **Densidade a serviço da conferência.** A cena principal é conferir números
   por horas. Elevação, ornamento e animação que competem com o número saem.
5. **A tela pode estar sendo vista por quem não tem login.** Discrição é
   requisito de layout, não só de autenticação.

## Accessibility & Inclusion

Compromisso já implementado e que deve ser preservado, herdado do entregável em
Excel e escrito em `portal/src/app/globals.css`:

- **Cor nunca carrega significado sozinha.** Todo estado é cor **mais** texto —
  o chip diz "faltante", não é apenas âmbar. A razão está no comentário do
  arquivo: cerca de 8% dos homens que vão abrir este portal não distinguem
  verde de vermelho.
- **Foco visível e consistente** (`:focus-visible` com contorno de 2px e
  deslocamento), porque o padrão do navegador some sobre fundo escuro e a tela
  tem ações destrutivas — quem navega por teclado precisa enxergar onde está
  antes de apertar Enter.
- **`font-variant-numeric: tabular-nums`** por padrão: tabela de dado com
  números precisa de alinhamento tabular.
- **`prefers-reduced-motion`** pula a cena de abertura por completo.

Nenhuma norma formal (WCAG A/AA) foi estabelecida como exigência contratual.
