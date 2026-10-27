# Redesenho do portal — decisões, fases e o que ficou arquivado

> Aprovado pelo dono em 27/10/2026. A proposta visual completa (38 itens com
> prévia desenhada) foi publicada como página privada para o dono; este arquivo é
> a versão que mora no repositório e que as sessões seguem.

## Por que

O inventário das 13 telas (27/10/2026) mediu o problema, não o supôs:

- Dentro do mandato **não havia abas**. Revisão só era alcançável por uma faixa
  que aparece quando existe pendência; Apresentação só pela Modelagem; cada
  subtela tinha um "voltar" diferente (**cinco** formas).
- A página do mandato tinha **12 ações** e **7 seções** empilhadas (846 linhas);
  a Modelagem, **18 ações** e o export em **4** variações de botão.
- Cerca de **35 explicações** viviam só em `title=` (dica de mouse), que não
  existe no toque — e o celular é a cena de uso 3 do `PRODUCT.md`.
- A tela mostrava ao usuário números de migration (0120, 0205, 0208, 0212),
  nomes de função (`fn_*`), `notify pgrst`, um `select * from …` e erro em JSON
  cru — e nenhuma tela tinha `loading`/`not-found`; só a Modelagem tinha `error`.

## Decisões do dono

| # | Pergunta | Decisão |
|---|---|---|
| 1 | Trocar os nomes de engenharia na tela? | **Sim** — ver a tabela em `PRODUCT.md` |
| 2 | Custo por mandato fica no Início? | **Não**, sai; não é argumento comercial |
| 3 | Outras casas vão assinar? | **Sim, no futuro** — arquivado |
| 4 | O cliente acessa o portal? | **Sim, no futuro**, o mandato da própria empresa — arquivado |

## A navegação-alvo

- **Barra lateral:** `+ Novo mandato` · Início · Mandatos · (recentes) ·
  Administração (Qualidade da automação).
- **Barra superior:** trilha (Mandatos › Caso › Aba) e conta. Busca ⌘K, avisos
  e modo discrição entram nas fases 2 e 4.
- **Dentro do mandato, abas fixas na ordem do trabalho:** Visão geral ·
  Documentos · Pendências · Perguntas ao cliente · Grupo econômico · Modelagem ·
  Entregáveis. Régua de etapas no cabeçalho.

## Fases

| Fase | O que entrega | Itens |
|---|---|---|
| **1 · Estrutura** | Barra lateral nova com ícones próprios e só os recentes; trilha e conta no topo; fim da abertura animada e do rodapé fixo; abas fixas do mandato com régua de etapas; `loading`/`error`/`not-found`; renomes; jargão de engenharia fora da tela; cabeçalhos padronizados | 01–06, 14, 15, 25, 26, 28, 35 |
| **2 · Redistribuir** | Visão geral enxuta com "Próximo passo"; aba Pendências única (absorve Revisão e as 4 seções); Documentos com painel lateral; Entregáveis (3 arquivos + campos da apresentação); Modelagem com uma barra de salvar; Início com 4 indicadores e fila filtrável; Mandatos em tabela com menu ⋯; explicações visíveis no lugar de `title=`; busca ⌘K | 08–10, 12, 16–18, 20, 21, 27 |
| **3 · O que vende** | Histórico do mandato; "Ver no original" (CONFERIR antes se o arquivo original está guardado); Grupo econômico em organograma; perguntas em lote; novo mandato em 2 passos; Administração | 13, 19, 22–24, 33 |
| **4 · Acabamento** | Imagem de fundo (do dono) no login e na faixa do Início; indicadores refinados; movimento; celular; modo discrição; avisos; modo escuro | 07, 11, 31, 32, 36–38 |
| **5 · Comercial** | Papéis e acesso por mandato **no banco primeiro**; tela de equipe; recuperar senha, MFA, SSO Microsoft | 29, 30 |

## Estado da execução — PAUSADO em 27/10/2026, ~21h05 UTC

> Pausa pedida pelo dono (fim de cota). Nada ficou pela metade **no código**:
> a árvore estava limpa e tudo commitado e empurrado em
> `claude/friendly-lamport-22ctle`, PR #265 (rascunho). O que parou no meio
> foi **verificação**, não implementação.

### Finalizado (Fase 1 inteira — 9 commits, `e4cade0..b9c44b8`)

| Commit | O quê | Itens |
|---|---|---|
| `e4cade0` | Decisões do dono no PRODUCT.md / DESIGN.md / este arquivo | — |
| `bdbbb6f` | Casco: barra com ícones e 5 recentes, trilha, menu de conta; sem abertura animada e sem rodapé | 01–05, 35 |
| `8d47e24` | 5 observações do Sonar no casco | — |
| `d000d54` | Abas fixas no mandato, régua de etapas, menu ⋯ (Fechar/Excluir) | 14, 15 |
| `ef7fb1b` | loading / error / not-found; recusa do export vira página HTML (invariante 40 em `verificar-export.mts`, medido: 3 de 5 reprovam sem a proteção) | 06 |
| `d8c6fe3` | 5 observações do Sonar nas abas | — |
| `a996022` | Renomes na tela (Aprovação, Grupo econômico, Empresa não identificada, Qualidade da automação, status) | 25 |
| `8866ac5` | Quality Gate do Sonar: URL `http://` fictícia no teste → `https`; props Readonly | — |
| `b9c44b8` | Jargão de engenharia para "Detalhes técnicos"; cabeçalho e "para que serve" em toda aba | 26, 28 |

Cada fatia passou localmente: `tsc`, `eslint`, `next build`, os 12
`verificar-*.mts` (export 866/0), portão do conhecimento e espelho do CLAUDE.md.

### Parou no meio (retomar por aqui, nesta ordem)

1. **CI do head `b9c44b8`** — o `suites.yml` estava rodando. Todos os vermelhos
   anteriores do PR foram jobs **cancelados** por push seguinte
   (`cancel-in-progress`), não reprovação; em `a996022` passaram portal, banco,
   n8n e e2e. Conferir que o head ficou verde; se não, é trabalho real.
2. **Sonar no head** — o Quality Gate tinha caído para B (S5332, `http://` no
   teste) e o conserto está em `8866ac5`; os comentários "failed" que chegaram
   depois eram de commits velhos. Conferir o gate do head e as issues novas de
   `b9c44b8` (as fatias anteriores geraram ~5 observações cada, quase todas
   `Readonly` em props).
3. **Revisão independente** (`revisor-defeito-silencioso`) sobre
   `git diff origin/main...HEAD` — foi **interrompida** na pausa, sem
   resultado. Refazer do zero. Focos pedidos: contagens das abas contra a tela
   de destino, o resumo "Em N de M etapas" da Qualidade da automação, ausência
   que virou silêncio depois de mover o jargão, Fechar/Excluir dentro do menu ⋯
   escondido, a recusa do export para quem não pede HTML.
4. **Conferência visual do dono** no deploy de pré-visualização da Vercel —
   nenhuma tela autenticada foi vista em navegador (sem sessão Supabase no
   container).
5. **`ESTADO.md`** ainda não cita o redesenho (passo do `estado-e-handoff` /
   `/fechar`), nem há ficha do conhecimento para ele.
6. Tirar o PR de rascunho só depois de 1–4.

### Pendências pequenas anotadas durante a Fase 1 (não bloqueiam)

- Funções puras novas sem teste: `escolherRecentes` (barra-lateral),
  `iniciaisDoEmail` (menu-conta), `passosDaTrilha` (trilha),
  `etapaDoMandato` (lib/etapa-do-mandato.ts), `mensagemDeLogin`. Um
  `verificar-navegacao.mts` exigiria linha no CI **e** no CLAUDE.md (o espelho
  reprova a divergência).
- Recentes: quem tem histórico vê a ordem trocar uma vez após a hidratação
  (servidor renderiza os 5 mais novos; o cliente reordena por visita). Mesma
  contagem, sem salto de layout.
- Menu ⋯ do mandato não fecha sozinho depois de Fechar/Excluir.
- Qualidade da automação ainda mostra "Completude (Portão 1)", "N0–N3" e
  "golden set" (tela de administração; o vocabulário decidido não cobre
  Portão 1).
- A aba é "Revisão" (só revisão de documento) até a aba "Pendências" unificada
  da Fase 2 existir.
- "Exportar dados" e "Ir para a modelagem" continuam na Visão geral até a aba
  Entregáveis (Fase 2).

### Ainda a fazer

Fases 2, 3, 4 e 5 da tabela acima, inteiras. A Fase 2 começa por: Visão geral
enxuta com "Próximo passo", aba **Pendências** única (absorve Revisão e as 4
seções da visão geral), aba **Documentos** com painel lateral, aba
**Entregáveis** (3 arquivos + campos da apresentação; a aba Apresentação some),
Modelagem com barra de salvar única, Início com 4 indicadores (custo sai — 
decisão 2), Mandatos em tabela com menu ⋯, explicações visíveis no lugar de
`title=`, busca ⌘K. A Fase 4 espera a imagem de fundo que o dono está criando.

## Arquivado (decidido, não agendado)

Nenhuma tela pode antecipar estes itens: interface que sugere separação de
acesso que o banco não garante é pior que nenhuma interface (`PRODUCT.md`,
"RLS por caso não existe ainda").

1. **Multiempresa — outras casas assinando o portal.** Exige isolar os dados de
   cada assinante no banco (organização acima do caso, RLS por organização),
   o que é maior que a Fase 5 e muda a ordem do roadmap. Reabrir quando houver
   o primeiro assinante em vista.
2. **Área do cliente.** O cliente acessa só o mandato da própria empresa, para
   subir documentos (contra o Kit Básico) e acompanhar o andamento. Pré-requisito:
   papéis e RLS por caso (Fase 5) e uma superfície externa isolada da interna —
   o cliente nunca vê pendência, premissa nem nota interna.
