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

## Estado da execução — 28/10/2026 (pausa pedida pelo dono)

> Execução PAUSADA a pedido do dono. Nada ficou pela metade: todo trabalho
> está commitado e empurrado em `claude/friendly-lamport-22ctle`, PR #265
> (rascunho), e nenhum agente está rodando. Cada fatia passou `tsc`,
> `eslint`, `next build` e os 12 `verificar-*.mts`; as regras novas têm
> invariante medido não-vazio (o número de asserts que reprovam está na
> mensagem de cada commit). Seis revisões independentes acharam e foram
> corrigidos mais de 40 defeitos silenciosos. Sonar: Quality Gate passando.
> **Nenhuma tela autenticada foi vista em navegador** — o container não tem
> sessão Supabase; a conferência visual é no preview da Vercel.

### Finalizado

| Bloco | Commits | O quê |
|---|---|---|
| Decisões | `e4cade0` | PRODUCT/DESIGN/este arquivo; multiempresa e área do cliente arquivadas |
| **Fase 1** | `bdbbb6f`..`b9c44b8`, `95a447e` | Casco (barra com ícones e recentes, trilha, menu de conta), abas fixas + régua + menu ⋯, loading/erro/não encontrado, recusa do export em página, renomes, jargão em "Detalhes técnicos" |
| **Vidro** | `ea05123`, `f42fc77`, `e813d53` | Foto "ORIA DIGITAL" na tela inteira, barra e topo suspensos em vidro escuro, folha creme sem backdrop-filter; diálogos por portal; contraste medido |
| **Fase 2** | `17b1116`, `e4baac2`, `f40e4b3`, `91cd0d5`, `25154ab`, `d8185d1`, `8350713`, `ff36ad6`, `459f21a` | Entregáveis; Visão geral com Próximo passo; Documentos com painel lateral; Pendências única; Início com 4 indicadores e fila; Mandatos em tabela; Modelagem com barra de salvar; explicações visíveis; busca ⌘K |
| **Fase 3** | `805c759`, `53360e2`, `87b44fe`, `a2881c2`, `37b07c5`, `277b672`, `1b25441`, `24a8bf6`, `68dd476` | "Ver no original" (na versão e página citadas); perguntas em lote com e-mail ao cliente; novo mandato em 2 passos; Grupo econômico em organograma; Administração (Qualidade da automação + Custos); Histórico do mandato (migration **0215** + tela pelo menu ⋯, paginação por (em, chave)) |
| **Fase 4 (parte)** | `bc0d1cf` | Modo discrição (borra valores financeiros; proteção só visual, limite declarado); celular com barra inferior (Início, Mandatos, Busca, Novo, Mais) |
| Correções | `9339d71`, `81aca9c`, `4813605`, `0e0f8f2`, `71f8a63` | Achados das revisões; Sonar; conferidor de chamadas reconhece o bucket do Storage |

### Em andamento

Nada. No momento da pausa o CI de `cf1a67f` estava rodando e o de `bc0d1cf`
começa com este envio; as rodadas anteriores só tiveram jobs CANCELADOS por
envio seguido (nenhum teste reprovou — `banco`, `portal`, `n8n-e-derivados`
e `e2e` passaram em `277b672`, `9339d71` e `81aca9c`). Conferir o CI do
último commit ao retomar.

### O dono faz à mão

- **Aplicar a migration 0215 em produção** (depois da 0214) e conferir
  `select chave, presente, detalhe from fn_instalacao_conferir() where
  migration = '0215' and not presente;` → zero linhas. Sem ela, a tela
  Histórico diz que falta a atualização do banco (não quebra).
- Olhar o preview da Vercel nas telas novas (nenhuma foi vista em
  navegador): Ver no original, Perguntas em lote, Novo mandato, Grupo
  econômico, Administração/Custos, Histórico, modo discrição e o celular.

### Pendências pequenas (não bloqueiam)

- Funções puras sem teste: `escolherRecentes`, `iniciaisDoEmail`,
  `passosDaTrilha`, `etapaDoMandato`, `mensagemDeLogin`.
- "Tempo médio de ingestão" e não "até aprovar": `caso` não tem data de
  aprovação — o indicador pedido precisa dessa coluna.
- Novo mandato sem "Produto" e "Responsável": `fn_upsert_caso` só grava o
  nome, e responsável exige coluna nova (migration).
- `createSignedUrl` contra objeto inexistente não foi exercitado no Storage
  real; se assinar sem erro, o clique cai num 404 do Storage.
- Modo discrição: indicadores do Início não marcados (são contagens); a
  marca nas premissas da Modelagem não foi medida; `viewport-fit=cover` não
  declarado (a margem do iPhone cai nos 12px de piso).
- Ramo da 0215 que tira da vinculação as linhas do lote sem assert (0 de 49).
- ~88 observações menores do Sonar (estilo); Quality Gate passando.
- Revisão independente da fatia `bc0d1cf` (Fase 4) ainda não feita.

### Ainda a fazer

1. **Revisar** `bc0d1cf` (revisor-defeito-silencioso) e corrigir o que achar.
2. **Fase 4 · resto** — avisos de processamento concluído (proposta: ler
   `lote_execucao` recém-concluído, "visto" por usuário; tabela de avisos só
   se precisar de estado no servidor); modo escuro (tokens em `globals.css`
   e DESIGN.md, contraste medido como no vidro).
3. **Fase 5 · Comercial** — papéis e RLS por caso **no banco primeiro**
   (hoje toda policy é `USING (true)` para authenticated); depois tela de
   equipe; recuperar senha, MFA, SSO Microsoft. Precisa de decisão do dono
   sobre os papéis (ex.: sócio, analista, leitura).
4. **Fechamento** — `ESTADO.md` e ficha do conhecimento do redesenho; tirar
   o PR #265 de rascunho; reduzir as observações de estilo do Sonar.

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
