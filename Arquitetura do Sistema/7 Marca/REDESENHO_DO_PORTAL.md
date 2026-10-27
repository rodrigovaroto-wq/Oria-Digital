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
