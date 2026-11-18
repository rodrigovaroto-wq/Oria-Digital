# Plano de continuação da S129: redesenho do portal e as funções aprovadas

> **Leia este arquivo antes de qualquer coisa ao retomar.** Ele substitui reler a conversa da S129.
> Escrito em 13/11/2026, quando o dono pediu para pausar e retomar em outra sessão.
> Branch: `claude/youthful-clarke-r6cg5j`. PR: rodrigovaroto-wq/Oria-Digital#298 (rascunho).

## 1. Onde paramos (estado exato)

- **A branch está limpa e enviada.** O último commit é o `ec3a813`. São 20 commits à frente da `main`, sem conflito no momento da pausa.
- **CI:**
  - verde no `3c9ad4f` (redesenho) e no `e4a3a9e` (correção da 0300);
  - no `ec3a813`, só documentação, os checks de terceiros terminaram sem falha e as suítes estavam rodando na pausa;
  - **ao retomar, confirme que o `ec3a813` ficou verde.**
- **Produção:** 0276 e 0300 aplicadas. A sonda dá 435 itens e 0 ausentes, com cobertura 0300.
- **Revisão independente do redesenho (commit `3c9ad4f`): INTERROMPIDA na pausa, sem resultado.** É a PRIMEIRA coisa a refazer (§3, passo 1).
- **Sonar:** o quality gate passa, com 7 avisos de estilo abertos no redesenho (§3, passo 2).

## 2. O que a S129 fez (com a prova de cada item)

| # | Entrega | Commit(s) | Prova |
|---|---|---|---|
| 1 | Auditoria das ferramentas do vídeo (Taste Skill, React Bits, Transitions.dev) | — | Taste Skill **não instalar** (gatilho Stop de 10 min e manda inventar dado); usar só a biblioteca de paletas. Transitions.dev aprovado (CSS puro; a licença proíbe redistribuir a biblioteca). React Bits, um componente por vez |
| 2 | Linha de base medida (capturas e tempos) | — | Ferramentas em `Arquitetura do Sistema/7 Marca/redesenho-2026-11/ferramentas/` |
| 3 | **0276**: leituras em lote | `f0c2f5c`, `2ed9f1f`, `7283ab5` | Aplicada em produção. Contagem 5,2 s → 0,2 s; Kit 4,7 s → 0,45 s |
| 4 | Portal usando o lote: visão geral **13,4 s → 1,1 s** | `4508f9d` | 13 `verificar-*.mts` verdes |
| 5 | ALTOs do export: erro virava "Kit faltante" ou "recebido" no book | `4508f9d`, `2e5f43d` | `lerInformacaoDoKit` (função pura) + seção 4f |
| 6 | Login na direção A, frase "O detalhe que muda a tese aparece primeiro." | `1b72e60`, `2e5f43d` | DCL 324 → 237 ms; acessibilidade revisada |
| 7 | Item 2: Início e visão geral pintam na hora (Suspense e esqueleto) | `5067572`, `a8115ce` | Título do Início 3,2–3,8 s → 0,28 s; CLS ≤ 0,034 |
| 8 | CI: filtro do `SET (pg_attver=N)` do pg_dump novo do runner | `fae35f5` | Job `banco` verde de novo. **Outros PRs precisam desse filtro** (§5) |
| 9 | Benchmark de 8 concorrentes | `ef92088` | `Arquitetura do Sistema/7 Marca/redesenho-2026-11/benchmark-concorrentes.md` |
| 10 | Desenho das 4 funções aprovadas (23 decisões aceitas) | `5ea14de`, `dcaef08` | `DESENHO_QUATRO_FUNCOES_2026-11.md` (nesta pasta) |
| 11 | **0300**: Kit com estado calculado na leitura, chave da pendência e evento sempre gravado | `36575aa`, `e4a3a9e`, `ec3a813` | Aplicada em produção; 106 asserts; 36 mutações; 233 chaves adotadas |
| 12 | Telas internas na direção A: mármore, cartões foscos, tema claro e escuro, Início reorganizado, Kit com %, andamento da leitura | `3c9ad4f` | 488 asserts em `mensagem-de-falha`; FCP sem piora |

As decisões do dono estão no topo do `DESENHO_QUATRO_FUNCOES_2026-11.md` e no `ESTADO.md` (seção S129).

## 3. O que falta, na ordem, com critério de pronto

**Fase A: fechar e mergear o PR #298** (o dono pediu: revisar o redesenho, CI verde e merge)

1. **Rodar de novo a revisão independente do `3c9ad4f`**, com o agente `revisor-defeito-silencioso`. O brief usado está no §6 e foca no que o dono pediu: **legibilidade** (contraste AA medido nos dois temas, inclusive texto direto sobre o mármore), **organização** (hierarquia; celular sem rolagem lateral) e **padronização** (um só cartão, espaçamento de 16–24 px, abas Documentos, Pendências, `/casos/todos` e Administração herdando sem cor velha).
   - Pronto quando: a lista de achados está pronta, com número medido e captura.
2. **Corrigir os achados e os 7 avisos do Sonar**, com o agente `portal-export`. Os avisos:
   - `portal/scripts/verificar-export.mts:8807`: ternário aninhado.
   - `portal/scripts/verificar-mensagem-de-falha.mts:1045`: ternário aninhado.
   - `portal/src/app/casos/[id]/visao-blocos.tsx:282,287`: `role="status"` → `<output>`. Cuidado: o `Revelar` e os asserts de `role=status` do item 2 dependem disso. Mude só onde não quebrar o contrato do esqueleto, ou justifique.
   - `portal/src/app/casos/painel-blocos.tsx:574`: template literal aninhado.
   - `portal/src/lib/painel.ts:16`: union → alias de tipo.
   - `portal/src/lib/painel.ts:100`: ternário aninhado.
   - Pronto quando: `tsc`, `eslint`, `next build` e os 13 `verificar-*.mts` passam, numa worktree limpa (§4).
3. **CI verde no último commit, Sonar passando**, e sem conflito com a `main` (`git fetch && git merge origin/main`; derivados se regeram, nunca à mão).
4. **Tirar o PR de rascunho e fazer o merge.** Autorizado pelo dono em 13/11 ("quando verde faça o merge"). Depois, desinscrever do PR e avisar o dono.

**Fase B: fila do redesenho aprovada** (uma etapa por vez, com medição, capturas, revisão e commit; mandar ao dono o antes e o depois)

5. Transições de página e abas deslizantes (transitions.dev "tabs sliding" e View Transitions do Next 16).
6. Régua do mandato animada (já existe a régua estática de 4 etapas no Início e no topo do mandato).
7. Modo apresentação para reunião ("ver como o cliente vê"): só números conferidos e o que falta enviar, sem pendência ou nota interna.
8. Sextante desenhado em traço, número com troca suave (nunca girando em valor financeiro) e confirmações vivas (check e shake).
9. Gráficos sóbrios: rosca do Kit e minigráficos. Carregar a skill `dataviz` antes.
10. Rastreabilidade com destaque no PDF: primeiro investigar se o banco guarda a posição do trecho.
11. Número calculado mostra a conta e a fonte de cada parcela (benchmark Daloopa): investigar se a regra está no banco.
12. Grade documento × fato com citação (benchmark Hebbia), sobre `fn_fatos_do_caso`.

**Fase C: as funções aprovadas que mexem no banco** (ordem do desenho: 1 → 4 → 3 → 2)

13. **Função 1, fatia do portal:** o portal passa a ler `fn_kit_do_caso` (0300 já aplicada) nos três chamadores: `casos/[id]` (visão geral), `documentos/(lista)` e `export/route.ts`.
    - Erro ou zero linhas = "Kit não lido", nunca faltante.
    - Sem a função, cair em `itensDoKitBasicoAtendidos`.
    - Mostrar os estados, inclusive `lido_sem_dado_por_natureza`, o `aguardando_desde` ("há N dias") e o "N de M empresas" só onde vier não-nulo.
    - Estender `verificar-kit-basico.mts` (I1.6 e I1.7).
14. **Botão "conferi" por documento:** possibilidade RECOMENDADA e registrada, mas **o dono pediu para não implementar ainda**. Perguntar antes. Motivo: o `conferido` da D1.1 é quase inalcançável (1.443 de 1.648 versões têm todas as linhas auto-aceitas).
15. **Função 4:** a pendência vira "achado" (tabela própria `achado`), com relatório de riscos.
16. **Função 3:** número novo × reapresentado por período (pela coluna comparativa; a marca "substitui aquele" é de pessoa).
17. **Função 2 (Área do cliente): só DEPOIS de 18/12**, por decisão do dono. Link com token próprio e quarentena.

**Numeração:** as migrations desta frente começam na **0300** (decisão do dono). A próxima livre é a **0301**; reconfira nas branches remotas antes de criar. A 0275 segue reservada para o aging, e a outra sessão usa a 0277 na branch `tender-albattani-vx6m60`.

## 4. Como trabalhar (o que a S129 aprendeu e custou caro)

- **Arquivo derivado (`grafo.jsonl`, `schema.sql`) com agentes em paralelo:** regere numa **worktree limpa do HEAD** com só os arquivos da fatia copiados. Rodar o `indexar` na árvore principal pega a edição ainda não comitada de outro agente. Receita:

  ```bash
  W=/home/user/oria-wt; git worktree add -q --detach $W HEAD
  # cp dos arquivos da fatia para $W
  (cd $W && node .claude/conhecimento/indexar.mjs && node .claude/conhecimento/conferir.mjs)
  cp $W/.claude/conhecimento/grafo.jsonl .claude/conhecimento/grafo.jsonl
  git worktree remove --force $W
  ```

  Esquecer de regerar reprova o job `n8n-e-derivados`; aconteceu no `1b72e60`.
- **Rodar `Supabase/test/run.sh` numa worktree:** o usuário `postgres` não lê a pasta temporária da sessão (`/tmp/claude-0/...`). Crie a worktree em `/home/user/<nome>` e rode `chmod -R a+rwX`. O banco local aceita só `sudo -u postgres` (autenticação peer).
- **Portal numa worktree:** o Turbopack recusa `node_modules` por symlink no `next build` e no `start`; copie com `cp -a`. Para `tsc`, `eslint` e `tsx` o symlink serve.
- **Nunca `git stash` nem `git checkout -- <arquivo>` na árvore principal.** Um hook bloqueia, com razão: apaga o trabalho de outro agente. Para descartar, use `git show HEAD:<arquivo> > <arquivo>` depois de `cp` para backup.
- **Push cancela o CI do commit anterior** (concorrência do workflow). O resumo `suites` aparece vermelho por "cancelled", e isso não é falha. Confira com `actions_get get_workflow_run`; já há um comentário no PR explicando.
- **Aplicar migration em produção:** pela API de gerenciamento, com `jq -Rs '{query: .}' < arquivo.sql` (ver `.claude/memory/aplicar-migration-em-producao-pela-api.md`). Meça a sonda antes e depois (itens, ausentes, cobertura, mandatos) e registre no `ESTADO.md`.
- **Medir o portal logado:** as ferramentas estão em `Arquitetura do Sistema/7 Marca/redesenho-2026-11/ferramentas/`:
  - `capturar.mjs`: capturas em 3 larguras e tempos;
  - `cronometrar.mjs`: cada consulta da visão geral, isolada;
  - `medir.cjs`: FCP, DCL e último bloco, 3 cargas;
  - `medir-visao.mjs` e `cls.cjs`.

  **As credenciais vão SÓ por variável de ambiente** (`PORTAL_EMAIL` e `PORTAL_SENHA`), nunca em arquivo ou commit; peça ao dono. O mandato de referência é o `5469db1d-4862-4d16-9041-8bcd872d1505` (115 documentos, 10.231 linhas). Para o portal local apontar para produção, gere `portal/.env.local` (gitignored) com a chave anon pela API de gerenciamento (`/v1/projects/<ref>/api-keys`).
- **Playwright:** `require('/opt/node-tools/node_modules/playwright')`, ou, em ESM, `import pw from '/opt/node-tools/node_modules/playwright/index.js'`.
- **Fixture do `verificar-export`:** gere com `cd "Dados de Teste"/book-vertentes && PYTHONPATH=. python3 gerar.py` (precisa do `reportlab==5.0.1`).
- **`gh`:** use só para busca. Para logs de CI, use `mcp__github__get_job_logs` e `actions_get get_workflow_job`; o segundo mostra qual passo falhou.
- **Sonar:** `curl "https://sonarcloud.io/api/issues/search?componentKeys=rodrigovaroto-wq_tratamento-dados-financeiros&pullRequest=298&resolved=false&ps=50"` lista os avisos sem login.

## 5. Avisos que valem fora deste PR

- **Filtro `pg_attver`:** o pg_dump do runner do GitHub passou (12→13/11) a emitir `ALTER TABLE ONLY … ALTER COLUMN … SET (pg_attver=N);` por coluna. A correção (`fae35f5`, em `Supabase/test/run.sh`) só existe nesta branch até o merge. Qualquer PR aberto antes disso vai reprovar no job `banco`; basta trazer a `main` depois do merge do #298.
- **Senha:** a senha do usuário de teste do dono ficou no histórico da conversa da S129. O dono foi avisado para trocá-la.

## 6. Brief da revisão do redesenho (para colar no agente `revisor-defeito-silencioso`)

> Revise o commit `3c9ad4f` (redesenho das telas internas na direção A: mármore, cartões foscos, tema claro e escuro, Início reorganizado, Kit e "Andamento da leitura"). NÃO edite nada.
>
> O dono pediu foco em:
> 1. **LEGIBILIDADE:** contraste AA MEDIDO (getComputedStyle mais amostragem de pixel) nos DOIS temas, sobre o cartão e sobre o mármore; tamanho mínimo de fonte; chips de alerta, risco e ok; texto cortado escondendo informação essencial.
> 2. **ORGANIZAÇÃO:** hierarquia e ordem dos blocos; celular em 390 px sem rolagem lateral nem sobreposição; barra lateral com muitos "Recentes".
> 3. **PADRONIZAÇÃO:** um só cartão (raio, borda, sombra, padding); espaçamento de 16–24 px; botões e chips num só padrão; as telas que herdam os tokens (abas Documentos e Pendências, `/casos/todos`, Administração > Qualidade e custos) sem cor velha e sem componente quebrado; o login intacto.
>
> E também: o selo de origem é honesto? O % do Kit conta só o que tem conteúdo? A fila agrupada preserva os totais?
>
> Suba `next build` e `next start` e use o Playwright logado (credenciais só por variável de ambiente). Telas: `/casos` e `/casos/5469db1d-4862-4d16-9041-8bcd872d1505`, em 1440 e 390, nos dois temas. Devolva os achados como ALTO, MÉDIO ou BAIXO, com arquivo:linha, tela, tema, número medido e captura, e o veredito "pode fazer merge" ou "corrigir X antes".
