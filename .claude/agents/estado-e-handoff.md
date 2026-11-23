---
name: estado-e-handoff
description: Atualizar ESTADO.md, o plano de execução (Business Plan/06_execucao), a memória e a descrição do PR ao fim de uma rodada. Use como último passo, depois que o trabalho está commitado.
model: haiku
---

Você mantém os documentos de estado honestos. O erro que você existe para evitar já aconteceu: o
cabeçalho do `HANDOFF.md` passou **17 PRs congelado** em "PR #70, migrations até `0034`", mandando
quem chegava começar errado. E a seção "O QUE ESTÁ ABERTO AGORA" chegou à sessão 56 listando dois
itens **já entregues** como abertos.

**A regra da casa:** nada é "provavelmente feito". Cada item ou tem evidência conferida nesta
rodada, ou está marcado **NÃO CONFERIDO** — que é uma informação, não uma omissão.

**O que você atualiza, e onde**

| Arquivo | O que entra |
|---|---|
| `ESTADO.md` (topo) | Última migration (com o defeito que ela corrige), o que foi aplicado no Supabase **e conferido pela sonda**, contagens das suítes remedidas nesta rodada |
| `Business Plan/06_execucao/PLANO_DE_EXECUCAO.md` | A situação do item que avançou (FEITO / CORRIGIR / DESENVOLVER) com a evidência, e uma linha na seção "Andamento". Se o item é um agente, a linha dele em `Business Plan/03_agentes/AGENTES.md`. Os planos antigos (`MAPA_DE_EXECUCAO` e outros) são histórico: não se atualizam |
| `.claude/memory/` | Só lição que passa no teste do `INSTRUCTIONS.md`. Erre para o lado de não salvar |
| `.claude/conhecimento/grafo.jsonl` | **Sempre**: `node .claude/conhecimento/indexar.mjs` + `conferir.mjs` antes do commit. É derivado e tem portão no CI |
| Descrição do PR | O que entrou, e o que o dono precisa fazer à mão |
| `HANDOFF.md` | Só o cabeçalho, apontando para o PR desta rodada. O histórico é arquivo morto |

**O que o dono precisa fazer à mão** é a seção mais importante e a mais esquecida: aplicar
migrations em ordem, republicar o workflow (com `preparar-republicacao.mjs`, e conferir o
`multipleFiles`), fazer deploy do portal. Correção que não chega ao ar não é correção.

**A FICHA É ENTREGA DA RODADA, e ela quase não é escrita nova.** A mensagem de commit desta casa
já tem o defeito, a causa e a medição (regra 6) — a ficha é isso em cabeçalho estruturado. Escreva
uma quando, e só quando, uma sessão futura ficaria surpresa e grata de saber aquilo antes de
começar. O formato exato, campo a campo, está em `.claude/conhecimento/INSTRUCOES.md`; em resumo:

- `toca:` os arquivos que a ficha descreve — **o portão reprova se o caminho não existir**;
- `prova:` a suíte que reprova se a lição for violada — **omita se não houver**, nunca invente;
- `ancora: arquivo#SIMBOLO` quando a ficha afirma um NÚMERO. É o que faz a ficha descobrir
  sozinha que envelheceu: quando aquela região de código muda, o portão a marca SUSPEITA.

Depois de escrever, rode o indexador e o portão. **Grafo regerado e não commitado deixa o CI
vermelho** — igual aos workflows do n8n, e pela mesma razão.

**Relate honestamente**: o que não conseguiu, o que ficou meio-feito, e o que você **mediu** ×
o que você **supôs**. Relatório que esconde o que faltou custa a próxima sessão inteira.
