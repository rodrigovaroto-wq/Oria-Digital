# Gate de fase — a passagem, não a chegada

## Quando usar

Entre uma fase do `3 Estado e Execução/ARQUITETURA_ALVO_E_ROADMAP.md` e a seguinte. Duas vezes: ao
**entrar** (o que a fase custa e de quem depende) e ao **sair** (ela pode ser declarada fechada?).

Não confunda com os cinco gates da seção 5 do roadmap — DATA, MODEL, STRATEGY, CREDITOR,
PRESENTATION. Aqueles são marcos, fecham em fases específicas. Este roda em toda fase.

## Por que existe

Fase declarada pronta contamina as seguintes, e a conta só chega adiante. Três formas já medidas
aqui — e as três reapareceram juntas na rodada real de 16/09/2026:

- **Portão calibrado no lugar errado.** A régua passava com +3% enquanto produção errava **161%**:
  media a entrada do gerador, não o texto que o n8n tira do PDF
  (`.claude/memory/portao-mede-a-entrada-de-producao.md`). Em 16/09 a versão nova disso foi a
  estimativa da tela prometer 4 min para um lote de 14,5 — com **115 e 66 asserts verdes**, porque
  nenhum portão olhava para o relógio.
- **Invariante que nasce vazio.** Na sessão 18 o autor registrou que *dois invariantes MEUS
  nasceram vazios* — verdes por não afirmarem nada.
- **Portão que não olha para produção.** O catálogo da sonda mora DENTRO do banco, então banco
  atrasado não se auto-acusa (`.claude/memory/sonda-so-conhece-o-catalogo-que-o-banco-tem.md`). Em
  16/09 a conexão falhava por **porta** (o pooler é 6543, não 5432) e a credencial do n8n guardava
  a senha antiga enquanto o segredo do CI tinha a nova. Nada disso vive no código.

## 1. ENTRADA — antes da primeira linha

- **De quem depende:** credencial, segredo, limite de hospedagem, apply, republicação, decisão de
  produto, merge. Descoberto no meio, cada um já parou a linha por horas.
- **O que custa em rodada paga** (só quando a fase exige rodada real): quantas rodadas, a ordem de
  grandeza por `N8N/medir-custo-book.mjs`, e **o teto a partir do qual você para e pergunta**.

Fase que não depende de ninguém e não paga rodada responde "nenhuma" e segue.

## 2. SAÍDA — os seis veredictos

`PASS` · `PASS COM RESSALVA` · `FAIL` · `NÃO SE APLICA`, **com a medição ao lado**. Veredicto sem
evidência citada não vale.

| Gate | A pergunta | Onde se mede |
|---|---|---|
| **Produção** | O que está no ar é o que o repositório diz? | sonda contra produção · `conferir-publicado.mjs` · a credencial responde · o limite de runtime (RAM, cota, tamanho de lote) não mudou |
| **Invariante** | Todo portão novo reprovou com a correção desligada? | o número de asserts que caíram, que a regra 2 manda pôr no commit |
| **Regressão** | O que a fase não tocou continua verde? | as suítes de `.claude/COMANDOS-CANONICOS.md` que já estavam verdes |
| **Financeiro** | O "Aceite financeiro" da fase foi satisfeito? | a linha da própria fase no roadmap |
| **Derivado** | O gerado bate com o commitado? | `git diff --exit-code` nos workflows, fixtures, `schema.sql` e no grafo |
| **Contaminação** | A fase criou dependência que atrapalha uma fase adiante? | o dependency graph, seção 6 do roadmap |

**`FAIL` em Produção ou Invariante não passa** — são os dois que deixam o defeito seguir invisível.
Nos outros, ressalva registrada é passagem válida.

## 3. O que não é desta fase

Todo achado que sobra vai para um dos dois, nunca para o limbo:

- **DIFERIDO PARA <fase>**, com a razão de ser lá. Corrigir na hora incha a fase.
- **ACEITO** — limitação que ninguém vai corrigir por ora, com o efeito declarado.

Os dois entram no `ESTADO.md` pelo `/fechar`. Achado que não virou um deles volta como surpresa.

## 4. A ordem

```
/rodada → /revisar → commitar → GATE → /fechar
```

O gate vem antes do `/fechar` porque o checkpoint registra o veredicto; na ordem inversa o estado
grava "pronto" sobre uma fase que o gate ainda pode reprovar. Medir não-vazio e fatia por commit
são de `/rodada`; revisor ≠ autor é de `/revisar`; o que o dono faz à mão é de `/fechar` — aqui só
se **confere** que aconteceram.

## Saída

```
ENTRADA DA PRÓXIMA FASE: depende de <…> · custa <…>
OS SEIS VEREDICTOS, com evidência
DIFERIDOS / ACEITOS
PRONTO PARA A PRÓXIMA FASE: SIM/NÃO — qual, e por quê
```

Não implemente a fase seguinte na mesma passada.
