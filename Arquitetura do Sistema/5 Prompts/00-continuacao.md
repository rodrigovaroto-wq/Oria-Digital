# Continuação — abrir uma sessão de trabalho autônomo

## Quando usar

Primeira mensagem de uma sessão nova. Substitui o `Arquitetura do Sistema/5 Prompts/PROMPT_CONTINUACAO.md` antigo, que era uma
fotografia da sessão 19 e mandava começar errado.

## Por que funciona

Ele **não diz** o que está feito, quantos testes existem, nem qual PR está aberto — manda medir.
Toda alegação sobre o estado vem de um comando rodado agora, nunca de um número lembrado. E separa
as três coisas que este projeto mistura com frequência: o que o repositório tem, o que está no ar,
e o que alguém acha que está no ar.

## O prompt

```
Você está assumindo o projeto Tratamento de Dados Financeiros (Oria Partners). Leia o `CLAUDE.md`
e o `.claude/memory/MEMORY.md` antes de qualquer outra coisa — os dois são curtos, e a memória é
a lista do que já custou caro aqui.

Você roda sozinho. NÃO faça perguntas: decida, execute, e registre a decisão junto com o motivo.
Onde houver ambiguidade genuína, escolha a opção mais conservadora — a que NÃO inventa número e a
que NÃO desfaz arquitetura existente —, implemente, e deixe a alternativa registrada para o dono
decidir depois.

## 1. Meça o estado antes de tocar em nada

Não estime nenhum destes; rode:

- `git log --oneline -12`, `git fetch origin main`, e a lista de PRs abertos. Já houve sessões em
  paralelo neste repositório — não assuma nada sobre o `main`.
- O topo do `ESTADO.md` e o `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md`. O `HANDOFF.md` é arquivo morto: procure
  nele com `grep -n`, não o leia inteiro.
- As suítes, com os comandos de `.claude/COMANDOS-CANONICOS.md`, ANTES de mudar qualquer coisa. Suíte vermelha que já
  estava vermelha não é sua regressão — mas você precisa saber disso agora, não depois.
- Se houver acesso ao banco: `select * from fn_instalacao_conferir() where not presente`. Se não
  houver, diga isso em vez de afirmar qualquer coisa sobre produção.

Ao fim desta etapa você sabe dizer, em uma frase: o que está mergeado, o que está aberto, o que
está APLICADO no Supabase, e o que está PUBLICADO no n8n. Os quatro são diferentes.

## 2. Escolha o trabalho pelo mapa, não pela vontade

`Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` diz o que falta, em ordem, com critério de pronto. Pegue de lá. Se o que
está no topo depende do dono e não de engenharia, diga isso e pegue o próximo que não depende.

## 3. Trabalhe orquestrando

A sessão principal decide e delega; os especialistas estão em `.claude/agents/`. Despache em
paralelo só quando as duas condições valerem — sem dependência entre as tarefas E arquivos
totalmente disjuntos. Quem comita é você, uma tarefa por vez, capturando o `HEAD` na hora.

Antes de fechar cada fatia, passe o diff pelo `revisor-defeito-silencioso`.

## 4. Ao terminar

- Atualize o topo do `ESTADO.md` e o `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` (agente `estado-e-handoff`).
- Acrescente à memória só o que passa no teste do `.claude/memory/INSTRUCTIONS.md`.
- Deixe EXPLÍCITO o que o dono precisa fazer à mão: aplicar migrations em ordem, republicar o
  workflow pelo `preparar-republicacao.mjs`, fazer deploy do portal. Correção que não chega ao ar
  não é correção.
- Relate honestamente o que você MEDIU × o que você SUPÔS, e o que ficou meio-feito. Relatório que
  esconde o que faltou custa a próxima sessão inteira.
```
