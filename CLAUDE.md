# Tratamento de Dados Financeiros — Oria Partners

> Memória de projeto do Claude Code. **Este arquivo é carregado em toda sessão, então ele é
> curto de propósito e não guarda número nenhum que envelhece.** Onde um número importa, ele
> aponta para quem o mede.

Pipeline que recebe documentos financeiros de mandatos de M&A/reestruturação, extrai as
demonstrações com IA, grava em Postgres/Supabase com proveniência, e exporta um book em Excel
com modelo de FP&A vivo em fórmula.

## Onde está o estado (leia nesta ordem, pare quando tiver o que precisa)

| Arquivo | Pergunta que responde |
|---|---|
| `node .claude/conhecimento/buscar.mjs "<assunto>"` | **Comece por aqui, sempre — vale para a sessão principal e para todo agente despachado.** Devolve, em um comando, as fichas, os arquivos com linha, o portão que prova cada coisa e os commits do assunto — sem abrir nada. Medido: as cinco perguntas de `BASELINE.md` caíram de 50.245 para 10.667 bytes. Quando ele responde **"NADA ENCONTRADO"**, isso é "procurei e não achei" — e só aí vale o `grep` |
| `ESTADO.md` (topo) | **Onde estamos agora** — última migration, suítes, a rodada mais recente |
| `Arquitetura do Sistema/3 Estado e Execução/MAPA_DE_EXECUCAO.md` | **O que falta até fechar**, em ordem, com critério de pronto |
| `Arquitetura do Sistema/3 Estado e Execução/PRONTIDAO_POR_ESTAGIO.md` | O projeto medido contra o próprio objetivo, estágio por estágio |
| `.claude/memory/MEMORY.md` | As lições que já custaram caro — **leia sempre, é curto** |
| `HANDOFF.md` | **Como chegou aqui** — arquivo morto, ~5.000 linhas. Não leia inteiro |

**Nenhum arquivo deste repositório é autoridade sobre o banco.** Quem responde é a sonda,
contra o banco em que você está conectado:

```sql
select chave, migration, tipo, objeto, presente, detalhe, porque
  from fn_instalacao_conferir() where not presente order by 1;
```

## As sete regras (cada uma nasceu de um defeito que chegou em produção)

1. **Nunca apresentar ausência como dado.** Zero fabricado numa premissa é indistinguível de
   uma medição de zero. Célula em branco + nota com o motivo **e o efeito** ("o bloco de dívida
   cobra juro zero"), sempre.
2. **Todo invariante novo precisa ser MEDIDO não-vazio.** Desligue a correção, rode a suíte,
   confirme que reprova, religue. O número de asserts que reprovaram vai na mensagem do commit.
3. **Invariante afirma COMPORTAMENTO, não mecanismo.** Um teste que descreve *como* o código faz
   protege o bug.
4. **Nunca inventar fixture para provar bug de produção.** Se não dá para reproduzir o arranjo
   real, diga isso no comentário e afirme só o que dá para provar.
5. **Comentário explica POR QUÊ, com o número medido junto.** "Corrige bug" não serve.
6. **Uma fatia por commit**, com mensagem que conta o defeito, a causa e a medição.
7. **Estágio que não rodou tem a mesma aparência de estágio que rodou e não achou nada.**
   Cobertura verde não é prova de execução — ver `.claude/memory/estagio-desligado-parece-limpo.md`.

## Comandos canônicos

**Estão em `.claude/COMANDOS-CANONICOS.md` — abra-o inteiro antes de rodar qualquer suíte**
(espelho do CI, com portão: `node .claude/verificar-espelho-claude-md.mjs`). Duas regras ficam
aqui porque valem mesmo sem rodar nada: **conflito de merge em arquivo derivado nunca se resolve
à mão** (regere, na ordem do arquivo), e **`npx` nunca** no lugar de `./portal/node_modules/.bin/<bin>`.

## Orquestrar, não implementar sozinho

A sessão principal entende, decide e delega. Trabalho implementável vai para o especialista
cuja linha casa com a tarefa — os arquivos estão em `.claude/agents/`.

| Agente | Quando usar | Nível |
|---|---|---|
| `migrations-postgres` | Migration, função SQL, sonda, `Supabase/test/*.sql` | médio |
| `n8n-workflow` | Geradores, `N8N/lib/*`, nós Code, republicação | médio |
| `portal-export` | `portal/src/**`, `export.ts`, endereços de célula | médio |
| `suites-invariantes` | Executar o protocolo de invariante não-vazio (condicional) | médio |
| `revisor-defeito-silencioso` | Revisar um diff sob a lente central do projeto | forte |
| `estado-e-handoff` | Atualizar `ESTADO.md`, `MAPA`, memória, PR | barato |
| `explorador` | Fan-out amplo, só depois de `buscar.mjs` vir vazio (condicional) | barato |

**Estes sete são a lista inteira.** Os 30 agentes `importado.*` e os 52 comandos de barra
importados foram removidos em 16/09/2026: custavam 19.439 bytes de `description` no prompt de
TODA sessão, nenhum conhecia as sete regras, e três contradiziam a regra 2 (`/test-generate`,
`/tdd-green`, `/sql-migrations`). A procedência ficou em `.claude/COMANDOS.md`. Sobraram três
comandos escritos aqui — `/rodada`, `/revisar`, `/fechar` —, e o portão que prova que todo
`subagent_type` citado existe é `node .claude/verificar-comandos.mjs`.

**O plugin `superpowers` está DESLIGADO neste projeto** (`.claude/settings.json`,
`enabledPlugins`), pelo mesmo critério que cortou os 52 comandos importados. Das 14 skills, 5
contradizem as regras 1, 6 e 7 em texto e 7 duplicam o que `/rodada`, `/revisar`, `/fechar` e o
`buscar.mjs` já fazem melhor; as 9 que sobrariam somam **29,7k tokens de on-invoke** sob uma skill
always-on que manda invocar "se houver 1% de chance de aplicar". A auditoria por skill, com os
trechos literais, está em `.claude/conhecimento/fichas/superpowers-cinco-skills-vetadas.md` — e
ela vale como veto se alguém religar o plugin. Versão nova é caso de reauditoria, não de religar
no escuro.

**Dois dos sete são condicionais, não automáticos.** `explorador` só quando
`buscar.mjs` devolveu pouco E a busca é ampla (fan-out por vários diretórios) — no caso normal a
sessão principal roda `buscar.mjs` direto, que é um comando de Bash. `suites-invariantes` só
quando o protocolo de medir não-vazio vai de fato ser EXECUTADO (desligar a correção, contar os
asserts, religar); lembrar que a regra existe não é motivo para abrir um contexto novo.

**Nível de modelo é escolhido por despacho, nunca herdado por acidente.** Despacho paralelo
(ondas) só quando **as duas** condições valem: sem dependência entre as tarefas **e** conjuntos
de arquivos totalmente disjuntos. Quem comita é sempre a sessão principal, uma tarefa por vez,
capturando o `HEAD` na hora. Ver `Arquitetura do Sistema/5 Prompts/03-onda-paralela.md`.

## Acompanhar PR

Assine o PR ao criá-lo, como o harness manda — mas **desinscreva assim que CI e Sonar
ficarem verdes** e diga isso ao dono. Notificação que chega depois de 1h parada regrava o
cache inteiro: medido US$ 2–4 por aviso com contexto de 465–520k (sessões de 06/10 e 30/10),
sem trabalho novo nenhum. Merge e comentário tardio são o dono quem traz.

## Antes de codar

Pedido aberto (mais de uma leitura razoável) → `Arquitetura do Sistema/5 Prompts/` primeiro, código depois.
Bug → causa raiz antes de qualquer correção; três correções falhas seguidas param a linha e
questionam a arquitetura, não tentam a quarta. **Antes de editar uma função, liste TODOS os
chamadores** (`grep -rn <nome> Supabase/ N8N/ portal/src/`) e corrija no ponto por onde todos
passam — mudar a semântica de uma muda a de todos (`custoEstimadoPorTamanho`, 46× abaixo, v31
reaberto: `.claude/memory/conta-parcial-vira-v31-quando-promovida.md`).

**A escada — sete perguntas antes de escrever QUALQUER código** (migration, nó, gerador, portal,
teste, script). Ela roda *depois* de entender o problema e ler o que a mudança toca, nunca no lugar
disso. Pare no primeiro degrau que resolve:

1. **Isto precisa existir?** Necessidade especulativa → não faça, e diga em uma linha.
2. **Já existe neste repositório?** `buscar.mjs` pelo que a coisa FAZ, não pelo nome que você daria
   → reuse. Duas implementações da mesma conta divergem sem erro nenhum.
3. **A biblioteca padrão resolve?** (Node, Python, as funções nativas do Postgres.)
4. **A plataforma resolve?** `check`/`unique`/FK/função no Postgres antes de validação em nó Code
   ou TypeScript; fórmula do Excel antes de valor calculado no export.
5. **Uma dependência que JÁ está no lock resolve?** Nunca uma nova para o que poucas linhas fazem.
6. **Cabe em uma linha?** Uma linha.
7. **Só então:** o mínimo que funciona — sem abstração de uma implementação só, sem configuração
   para valor que nunca muda, sem andaime "para depois".

**O que a escada NUNCA corta:** validação na fronteira de confiança (o documento do cliente, a
saída da extração), tratamento que evita perda de dado, segurança, e as sete regras — a nota de
ausência (1), o invariante medido não-vazio (2), o porquê com o número no comentário e no commit
(5 e 6), o sinal positivo de que o estágio rodou (7). Simplificação deliberada com teto conhecido
leva comentário com o teto e quando subir. Menos código é consequência, não meta.

## Memória

`.claude/memory/INSTRUCTIONS.md` diz o que vira memória e o que não vira. Regra em uma linha:
**uma sessão futura ficaria surpresa e grata de saber disso antes de começar?** Se dá para
derivar lendo o código, não é memória.

**E ela agora tem índice e portão.** `.claude/conhecimento/INSTRUCOES.md` é o manual em uma
página: `buscar.mjs` antes de abrir arquivo, ficha com `toca`/`prova`/`ancora` ao fechar a
rodada, `indexar.mjs` + `conferir.mjs` antes do commit. O `grafo.jsonl` é **derivado e
versionado** — quem o regera commita o resultado, senão o CI fica vermelho, exatamente como
nos workflows do n8n. A âncora é o que faz uma ficha descobrir sozinha que envelheceu: quando
a região de código que ela cita muda, o portão a marca SUSPEITA e manda relê-la.
