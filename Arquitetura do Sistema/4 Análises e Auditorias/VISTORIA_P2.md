# VISTORIA P2 — portal por papel, medida em produção

Medida em 2026-11-04 contra https://tratamento-dados-financeiros.vercel.app (mesmo Supabase do PR), com dado sintético autorizado pelo dono. Script reprodutível: `Verificação/vistoria-por-papel.mts` (variáveis `P2_USUARIOS`, `SUPABASE_URL`, `P2_SAIDA`; `P2_ENVIAR=1` para o envio; `P2_SO=matriz` refaz só a matriz). Capturas e `resultado.json` bruto: pasta do scratchpad da sessão (`.../scratchpad/p2/`, 146 PNG, deviceScaleFactor 1) — fora do repositório, de propósito. Nenhuma senha foi gravada em arquivo do repositório nem aparece em captura.

## 1. Envio válido ponta a ponta (Sócio de teste, pelo navegador)

Executado uma vez, pelo navegador, com o mesmo roteiro que está no script (o script só repete o envio com `P2_ENVIAR=1`; esta rodada final dele não repetiu o envio, para não duplicar documento).

| Item | Medido |
|---|---|
| Passos | login → `/casos/novo` (nome "S117 P2 sintetico") → redireciona para `/casos/<id>/adicionar` → seleciona `01_BP_...pdf` e `07_DRE_...pdf` → "Enviar 2 arquivos" |
| Resposta da tela | "2 arquivo(s) enviado(s) para o mandato", aviso "cerca de 1 minutos" (plural errado, defeito D8); 0 erros de console |
| Token / n8n | o portal assinou o token e o n8n aceitou: execução n8n `9393`, lote `0950b8eb…` |
| Lote | aberto 18:08:52, **fechado 18:09:28 UTC: 36 s** |
| Documentos | 2 de 2 planejados (BALANCO e DRE, status `em_validacao`, fonte `nome_arquivo`, confiança 0,9); 0 com falha; 0 sem medição; 0 fatiados |
| Linhas / contas | 253 linhas extraídas; 127 contas nos documentos, 127 extraídas; **cobertura 1** |
| Custo | US$ 0,0098 medido (estimado 0,01); tokens entrada 18.452, saída 6.293, cache 7.962 |
| Pendências geradas | 10 (8 abertas, 2 resolvidas pelo sistema): 6 itens do Kit Básico ausentes (bloqueantes) + 2 de perímetro (papel no grupo, forma de controle) |
| Equipe | pela tela `/administracao/equipe` (existe): Analista e Leitura alocados no mandato com o seletor "Alocar em…"; ambos passaram a ver exatamente 1 mandato |

## 2. Matriz papel × tela

**168 células** medidas (132 desktop 1280×800, 36 celular 390×844): 42 por perfil × 4 perfis (anônimo, Sócio, Analista, Leitura). 29 rotas distintas no desktop; as rotas de `portal/src/app` que não são tela (`export`, `original`, `transcricao`) foram medidas só por status, sem seguir o redirect. **NÃO EXECUTADO:** `POST /api/intake` (escreveria no n8n; o equivalente seguro, `GET /api/intake/destino`, foi medido), `/api/intake/status`, `/auth/confirmar` com código válido, `/login/nova-senha` com link de recuperação válido, e as telas de documento por papel além do documento-exemplo. Tempo de carga desktop: mediana 1,8 s, máximo 7,6 s. Erros de console de usuário autenticado: 0; os únicos são os 401 esperados do anônimo em `/api/*`.

Cada célula: status HTTP → destino final quando houve redirect. `C` = `/casos/<id>`. Mandato A = o sintético (alocado a Analista e Leitura); Mandato B = outro mandato, ao qual Analista e Leitura NÃO estão alocados.

| Rota | Anônimo | Sócio | Analista | Leitura |
|---|---|---|---|---|
| `/` | 200→/login | 200→/casos | 200→/casos | 200→/casos |
| `/casos` | 200→/login | 200 | 200 | 200 |
| `/casos/todos` | 200→/login | 200 | 200 | 200 |
| `/casos/novo` | 200→/login | 200 | 200 | 200 |
| `/autonomia` | 200→/login | 200→/administracao | 200→/administracao | 200→/administracao |
| `/administracao` | 200→/login | 200 | 200 | 200 |
| `/administracao/custos` | 200→/login | 200 | 200 | 200 |
| `/administracao/equipe` | 200→/login | 200 | 200 | 200 |
| `/login` | 200 | 200 | 200 | 200 |
| `/login/recuperar` | 200 | 200 | 200 | 200 |
| `/login/nova-senha` | 200→/login | 200 | 200 | 200 |
| `/auth/confirmar` | 200→/login/recuperar | 200→/login/recuperar | 200→/login/recuperar | 200→/login/recuperar |
| `/api/busca?q=Vertentes` | 401 | 200 | 200 | 200 |
| `/api/intake/destino?apenas=agora` | 401 | 200 | 200 | 200 |
| `C` | 200→/login / 200→/login | 200 / 200 | 200 / 200 | 200 / 200 |
| `C/adicionar` | 200→/login | 200 | 200 | 200 |
| `C/apresentacao` | 200→/login | 200→C/entregaveis | 200→C/entregaveis | 200→C/entregaveis |
| `C/documentos` | 200→/login / 200→/login | 200 / 200 | 200 / 200 | 200 / 200 |
| `C/entregaveis` | 200→/login | 200 | 200 | 200 |
| `C/historico` | 200→/login | 200 | 200 | 200 |
| `C/modelagem` | 200→/login | 200 | 200 | 200 |
| `C/pendencias` | 200→/login / 200→/login | 200 / 200 | 200 / 200 | 200 / 200 |
| `C/perguntas` | 200→/login | 200 | 200 | 200 |
| `C/perimetro` | 200→/login | 200 | 200 | 200 |
| `C/revisao` | 200→/login | 200→C/pendencias | 200→C/pendencias | 200→C/pendencias |
| `C/documentos/{ID}` | 200→/login | 200 | 200 | 200 |
| `C/export` | 307 / 307 | 409 / 409 | 409 / 404 | 409 / 404 |
| `C/documentos/{ID}/original` | 307 | 302 | 302 | 302 |
| `C/documentos/{ID}/transcricao` | 307 | 200 | 200 | 200 |

Nas linhas `C…` repetidas, a primeira ocorrência é o mandato A e a segunda o mandato B. Para Analista e Leitura, o mandato B responde **200 com o texto "Mandato não encontrado"** (sem vazar nada; ver D5); para o Sócio abre normalmente. O `export` completo devolve 409 a todos (6 pendências bloqueantes: recusa correta); no mandato B, 404 a Analista/Leitura.

### O que cada papel vê e faz (medido nas telas do mandato A)

| Tela | Sócio | Analista | Leitura |
|---|---|---|---|
| `/casos/todos` | 78 mandatos; "Novo mandato" | 1 mandato; "Novo mandato" | 1 mandato; sem "Novo mandato" |
| `/casos/novo` | formulário | formulário | só a faixa "Seu papel é Leitura…" + "Voltar aos mandatos" |
| `/administracao`, `/custos`, `/equipe`, `/autonomia` | abre (Equipe: Salvar, ✕, Alocar) | "Esta área é dos Sócios" | "Esta área é dos Sócios" |
| `C/adicionar` | formulário de envio | formulário de envio | só "Voltar à Visão geral" + motivo |
| `C/pendencias` | 3 botões de decisão | 3 botões de decisão | lista sem botão algum |
| `C/modelagem`, `C/entregaveis` | Salvar parâmetros, Ativar, Salvar capítulo | idem | os mesmos botões, mas dentro de `fieldset disabled` (clique expira: inerte) |
| `C` (visão geral) | Adicionar arquivos, Ver pendências | idem | só Ver pendências |

Celular (390×844): 9 telas × 4 perfis, 0 erro de console. **`/casos/<id>/modelagem` estoura a largura nos três papéis (página de 421 px num viewport de 390)** — D2. Em captura de página inteira a barra inferior fixa cobre o conteúdo; é artefato da captura, não foi contado como defeito.

## 3. Escalada por API (JWT de cada papel)

60 tentativas; passaram 9, todas as passagens são as que o desenho de `0216` prevê (Analista alocado escreve; qualquer papel alocado lê). **Nenhuma escrita passou indevidamente; nenhum achado ALTO.** Mandatos visíveis: Sócio 78, Analista 1, Leitura 1, anônimo erro 42501 (sem permissão na tabela). O que passou e mudava dado foi desfeito: caso de teste apagado (0 sobras), pendência devolvida de `reenviada_ao_cliente` para `aberta` (8 abertas, 2 resolvidas, como antes), 0 sondas restantes no bucket, dial `completude_portao1` intacto (N2, `atualizado_em` de 16/07).

| Papel | Tentativa | Esperado | Obtido |
|---|---|---|---|
| analista | ler `caso` (todos) | só os alocados (1) | 1 de 78 mandatos visíveis |
| analista | ler `pendencia`/`documento` do mandato NÃO alocado | 0 linhas | pendencia: 0 linhas visíveis; documento: 0 linhas visíveis |
| analista | ler `estagio_autonomia`, `membro`, `alocacao`, `evento_auditoria`, `golden_criterio`, `lote_execucao` | ver nota | estagio_autonomia: BARRADO (?: ); membro: BARRADO (?: ); alocacao: BARRADO (?: ); evento_auditoria: 20 linhas visíveis; golden_criterio: BARRADO (?: ); lote_execucao: 1 linhas visíveis |
| analista | fn_mudar_dial(completude_portao1, N2 = nível atual) | barrado | BARRADO (42501: Mudar o dial de autonomia é reservado a Sócio (seu papel: analista)) |
| analista | UPDATE direto em `estagio_autonomia` (mesmo nível) | barrado | BARRADO (42501: Mudar o dial de autonomia é reservado a Sócio (seu papel: analista)) |
| analista | UPDATE em `estagio_autonomia` com filtro que não casa nada (sonda de política) | barrado | BARRADO (0 linhas, sem erro) |
| analista | INSERT em `caso` (novo mandato) | passa ou barra conforme o desenho (ver nota) | PASSOU (1 linha, desfeito) |
| analista | UPDATE em `caso` do mandato alocado (mesmo nome) | passa (escreve no alocado) | PASSOU (1 linha, valor idêntico) |
| analista | UPDATE direto em `pendencia` do mandato alocado (mesmo estado) | passa | PASSOU (1 linha, valor idêntico) |
| analista | UPDATE direto em `documento` do mandato alocado (status = o atual) | passa | PASSOU (2 linhas, valor idêntico) |
| analista | fn_decidir_pendencia(contatar_cliente) numa pendência real | passa | PASSOU (estado aberta -> reenviada_ao_cliente; restaurado) |
| analista | fn_definir_papel(si mesmo, mesmo papel) | barrado | BARRADO (42501: Gerir a equipe é reservado a Sócio (seu papel: analista)) |
| analista | fn_alocar(mandato NÃO alocado, si mesmo) | barrado | BARRADO (42501: Alocar na equipe do mandato é reservado a Sócio (seu papel: analista)) |
| analista | fn_desalocar(mandato NÃO alocado, si mesmo; sem alocação a perder) | barrado | BARRADO (42501: Retirar da equipe do mandato é reservado a Sócio (seu papel: analista)) |
| analista | fn_eh_socio() | false | false |
| analista | storage: subir objeto em `documentos/<mandato alocado>/` | passa | PASSOU (objeto removido pelo Sócio) |
| analista | storage: subir objeto em `documentos/<mandato NÃO alocado>/` | barrado | BARRADO (403: new row violates row-level security policy) |
| analista | storage: apagar a sonda do mandato alocado | passa (ou barra) | PASSOU (objeto sumiu) |
| analista | storage: assinar/ler objeto de mandato NÃO alocado | barrado | BARRADO (404: Object not found) |
| analista | storage: assinar/ler objeto do mandato alocado | passa | PASSOU (URL assinada emitida) |
| leitura | ler `caso` (todos) | só os alocados (1) | 1 de 78 mandatos visíveis |
| leitura | ler `pendencia`/`documento` do mandato NÃO alocado | 0 linhas | pendencia: 0 linhas visíveis; documento: 0 linhas visíveis |
| leitura | ler `estagio_autonomia`, `membro`, `alocacao`, `evento_auditoria`, `golden_criterio`, `lote_execucao` | ver nota | estagio_autonomia: BARRADO (?: ); membro: BARRADO (?: ); alocacao: BARRADO (?: ); evento_auditoria: 21 linhas visíveis; golden_criterio: BARRADO (?: ); lote_execucao: 1 linhas visíveis |
| leitura | fn_mudar_dial(completude_portao1, N2 = nível atual) | barrado | BARRADO (42501: Mudar o dial de autonomia é reservado a Sócio (seu papel: leitura)) |
| leitura | UPDATE direto em `estagio_autonomia` (mesmo nível) | barrado | BARRADO (42501: Mudar o dial de autonomia é reservado a Sócio (seu papel: leitura)) |
| leitura | UPDATE em `estagio_autonomia` com filtro que não casa nada (sonda de política) | barrado | BARRADO (0 linhas, sem erro) |
| leitura | INSERT em `caso` (novo mandato) | barrado | BARRADO (42501: new row violates row-level security policy for table "caso") |
| leitura | UPDATE em `caso` do mandato alocado (mesmo nome) | barrado | BARRADO (42501: new row violates row-level security policy for table "caso") |
| leitura | UPDATE direto em `pendencia` do mandato alocado (mesmo estado) | barrado | BARRADO (42501: new row violates row-level security policy for table "pendencia") |
| leitura | UPDATE direto em `documento` do mandato alocado (status = o atual) | barrado | BARRADO (42501: new row violates row-level security policy for table "documento") |
| leitura | fn_decidir_pendencia(contatar_cliente) numa pendência real | barrado | BARRADO (42501: new row violates row-level security policy for table "pendencia") |
| leitura | fn_definir_papel(si mesmo, mesmo papel) | barrado | BARRADO (42501: Gerir a equipe é reservado a Sócio (seu papel: leitura)) |
| leitura | fn_alocar(mandato NÃO alocado, si mesmo) | barrado | BARRADO (42501: Alocar na equipe do mandato é reservado a Sócio (seu papel: leitura)) |
| leitura | fn_desalocar(mandato NÃO alocado, si mesmo; sem alocação a perder) | barrado | BARRADO (42501: Retirar da equipe do mandato é reservado a Sócio (seu papel: leitura)) |
| leitura | fn_eh_socio() | false | false |
| leitura | storage: subir objeto em `documentos/<mandato alocado>/` | barrado | BARRADO (403: new row violates row-level security policy) |
| leitura | storage: subir objeto em `documentos/<mandato NÃO alocado>/` | barrado | BARRADO (403: new row violates row-level security policy) |
| leitura | storage: apagar a sonda do mandato alocado | barrado | BARRADO (0 objetos removidos, sem erro) |
| leitura | storage: assinar/ler objeto de mandato NÃO alocado | barrado | BARRADO (404: Object not found) |
| leitura | storage: assinar/ler objeto do mandato alocado | passa | PASSOU (URL assinada emitida) |
| anonimo | ler `caso` (todos) | 0 | BARRADO (42501: permission denied for table caso) |
| anonimo | ler `pendencia`/`documento` do mandato NÃO alocado | 0 linhas | pendencia: BARRADO (?: ); documento: BARRADO (?: ) |
| anonimo | ler `estagio_autonomia`, `membro`, `alocacao`, `evento_auditoria`, `golden_criterio`, `lote_execucao` | 0 / barrado | estagio_autonomia: BARRADO (?: ); membro: BARRADO (?: ); alocacao: BARRADO (?: ); evento_auditoria: BARRADO (?: ); golden_criterio: BARRADO (?: ); lote_execucao: BARRADO (?: ) |
| anonimo | fn_mudar_dial(completude_portao1, N2 = nível atual) | barrado | BARRADO (42501: permission denied for function fn_mudar_dial) |
| anonimo | UPDATE direto em `estagio_autonomia` (mesmo nível) | barrado | BARRADO (42501: permission denied for table estagio_autonomia) |
| anonimo | UPDATE em `estagio_autonomia` com filtro que não casa nada (sonda de política) | barrado | BARRADO (42501: permission denied for table estagio_autonomia) |
| anonimo | INSERT em `caso` (novo mandato) | barrado | BARRADO (42501: permission denied for table caso) |
| anonimo | UPDATE em `caso` do mandato alocado (mesmo nome) | barrado | BARRADO (42501: permission denied for table caso) |
| anonimo | UPDATE direto em `pendencia` do mandato alocado (mesmo estado) | barrado | BARRADO (42501: permission denied for table pendencia) |
| anonimo | UPDATE direto em `documento` do mandato alocado (status = o atual) | barrado | BARRADO (42501: permission denied for table documento) |
| anonimo | fn_decidir_pendencia(contatar_cliente) numa pendência real | barrado | BARRADO (42501: permission denied for function fn_decidir_pendencia) |
| anonimo | fn_definir_papel(si mesmo, mesmo papel) | barrado | BARRADO (42501: permission denied for function fn_definir_papel) |
| anonimo | fn_alocar(mandato NÃO alocado, si mesmo) | barrado | BARRADO (42501: permission denied for function fn_alocar) |
| anonimo | fn_desalocar(mandato NÃO alocado, si mesmo; sem alocação a perder) | barrado | BARRADO (42501: permission denied for function fn_desalocar) |
| anonimo | fn_eh_socio() | barrado/false | BARRADO (42501: permission denied for function fn_eh_socio) |
| anonimo | storage: subir objeto em `documentos/<mandato alocado>/` | barrado | BARRADO (403: new row violates row-level security policy) |
| anonimo | storage: subir objeto em `documentos/<mandato NÃO alocado>/` | barrado | BARRADO (403: new row violates row-level security policy) |
| anonimo | storage: apagar a sonda do mandato alocado | barrado | BARRADO (0 objetos removidos, sem erro) |
| anonimo | storage: assinar/ler objeto de mandato NÃO alocado | barrado | BARRADO (404: Object not found) |
| anonimo | storage: assinar/ler objeto do mandato alocado | barrado | BARRADO (404: Object not found) |

`BARRADO (0 linhas, sem erro)` é a RLS filtrando em silêncio: é o comportamento certo para UPDATE, mas só é seguro porque a tela esconde ou desabilita o botão. **NÃO EXECUTADO:** troca real de nível do dial por Analista/Leitura (só a reafirmação do nível atual, para não alterar produção), `fn_definir_papel` para papel diferente do próprio (a tentativa usou o mesmo papel, que já fica barrada pelo gate de Sócio), e leitura do CONTEÚDO de `evento_auditoria` (Analista e Leitura leem 20 e 21 linhas; a policy restringe ao mandato do evento, mas as linhas não foram abertas para conferir).

## 4. Defeitos

Nenhum de severidade ALTA. Nenhum código do portal foi alterado.

### D1 — MÉDIA
- **Papel:** Sócio
- **Tela:** `/casos/todos`
- **Passo a passo:** Entrar como Sócio (78 mandatos) → abrir Mandatos em 1280×800.
- **Esperado:** Sem rolagem horizontal.
- **Obtido:** A página tem 1419 px de largura (captura 1419×7369): estoura 139 px. Com Analista/Leitura (1 mandato) não ocorre, então o gatilho é a lista longa.
- **Captura:** `socio-desk-_casos_todos.png`

### D2 — MÉDIA
- **Papel:** Sócio, Analista, Leitura
- **Tela:** `/casos/<id>/modelagem` no celular
- **Passo a passo:** Abrir o mandato → Modelagem em 390×844.
- **Esperado:** Largura 390.
- **Obtido:** Página de 421 px (31 px a mais) nos três papéis; o conteúdo extra obriga rolagem lateral. As outras 8 telas de celular medidas cabem.
- **Captura:** `socio-mob-_casos_ID_modelagem.png`, `analista-mob-…`, `leitura-mob-…`

### D3 — MÉDIA
- **Papel:** Analista
- **Tela:** Storage `documentos/<mandato alocado>/`
- **Passo a passo:** Com o JWT de Analista, `storage.from('documentos').remove([<objeto do mandato alocado>])`.
- **Esperado:** Decisão consciente do dono: original do cliente é irreversível.
- **Obtido:** O objeto some (passou; a sonda foi recriada pelo Sócio). É o desenho da `0216` (quatro operações por `<caso_id>/` para quem escreve no mandato), mas não há trilha nem lixeira. Registrado como decisão pendente, não como falha de RLS.
- **Captura:** sem captura (API)

### D4 — BAIXA
- **Papel:** Analista, Leitura
- **Tela:** `/casos/<idB>`, `/documentos`, `/pendencias` de mandato alheio
- **Passo a passo:** Abrir o endereço de um mandato ao qual não está alocado.
- **Esperado:** 404.
- **Obtido:** HTTP 200 com "Mandato não encontrado" (soft 404). Não vaza dado; o ponto é só o status, que engana monitoramento e cache.
- **Captura:** `analista-desk-_casos_ID.png` (2ª ocorrência)

### D5 — BAIXA
- **Papel:** Leitura
- **Tela:** `/casos/<id>/modelagem`, `/entregaveis`
- **Passo a passo:** Abrir como Leitura.
- **Esperado:** Controles de escrita ausentes ou com o motivo ao lado de cada bloco.
- **Obtido:** Dezenas de "Ativar" e 12 "Salvar capítulo" aparecem inertes (`fieldset disabled`). Em `modelagem` há a nota "Somente consulta"; em `entregaveis` a nota não foi localizada nas capturas. Não grava nada (clique expira).
- **Captura:** `leitura-desk-_casos_ID_modelagem.png`

### D6 — BAIXA
- **Papel:** todos logados
- **Tela:** `/login`, `/login/nova-senha`
- **Passo a passo:** Com sessão ativa, abrir `/login`.
- **Esperado:** Redirecionar a `/casos`.
- **Obtido:** Mostra o formulário de login de novo.
- **Captura:** `socio-desk-_login.png`

### D7 — BAIXA
- **Papel:** Sócio
- **Tela:** `/`, `/casos`, `/autonomia`, `/administracao/custos`
- **Passo a passo:** Primeiro acesso após o login.
- **Esperado:** Carga rápida.
- **Obtido:** Primeira carga de 5,9 a 7,6 s (máximo da vistoria); mediana geral 1,8 s. Provável partida a frio da Vercel; não reproduzido de forma estável.
- **Captura:** `resultado.json`, campo `ms`

### D8 — BAIXA
- **Papel:** Sócio
- **Tela:** `C/adicionar` após o envio
- **Passo a passo:** Enviar 2 arquivos.
- **Esperado:** "cerca de 1 minuto".
- **Obtido:** "cerca de 1 minutos" (concordância). O lote real levou 36 s.
- **Captura:** `envio-3-enviado.png`

### Por desenho, não defeito (registrado para o leitor não procurar)
- Analista abre mandato (`criarMandato` liberado a Sócio e Analista) — INSERT em `caso` passou e foi desfeito.
- `/autonomia` redireciona para `/administracao` para todos; `/apresentacao` para `/entregaveis`; `/revisao` para `/pendencias`.
- `export` completo recusa com 409 enquanto há pendência bloqueante.
- `anônimo` em `/api/busca` e `/api/intake/destino`: 401 (aparece como erro de console, esperado).
- Chave anon obtida do cabeçalho `apikey` do próprio portal (não está no HTML do login nem em `.env.example`).

---

## 5. Fase 2 — exploração por persona (04/11/2026, produção, mandato "S117 P2 sintetico")

Três agentes, cada um dirigindo o portal com Playwright como uma pessoa, sem ler o código para saber onde clicar. Cada ação foi gravada com captura (fora do repositório, no scratchpad da sessão). As três rodaram ao mesmo tempo no mesmo mandato, então contagens mudaram durante o teste (documentos 3→5, pendências 7→10→9) — isso é concorrência do teste, não achado.

| Persona | Papel | Objetivos completos | Envios | O que ficou NÃO EXECUTADO |
|---|---|---|---|---|
| **Marina**, Sócia, no celular, com pressa | socio | 3 de 6 (status, Excel, discrição); confiança parcial; equipe com atrito; **aprovar impossível** (5 pendências que só o cliente resolve) | — | sino, abas Perguntas e Grupo econômico, Fechar/Excluir |
| **Lucas**, Analista júnior, 1ª semana | analista | achar mandato, ler pendências, base de dados: ok; Excel do Modelo bloqueado (409 com mensagem clara); bloqueios de Sócio e isolamento por URL ok | DFC válido (29 linhas, 99%, 20 s); `.txt` de 57 bytes **aceito**; PDF corrompido de 14 bytes → falha com erro cru | "Marcar como enviada", premissas, Gravar papel/forma |
| **Paulo**, Leitura, cético | leitura | 5 de 5; tela × Excel batem em 5 números (Receita 106.580, Prejuízo −17.903, Caixa 380, Empréstimos 27.718, PL 6.899, recalculados no LibreOffice); depois de Sair, nada em cache | — | PDF por "Ver original" (headless não renderiza); histórico real do navegador |

A primeira versão do Paulo (sondagem de URLs adivinhadas e da API à mão) foi **interrompida pelas salvaguardas do modelo** e refeita só com o escopo de usabilidade. A cobertura de acesso por papel é a da seção 3 (60 tentativas por API). Sondagem livre de endpoints fica **NÃO EXECUTADA**: o caminho é `/security-review` sobre o código do portal ou um pentest autorizado.

**Estado deixado em produção, no mandato de teste:** "Faturamento Intragrupo" e "Faturamento em 24 meses" ficaram com a etiqueta "Contatar o Cliente" (a tela não volta a "sem etiqueta"); documentos `anotacoes.txt` (confirmado "sem tipo") e `relatorio_vazio.pdf` (falha de extração) continuam no mandato; parâmetros da Modelagem salvos (Vertentes Metalurgica, 2026–2030). Tudo o mais foi desfeito. Nenhum mandato real foi tocado.

## 6. Diagnóstico consolidado (fase 1 + personas), por tema e prioridade

Ids de origem: D = fase 1; S = Marina; A = Lucas; L = Paulo.

### ALTA — corrigir antes de qualquer cliente
1. **Decisão de um toque, sem freio** (S1, A3, A2, S3). "Prosseguir sem resolução" aceita pendência BLOQUEANTE sem confirmação e sem motivo; "Confirmar" aceita documento **sem tipo** e o marca "100% · Humano"; "✕" retira membro da equipe sem confirmação. O estado anterior nem sempre volta pela tela.
2. **Entrada inválida vira fato** (A1, A6). Um `.txt` de 57 bytes entrou como documento, a linha "Saldo de caixa: 1000" foi **auto-aceita** e chegou ao Excel como ACEITO, sem entidade nem período (283 linhas aceitas, 0 pendentes no Resumo). A tela de envio diz "PDF, imagens". O PDF corrompido falha com o erro cru do provedor em inglês, sem ação de reenviar/remover, e o filtro "Arquivos ilegíveis" mostra 0.
3. **Proveniência que não fecha** (L3, L4, L5, L7, S5, A9). Coluna PÁGINA "—" em 197/197 linhas do Balanço (DRE e Fluxo têm página); totais do Excel (Receita Líquida, Lucro Líquido, subtotais de Empréstimos) sem nota de origem; nota do PL diz "soma = −32.252 contra informado 6.899" (subtotais somados com as contas) enquanto a tela mostra 100% ACEITO; "Todas as linhas foram aceitas" quando o aceite é automático e nenhuma classe contábil foi decidida por humano; na Modelagem, "101.300 ÷ 106.580" exibido como 88% (a divisão dá 95%). É o núcleo da regra 1: o número não diz de onde veio.
4. **Modo discrição vaza** (L1, L2, S10). O atributo `title` do parágrafo borrado traz o texto inteiro (aparece ao passar o mouse); o botão do avatar mostra o e-mail; nome do cliente, entidade, arquivos, contrapartes nos rótulos, Ctrl+K e sino ficam legíveis.
5. **Início estoura no celular** (S2). A coluna "Precisa de você" mede 643 px num viewport de 390; a barra inferior fica parcialmente fora e o toque em "Mais" é interceptado (confirmar em aparelho real).

### MÉDIA
6. **Jargão de engenharia nas telas e no Excel** (S6, A4, L6, S7, L5): "regra 1 do CLAUDE.md", `fn_entidade_definir_forma_de_controle`, `fn_perimetro_situacao`, "fatia 1.5", "dial N2, limiar 0.95", caminho de arquivo do repositório e o erro do provedor de IA na aba Resumo.
7. **Excel não diz o estado do mandato** (S7): sai sem dizer que está em triagem, com 5 bloqueantes e o Modelo bloqueado.
8. **Pendência não leva à solução** (A5, S4): "Papel no Grupo" e "Forma de Controle" oferecem "Contatar o Cliente", mas a solução está na aba Grupo econômico; Equipe só se acha por tentativa; "Alocar alguém…" só aparece depois de retirar alguém.
9. **Layout** (D1, D2): rolagem horizontal em `/casos/todos` com 78 mandatos; Modelagem com 421 px no celular.
10. **Decisão do dono** (D3): o Analista apaga o original do cliente no bucket, sem trilha — é o desenho da 0216.
11. **Contagens que não se reconciliam** (L8, S8): "156 de 156 linhas" no Início × 282/283 no mandato; Fluxo de Caixa ausente no Início e recebido no mandato.

### BAIXA
12. Mensagens e detalhes: "cerca de 1 minutos" (D8, A7 — o real foi ~20 s); mandato alheio com HTTP 200 "não encontrado" (D4, A12); `/login` não redireciona quem já está logado (D6); depois do login vai a /casos e não ao link (L10); `<title>` igual em todas as páginas (L10); "classificar" habilitado para Leitura sem efeito (L9); controles inertes para Leitura (D5); esqueleto de ~5 s no Início (D7, S12); "Quarta-Feira, 04 De Novembro" com maiúsculas; "Excluir" colado em "Fechar"; códigos crus (FAT_INTRAGRUPO, CONTRATO_SOCIAL) no Início e no Histórico (A8); dica do 409 cita "Exportar dados" e o botão chama "Baixar base de dados" (A10); "Ver original" expira em 2 min (L12); sem busca de conta no Balanço (L11); um chunk JS com 502 uma vez (S11).

### O que funcionou (medido)
Envio válido ponta a ponta em 36 s, US$ 0,0098; DFC extraído com 99% em 20 s e a pendência do Kit Básico se resolveu sozinha; isolamento por papel e por mandato (51/51 escritas indevidas barradas, Analista/Leitura veem 1 de 78 mandatos, dial e papéis com 42501); tela × Excel batem nos 5 números conferidos; nada em cache depois de Sair; 0 erro de console autenticado.

### Feedback das personas (baseado só no que aconteceu)
- **Marina:** "Vi rápido que não dá para aprovar e por quê, e baixei o Excel em três segundos. Mas o arquivo traz um erro técnico e não diz que o caso está travado, e num toque aceitei uma pendência sem ninguém me perguntar nada. No celular a tela inicial escapa pela direita, e eu não sei se os números fecham."
- **Lucas:** pendências na língua do sistema, os mesmos 3 botões para tudo, e dois arquivos errados entraram como se estivessem certos.
- **Paulo:** os números da tela batem com o Excel, mas não consigo achar a página de nenhum número do Balanço, os totais do Excel não dizem de onde vieram, e a discrição esconde o valor e deixa o nome do cliente.

**Para onde vai:** os itens 1–5 entram no lote 1 da P16 (antes de P17), junto com a F3 nos itens 2–3 (entrada inválida e proveniência são extração, não só tela). O item 10 é decisão do dono.
