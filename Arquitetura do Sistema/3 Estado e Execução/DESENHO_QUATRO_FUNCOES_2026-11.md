# Desenho técnico — quatro funções aprovadas pelo dono (sem código)

> **Decisões do dono (13/11/2026):**
> - Aceitas TODAS as recomendações (D1.1 a D4.6).
> - A Área do cliente (função 2) entra DEPOIS do portão de 18/12.
> - As migrations desta frente começam na **0300**, não na 0277. Os números abaixo já foram renumerados (0277–0283 → 0300–0306) e precisam ser reconferidos na hora de escrever.
> - A 0275 continua reservada para o aging.


**Data:** 13/11/2026 · **Base lida:** `main` em `ef92088` · **Escrito por:** agente de desenho, sem
editar o repositório.

**Numeração.** A migration mais nova no repositório é a `0276`. A `0275` está RESERVADA para a
correção do aging (ESTADO S127b) e não aparece aqui. Proponho `0300` a `0306`. **Os números têm de
ser reconferidos na hora de escrever** (`ls Supabase/migrations | tail`), porque três contas
escrevem migration em paralelo e a 0243 da P27 continua sem número final.

**Regra de leitura deste desenho.** Toda afirmação sobre "o que existe" tem arquivo:linha. Nada foi
medido em produção nesta rodada: onde um número importa, a fatia 0 de cada função manda medir.

---

## 0. O achado que muda o tamanho das quatro funções

| Função | Quanto já existe | O que de fato falta |
|---|---|---|
| 1. Envio fecha o Kit e a pendência | **~70%.** `fn_recomputar_completude` já abre e resolve `item_faltante` sozinha quando chega documento que serve como o tipo, e abre `item_sem_conteudo` quando ele não rende linha | O estado **conferido**, a janela "aguardando extração", a chave estável da pendência, o rastro de qual documento fechou, e o sinal positivo de que a conferência rodou |
| 2. Link do cliente | **~20%.** Token HMAC por caso (0222), Vault, tetos de envio | Identidade sem login, revogação, quota, superfície externa isolada, quarentena |
| 3. Número novo × reapresentado | **~50%.** `fn_conflitos_do_caso` (0159) já acha dois documentos discordando na mesma conta × entidade × exercício; isso já pega a reapresentação com mudança | Classificar **novo / reapresentado igual / reapresentado com mudança / sem anterior**, e o vínculo "este documento substitui aquele" |
| 4. Pendência vira achado | **~10%.** `pendencia`, `decisao`, `documento_fato`, export | Tabela de achado, ciclo de vida, relatório |

**Dois fatos do modelo que o pedido supõe diferentes:**
1. **`documento_versao` NÃO é "versão anterior do documento" no sentido Daloopa.** Versão nova só
   nasce quando chega o MESMO arquivo (mesmo `hash`) de novo: é reextração
   (`0230_…sql:186-195`; o book diz "Reextração é substituição", `portal/src/lib/export.ts:3244`).
   Um balanço refeito pelo cliente é um **documento novo**. Comparar `documento_versao` entre si
   compararia duas leituras da IA do mesmo papel — ruído de extração, não reapresentação.
2. **O Kit Básico é por caso × tipo, não por entidade.** `fn_recomputar_completude` passo 1
   pergunta "existe algum documento do caso que sirva como o tipo"
   (`0188_…sql:1727`, corpo em `Supabase/schema.sql:10892-11084`). Num grupo de 8 empresas, um
   BALANCO da empresa A fecha o item BALANCO do grupo inteiro. As linhas exigidas é que descem à
   entidade (0119).

---

## 1. O envio fecha sozinho o item do Kit Básico e a pendência

### (a) O problema em uma linha
A chegada já fecha o item, mas a tela não distingue recebido, extraído e conferido, e nada prova que
a conferência rodou.

### (b) O que já existe e serve

| O quê | Onde | Para que serve aqui |
|---|---|---|
| `fn_recomputar_completude(caso)` | `Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql:1727` | Passo 1 abre/resolve `item_faltante` (linhas 1766-1779); passo 2 abre `item_sem_conteudo`; passo 3 grava `presente`/`recebido_nao_valido` no checklist |
| `fn_documento_serve_como(doc, tipo)` | `0157_o_combinado_que_travava_o_kit_basico.sql:197` | A regra única de "este documento atende o item" |
| `fn_algum_documento_serve_como(uuid[], tipo)` | `0276_…sql` (aplicada em 12/11) | A mesma pergunta em lote |
| `checklist_item_status` | `Supabase/schema.sql:18984` | Uma linha por documento recebido, inserida no registro (`0230_…sql:234`) com `status='presente'` ANTES da extração |
| `fn_versao_extracao_concluida(versao)` | `0233_…sql:122` | Distingue "ainda não extraiu" de "extraiu e não achou" |
| `fn_versao_com_extracao(doc)` | `Supabase/schema.sql:18359` | A versão vigente |
| `campo_extraido.status_aceite`, `aceito_por` | `Supabase/schema.sql:17818` | Aceite humano (`fn_aceitar_extracao`, `0036_…sql:234`) × auto-aceite do sistema (`aceito_por = 'sistema:auto_aceite …'`, `0029_…sql:273`) |
| `itensDoKitBasicoAtendidos` | `portal/src/lib/kit-basico.ts:54` | A tela pergunta ao banco, nunca rederiva |
| Grade do Kit | `portal/src/app/casos/[id]/documentos/(lista)/page.tsx:231` e `:406` | Hoje só "✓ recebido" ou "sem conteúdo" |
| Chamada pelo n8n | `N8N/build-workflow.mjs:3259`, `N8N/lib/completude.mjs:39` | Quem dispara a conferência no fim do lote |
| Suíte | `portal/scripts/verificar-kit-basico.mts` (portão em `.github/workflows/suites.yml:454`) | Tela concorda com o banco |

### (c) A mudança mínima, pela escada
1. **Precisa existir?** Sim: o dono aprovou, e a fila de telas já pede "Kit com % de prontidão
   (recebido ≠ conferido)" (ESTADO S129, fila item 2).
2. **Já existe?** A transição de chegada, sim. Não se reescreve. O que falta é a **leitura** do
   estado com cinco degraus, e ela tem de sair de UM lugar.
3. **Postgres resolve.** Uma função `stable` que DERIVA o estado na leitura, em vez de uma coluna de
   status que envelhece.

**Migration `0300` (proposta):**
- **Função nova `fn_kit_do_caso(p_caso uuid)`**, `stable`, `security invoker` (a RLS da 0216 vale
  sozinha). Uma linha por item do Kit (tipo obrigatório): `tipo`, `estado`, `documentos uuid[]`,
  `motivo` (texto do porquê, inclusive do efeito), `conferido_por`, `conferido_em`. É a única
  resposta para a tela interna, para o export e, depois, para o link do cliente (Função 2).
- **Chave estável em `item_faltante`.** Hoje a pendência casa por TEXTO de `descricao`
  (`0188_…sql:1766-1779`). Passa a casar por `motivo = 'completude:item_faltante:<TIPO>'`, como já
  fazem `item_sem_conteudo` e `linha_exigida_ausente`. Backfill das abertas em produção, com
  contagem gravada em evento (zero também).
  - **Cuidado medido no código:** `fn_decidir_pendencia` grava `motivo = coalesce(p_motivo, motivo)`
    (`0109_…sql:194`, mantido em `0227_…sql:81`). Se a tela um dia mandar motivo humano, a chave some e a
    completude reabre a pendência. A 0300 tem de guardar a chave em coluna própria
    (`pendencia.chave_motor text`) ou a fn_decidir_pendencia tem de deixar de sobrescrever `motivo`.
    Recomendo a coluna própria: não mexe em função com 8 chamadores.
- **Rastro do fechamento.** Coluna `pendencia.resolvida_por_documento_id uuid references documento
  on delete set null`. NÃO reaproveitar `pendencia.documento_id`: `fn_revisar_documento` e outras
  resolvem pendência por `documento_id`, e preenchê-lo daria a elas uma pendência que não é delas.
- **Sinal positivo (regra 7).** `fn_recomputar_completude` grava SEMPRE um `evento_auditoria`
  `completude_recomputada` com as contagens (abertas, resolvidas, sem mudança), inclusive tudo zero.
  Hoje ela só grava evento na troca de status do caso. `fn_kit_do_caso` devolve
  `conferencia_em` (último evento) e `documentos_depois_da_conferencia` (documentos com
  `criado_em` maior). Se o n8n morreu antes de chamar a conferência, a tela diz "o Kit não foi
  reconferido desde HH:MM; N documentos chegaram depois".
- **O que NÃO entra:** reemitir `fn_registrar_documento` ou `fn_registrar_campos_extraidos`. As duas
  são reemitidas por outras contas (bloqueio da P27 com a 0270, ESTADO S128). Gatilho em
  `documento` também não: a P27 põe o dela lá, com custo medido de 2,06 s por UPDATE.
- **Sonda:** requisitos `funcao fn_kit_do_caso`; `coluna pendencia.resolvida_por_documento_id`;
  `coluna pendencia.chave_motor`; `corpo fn_recomputar_completude` com o marcador
  `completude_recomputada`; `corpo fn_recomputar_completude` com `completude:item_faltante:`.
  Subir `instalacao_cobertura` para 0300 (e nunca rebaixar quando a 0275 entrar).

**n8n:** nada. A chamada `fn_recomputar_completude` continua a mesma; a assinatura não muda.

**Portal (dono do diretório: Claude Oria 2):**
- `lib/kit-basico.ts` passa a ler `fn_kit_do_caso` (UMA ida). `itensDoKitBasicoAtendidos` fica como
  queda para banco sem a 0300, como a 0276 já fez.
- Grade do Kit com os cinco estados e o percentual **por estado**, nunca um só "% pronto".
- Os TRÊS chamadores do Kit mudam juntos: `casos/[id]/page.tsx`, `documentos/(lista)/page.tsx`,
  `casos/[id]/export/route.ts:597`. Erro na leitura = "Kit não lido", nunca "faltante" (ALTO da
  S129, que já foi corrigido uma vez).

### (d) Estados e transições

Estado do **item do Kit** (derivado na leitura; nada gravado):

| Estado | Condição (banco) | Texto da tela |
|---|---|---|
| `faltante` | nenhum documento serve como o tipo | "Falta" |
| `aguardando_extracao` | serve, e nenhuma versão concluiu a extração (`fn_versao_extracao_concluida` falso, sem `extracao_falhou` aberta) | "Recebido — lendo" |
| `recebido_sem_linha` | serve, extração concluída ou falhada, zero linha na vigente (= `recebido_nao_valido`) | "Recebido, sem dado lido" + efeito |
| `extraido` | vigente com linha, e alguma linha sem aceite humano | "Lido, não conferido" |
| `conferido` | vigente com linha, toda linha com aceite HUMANO (ver D1.1) | "Conferido por X em D" |
| `dispensado` | `item_faltante` em `aceita_com_ressalva` e ainda `faltante` | "Seguiu sem o documento (ressalva)" |

| Transição | Quem decide |
|---|---|
| faltante → aguardando_extracao | **Banco** (`fn_documento_serve_como`), quando o **n8n** registra o documento |
| aguardando → recebido_sem_linha / extraido | **Banco**, depois que o **n8n** grava (ou falha) a extração |
| extraido → conferido | **Pessoa** (aceite no portal, `fn_aceitar_extracao`) |
| conferido → extraido | **Banco**: versão vigente nova chegou (reextração) e não tem aceite humano |
| qualquer → faltante | **Banco**: documento reclassificado ou apagado |
| faltante → dispensado | **Pessoa**: "Prosseguir sem resolução" na pendência |

Estado da **pendência `item_faltante`** (gravado, como hoje):
`aberta` → `reenviada_ao_cliente` (pessoa) → `resolvida` (banco, quando chega documento que serve).
`resolvida` quer dizer **chegou**, nunca "atendido". Quem garante conteúdo é `item_sem_conteudo`
(banco, abre em `recebido_sem_linha`, fecha quando aparece linha).

### (e) Riscos de defeito silencioso e como o desenho evita
1. **Recebido parecer conferido (regra 1).** A linha do checklist nasce `presente` no registro
   (`0230_…sql:234`), antes de existir linha. Se o n8n morre antes da conferência, ela fica
   `presente` para sempre. → O estado é DERIVADO de `campo_extraido` na leitura, não lido do
   checklist.
2. **Auto-aceite contado como conferência.** O sistema aceita sozinho linha com confiança ≥ 95%. →
   `conferido` exige `aceito_por` que não comece com `sistema:`.
3. **Conferência que não rodou parece Kit em dia (regra 7).** → evento `completude_recomputada`
   sempre, e a tela mostra documentos chegados depois dele.
4. **Chave por texto.** Mudar a frase da descrição duplica ou resolve pendência errada. → chave em
   coluna própria.
5. **Decisão humana sobrescrita.** O passo 1 resolve `item_faltante` em `aceita_com_ressalva` e
   `rejeitada` também (`estado <> 'resolvida'`). → D1.3; em qualquer opção, o evento guarda o
   estado anterior.
6. **Grupo com várias empresas.** Um BALANCO de uma empresa fecha o item do grupo. → Dito na tela
   ("atendido por 1 de 8 empresas") enquanto a D1.2 não muda a granularidade.

### (f) Invariantes (comportamento)
- I1.1 Documento cuja versão vigente tem zero linha nunca aparece como `extraido`, `conferido` nem
  conta como atendido no percentual.
- I1.2 Versão com todas as linhas aceitas SÓ pelo auto-aceite fica `extraido`, não `conferido`.
- I1.3 Chega documento que serve → `item_faltante` resolvida, com o id desse documento em
  `resolvida_por_documento_id`; o documento é reclassificado para outro tipo → a pendência reabre
  (nova, aberta).
- I1.4 Entre o registro e a gravação das linhas, o item é `aguardando_extracao`, nunca
  `recebido_sem_linha` nem `extraido`.
- I1.5 Rodar a conferência sem nada a mudar grava um evento com contagens zero; documento criado
  depois do último evento aparece em `documentos_depois_da_conferencia`.
- I1.6 A tela e `fn_kit_do_caso` dão o mesmo estado para cada item (estender
  `verificar-kit-basico.mts`).
- I1.7 Falha na leitura do Kit → a tela e o export dizem "não lido"; nenhum item vira `faltante`.
- I1.8 Mudar o texto de `descricao` de uma `item_faltante` aberta não cria outra nem a resolve.

Cada um medido não-vazio (regra 2): desligar a parte, contar quantos reprovam, religar.

### (g) Fatias, uma por commit
| # | Fatia | Pronto quando |
|---|---|---|
| 1.0 | **Medir antes (só leitura, produção).** Quantas linhas `presente` têm zero linha na vigente; quantas `item_faltante` resolvidas estavam decididas por pessoa antes; quantas abertas casariam pela chave nova | Três números no cabeçalho da 0300 |
| 1.1 | `0300`: `fn_kit_do_caso` + colunas + chave + evento + sonda + teste SQL | `run.sh` verde; I1.1–I1.5 e I1.8 medidos não-vazio, número no commit |
| 1.2 | Portal: os três chamadores leem `fn_kit_do_caso`, com queda | `verificar-kit-basico.mts` com I1.6 e I1.7 medidos; `tsc` e `eslint` limpos |
| 1.3 | Portal: grade com os cinco estados e "reconferido às HH:MM" | Vistoria no navegador num mandato com documento sem linha |
| 1.4 | Aplicar em produção (dono) | Sonda: 0 ausentes da 0300; evento `completude_recomputada` aparece no primeiro lote |

### (h) Decisões do dono
Estão na seção 6, D1.1 a D1.4.

---

## 2. Link para o cliente enviar documentos (Área do cliente)

### (a) O problema em uma linha
Hoje só quem tem login da Oria envia; o cliente manda por e-mail e o analista reenvia, e o portal não
tem superfície externa que mostre só o que falta.

### (b) O que já existe e serve

| O quê | Onde | Serve? |
|---|---|---|
| Token v2 `v2.<exp>.<usuario>.<caso>.<hmac>` | `0222_…sql:148-262`; assina em `portal/src/lib/assinatura-do-envio.ts` | **Em parte.** O HMAC e o segredo servem. Mas o v2 exige um `usuario` que escreva no caso (`fn_pode_escrever_caso_de`, `0222:216`): o cliente não tem. E vale 30 min (`assinatura-do-envio.ts:31`), sem revogação |
| Segredo no Vault `n8n_intake_segredo` | `0217_…sql` | Sim, o mesmo segredo assina |
| `emitirTokenDoEnvio` | `portal/src/lib/supabase/acesso.ts:69` | Não direto: lê `auth.getUser()` |
| `/api/intake/destino` | `portal/src/app/api/intake/destino/route.ts` | Modelo do fluxo (papel → token → URL do Form). Só para logado |
| RLS por caso | `0216_…sql:285-304` (`fn_pode_ler_caso`, `fn_pode_escrever_caso`) | Sim: o cliente NÃO entra nela (ver D2.1) |
| `anon` sem privilégio | `0218` + `Supabase/test/o_dial_e_o_anon.test.sql` | Sim: base da superfície externa |
| Tetos | `N8N/lib/custo.mjs:633` (15 MiB/arquivo), `portal/src/lib/limite-de-envio.ts`, suíte `portal/scripts/verificar-limite-de-envio.mts` | Sim, reaproveitar |
| Rotas públicas | `portal/src/lib/supabase/proxy.ts:55` (`rotaPublica`, de `lib/recuperar-senha`) | Sim: a página do link entra na lista |
| Rascunho de e-mail ao cliente | `portal/src/lib/email-ao-cliente.ts` | Modelo do que pode sair da casa (só texto da pergunta) |
| Kit do caso | Função 1, `fn_kit_do_caso` | **Pré-requisito**: o "o que falta" do cliente é o MESMO Kit |

**O portal não tem chave `service_role`** (busca em `portal/src` vazia). O desenho mantém isso.

### (c) A mudança mínima, pela escada
**Identidade (recomendação, D2.1):** link com token próprio, sem login. Login de cliente com papel
novo na 0216 obrigaria TODA policy de leitura a excluir o papel novo: `fn_pode_ler_caso` hoje
devolve verdadeiro para qualquer `membro` alocado, e todas as tabelas por caso da 0216 (a lista começa em `0216_…sql:644`) leem por ela ou pela forma de conjunto `fn_casos_legiveis`. Um esquecimento em
uma delas mostra número ao cliente, sem erro nenhum. O link não entra na RLS: ele só fala com
funções `security definer` que devolvem uma lista fechada de campos.

**Migration `0304` (proposta; depois de 0300–0303):**
- **Tabela `link_cliente`**: `id`, `caso_id` (FK, on delete cascade), `token_hash bytea` (SHA-256 do
  token; **o token nunca é gravado**), `criado_por uuid`, `criado_em`, `expira_em` (not null),
  `revogado_em`, `revogado_por`, `motivo_revogacao`, `teto_arquivos int`, `teto_bytes bigint`,
  `rotulo text` (para quem foi enviado, interno). `check (expira_em > criado_em)`.
  RLS ligada; SELECT para quem lê o caso; nenhuma policy de escrita; `revoke insert, update,
  delete, truncate` explícito do `authenticated` (o default privilege de produção concede ALL,
  ESTADO S128 "ACL de produção ≠ ACL local").
- **Tabela `envio_cliente`**: um registro por arquivo que o cliente tenta mandar: `link_id`,
  `caso_id`, `nome_original`, `bytes`, `tipo_mime`, `extensao`, `hash`, `estado`
  (`reservado` | `recebido` | `recusado` | `promovido` | `descartado`), `motivo_recusa`,
  `caminho_storage`, `documento_id` (quando promovido), datas, `promovido_por`.
- **Funções:**
  - `fn_link_cliente_emitir(caso, validade, rotulo)` → devolve o token UMA vez. `security definer`,
    só quem escreve no caso, evento `link_cliente_emitido`. O token é gerado no banco
    (`gen_random_bytes(32)`, 256 bits).
  - `fn_link_cliente_revogar(link, motivo)`. Fechar o mandato revoga todos (gatilho em
    `caso.fechado_em`, ou a pergunta "caso fechado" dentro de cada leitura — recomendo a pergunta:
    sem gatilho).
  - `fn_link_cliente_painel(token text)` → `security definer`, **EXECUTE para `anon`**. Devolve só:
    nome do mandato para exibição (ver D2.8), validade, e a lista do Kit em três estados para o
    cliente (`falta`, `recebido`, `recebido_ilegivel` conforme D2.4), com o nome do tipo em
    português e o "por que este documento importa". **Nada de** pendência, premissa, nota, valor,
    nome de arquivo de outro remetente, entidade interna, analista.
  - `fn_link_cliente_reservar(token, nome, bytes, mime)` → `anon`. Confere link ativo, mandato
    aberto, tipo e tamanho permitidos, quota do link; grava `envio_cliente` `reservado` e devolve o
    caminho de destino.
  - Toda leitura com token inválido, expirado ou revogado devolve a MESMA resposta
    (`{ valido: false }`) e grava evento interno com o motivo real (sem o token).
- **Storage (D2.2, recomendação "quarentena"):** bucket `envio_cliente`, privado, com
  `file_size_limit` e `allowed_mime_types` do próprio bucket. Policy de INSERT para `anon` só no
  caminho reservado e ainda não usado. Sem SELECT, UPDATE nem DELETE para `anon`.
- **Sonda:** `tabela`/`rls_ligada` para as duas tabelas; `sem_privilegio` de escrita do
  `authenticated` e de tudo do `anon` nelas; `privilegio` de EXECUTE do `anon` SÓ nas duas funções
  do link; `corpo fn_link_cliente_painel` com marcador da lista fechada; `comportamento`: token
  expirado devolve `valido = false`.

**Portal:**
- Rota pública `/enviar/[token]` (fora do `/casos`, entra em `rotaPublica`). Layout próprio, sem o
  casco interno, sem busca global, sem nada importado de `casos/**`. Cabeçalho
  `Referrer-Policy: no-referrer` e `Cache-Control: no-store` (o token está na URL).
- Rota `/api/cliente/reservar` pública; o 401 do `proxy.ts:47` para `/api/*` sem sessão precisa de
  exceção só para ela.
- Tela interna "Link do cliente": emitir, ver validade, revogar, ver o que chegou, **promover** para
  extração (usa o envio do analista que já existe, com o token v2 dele). E **"ver como o cliente
  vê"** (padrão DealRoom, já na fila aprovada) chamando a mesma `fn_link_cliente_painel`.
- Expirado/revogado/inexistente: uma página só — "Este link não está mais ativo. Peça um novo a
  quem o enviou." Sem nome do mandato, sem dizer qual dos três motivos.

**n8n:** na opção recomendada (quarentena), **nada**. O cliente não dispara IA. O analista promove e
o envio segue pelo caminho atual. Nas opções que mandam direto ao n8n, `fn_conferir_envio` ganha um
ramo `v3.<exp>.<link>.<caso>.<hmac>` e o nó "Conferir Envio" passa a aceitar `usuario_id` que não é
uuid — conferir antes se algum nó faz cast dele (`N8N/build-workflow.mjs:2952` só o repassa; o
resto não foi lido).

### (d) Estados e transições

**Link:** `ativo` → `expirado` (banco, relógio) · `ativo` → `revogado` (pessoa) · `ativo` →
`inativo_mandato_fechado` (banco, ao ler) · não há volta: renovar = emitir outro.

**Arquivo do cliente (`envio_cliente.estado`):**
| De → para | Quem |
|---|---|
| — → `reservado` | **Banco** (`fn_link_cliente_reservar`) |
| `reservado` → `recebido` | **Banco** (objeto existe no Storage com o tamanho declarado; conferido por pessoa na tela ou por varredura) |
| `reservado` → `recusado` | **Banco** (tipo, tamanho, quota, link inválido) |
| `recebido` → `promovido` | **Pessoa** (analista), que dispara o envio pelo **n8n** |
| `recebido` → `descartado` | **Pessoa**, com motivo |
| `reservado` sem objeto após 24 h → `recusado` (motivo `upload_nao_concluido`) | **Banco**, na próxima leitura |

**Item do Kit que o cliente vê:** `falta` → `recebido` quando um `envio_cliente` do tipo chega
(classificado pelo analista na promoção) ou quando `fn_kit_do_caso` sai de `faltante`.

### (e) Riscos de defeito silencioso e de segurança
1. **Vazamento por RLS esquecida.** → O cliente não tem papel; só funções com lista fechada. O teste
   planta pendência, premissa e valor e procura o texto e o número no payload.
2. **Custo de IA disparado por quem tem o link.** → Quarentena: o cliente nunca chama o n8n.
3. **Negação de serviço no n8n.** O Form é público e lê o arquivo inteiro antes de recusar
   (memória ~600 MB + 50× o arquivo, PLANO_MVP §1). → Bytes do cliente vão ao Storage, não ao n8n.
4. **Token vazado.** → Hash só; validade curta (D2.3); revogação; quota; evento por abertura e por
   arquivo com IP truncado e user-agent; `no-referrer`.
5. **Oráculo de existência.** → Mesma resposta para inexistente, expirado e revogado.
6. **Link de mandato fechado continua aceitando.** → A pergunta "mandato aberto" está em cada função.
7. **"Recebido" para o cliente lido como "aceito".** → O cliente vê "recebido", nunca
   "conferido" nem "completo"; o texto diz que a Oria ainda vai conferir.
8. **Upload que não terminou parece entregue (regra 7).** → `reservado` sem objeto vira `recusado`
   com motivo, visível ao analista.
9. **Força bruta.** 256 bits tornam inútil; mesmo assim, contar recusas por hora no evento e alertar
   acima de um teto. Limite: o banco não vê o IP real atrás do PostgREST; o teto por IP fica na rota
   do portal, e a Vercel não tem rate limit nativo neste plano (não medido).

### (f) Invariantes
- I2.1 Token expirado, revogado, inexistente e de mandato fechado: mesma resposta; nada gravado em
  `envio_cliente`; um evento interno com o motivo certo.
- I2.2 O payload do painel não contém nenhum `valor_num`, nenhuma `descricao` de pendência, nenhum
  texto de premissa ou nota do mandato (fixture com valores e textos plantados).
- I2.3 Link do mandato A não lê nem reserva no mandato B.
- I2.4 `anon` não lê nenhuma tabela e só executa as funções do link.
- I2.5 Arquivo acima do teto, de tipo fora da lista ou além da quota é recusado com o nome do
  arquivo e o motivo, antes de qualquer byte gravado.
- I2.6 Nenhuma coluna do banco contém o token em claro (busca do token em todas as colunas de texto
  depois de emitir).
- I2.7 Revogar faz a próxima chamada falhar, na mesma transação seguinte.
- I2.8 "Ver como o cliente vê" mostra exatamente o mesmo payload que a página externa.

### (g) Fatias
| # | Fatia | Pronto quando |
|---|---|---|
| 2.0 | **Decisões D2.1–D2.8** respondidas por escrito | Registradas no PLANO_MVP §4 |
| 2.1 | `0304`: tabelas, emitir/revogar, painel, sonda, teste | I2.1–I2.4, I2.6, I2.7 medidos não-vazio |
| 2.2 | `0305`: reservar + bucket + policy de Storage + quota | I2.5 medido; varredura do `reservado` sem objeto |
| 2.3 | Portal interno: emitir, revogar, ver como o cliente vê | I2.8 na suíte; revisão independente com a lente de segurança |
| 2.4 | Portal externo `/enviar/[token]` | Vistoria no navegador: link válido, expirado, revogado, mandato fechado, arquivo grande |
| 2.5 | Portal interno: quarentena e promoção | Arquivo promovido vira documento e muda o Kit; descartado não |
| 2.6 | Aplicar e piloto com um cliente (dono) | Sonda 0 ausentes; um envio real promovido; eventos conferidos |

---

## 3. Por período, número novo × número reapresentado

### (a) O problema em uma linha
Quando o balanço de 2025 traz 2024 com outro número, o analista só descobre se cair no conflito da
reconciliação, e o "igual" e o "novo" não aparecem em lugar nenhum.

### (b) O que já existe e serve

**Como versão, período e conta se relacionam hoje:**
- `documento` (caso, entidade, **período do documento**, tipo) → `documento_versao` (n_versao,
  `hash`) → `campo_extraido` (`chave` = rótulo, `valor_num`, `unidade`, `secao_canonica`,
  `entidade_coluna`, **`periodo_coluna`** = texto do cabeçalho da coluna, `ln`)
  (`Supabase/schema.sql:17818`, `:19171`, `:19241`).
- O período de cada número é o da **coluna** (`periodo_coluna`), com o do documento como queda.
- Versão nova = mesmo arquivo de novo (`0230_…sql:186-195`). Versão vigente:
  `fn_versao_com_extracao` (`schema.sql:18359`).
- Não existe conta canônica por linha: a identidade é `fn_normalizar_texto(chave)` +
  `secao_canonica`. A P27 (`fato_financeiro`, 0243) daria isso, e está parada (ESTADO S128).

| O quê | Onde | Serve para |
|---|---|---|
| `fn_conflitos_do_caso` | `0159_o_rotulo_que_a_propria_estrutura_desmente.sql:251` | Já agrupa por (seção, rótulo, entidade, exercício, DOCUMENTO), converte escala (`fn_valor_em_base`), filtra papel `conta`, aplica tolerância 100 na base ou 0,5%, e devolve só os pares que DISCORDAM |
| `fn_reconciliar_versoes_do_periodo` | `0159:477` | Já transforma esses pares em pendência de reconciliação |
| `fn_autoridade_do_documento` | `0151_…sql` | Autoridade documental; a 0151 recusou desempatar por `criado_em` (hora do upload) |
| `fn_valores_por_ano` | `0201_…sql:149` | Regras de coluna: abertura = ano anterior, movimento não é saldo, parcial só sem anual |
| `fn_anos_periodo`, `fn_exercicio_da_coluna`, `fn_ano_da_coluna`, `fn_coluna_e_abertura`, `fn_periodo_e_parcial` | 0199–0201, 0234 | Ano do documento e da coluna |

**A comparação é possível só com o que existe?** Para o caso principal, **sim**: a coluna
comparativa de um documento posterior contra o documento do próprio exercício. Isso não precisa de
dado novo. Precisa de dado novo (uma coluna) só para o caso "o cliente mandou um balanço 2024
refeito que substitui o balanço 2024 anterior" (D3.1).

**Atenção a duas implementações do ano da coluna:** `fn_conflitos_do_caso` usa
`fn_exercicio_da_coluna`; `fn_valores_por_ano` usa `fn_ano_da_coluna` com a regra da abertura. Se
divergirem, uma reapresentação aparece num e não no outro. A fatia 3.0 mede quantas linhas de
produção dão anos diferentes nas duas.

### (c) A mudança mínima, pela escada
**Definições (regra 1: nada se compara com o que não existe):**
- **Ano do documento** `A(D)`: o ano do período do documento (`fn_anos_periodo`), só documento anual
  não parcial na primeira versão.
- **Ano da linha** `a(l)`: o da coluna, com a regra da abertura.
- **Apresentação original** de (entidade, conta, ano Y): linha de documento com `A(D) = Y`.
- **Reapresentação** de Y: linha de documento com `A(D) > Y` (coluna comparativa ou saldo anterior).
- Para cada documento D, cada linha cai em UM rótulo:

| Rótulo | Condição |
|---|---|
| `novo` | `a(l) = A(D)`: número do próprio exercício do documento |
| `reapresentado_igual` | `a(l) < A(D)` e há original de `a(l)`, diferença dentro da tolerância |
| `reapresentado_com_mudanca` | `a(l) < A(D)` e há original, diferença acima da tolerância. Mostra os dois valores e os dois documentos |
| `sem_apresentacao_anterior` | `a(l) < A(D)` e nenhum documento do mandato é de `a(l)`. **Célula de comparação em branco**, nota: "o mandato não tem o documento de Y; não dá para saber se este número mudou" |
| `conta_nao_localizada` | há original de `a(l)`, mas a conta (rótulo + seção) não aparece nele. Nota: "pode ter sido renomeada; comparar à mão" — **nunca** `novo` |
| `nao_comparavel` | parcial, movimento, sem escala, sem seção canônica, papel ≠ `conta`; com o motivo |

**Migration `0302` (proposta):**
- **Função `fn_ocorrencias_por_documento(caso, entidade)`** `stable`, invoker: o CTE `por_documento`
  de `fn_conflitos_do_caso` extraído para uma função só, com o ano do documento junto. Escada degrau
  2: duas montagens da mesma conta divergem sem erro.
- **Função `fn_apresentacoes_por_periodo(caso, entidade)`** `stable`, invoker, lê a de cima e devolve
  uma linha por (documento, conta, ano) com o rótulo, os dois valores, os dois documentos, a
  diferença em base e o motivo. **Nada gravado**: é leitura.
- **Fatia separada:** `fn_conflitos_do_caso` passa a ler `fn_ocorrencias_por_documento`. Antes,
  listar os chamadores (`grep -rn fn_conflitos_do_caso Supabase/ N8N/ portal/src/`) e provar a saída
  idêntica na fixture do Canastra e num mandato real (leitura).
- **Migration `0303` (só se D3.1 = b):** `documento.substitui_documento_id uuid references documento
  on delete set null`, escrito só por `fn_documento_marcar_substituicao` (pessoa que escreve no
  caso, evento). Com ela, "versão anterior" de um balanço 2024 refeito = o balanço 2024 marcado.
  Sem marca, os dois continuam sendo conflito (como hoje), nunca "novo × reapresentado".
- **Sonda:** `funcao` das duas; `comportamento`: a fixture com 2024 original e 2025 comparativo
  devolve um `reapresentado_com_mudanca`.

**n8n:** nada.

**Portal:** página por mandato, entidade e ano: blocos "Novo", "Reapresentado com mudança"
(primeiro), "Reapresentado igual" (recolhido, com contagem), "Sem apresentação anterior" e "Não
comparável" (com contagem e motivo). Cada número com o documento e a página de origem. Linhas vazias
escondidas só com "N linhas sem dado ocultas" (benchmark §5.3).

### (d) Estados e transições
Não há estado gravado: o rótulo é recalculado a cada leitura. Ele muda quando:
- chega documento novo (**n8n** registra; o **banco** recalcula na leitura);
- a versão vigente muda por reextração (**banco**);
- uma **pessoa** marca substituição (D3.1 = b) ou corrige período/entidade/tipo do documento.
A decisão sobre QUAL número vale continua onde está: autoridade documental + pessoa (0151/0159).

### (e) Riscos de defeito silencioso
1. **Fabricar diferença sem anterior (regra 1).** → `sem_apresentacao_anterior` com célula em
   branco e nota com o efeito.
2. **Ruído de extração lido como reapresentação.** Duas leituras do mesmo arquivo. → Só a versão
   vigente entra; `documento_versao` nunca é comparada com outra do mesmo documento.
3. **Renomeação lida como "novo".** → `conta_nao_localizada`, separado.
4. **Ordem do upload decidindo o que é anterior.** → Só o período do documento; a 0151 já vetou
   `criado_em`.
5. **Duas regras do ano da coluna.** → Uma função de base para as duas; medida antes.
6. **Função que não rodou parece "nenhuma mudança" (regra 7).** → A página mostra o total de
   linhas comparadas por rótulo, inclusive zero, e "não comparável" com contagem.
7. **Chave por período errado (lição da 0274, ALTO 1).** → A chave é o ano da **coluna**, nunca o
   `periodo_id` do documento.
8. **Escala.** "1.000" em milhares × "1.000.000" em reais. → Comparar em base, como a 0151.
9. **Custo.** `campo_extraido` tem ~200 mil linhas; a versão cartesiana da 0151 levava 12,4 s. →
   Mesmo desenho agrupado da 0152; medir num mandato de 115 documentos antes de pôr na tela.

### (f) Invariantes
- I3.1 Sem documento do ano Y no mandato, a linha comparativa de Y sai `sem_apresentacao_anterior`,
  com valor anterior nulo, nunca `novo` e nunca diferença.
- I3.2 O mesmo arquivo reextraído (versão 2 com outro valor) não produz nenhuma reapresentação.
- I3.3 Todo par de `fn_conflitos_do_caso` entre documentos de anos diferentes aparece como
  `reapresentado_com_mudanca`, e vice-versa (as duas funções concordam).
- I3.4 Diferença dentro da tolerância → `reapresentado_igual`; acima → `com_mudanca`.
- I3.5 Mesma conta em milhares num documento e em reais no outro, mesmo valor → `igual`.
- I3.6 Rótulo diferente para a mesma seção → `conta_nao_localizada`, nunca `novo`.
- I3.7 Saldo anterior (abertura) de 2025 compara com o fechamento de 2024.

### (g) Fatias
| # | Fatia | Pronto quando |
|---|---|---|
| 3.0 | **Medir antes (leitura, produção).** Quantos (entidade, conta, ano) têm original E reapresentação; quantos discordam; quantas linhas dão ano diferente em `fn_exercicio_da_coluna` × `fn_ano_da_coluna`; tempo da consulta no maior mandato | Quatro números no cabeçalho da 0302 |
| 3.1 | `0302`: `fn_ocorrencias_por_documento` + `fn_apresentacoes_por_periodo` + sonda + teste | I3.1, I3.2, I3.4–I3.7 medidos não-vazio |
| 3.2 | `fn_conflitos_do_caso` lê a função de base | Saída idêntica antes × depois (fixture e um mandato real em leitura); I3.3 medido |
| 3.3 | Portal: página por período | Vistoria com um mandato que tenha DF de dois anos |
| 3.4 | (se D3.1 = b) `0303`: marcar substituição | Marcar e desmarcar muda o rótulo; evento gravado |
| 3.5 | (se D3.3 ≠ a) aba ou marca no book | `verificar-export.mts` reprova célula de comparação sem origem |

---

## 4. A pendência vira "achado"

### (a) O problema em uma linha
A pendência diz o que falta corrigir no dado; o cliente quer levar da reunião a lista de riscos, com
dono, efeito e mitigação, e ela não existe.

### (b) O que já existe e serve

| O quê | Onde | Observação |
|---|---|---|
| Tabela `pendencia` | `Supabase/schema.sql:20454` | `tipo` (19 valores, `schema.sql:242`), `severidade` (bloqueante/importante/complementar), `estado`, `sobrepujavel`, `descricao`, `motivo` (usado como chave do motor), documento/entidade/período |
| Estados | enum em `schema.sql:219`; `ESTADOS_EM_ABERTO` em `portal/src/lib/pendencia.ts:115`; `ESTADOS_DECIDIDOS` logo abaixo | `resolvida` é do sistema; os decididos são de pessoa |
| `fn_decidir_pendencia` | `0227_a_pendencia_decidida_que_nao_tinha_volta.sql:24` | Três botões + reabrir; grava `decisao` e evento |
| Portão 2 `fn_avaliar_portao2` | `0109_pendencia_tres_botoes.sql:55` (corpo em `schema.sql:1301`) | Bloqueia só por bloqueante sem decisão; conta ressalvas como informação |
| `decisao` | `schema.sql:19157` | Trilha de ressalva/override |
| `documento_fato` | `schema.sql` (covenant, ressalva de auditor, continuidade) e `fn_fatos_do_caso` (`0149_…sql:243`) | "Não é pendência: é o dado". Fonte natural de achado também |
| Export | `portal/src/lib/export.ts` (abas por `addWorksheet`, Resumo em `:3208`); `casos/[id]/export/route.ts:131` já lê pendência `extracao_falhou` | Não há aba de pendências nem de riscos no book |

Produção (ESTADO S127b): 2.999 pendências. A maioria é de dado (reconciliação, extração), não risco.

### (c) A mudança mínima, pela escada
Colunas novas em `pendencia` (opção D4.1 a) pareceriam menores. Não são: a pendência **se resolve
sozinha** quando o dado aparece (`resolvida`, do motor), e um risco da tese não deixa de existir
porque a linha foi extraída. Duas vidas diferentes na mesma linha = um achado que some quando o
motor resolve a pendência. Por isso a recomendação é tabela própria.

**Migration `0301` (proposta):**
- **Tabela `achado`**: `id`, `caso_id`, `titulo text not null`, `descricao text not null`,
  `categoria` (texto livre na primeira versão; enum só depois de medir, como `periodo.tipo`),
  `severidade` (`alta` | `media` | `baixa`), `efeito_em` (`numero` | `tese` | `ambos`),
  `efeito_descricao text not null`, `efeito_valor numeric null`, `efeito_unidade text`,
  `efeito_nao_quantificado_motivo text` com `check ((efeito_valor is null) = (motivo is not null))`
  (regra 1: sem valor exige o porquê), `mitigacao text`, `dono_usuario_id uuid` (membro) ou
  `dono_externo text` (D4.2), `prazo date`, `estado` (D4.5), `entidade_id`, `periodo_id`,
  `criado_por`, `criado_em`, `atualizado_em`, `encerrado_por`, `encerrado_em`, `motivo_encerramento`.
- **Tabela `achado_origem`**: `achado_id`, `pendencia_id` ou `documento_fato_id` ou
  `reconciliacao_id` (um não nulo, `check`), `on delete set null` + `origem_apagada_em` para a
  fusão de entidade não apagar o vínculo em silêncio.
- **Funções** (`security definer`, `search_path` fixo, só quem escreve no caso, evento em cada uma):
  `fn_achado_promover(pendencia, campos…)`, `fn_achado_criar(campos…)`,
  `fn_achado_atualizar(achado, campos…)`, `fn_achado_mudar_estado(achado, estado, motivo)`.
  Promover NÃO mexe na pendência: ela continua no fluxo dela.
- **Leitura:** `fn_relatorio_de_riscos(caso)` `stable`, invoker. Uma linha por achado com origem,
  estado da pendência de origem, e as contagens: abertos, mitigados, aceitos, encerrados; mais
  `pendencias_bloqueantes_sem_achado` (informação).
- **RLS:** SELECT por `fn_casos_legiveis()` (forma de conjunto da 0216); sem policy de escrita;
  `revoke insert, update, delete, truncate` do `authenticated` explícito.
- **Sonda:** `tabela` ×2, `rls_ligada` ×2, `sem_privilegio` de escrita ×2, `funcao` ×5, `corpo
  fn_achado_promover` com o evento.

**n8n:** nada.

**Portal:** botão "Promover a achado" na pendência (só para quem escreve); aba "Achados" do
mandato; página do relatório; contagem de achados abertos na visão geral. **Export:** ver D4.3.

### (d) Estados e transições (recomendação D4.5)
| De → para | Quem |
|---|---|
| — → `aberto` | **Pessoa** (promover ou criar) |
| `aberto` → `em_mitigacao` | **Pessoa** (com mitigação escrita) |
| `aberto`/`em_mitigacao` → `mitigado` | **Pessoa**, com o motivo |
| `aberto`/`em_mitigacao` → `aceito` | **Pessoa** (risco assumido, com motivo) |
| qualquer → `encerrado` | **Pessoa** (não procede, com motivo) |
| `mitigado`/`aceito`/`encerrado` → `aberto` | **Pessoa** (reabrir, como a 0227) |
O **banco** nunca muda o estado de um achado. Ele só **avisa**: "a pendência de origem foi
resolvida em D" aparece ao lado, e a pessoa decide.

### (e) Riscos de defeito silencioso
1. **Efeito zero fabricado.** → `efeito_valor` nulo exige motivo; o relatório escreve "não
   quantificado: <motivo>", nunca 0.
2. **Achado que some com a pendência.** → Tabela própria; o motor não toca em achado.
3. **Relatório vazio por não ter rodado (regra 7).** → O relatório escreve "0 achados registrados
   em <data>" quando é zero, e "relatório não lido" quando a consulta falha. O export não omite a
   aba em silêncio.
4. **Reuso de `pendencia.motivo`.** Ele já é chave do motor e é sobrescrito por
   `fn_decidir_pendencia`. → Nenhum campo do achado mora na pendência.
5. **Fusão de entidade apaga a origem.** (0153/0211/0213 reapontam tudo.) → `on delete set null` +
   data; o achado continua com o texto.
6. **Achado no book indo ao cliente sem querer.** → D4.3: o book só leva achado se o dono decidir, e
   por marca explícita.

### (f) Invariantes
- I4.1 Achado sem valor de efeito aparece no relatório com o motivo, nunca com 0.
- I4.2 A pendência de origem resolvida pelo motor não muda o estado do achado.
- I4.3 Leitura não cria nem edita achado; analista de outro mandato não vê.
- I4.4 Mandato sem achado: o relatório diz "0 achados em <data>"; erro de leitura: "não lido".
- I4.5 Apagar/fundir a origem mantém o achado, com a data da perda da origem.
- I4.6 Toda mudança de estado grava evento com antes, depois e autor.
- I4.7 (se for ao book) Cada linha da aba de riscos aponta para o achado; célula sem dado = branco
  + nota (`verificar-export.mts`).

### (g) Fatias
| # | Fatia | Pronto quando |
|---|---|---|
| 4.0 | **Medir antes.** Quantas pendências abertas por tipo e severidade; quantos `documento_fato`; o dono marca 5 pendências reais que seriam achado (amostra) | Números e amostra no cabeçalho da 0301 |
| 4.1 | `0301`: tabelas, funções, RLS, sonda, teste | I4.1–I4.6 medidos não-vazio |
| 4.2 | Portal: promover, aba Achados, mudar estado | Vistoria com um Analista de teste e um Leitura |
| 4.3 | Relatório: página + export (D4.3) | I4.4 e I4.7 na suíte; o arquivo abre no Excel sem reparo |

---

## 5. Ordem, dependências e conflitos

### Ordem recomendada: 1 → 4 → 3 → 2
1. **Função 1 primeiro.** É a menor, 70% já existe, e o `fn_kit_do_caso` é pré-requisito da 2 (o
   cliente vê o MESMO Kit). Também destrava o item 1 da fila de telas já aprovada ("Kit com % de
   prontidão, recebido ≠ conferido").
2. **Função 4 em seguida.** Só superfície interna, sem dado novo de extração, sem dependência da
   P27. Entrega o que o cliente leva da reunião.
3. **Função 3 depois.** Só leitura, mas toca `fn_conflitos_do_caso` (núcleo da reconciliação) e
   precisa de medição em produção e da decisão do ano da coluna. Ganha muito se a MA2 (`ln`) e a
   P27 chegarem antes.
4. **Função 2 por último.** É a maior, a única com superfície externa e a única em conflito direto
   com o PLANO_MVP. Precisa da 1 pronta, das 8 decisões e de revisão de segurança.

### Dependências
- 2 depende de 1 (`fn_kit_do_caso`) e do segredo no Vault (0217/0222).
- 3 depende de `fn_conflitos_do_caso` (0159) e das funções de ano (0199–0201, 0234); NÃO depende da
  P27, mas deve migrar para `fato_financeiro` quando a P27 estiver no ar (D3.5).
- 4 é independente; liga-se a 3 (reapresentação pode virar achado) e a `documento_fato`.
- Portal: `portal/src/**` é da Claude Oria 2; `export.ts` é da Claude Oria (PLANO_MVP §3). Cada
  fatia de portal tem um dono só.
- O patch interrompido da S129 (streaming, `patches/s129-item2-streaming-NAO-TESTADO.patch`) mexe em
  `casos/[id]/page.tsx`, que a fatia 1.2 também mexe. Fechar o patch antes.

### Conflitos
1. **PLANO_MVP §5 tira "Área do cliente e multiempresa" do MVP** ("ninguém de fora usa o sistema no
   MVP"). A Função 2 contraria isso. É a D2.6.
2. **Calendário do PLANO_MVP §3** está cheio até 18/12 (33 fatias). Estas quatro somam ~20 fatias.
   Sem tirar algo, o fim do MVP anda. Recomendo: Funções 1 e 4 entram no MVP (são pequenas e
   servem ao analista); 3 e 2 depois do portão do MVP.
3. **Faixas de migration** (`STATUS_POR_ETAPA_2026-11-11.md:359`): 0240–0269 Claude Oria,
   0270–0299 Claude Oria 2, 0300+ Claude Pessoal. A 0300+ cai na faixa da Claude Oria 2. Quem
   escrever confere a faixa e o `ls` na hora.
4. **Reserva da 0275.** Nada aqui usa 0275. Ao aplicar, a `instalacao_cobertura` sobe para o
   número novo e **nunca** é rebaixada quando a 0275 entrar (ESTADO S127b).
5. **0243 (P27)** reemite `fn_registrar_campos_extraidos` e põe gatilho em `documento`. Nenhuma
   destas funções reemite essa função nem `fn_registrar_documento`, nem põe gatilho em `documento`.
6. **ACL de produção** dá ALL ao `authenticated` em tabela nova (ESTADO S128). Toda tabela nova aqui
   revoga escrita explicitamente e tem requisito `sem_privilegio` na sonda.

### Migrations propostas (reconferir na hora)
| Nº | Função | Conteúdo |
|---|---|---|
| 0300 | 1 | `fn_kit_do_caso`, chave estável, rastro, evento `completude_recomputada` |
| 0301 | 4 | `achado`, `achado_origem`, funções, relatório |
| 0302 | 3 | `fn_ocorrencias_por_documento`, `fn_apresentacoes_por_periodo` |
| 0303 | 3 | (só se D3.1 = b) `documento.substitui_documento_id` |
| 0304 | 2 | `link_cliente`, `envio_cliente`, emitir/revogar/painel |
| 0305 | 2 | reservar, bucket, policy de Storage, quota |
| 0306 | 2 | (só se D2.2 ≠ b) ramo v3 em `fn_conferir_envio` |

---

## 6. Decisões do dono

### Função 1
**D1.1 — O que é "conferido" no Kit?**
- (a) Toda linha da versão vigente aceita por pessoa (aceite do sistema não conta).
- (b) Um clique "conferi este documento", por documento.
- (c) As duas: (a) ou (b).
- (d) Não ter "conferido"; parar em "lido".
- **Recomendo (a):** reusa o aceite que já existe, sem clique novo, e separa o auto-aceite.

**D1.2 — De que tamanho é um item do Kit?**
- (a) Mandato × tipo (como hoje).
- (b) Mandato × tipo × empresa.
- (c) Mandato × tipo × empresa × período.
- **Recomendo (a) agora**, com "atendido por N de M empresas" na tela. (b) muda o Portão 1 e merece
  decisão própria.

**D1.3 — O documento chega para uma pendência "item faltante" que alguém já decidiu (seguiu sem /
não procede). O que acontece?**
- (a) Vira "resolvida" (como hoje), com o estado anterior guardado no evento.
- (b) Fica como a pessoa decidiu; só o Kit mostra "recebido".
- **Recomendo (a):** o problema deixou de existir, e a trilha guarda a decisão.

**D1.4 — Quem dispara a conferência do Kit?**
- (a) O n8n no fim do lote (como hoje), mais o aviso "N documentos chegaram depois da última
  conferência".
- (b) Um gatilho no banco a cada documento.
- **Recomendo (a):** o gatilho em `documento` colide com o da P27 e custa segundos por UPDATE; a
  leitura derivada já deixa a tela certa.

### Função 2
**D2.1 — Como o cliente se identifica?**
- (a) Link com token, sem login.
- (b) Login de cliente, com papel novo na RLS.
- (c) Link + código por e-mail a cada acesso.
- **Recomendo (a):** não mexe nas policies por caso da 0216; a superfície é uma lista fechada de funções.
  (c) se o dono quiser uma segunda prova de posse.

**D2.2 — Para onde vão os arquivos do cliente?**
- (a) Direto ao n8n, extração automática.
- (b) Quarentena no Storage; o analista promove para a extração.
- (c) Quarentena com promoção automática até um teto de custo por link.
- **Recomendo (b):** quem tem o link não dispara custo de IA nem derruba o n8n.

**D2.3 — Por quanto tempo o link vale?**
- (a) 7 dias.
- (b) 30 dias, renovável e revogável.
- (c) Até o mandato fechar, revogável.
- **Recomendo (b).** Fechar o mandato desliga sempre.

**D2.4 — O que o cliente vê de um item que já mandou?**
- (a) Só "recebido".
- (b) "Recebido" ou "recebido, mas não conseguimos ler — reenvie".
- (c) Também "conferido".
- **Recomendo (b):** fala do arquivo, não do número. "Conferido" é interno.

**D2.5 — Quem emite e revoga o link?**
- (a) Só Sócio.
- (b) Sócio e Analista alocado no mandato.
- **Recomendo (b)**, com evento em cada emissão e revogação.

**D2.6 — A Área do cliente entra no MVP?**
- (a) Sim, deslocando outra fatia.
- (b) Depois do portão do MVP (18/12).
- (c) Só o banco agora (0304–0305), telas depois.
- **Recomendo (b):** o PLANO_MVP §5 a deixou fora, e ela é a maior das quatro.

**D2.7 — Que limites o link tem?**
- (a) Os mesmos do analista (15 MiB por arquivo, tipos atuais).
- (b) Os do analista, mais teto por link (ex.: 50 arquivos e 300 MB por link; números do dono).
- (c) Mais estreito: só PDF, XLSX, CSV, OFX e ZIP.
- **Recomendo (b)**, com os números definidos pelo dono.

**D2.8 — O que a página externa mostra do mandato?**
- (a) O nome do mandato como está no portal.
- (b) Um nome de exibição escrito por quem emitiu o link.
- (c) Nada; só "Documentos solicitados pela Oria".
- **Recomendo (b):** o nome interno pode conter apelido ou nome de operação sigilosa.

### Função 3
**D3.1 — O que conta como "versão anterior"?**
- (a) Só a coluna comparativa de um documento posterior contra o documento do próprio ano (dado que
  já existe).
- (b) (a) + uma marca "este documento substitui aquele", feita por pessoa.
- (c) (a) + a ordem de envio.
- **Recomendo (b), em duas fatias.** (c) não: a 0151 já recusou a hora do upload como critério.

**D3.2 — Qual tolerância separa "igual" de "mudou"?**
- (a) A da reconciliação (100 na base ou 0,5%).
- (b) Uma materialidade por mandato.
- **Recomendo (a):** uma regra só; senão a tela diz "igual" onde a reconciliação diz "conflito".

**D3.3 — Onde aparece?**
- (a) Só numa página do portal.
- (b) Página + aba no book.
- (c) Página + aba + cor na célula do book.
- **Recomendo (a) primeiro.** (c) junto com a convenção de cor por origem, que já está na fila.

**D3.4 — Reapresentação com mudança abre pendência nova?**
- (a) Não: ela já sai como conflito na reconciliação; só ganha o rótulo.
- (b) Sim, um tipo novo `reapresentacao`.
- **Recomendo (a):** duas pendências para o mesmo fato dividem a decisão.

**D3.5 — Como reconhecer a mesma conta em dois documentos?**
- (a) Rótulo normalizado + seção (como a reconciliação hoje), com "conta não localizada" explícito.
- (b) Esperar a P27 (`fato_financeiro`).
- **Recomendo (a) agora** e trocar para (b) quando a P27 estiver no ar.

### Função 4
**D4.1 — Onde mora o achado?**
- (a) Colunas novas na pendência.
- (b) Tabela própria, ligada a pendências, fatos e reconciliações.
- **Recomendo (b):** a pendência se resolve sozinha; o risco não.

**D4.2 — Quem é o "dono" do achado?**
- (a) Só alguém da equipe (usuário do portal).
- (b) Equipe ou um nome externo (ex.: "CFO do cliente").
- **Recomendo (b):** a mitigação quase sempre é do cliente.

**D4.3 — Como sai o relatório de riscos?**
- (a) Aba "Riscos" no book, sempre.
- (b) Página no portal + arquivo próprio, fora do book.
- (c) (b) + aba no book só para achados marcados "vai ao book".
- **Recomendo (b) agora, (c) depois:** o book sai da casa, e o achado é análise interna até alguém
  decidir mostrá-lo.

**D4.4 — Como registrar o efeito no número?**
- (a) Só texto.
- (b) Texto obrigatório + valor opcional; sem valor, motivo obrigatório.
- (c) Valor obrigatório.
- **Recomendo (b):** (c) forçaria zero fabricado (regra 1).

**D4.5 — Quais estados o achado tem?**
- (a) aberto, em mitigação, mitigado, aceito, encerrado (com reabrir).
- (b) aberto e encerrado.
- **Recomendo (a):** é o que separa "risco tratado" de "risco assumido".

**D4.6 — Achado trava o Portão 2?**
- (a) Não; só informação, como as ressalvas.
- (b) Achado de severidade alta sem mitigação trava.
- **Recomendo (a):** o Portão 2 é sobre o dado (0109); risco da tese é decisão do comitê.
