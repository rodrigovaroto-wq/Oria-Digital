# Camada de banco (Supabase / Postgres) — Fatia 1

Materializa o schema conceitual (`Arquitetura do Sistema/2 Especificação/f0/05_schema_conceitual.md`) no Postgres do Supabase, no
subconjunto necessário para a **Fatia 1 (E1 — Intake determinístico)** da F1.

> **Fonte da verdade do estado = Postgres** (ver `Arquitetura do Sistema/1 Visão e Doutrina/02`, trava de stack nº 1). O N8N é
> stateless; o portal Vercel lê/escreve via camada que respeita RLS.

## Faixas de numeração — leia antes de criar uma migration

| Faixa | De quem |
|---|---|
| `0001`–`0034` | já aplicadas em produção, **não tocar** |
| `0035`–`0099` | reservada ao **dono** |
| `0100`+ | **estagiário / colaborador** |

**Nunca reaproveite um número existente**, e buraco na sequência (`0034` → `0100`) é o
estado esperado.

**Por que a faixa existe:** duas migrations com o mesmo prefixo **não geram conflito de
merge**. O git aceita `0035_a.sql` e `0035_b.sql` vindas de branches diferentes sem uma
palavra; o laço de aplicação (`Supabase/test/run.sh`, e a tabela abaixo) as aplica na ordem
alfabética do **sufixo**, que é arbitrária — e a "ordem de aplicação" documentada aqui passa
a mentir em silêncio. `Supabase/test/run.sh` reprova prefixo duplicado antes de aplicar qualquer
coisa, então a colisão morre no PR e não no banco; a faixa é o que evita chegar até lá. Quem
aplica migration em produção é só o dono (ver `CLAUDE.md`).

## Migrations (aplicar nesta ordem)

| Arquivo | O que faz |
|---|---|
| `migrations/0001_schema_fatia1.sql` | Tipos enumerados (máquinas de estado de `Arquitetura do Sistema/2 Especificação/f0/04`) + tabelas: `caso`, `entidade`, `periodo`, `taxonomia_tipo_documento`, `documento`, `documento_versao`, `checklist_item_status`, `pendencia`, `decisao`, `evento_auditoria`, `estagio_autonomia`. |
| `migrations/0002_seed_taxonomia_e_dial.sql` | Seed da taxonomia v1 (`Arquitetura do Sistema/2 Especificação/f0/03`: Kit Básico + Variáveis) e do dial de autonomia inicial (`Arquitetura do Sistema/2 Especificação/f0/04`). Idempotente. |
| `migrations/0003_rls_e_storage.sql` | RLS por tabela + bucket privado `documentos` no Storage. |
| `migrations/0004_funcoes_e1.sql` | Coluna `nao_sobrepujavel` + funções RPC do E1 (`fn_upsert_caso`, `fn_registrar_documento`, `fn_recomputar_completude`). |
| `migrations/0005_extracao_e2.sql` | Tabela `campo_extraido` + `fn_registrar_campos_extraidos` (extração em **N0/sombra**); redefine `fn_registrar_documento` p/ retornar os dois ids. |
| `migrations/0006_reset_funcoes.sql` | **Reset forçado das 4 funções RPC.** Roda sempre que houver dúvida sobre o estado delas (ex.: aplicações parciais/repetidas deixaram assinatura divergente) — derruba qualquer sobrecarga existente e recria do zero. **Seguro de rodar a qualquer momento** (idempotente). |
| `migrations/0007_justificativa_pendencia.sql` | Adiciona `p_justificativa` (parâmetro trailing com default) a `fn_registrar_documento` — a pendência de classificação incerta passa a incluir a explicação objetiva da IA ("Motivo: ..."), não só o número de confiança. |
| `migrations/0008_portal_revisao.sql` | Suporte de banco para o **Portal**: coluna `confianca`/`fonte`/`justificativa` em `documento` (para o dashboard não precisar fazer parsing de `evento_auditoria.depois`); `fn_registrar_documento` passa a gravá-las (mesma assinatura de 0007). Nova função `fn_revisar_documento` — a fila de revisão do portal chama essa RPC para confirmar/corrigir a classificação: resolve a pendência, registra `decisao`+`evento_auditoria`, realoca o checklist, recomputa a completude. |
| `migrations/0009_reconciliacao_e3.sql` | **E3 — Reconciliação, Classe A** (primeira fatia, `Arquitetura do Sistema/2 Especificação/04_RECONCILIACAO.md`). Tabela `reconciliacao` (log append-only de cada checagem); `fn_valor_conceito` casa `campo_extraido.chave` (texto livre) com um conceito canônico por termos obrigatórios/excludentes normalizados; duas checagens — `fn_reconciliar_ativo_passivo_pl` (Ativo = Passivo + PL no Balanço) e `fn_reconciliar_caixa_bp_fluxo` (Caixa do Balanço vs. saldo final do Fluxo de Caixa, aborta se as unidades divergirem); `fn_reconciliar_por_documento(documento_id)` é o ponto de entrada chamado pelo N8N logo após a extração — dispara as checagens do tipo do documento. Opera em **N1**: gera `pendencia` tipada (`divergencia_reconciliacao` ou `precondicao_nao_satisfeita`), nunca escreve um número como fato. |
| `migrations/0010_diagnostico_e1e2.sql` | **Diagnóstico de conteúdo + planilha organizada (E1/E2).** Colunas novas: `campo_extraido.secao` (agrupador de planilha), `documento.resumo`, `documento_versao.nota_legibilidade`. `fn_registrar_campos_extraidos` (mesma assinatura) passa a gravar `secao`. Nova função `fn_registrar_diagnostico` — chamada pelo N8N logo após a extração, com o bloco `diagnostico` da MESMA chamada de IA (não aumenta o nº de chamadas): preenche `entidade` só quando ainda vazia (fecha uma lacuna, nunca sobrescreve), confere tipo/período contra o que já está registrado (gera `pendencia` tipada `tipo_incorreto`/`periodo_incorreto`/`entidade_incorreta` quando diverge — nunca corrige sozinha), grava a `legibilidade` real do arquivo (antes hardcoded `'ok'`) e gera `arquivo_ilegivel` quando o conteúdo está ilegível. Idempotente (reaproveita pendência aberta da mesma checagem) e auto-resolve quando a divergência some (ex.: humano já corrigiu). |
| `migrations/0011_aceite_export_e4.sql` | **E4 — Portão 2 mínimo + suporte ao Export Excel** (`Arquitetura do Sistema/2 Especificação/f0/07_output_spec.md`). Colunas novas em `campo_extraido`: `status_aceite` (`pendente`/`aceito`/`com_ressalva`), `aceito_por`, `aceito_em` — sem isso nenhuma linha extraída tinha mecanismo de aceite humano (princípio inegociável da spec: "nenhum número entra no export sem uma `decisao` de aceite humano ligada"). Nova função `fn_aceitar_extracao(documento_versao_id, autor, motivo)` — aceita **todas as linhas de uma versão de documento de uma vez** (granularidade v0; a spec permite refinar o "layout fino" depois), registra `decisao` (tipo `aprovacao`) + `evento_auditoria`. Idempotente. |
| `migrations/0012_secao_canonica_e4.sql` | **Seção canônica sugerida pela IA (classificação do export, E4).** Coluna nova `campo_extraido.secao_canonica`. `fn_registrar_campos_extraidos` (mesma assinatura de 0005/0006/0010) passa a gravá-la. A IA já classifica cada linha, na MESMA chamada de extração (não aumenta o nº de chamadas), numa seção canônica pelo **significado contábil** da conta (`N8N/lib/extract.mjs`). O classificador do export (`portal/src/lib/statement-templates.ts`) usa essa sugestão só como **fallback** (quando âncora/seção-livre/palavra-chave não classificaram) — reduz o bloco "Contas Não Classificadas" sem sobrepor a regra determinística. **N1/advisory**: afeta só ONDE a linha aparece; a linha continua pendente/âmbar até o aceite humano (anti-ancoragem, `Arquitetura do Sistema/1 Visão e Doutrina/01`). Subir a IA para prioridade/auto-clear exige golden set + concordância medida (`Arquitetura do Sistema/2 Especificação/f0/06`). |
| `migrations/0013_guarda_extracao_suspeita.sql` | **Guarda de segurança contra extração suspeita (E2)** — achado testando com um documento real (sessão 7, `HANDOFF.md`): um balanço multi-entidade fez a IA fabricar ~20 contas com o MESMO valor repetido, confiança declarada ALTA (0.99). `fn_registrar_campos_extraidos` (mesma assinatura) passa a checar, depois de gravar o lote da própria chamada (não relê extrações anteriores): (1) `extracao_padrao_suspeito` (tipo novo no enum `pendencia_tipo`) — 4+ contas distintas com o EXATO mesmo valor não-zero; (2) `extracao_baixa_confianca` (enum já existia desde 0001, nunca tinha sido usado) — parcela relevante das linhas (≥3 e ≥30%) com confiança < 0.7. Gera `pendencia` tipada, idempotente (reaproveita pendência aberta pela mesma versão), auto-resolve numa reextração que não repete o padrão. **Não resolve a causa raiz** (documentos multi-entidade/combinados quebram a extração) — só torna o problema visível antes do aceite humano. |
| `migrations/0014_entidade_coluna_multi_entidade.sql` | **Suporte a documentos multi-entidade (E2)** — ataca a causa raiz da fabricação vista na `0013`: coluna nova `campo_extraido.entidade_coluna` (nome da coluna/entidade da linha, quando o documento traz várias empresas lado a lado, ex. balanço combinado "Tecn \| Part \| Com \| Total"; null no caso comum de 1 entidade só). `fn_registrar_campos_extraidos` (mesma assinatura) passa a gravá-la. `N8N/lib/extract.mjs` (schema+prompt) passa a pedir uma linha por (conta × coluna) em vez de resumir/adivinhar um valor único. O export (`portal/src/lib/export.ts`) usa `entidade_coluna` para separar cada empresa em sua própria coluna. |
| `migrations/0015_reconciliacao_classe_b.sql` | **E3 — Reconciliação, Classe B** (segunda fatia, `Arquitetura do Sistema/2 Especificação/04_RECONCILIACAO.md`). Semi-objetiva (agregação/período) — travada em **N1** (nunca sobe pra N2 como a Classe A pode): banda de materialidade mais folgada (piso R$ 50k **e** 5%), qualquer divergência na zona cinzenta vira revisão humana, nunca auto-clear. Duas checagens canônicas: `fn_reconciliar_receita_dre_vs_faturamento` (Receita Bruta da DRE vs. soma das linhas mensais de `FATURAMENTO_24M` do mesmo ano — recorte por ano no rótulo, exclui linhas de total/média) e `fn_reconciliar_despfin_dre_vs_divida` (Despesa Financeira da DRE vs. soma das linhas de juros/encargos do `MAPA_DIVIDA`). Novo helper `fn_somar_conceito`/`fn_somar_faturamento_ano` (agregação, não casamento de uma linha só como `fn_valor_conceito` da 0009) e `fn_registrar_reconciliacao_b` (log + pendência idempotente, mesmo padrão da 0009). `fn_reconciliar_por_documento` redefinida para disparar A+B pelo tipo do documento. Pré-condição não satisfeita (documento ausente, rótulo não casou, período não identificado) é o comportamento ESPERADO enquanto `FATURAMENTO_24M`/`MAPA_DIVIDA` só tiverem schema genérico de linhas — vira pendência, nunca "OK" falso. |
| `migrations/0016_guarda_extracao_falhou.sql` | **Guarda de segurança contra extração que falhou/veio vazia (E2)** — achado em produção (sessão 7 cont.⁷, `HANDOFF.md`): 16 documentos ("teste v14") foram classificados com sucesso mas tiveram 0 linhas extraídas; n8n mostrava sucesso em todo node, reprocessar não mudava nada. Causa: a chamada de extração (schema com array `linhas` sem limite de tamanho) não tinha `max_tokens` explícito nem checagem de `finish_reason` — uma resposta truncada virava JSON inválido, e `parseExtractionResponse` devolvia `campos: []` silenciosamente; `fn_registrar_campos_extraidos` tratava array vazio como "0 campos, sucesso" e retornava sem checar nada. `fn_registrar_campos_extraidos` (mesma assinatura de 0005/.../0013 + `p_falha_motivo text default null`) agora roda a checagem de documento/caso mesmo com 0 campos e gera `pendencia` tipada `extracao_falhou` (severidade importante, idempotente, auto-resolve numa reextração que vier ok) sempre que o n8n mandar um motivo de falha. O fix de `max_tokens` (16384) e a detecção de truncamento/erro de API ficam em `N8N/lib/extract.mjs` + mirror em `N8N/build-workflow.mjs` — **precisa reimportar o workflow no N8N** para ter efeito. |
| `migrations/0017_periodo_coluna.sql` | **Suporte a documentos COMPARATIVOS (colunas de período, E2/E4)** — lacuna achada testando o export (sessão 7 cont.⁹): uma demonstração comparativa (ex. "Balanço consolidado 2023 x 2024.pdf", 2023 e 2024 lado a lado da MESMA entidade) colapsava os dois anos numa coluna só no export — perda de dado, e inútil pra modelagem (análise horizontal/vertical exige os anos lado a lado). Coluna nova `campo_extraido.periodo_coluna` (rótulo da coluna de período da linha; null no caso comum de período único). É ORTOGONAL a `entidade_coluna` (0014): um documento pode ter várias empresas E vários anos → linha por (conta × empresa × período). `N8N/lib/extract.mjs` (schema+prompt) pede uma linha por (conta × período); o export (`portal/src/lib/export.ts`) usa `periodo_coluna` na chave de coluna. **Limpeza de schema junto:** a `0016` deixou DUAS sobrecargas de `fn_registrar_campos_extraidos` (3 e 4 params) porque `create or replace` com nº de params diferente cria overload novo — chamada posicional de 2 args ficava ambígua ("is not unique"); a `0017` derruba a de 3 params e recria só a de 4 (grava `periodo_coluna` também). **Precisa reimportar o workflow no N8N.** |
| `migrations/0018_fix_revisar_documento_pendencias.sql` | **Fix: `fn_revisar_documento` só resolvia UM dos 4 tipos de pendência da fila de revisão** — achado em produção (sessão 7 cont.¹⁴, "teste v20"): o dono confirmava/salvava na fila, o documento era corretamente atualizado (fonte='humano', confiança=100%), mas o CARD continuava aparecendo. Causa: a função (0008) só fechava `classificacao_pendente`; as outras três (`tipo_incorreto`/`entidade_incorreta`/`periodo_incorreto`, introduzidas pela 0010) nunca eram resolvidas pela mesma ação. `fn_revisar_documento` (mesma assinatura) agora resolve os quatro tipos. |
| `migrations/0019_auto_aceite_alta_confianca.sql` | **Auto-aceite de linhas com confiança >=95%** — pedido explícito do dono (decisão de produto, registrada com a ressalva honesta de que sobe a autonomia da extração além do que a doutrina padrão exigiria sem golden set). `fn_registrar_campos_extraidos` (mesma assinatura de 0017) grava `status_aceite='aceito'`/`aceito_por`/`aceito_em` já na inserção quando `confianca >= 0.95`, registrando UM `decisao`+`evento_auditoria` por chamada (resumo, não um por linha). Inclui backfill: linhas já gravadas antes desta migration, com confiança >=95% e ainda pendentes, são promovidas agora (um `decisao` por caso afetado). |
| `migrations/0020_periodo_canonico.sql` | **Comparação de período por FORMA CANÔNICA (elimina `periodo_incorreto` falso)** — achado no "teste v22": a fila de revisão marcava "período pode estar incorreto" quando o diagnóstico sugeria o MESMO período do registrado em NOTAÇÃO diferente (`2025-01-15` × `15/01/2025`; `anual 2025` × `anual 12M25`). `fn_registrar_diagnostico` (0010) comparava a string crua. Novas funções `fn_ano4` + `fn_periodo_canonico(tipo, referencia)` (mesma semântica de `formatarPeriodo` do portal) colapsam notações equivalentes; `fn_registrar_diagnostico` (mesma assinatura) só gera pendência quando os períodos são canonicamente DISTINTOS. Pendências falsas já abertas auto-resolvem na próxima passada. Sem mudança no N8N. |

| `migrations/0021_classe_b_checagem_unidade.sql` | **Classe B: pré-condição de UNIDADE/ESCALA entre os dois documentos** — achado na auditoria de endurecimento: as duas checagens B (0015) comparam valores de DOIS documentos diferentes (Receita da DRE × soma do FATURAMENTO_24M; Despesa Financeira × juros do MAPA_DIVIDA) **sem** conferir a escala — ao contrário da Classe A (0009). Se a DRE está em milhares e o mapa em unidades, a comparação é entre grandezas 1000x distintas (divergência sem sentido, ou pior, falso "ok"). Novas `fn_unidade_predominante(documento_versao_id)` (moda da escala entre as linhas que a declaram — linhas não-monetárias têm `unidade` null por construção e não distorcem) e `fn_motivo_escala_incomparavel(...)`; as duas checagens B (mesmas assinaturas de 0015) passam a devolver `precondicao_nao_satisfeita` com motivo explícito quando as escalas divergem. Escala ausente num dos lados não bloqueia (mesmo critério conservador da 0009). Sem mudança no N8N. |

| `migrations/0022_periodo_por_ano_e_guardas.sql` | **Período por CONJUNTO DE ANOS + reconciliação tolerante a granularidade + guarda sem falso positivo** — três achados do "teste v24" (book Vertentes, 14 documentos). (1) A comparação canônica da 0020 ainda acusava divergência entre o MESMO período em granularidades diferentes (`anual 2025` × `data-base 2025-12-31`; `L24M` × `janeiro/2024 a dezembro/2025`): novas `fn_anos_periodo` e `fn_periodos_equivalentes` comparam o conjunto de anos, e só divergem quando os dois lados declaram anos e eles diferem. (2) As 4 checagens A/B casavam documentos por `periodo_id` EXATO — como cada arquivo declara a granularidade que quer, deu 11 pré-condições "documento ausente" com todos os documentos presentes; agora cada lookup aceita períodos COMPATÍVEIS (`fn_periodos_compativeis`, anos que se intersectam). (3) A guarda de padrão suspeito contava valores repetidos no lote inteiro — num combinado (5 empresas × 2 anos) o mesmo valor reaparece por coluna e valores pequenos coincidem à toa (5 alertas falsos): agora conta repetições DENTRO da mesma coluna e só considera valores materiais. Assinaturas inalteradas. |
| `migrations/0023_reconciliacao_sem_ruido.sql` | **Reconciliação sem ruído — 36 pendências → 0** (achado do "teste v25": o portal listava 36 pendências de reconciliação com o book extraído corretamente; reproduzido em `Supabase/test/`). Cinco causas: (1) **ausência de documento virava pendência** (20 das 36) — documento que falta é cobrança do CHECKLIST do Kit Básico (`fn_recomputar_completude`), não da fila de revisão: a tentativa segue registrada em `reconciliacao` para auditoria, mas não abre pendência que o humano não tem como acionar; (2) **o COMBINADO não era aceito como balanço** — as checagens só olhavam `tipo_taxonomia='BALANCO'`, agora aceitam BALANCO→COMBINADO→BALANCETE (`fn_documento_balanco`); (3) **coluna era ignorada** — `fn_valor_conceito` pegava `limit 1` na versão inteira, comparando o Ativo de um ano contra o Passivo de outro num comparativo; novo `fn_valor_conceito_col` + `fn_coluna_entidade`/`fn_coluna_periodo_do_ano`, e a checagem roda **uma vez por ano declarado**; (4) **total de seção sem linha de total** — "RECEITA OPERACIONAL BRUTA" é cabeçalho sem valor em demonstração BR; novo `fn_soma_secao` soma as contas-folha excluindo o total da seção, as seções irmãs e as âncoras de cascata; (5) **escala divergente recusava a comparação** — com as duas escalas declaradas e conhecidas, converter é determinístico: `fn_fator_escala`/`fn_valor_em_base` convertem e só recusam escala ausente ou fora do vocabulário. Novo registro unificado `fn_registrar_reconciliacao` (Classe A e B). Assinaturas preservadas — o N8N chama `fn_reconciliar_por_documento` e não muda. Testes: `Supabase/test/run.sh`. |
| `migrations/0024_taxonomia_dmpl_dva.sql` | **DMPL e DVA na taxonomia** (achado do "teste v25": a DMPL do book Vertentes saía classificada como `MUTUOS`). Não era erro da IA: `tipo_sugerido` é um enum FECHADO nos códigos que existem na taxonomia (`N8N/lib/ia.mjs` → `codigosConhecidos`), e não havia código nenhum para DMPL — o modelo escolheu o vizinho mais próximo. Entram como **complementar** (Nível 2): mexer no Kit Básico mudaria a completude de todo caso já aberto, e isso é decisão de produto, não efeito colateral de migration de vocabulário. Acompanham a migration, fora do banco: aliases de nome (`N8N/lib/taxonomia.mjs` + espelho no gerador), os valores `dmpl`/`dva` em `SECAO_CANONICA_ENUM` (roteamento por LINHA, para a DMPL embutida num PDF composto não ser somada como conta do PL) e abas próprias no export. **Só afeta classificações NOVAS** — documento já registrado como MUTUOS continua MUTUOS até ser reextraído ou corrigido na fila de revisão. |
| `migrations/0025_indices_macro.sql` | **Índices macroeconômicos — histórico + expectativa.** Alimenta as premissas da aba de Modelagem (inflação que corrige receita e contratos, juro que precifica a dívida), que até aqui eram digitadas de memória. Duas tabelas porque são dois FATOS diferentes: `indice_macro_obs` (o que ACONTECEU — série mensal publicada) e `indice_macro_expectativa` (o que o mercado ESPERA — Focus/BCB, por ano). Misturá-los seria tratar previsão como histórico. A observação é chaveada por (serie, data_ref, **FONTE**): guardar BCB e IBGE lado a lado é o que permite `fn_divergencias_indice_macro` conferir — sobrescrever uma com a outra destruiria a evidência que autoriza chamar o dado de validado. `fn_indice_macro_anual` acumula o ano por **composição** (12 meses de 1% dão 12,68%, não 12%) para série de TAXA e por variação entre fechamentos para série de NÍVEL (câmbio), e devolve o nº de meses para que ano incompleto não entre numa média de 3/5/10 anos como se fosse cheio. Coleta pelo workflow `N8N/workflow.macro.json` (mensal, dia 12 — depois da divulgação do IPCA). Testes: `Supabase/test/macro.test.sql`. |
| `migrations/0026_reextracao_por_hash.sql` | **Reextração é versão nova do mesmo documento (idempotência por hash) + limpeza do overload morto.** O comentário da `0004` dizia "idempotente-ish por hash", mas nenhum corpo (0004→0008) chegou a CONSULTAR o hash: todo reenvio do mesmo arquivo inseria `documento` + `documento_versao` + `checklist_item_status` novos. Duas consequências reais — o mesmo arquivo virava dois documentos (duas linhas na fila, dois itens de checklist, colunas duplicadas da mesma empresa no export) e **reextrair ficava impossível sem sujar o caso**, sendo que reextrair é a ÚNICA forma de um documento já processado pegar prompt/taxonomia novos (a DMPL registrada como `MUTUOS` antes da `0024`, por exemplo). Agora mesmo `(caso_id, hash)` → nova `documento_versao` sob o MESMO documento (`n_versao+1`), sem duplicar checklist nem pendência; hash NULO nunca casa (dois desconhecidos não são o mesmo arquivo, e fundir documentos distintos é o erro mais caro aqui); e a classificação da máquina **não sobrepõe revisão humana** (`documento.fonte='humano'`). O retorno ganha `n_versao`/`reaproveitou_documento` (aditivo — o N8N atual não muda). Do lado do export, `versoesVigentes` usa a versão mais recente **com dado** (reextração que falha e volta vazia, `0016`, não pode apagar do book o que a anterior extraiu). **Não deixa de PAGAR** a extração repetida: isso exige fingerprint de prompt+modelo e curto-circuito no grafo do N8N — fatia própria, com o N8N vivo. Testes: `Supabase/test/reextracao.test.sql`. |
| `migrations/0027_ordem_da_linha.sql` | **ORDEM da linha no documento** — achado do teste v28: o Ativo Circulante da VT Logística saiu **7.254** onde o documento diz **3.961**, porque "Contas a Receber" (3.293) foi somada JUNTO com os seus componentes "Fretes a receber" (3.562) e "(-) PECLD" (−269). As duas detecções de subtotal que o export já tinha não pegam esse caso: uma exige que alguma linha declare `secao` com o nome do subtotal (a extração daquele arquivo anotou a seção de TOPO em todas), a outra exige que o valor bata com a soma dos irmãos da MESMA seção (ali os irmãos são o circulante inteiro) — e como o documento não trouxe linha de total, não havia nem conferência: o número errado não tinha como ser percebido. O sinal que sobra é o que toda demonstração publicada dá: **o subtotal vem impresso imediatamente ANTES dos seus componentes**. Coluna `campo_extraido.ordem` + índice `(documento_versao_id, ordem)`; assinatura de `fn_registrar_campos_extraidos` INALTERADA (o N8N chama do mesmo jeito), só o JSON de entrada passa a aceitar `ordem` por linha — que o `N8N/lib/extract.mjs` preenche com a POSIÇÃO NO ARRAY, não pedindo o campo ao modelo. Extração antiga fica `null` e nada muda para ela: **só reprocessamento traz o ganho**. Invariante 17 de `verificar-export.mts`, com caso negativo. |
| `migrations/0028_rls_e_grant_indices_macro.sql` | **RLS e GRANT dos índices macro, esquecidos na 0025.** O dono aplicou 0025 + o seed + reimportou os workflows, e o export continuava com a aba Macro vazia. Comparando com toda migration anterior que cria tabela/função chamada pelo portal, faltavam os dois passos que o resto do banco sempre faz: (1) `indice_macro_serie`/`indice_macro_obs`/`indice_macro_expectativa` sem `enable row level security` nem policy — RLS habilitado sem policy devolve **zero linhas sem erro nenhum**, indistinguível de "sem dado coletado"; (2) `fn_indice_macro_anual` (chamada pelo portal via `supabase.rpc()`, que resolve para o papel `authenticated`) sem `grant execute`, ao contrário de `fn_revisar_documento` (0008) e `fn_aceitar_extracao` (0011), as outras duas funções que o portal chama diretamente. Função chamada só pelo N8N não precisa disso porque o N8N conecta via Postgres NATIVO (Session Pooler), nunca pelo PostgREST. Verificação embutida na própria migration: insere linha real, troca para o papel `authenticated` (`set local role`) e confere por `COUNT(*)` — RLS sem policy não estoura exceção, só esconde a linha, e testar contra tabela vazia não prova nada. `Supabase/test/run.sh` passou a replicar o GRANT de tabela que o Supabase provê por padrão a todo projeto nascente (sem isso, `set role authenticated` falharia para QUALQUER tabela local, não só a com o bug — é por isso que nenhum teste daqui tinha pego essa classe de defeito). Do lado do portal, `export/route.ts` parou de engolir `.error` das consultas macro (`?? []` sem olhar erro) — a aba Macro agora distingue "a consulta FALHOU" (pode haver dado) de "sem dado coletado" (a base está genuinamente vazia). |
| `migrations/0029_extracao_aceite_depois_das_guardas.sql` | **Quatro defeitos que faziam a extração parecer bem-sucedida quando não foi.** (1) **Auto-aceite atropelava as guardas** — o mais grave, porque furava a anti-ancoragem (`Arquitetura do Sistema/1 Visão e Doutrina/01`, `Arquitetura do Sistema/2 Especificação/f0/06`): a `0027` gravava `status_aceite='aceito'` DENTRO do loop para toda linha com confiança ≥95%, e só depois rodava as três guardas (padrão suspeito / baixa confiança / extração falhou); nenhuma guarda revertia o aceite. Uma extração alucinada — cujo padrão típico é justamente vir com confiança ALTA e o mesmo valor repetido em muitas contas — entrava como **fato aceito**, com o Sinal 1 abrindo uma pendência ao lado sem desfazer nada. Uma guarda que dispara depois do aceite não é guarda, é legenda. Agora toda linha entra `pendente` e a promoção acontece no fim, só se nenhuma guarda disparou; guarda que barra promoção vira `evento_auditoria`, para não parecer que o auto-aceite não rodou. (2) **Extração vazia sem erro de API não gerava pendência nenhuma** — a `0016` fechou "a chamada falhou", não "a chamada respondeu JSON válido com `linhas: []`": aí `p_falha_motivo` é nulo e `v_count` é zero, e os três sinais eram pulados. O documento ficava com tipo, confiança alta, `em_validacao`, zero linhas e zero pendências, indistinguível de um documento que legitimamente não tem números — e o pipeline produz esse estado de propósito, porque `.xlsx` e mime não previsto mandam para a IA uma string de aviso em vez do arquivo. (3) **`extracao_falhou` nunca fechava**: a chave era `'extracao:falhou:' || documento_versao_id`, então reenviar (que cria versão nova) abria/fechava uma chave diferente e a pendência antiga ficava aberta para sempre — e `fn_revisar_documento` (0018) não resolve nenhuma das quatro de extração, ou seja, não havia ação humana capaz de fechá-las. As três chaves passam a ser por `documento_id`, com migração das já gravadas (sem ela, a própria correção deixaria as pendências existentes órfãs). (4) **Documento inexistente descartava o motivo da falha**: `if v_documento_id is null then return v_count;` com o comentário "nunca deveria acontecer (FK)" — mas FK não dispara com `null`, e o caminho era real e caro: falha em `Registrar Documento` → `documento_versao_id` nulo → extração **executada** (dinheiro gasto) → função retorna 0 jogando fora o `p_falha_motivo` antes do Sinal 3. Agora registra em `evento_auditoria` + `warning`; a prevenção do gasto fica no pipeline, onde `Montar Req Extracao` recusa montar requisição sem versão. Verificação embutida com 5 asserts, todos provados não-vazios (desligando cada fix, o `run.sh` reprova com a mensagem específica). |
| `migrations/0030_entidade_e_periodo_canonicos.sql` | **Canonicalizar entidade e período no caminho de ESCRITA.** Três defeitos com a mesma forma: o dado é gravado cru, a comparação depois é mais esperta, e o descasamento produz duplicata ou "não achei" — em silêncio. (1) **Entidade duplicada** — regressão introduzida pelo PR #65: `fn_registrar_documento` casava por `lower(razao_social)`, e desde que a entidade passou a sair também do NOME DO ARQUIVO existem duas fontes que escrevem diferente (`Vertentes Metalurgica` sem acento, porque `normalize.mjs` remove diacríticos, × `Vertentes Metalúrgica Ltda.` do diagnóstico). `lower()` não aproxima as duas ⇒ duas linhas `entidade` para a mesma empresa ⇒ o export conta cada uma como coluna e toda soma do grupo duplica. O export já mascarava o sintoma (`consolidarNomesDeEntidade`), e é por isso que a duplicidade na base passou sem ser vista. (2) **`fn_coluna_entidade` casava por igualdade exata** — causa da pendência "não foi possível localizar Ativo Total / Passivo+PL" do teste v31: no balanço COMBINADO os cabeçalhos são apelidos curtos (`Metalúrgica`) e `razao_social` é a razão completa, então nunca casava, a função devolvia o sentinela `E'\x01'`, `fn_valor_conceito_col` e `fn_soma_secao` não retornavam nada e `v_n_anos` era 0. Os rótulos estavam certos desde sempre. O portal já resolvia isso com casamento por token com prefixo; o banco não tinha equivalente. (3) **Período gravado cru** fragmentava o exercício: `2025` e `12M25` viravam duas linhas em `periodo` — a `0022` canonicalizava só na comparação, então a reconciliação achava o par mas dashboard, checklist e export viam dois períodos. Introduz `fn_entidade_canonica` (sem acento, pontuação nem sufixo societário — `SPE` NÃO é descartado, faz parte do nome), `fn_mesma_entidade` (igualdade canônica ou token do nome curto como prefixo do longo, exigindo pelo menos um token de 4+ chars porque fundir empresas é pior que não casar), `fn_upsert_entidade` e `fn_upsert_periodo`. `fn_registrar_documento` é redefinida com o corpo EXATO da `0026` trocando só as duas buscas — extrair os passos em funções próprias é o que os torna testáveis sozinhos e o que evita repetir o erro da `0006`, que recriou um corpo antigo inteiro e regrediu funções. Testes em `Supabase/test/canonico.test.sql` (13 asserts, todos provados não-vazios). **Limitação conhecida e fixada por teste:** o viés é para CONSOLIDAR — nome curto é absorvido pelo longo que o contenha por prefixo, e numeral romano não desempata (`SPE I` casa `SPE II`). É o mesmo comportamento do portal, que está em produção, e é o preço de fazer `Metalúrgica` casar `VERTENTES METALÚRGICA LTDA.`. Se aparecer caso real de fusão indevida, o desempate é CNPJ — a coluna já existe em `entidade` e ninguém preenche. |
| `migrations/0031_caixa_por_secao.sql` | **Reconciliação do caixa: usar a SEÇÃO, que o documento já declarava.** Segunda das duas pendências de PRÉ-CONDIÇÃO do teste v31 ("não foi possível localizar o Caixa/Disponível do Balanço"). A causa não era rótulo ruim nem extração falha: `fn_valor_conceito_col` exige que TODOS os termos apareçam como substring de `ce.chave` e **nunca olha `ce.secao`**. Contra os rótulos reais do book, duas das cinco empresas não casavam nenhuma das quatro tentativas — `VT Logística` tem chave `Bancos Conta Movimento` (e seção `Disponível`, onde o dado estava todo esse tempo) e a SPE tem chave `Caixa` puro, que as tentativas rejeitavam porque exigiam `equivalentes` ou `bancos` junto. Sem os dois lados, `continue` ⇒ `v_n = 0` ⇒ pendência: a reconciliação reclamava de dado que ela mesma não tinha procurado onde estava. Introduz `fn_valor_conceito_secao` (gêmea da original, casando contra `ce.secao`; função separada em vez de parâmetro novo, porque a original é chamada de muitos lugares e mudar a assinatura obrigaria a revisar todos) e três tentativas novas na cascata do caixa, **depois** das buscas por rótulo — rótulo é mais específico que seção, e documento que declara as duas coisas deve escolher a linha, não o grupo. O `EXCLUI` olha chave E seção, para seção que casou não salvar rótulo proibido. Nenhuma outra checagem muda. |
| `migrations/0032_cambio_perdia_janeiro.sql` | **A variação anual do câmbio perdia janeiro, todo ano.** `fn_indice_macro_anual` (0025) calculava série de NÍVEL comparando dezembro com dezembro do ano anterior por uma janela que descartava o primeiro mês. Corrige a janela e o teste trava o comportamento — a fixture anterior CONSAGRAVA o erro. |
| `migrations/0033_precondicao_que_nomeia_o_rotulo.sql` | **A pré-condição de Ativo × Passivo+PL dizia que falhou, nunca por quê.** No v33, cinco reconciliações A.1 saíram como "pré-condição não satisfeita" sem dizer qual lado faltou. A mensagem passa a listar os rótulos que a extração trouxe, o que transformou o diagnóstico seguinte (0034) em leitura, não em adivinhação. |
| `migrations/0034_total_do_grupo_sem_a_palavra_total.sql` | **O total do grupo raramente se chama "total", e a A.1 exigia a palavra.** Causa raiz achada no v35 pela mensagem que a 0033 passou a escrever. Introduz `fn_rotulo_estrutural` — a mesma função que a 0042 reaproveita para o papel da linha. |
| `migrations/0035_moeda_por_linha.sql` | **A moeda que a extração sempre soube e nunca gravou** (§7.4 #2 do Onboarding). Coluna `campo_extraido.moeda`; sem ela, linha em USD e linha em BRL somavam na mesma coluna sem uma marca. |
| `migrations/0036_completude_exige_conteudo.sql` | **Documento que chegou vazio para de contar como item cumprido** (§7.4 #3 e #4). Checklist exigia o arquivo, não o conteúdo: PDF ilegível fechava o item. Recusa RETORNADA (não exceção), porque exceção em plpgsql desfaria o registro da própria tentativa. |
| `migrations/0037_portao2.sql` | **O Portão 2 do caso existe** — era só um valor de enum. `caso_status` tinha `aprovado`/`pronto_para_base` desde a 0001 e nenhuma função transicionava para eles; `pendencia.sobrepujavel` era gravado e nunca lido. `fn_avaliar_portao2` (só lê) + `fn_aprovar_caso`, com teto de ressalvas em 3 e ressalva expirada avaliada NA LEITURA. |
| `migrations/0038_premissas_catalogo.sql` | **Catálogo de premissas, e a escolha de modelagem por caso.** As 15 premissas do modelo eram constantes de código; viram dado (`premissa_catalogo`, `caso_premissa`, `caso_linha_premissa`, `caso_modelagem`), com sugestão por setor e sete primitivas de fórmula. |
| `migrations/0039_linhas_para_modelagem.sql` | **As linhas do caso, para a tela de Modelagem.** `fn_linhas_para_modelagem` — função e não consulta no portal porque `campo_extraido` não tem `caso_id`: o escopo por caso mora aqui, uma vez só. |
| `migrations/0040_sazonalidade_do_caso.sql` | **Sazonalidade DERIVADA do histórico do próprio caso** (decisão do dono, 7.5). A curva mensal não é digitada: sai do faturamento do mandato. Sem 12 meses, não há curva — e o arquivo diz isso, em vez de ratear 1/12. |
| `migrations/0041_dial_manda.sql` | **O dial de autonomia volta a ser estado do sistema.** `estagio_autonomia` nascia na 0001 e não tinha um único leitor, enquanto o auto-aceite usava `0.95` hardcoded. `limiar_auto_clear` vira dado, `fn_dial`/`fn_mudar_dial` respeitam o teto e gravam `mudanca_dial`, e baixar a autonomia passa a ser UMA chamada em vez de um deploy. |
| `migrations/0042_papel_da_linha.sql` | **A linha diz o que ela é antes de ser projetada.** `fn_papel_linha` (conta/subtotal/derivado/serie_mensal, lista fechada); `fn_linhas_para_modelagem` reemitida com papel, valor COM SINAL, unidade/moeda, documentos e `sobreposicao_suspeita`; vínculo em linha que não é conta é recusado no banco. Corrige também `fn_mes_do_rotulo` (o `left(chave,3)` devolvia curva vazia com o rótulo real da extração). |
| `migrations/0043_reconferir_o_que_ja_esta_no_banco.sql` | **Reaplicar as regras de HOJE sobre o dado já gravado, sem gastar IA.** Pendência é estado gravado e nada a reavaliava quando a regra mudava — o portal mostrava, por tempo indeterminado, achado que a regra atual não faria mais. `fn_avaliar_guardas_extracao` vira fonte única dos três sinais; `fn_reconferir_caso` é o ponto de entrada. |
| `migrations/0044_valores_por_ano.sql` | **O valor de cada linha lógica por exercício.** `fn_valores_por_ano(caso, entidade)` — o filtro de entidade **não é opcional**: sem ele, "Ativo Circulante 2024" devolvia o de uma empresa do grupo e o passivo de outra. Ano vem de `periodo_coluna` primeiro (balanço comparativo traz dois anos no mesmo documento). |
| `migrations/0100_papel_por_secao.sql` | **O papel da linha é da SEÇÃO, não do rótulo solto no caso.** A tela agrupa por (seção, rótulo) e a guarda agrupava só por rótulo, resolvendo o empate pelo papel mais restritivo — então ela recusava a linha que a tela tinha acabado de oferecer, e o "aplicar em lote" caía inteiro na primeira recusa. A guarda passa a ler o papel da mesma seção que a tela mostrou; recusa por linha vai para `ignoradas` e o lote segue; recusa global (premissa não ativa) continua abortando. **Primeira migration na faixa `0100`+** (colaborador). |
| `migrations/0102_modelagem_versao_vigente.sql` | **A Modelagem lê a versão VIGENTE de cada documento.** A `0026` estabeleceu que reextrair cria `documento_versao` nova sem perder a anterior — e os cinco leitores por caso (`fn_linhas_para_modelagem`, `fn_papel_do_rotulo_no_caso`, `fn_sazonalidade_do_caso`, `fn_valores_por_ano`, `fn_linhas_do_tipo`) nunca mencionavam `n_versao`, então as ocorrências de TODAS as versões entravam no mesmo agrupamento. Medido: `Estoques` ia de 7 ocorrências/24.610 para 8/777.777 depois de UMA reextração — a versão superada somava e podia **ditar o valor que sai no Excel**. E cada rodada de reextração acrescentava um jogo inteiro de ocorrências, o que devolveria o caso ao `statement_timeout` que a `0101` acabou de destravar, sem ninguém mexer em código. A regra vive numa definição só, `fn_versao_com_extracao` — que difere de `fn_versao_atual` de propósito, porque `max(n_versao)` puro deixaria a tela em branco na janela entre registrar o documento e extrair. Traz também `fn_diagnostico_modelagem`, para responder "a correção está no banco?" sem adivinhar. |
| `migrations/0101_modelagem_dentro_do_tempo.sql` | **A tela de Modelagem cabe dentro do `statement_timeout`.** Medido num caso do tamanho do v35 (14 documentos, 770 ocorrências): `fn_conferir_modelagem` levava **9,3 s** — acima do teto de 8 s do Supabase —, era cancelada, e a tela mostrava isso como "este caso não tem linha extraída". Duas causas: `fn_conferir_modelagem` chamava `fn_linhas_para_modelagem` **cinco vezes**, duas delas dentro de `exists` correlacionado (uma execução completa **por vínculo**); e `fn_papel_linha`, que custa ~1,6 ms, era avaliada **por ocorrência** quando o papel é propriedade do RÓTULO. Agora a conferência é uma passada só, o papel é calculado uma vez por rótulo distinto e a marca de sobreposição virou join por igualdade. **9,3 s → 96 ms**, com resultado idêntico campo a campo. Traz também os `grant execute` dos auxiliares da 0042 que nasceram sem nenhum. |
| `migrations/0103_papel_linha_tokeniza_uma_vez.sql` | **A terceira fatia do mesmo problema: parar de repetir o trabalho DENTRO de cada rótulo.** A `0101` foi medida contra um caso de 55 rótulos distintos; o real tem ~250, e refeita a medição com a forma certa as duas funções da tela voltaram a **~1,9 s cada** — o teto de novo. `fn_papel_linha` chamava `fn_rotulo_estrutural` **nove vezes** e cada chamada re-tokenizava o mesmo rótulo do zero; e `sobreposicao_suspeita` chamava `fn_rotulo_contido` **por par de linhas**, re-tokenizando os dois rótulos a cada par. Agora a tokenização é `fn_tokens_estruturais` (uma vez por rótulo) e a contenção virou o operador de array `<@` sobre radicais calculados uma vez por linha. **1,9 s → 310 ms**, mantendo o filtro de versão vigente da `0102`. `fn_rotulo_estrutural` e `fn_rotulo_contido` continuam existindo, reemitidas sobre os helpers, para não haver duas definições da mesma regra. |
| `migrations/0104_desativar_premissa.sql` | **Remover premissa deixa de ser impossível — e não deixa vínculo órfão para trás.** `fn_ativar_premissa` (0038) ligava e ajustava; não havia como desligar, e uma premissa ativada por engano ficava para sempre. Desativar não é só `ativo = false`: `caso_linha_premissa` não olha essa bandeira, então baixá-la sozinha faria a TELA (que monta o seletor a partir das ativas) mostrar a linha sem premissa, a CONFERÊNCIA continuar contando aquela linha como configurada, e o EXPORT não achar a premissa do vínculo e emitir a linha sem projeção — três leituras do mesmo caso, todas em silêncio. `fn_desativar_premissa` limpa as duas colunas de vínculo (premissa e sazonalidade), apaga a linha que ficou sem as duas, **devolve quantos desfez** e preserva `valores` para a reativação. |
| `migrations/0105_reconciliar_duplicidade_de_rotulo.sql` | **A mesma conta com dois rótulos: detectar, dizer o tamanho, e não apagar nada.** Achado da auditoria do arquivo entregue (sessão 40): depois de excluir os subtotais informados, sobrava resíduo de outra natureza — `Prejuízos acumulados` e `Resultados Acumulados`, ambos −39.150; `Capital social subscrito` e `Capital social subscrito e integralizado`. São o MESMO fato transposto com nomes diferentes por dois documentos do caso, e a extração, fiel a cada um, grava as duas; somadas, inflam o patrimônio. O export já faz a parte dele (cada grupo segue o TOTAL INFORMADO e a diferença aparece numa linha de reconciliação), mas isso deixa o número certo sem dizer QUAL das duas é a conta — e adivinhar por semelhança de valor apagaria conta legítima (duas provisões de mesmo valor existem). Então `fn_pares_duplicados_do_caso` acha os pares candidatos por critério ESTREITO (mesma `secao_canonica`, valor idêntico ao centavo na mesma coluna entidade×período, papel `conta`, só a versão vigente, e ≥2 colunas coincidentes **ou** radical estrutural compartilhado via `fn_tokens_estruturais` da 0103) e `fn_reconciliar_duplicidade` abre pendência com os rótulos e o valor dobrado. **Nenhuma linha é apagada nem reescrita** — decisão humana, com o número na frente. `fn_reconciliar_por_documento` reemitida chamando a checagem nova em BALANCO/BALANCETE/COMBINADO. Verificação embutida com 6 asserts, incluindo os dois que RECUSAM falso positivo (duas provisões de mesmo valor num ano só, e rótulos de valores diferentes) e o que prova que a checagem não toca no dado. |
| `migrations/0106_rejeitar_pendencia.sql` | **O Portão 2 ganha o segundo lado: a pendência que NÃO PROCEDE.** A `0037` deu ao portal um botão só — *aprovar* — que é exatamente o que a regra proíbe enquanto houver pendência bloqueante viva: o caso trava, a tela explica o motivo, e não existe ação que mude o motivo. `Arquitetura do Sistema/2 Especificação/f0/04` define três saídas para a pendência (`resolvida`, `rejeitada`, `aceita_com_ressalva`) e só a primeira existia em código, escrita por `sistema:*`. `fn_rejeitar_pendencia` entrega a rejeição HUMANA, com três guardas: **motivo obrigatório de no mínimo 15 caracteres** (`fn_min_motivo_rejeicao`, espelhado em `portal/src/lib/pendencia.ts`), **estado terminal não se rejeita** (`resolvida` → `rejeitada` reescreveria o passado; rejeitar de novo é no-op declarado) e **nada é apagado** — a linha fica com autor e motivo, e a decisão vai para `decisao(override)` + `evento_auditoria`, inclusive a TENTATIVA recusada. Como `rejeitada` é estado terminal nas três condições da `0037`, rejeitar libera o portão **sem teto, inclusive para a lista fechada de não-sobrepujáveis** — que é o que `Arquitetura do Sistema/2 Especificação/f0/04` manda ("tem de ser resolvida ou rejeitada") e a alavanca mais forte do sistema. Por isso `fn_avaliar_portao2` foi republicada (regra idêntica) publicando `rejeitadas` e `rejeitadas_nao_sobrepujaveis`: a contagem aparece na tela e fica gravada dentro da `decisao` de aprovação, para um caso destravado por rejeição parar de ter a mesma aparência de um caso limpo. Testes: `Supabase/test/rejeitar_pendencia.test.sql`, incluindo o que prova que a rejeição **sobrevive ao recomputo da completude** (sem isso o botão seria decorativo). |
| `migrations/0107_papel_ressalva_e_tratamento.sql` | **A máquina de estado da pendência fica inteira (`Arquitetura do Sistema/2 Especificação/f0/04`).** Dos seis estados especificados na F0, o código escrevia três — e os que faltavam não eram detalhe: `reenviada_ao_cliente` representa a ação mais comum do processo real ("pedi o documento de novo") e não tinha onde ser registrada, e `aceita_com_ressalva` era um controle **publicado sem existir** (o card do Portão 2 fala do teto de 3 desde a `0037` e ninguém conseguia criar uma). A ressalva exigia antes uma decisão: `Arquitetura do Sistema/2 Especificação/f0/04` pede **papel sênior**, que não existia no schema. Entra aqui no menor tamanho que resolve — `usuario_papel` (e-mail → `analista`/`senior`), `fn_papel()` com default no **menor privilégio**, e escrita SEM policy: cadastrar sênior é ação de banco, porque uma tela que promove o próprio usuário não é controle. `fn_ressalvar_pendencia` cobra as quatro exigências de `Arquitetura do Sistema/2 Especificação/f0/04` (sênior, motivo, expiração futura, teto) e **recusa a lista fechada** — aceitar ali deixaria o humano achando que resolveu com o caso travado do mesmo jeito. `fn_tratar_pendencia` move entre os estados de tratamento, **sem liberar o portão** e sem gravar `decisao` (ninguém decidiu sobre o mérito). E `fn_rejeitar_pendencia` é republicada com um aperto sobre a `0106`: rejeitar **não-sobrepujável** passa a exigir sênior; a rejeição comum continua aberta. **Depois de aplicar, cadastre o primeiro sênior** — sem isso ninguém ressalva: `insert into usuario_papel (email, papel) values ('voce@dominio', 'senior');`. Testes: `Supabase/test/papel_ressalva.test.sql`. |
| `migrations/0108_falha_de_execucao.sql` | **Quando o pipeline falha, a TELA fica sabendo.** O dono subiu 35 documentos, o n8n recusou o lote no orçamento (corretamente, sem gastar nada) e o portal continuou dizendo *"estamos organizando tudo com cuidado… assim que estiver pronto, avisamos"* — para sempre. A rota `/api/intake/status` deduz progresso de sinais POSITIVOS (documento criado, evento de extração), e falha produz **ausência** — indistinguível de "ainda processando". Tela de espera sobre processo morto é pior que erro na tela: é mentira com cara de calma. Nova tabela `execucao_falha` (própria, não `evento_auditoria`: isto é estado operacional que a tela lê a cada 3s e alguém marca como visto), `fn_registrar_falha_execucao` (aceita `caso_id` nulo — a falha pode acontecer antes de o caso existir, e falha órfã é falha invisível), `fn_falhas_abertas` e `fn_marcar_falha_vista`. Traz também **`fn_excluir_caso`**: exclui o mandato e o que depende dele, devolvendo a contagem do que se perdeu e gravando a exclusão em `evento_auditoria` ANTES do delete — a trilha não tem FK para `caso`, então o rastro sobrevive ao caso. |
| `migrations/0109_pendencia_tres_botoes.sql` | **A pendência vira três botões, sem formulário e sem teto** (decisão do dono, 11/08/2026). `fn_decidir_pendencia` atende os três de uma vez: *Contatar o Cliente* (não libera o portão — o documento ainda não chegou), *Prosseguir sem resolução* (aceita com ressalva) e *Pendência não procede* (rejeita). **Desfaz, por decisão de produto, guardas da `0106`/`0107`** e o registro disso é obrigação: sai o motivo obrigatório (a trilha passa a responder QUEM e QUANDO, não POR QUÊ), sai a data de expiração, sai o teto de 3 e sai a exigência de papel sênior — `usuario_papel`/`fn_papel` ficam no schema, parados. A lista fechada de `Arquitetura do Sistema/2 Especificação/f0/04` deixa de bloquear quando o humano decide seguir: com um botão só, "Prosseguir sem resolução" que não faz o caso prosseguir seria um botão que mente. O que fica é o que sustenta a decisão: **nada é apagado e tudo é contado** — o Portão 2 deixa de IMPEDIR e passa a INFORMAR, publicando quantas foram ressalvadas e quantas declaradas improcedentes (inclusive da lista fechada), dentro da própria decisão de aprovação. |
| `migrations/0110_remove_papel_de_usuario.sql` | **O papel de usuário sai do schema** (decisão do dono, 11/08/2026). A `0107` criou `usuario_papel`/`fn_papel` porque `Arquitetura do Sistema/2 Especificação/f0/04` exige sênior para ressalvar; a `0109` tirou a exigência, e a tabela ficou **sem um único leitor**. A `0109` disse que ela custava pouco parada — o argumento está errado: tabela sem leitor é o mesmo defeito que a `0037` corrigiu do outro lado (`pendencia.sobrepujavel` gravada desde a 0001 e nunca lida, o que fazia "não-sobrepujável" ser decoração). Schema que guarda o que não usa ensina quem lê a não confiar no que vê. Se o controle por papel voltar, volta com a regra que o justifica. |
| `migrations/0111_documento_sem_dado_financeiro_nao_e_falha.sql` | **Certidão sem número não é extração falha** (achado no "Teste V45 - Canastra"). O Sinal 3 de `fn_registrar_campos_extraidos` abria `extracao_falhou` para TODO documento com zero linhas gravadas, sem distinguir "a chamada falhou" de "o documento não tem valor monetário nenhum, por natureza" (certidão negativa, organograma societário, parecer do auditor — o próprio `book-canastra` lista isto como armadilha deliberada). Novo parâmetro `p_tem_dado_financeiro` (vem do diagnóstico da própria chamada de extração, `N8N/lib/extract.mjs`): Sinal 3 só dispara quando ele é `null` (chamador antigo — comportamento idêntico ao de sempre) ou `true`; `false` explícito é o único jeito de silenciar a guarda, e só o modelo que leu o arquivo pode dizer isso. **Reimportar `N8N/workflow.e1-ingestao.json`** — o schema de extração ganhou o campo novo e o nó `Gravar Campos (Sombra)` passa 4 argumentos em vez de 3. |
| `migrations/0112_lote_conferido_documento_por_documento.sql` | **Documento que o pipeline PULOU passa a ser denunciado.** No "Teste V45 - Canastra", 19 dos 35 documentos registrados **nunca tiveram a extração chamada** — e o sistema inteiro ficou calado: sem linha em `campo_extraido`, sem `extracao_sombra` em `evento_auditoria`, sem pendência, checklist verde, Portão 1 satisfeito. A causa imediata foi de mecânica do n8n (duas conexões cruas no mesmo input do `Registrar Documento`, corrigida no mesmo commit com um nó Merge e o `Recompor Contexto`), mas a lição é estrutural: **toda guarda de extração deste repositório vive DENTRO do caminho da extração**, e guarda que mora no caminho não cobre o caminho não percorrido. `fn_documentos_nao_extraidos` mede de fora (documentos registrados × documentos com evento de extração) e `fn_conferir_lote` abre pendência **bloqueante não-sobrepujável por documento**, com `lote_integro` como o booleano que decide se a rodada vale. Não gasta IA, é idempotente e auto-resolve quando o documento é reprocessado. Ligada no fim do canvas como nó `Conferir Lote`. |
| `migrations/0113_linha_exigida_por_tipo.sql` | **A linha exigida por tipo de documento vira DADO, e o Portão 1 cobra pelo nome.** Quando a linha de que uma checagem depende falta no documento (balanço sem caixa, DRE sem receita bruta), a reconciliação sai `precondicao_nao_satisfeita` — pendência MOLE (importante, sobrepujável), publicada por período pelo despachante, e só para as ~10 linhas que as cinco checagens cruzam; linha que nenhuma checagem toca não é verificada nunca, e o caso segue como se tivesse conferido. Materializa a entrega aprovada (13/08/2026): `taxonomia_linha_exigida` (o QUE cada tipo precisa ter, filha da taxonomia) + `taxonomia_linha_localizador` (COMO se procura — cascata no formato inclui/exclui de `fn_valor_conceito`, com `contra` chave/seção/estrutural espelhando 0009/0031/0034). `origem` separa **'codigo'** (11 exigências cujos termos são cópia literal das reconciliações vigentes) de **'proposta'** (3, para MUTUOS/FAT_INTRAGRUPO/CONTRATO_SOCIAL, que nenhuma checagem lê hoje); `depende_de` registra o FATO de qual checagem/indicador para sem a linha. `fn_recomputar_completude` ganha o passo (2b): tipo presente COM conteúdo mas sem linha exigida abre pendência `linha_exigida_ausente` que NOMEIA a linha (0033) e resolve sozinha quando ela aparece. **Política é do dono**: `severidade`/`sobrepujavel` nascem NULL (default = o peso de hoje: importante, sobrepujável) — nada endurece sozinho, `pronto_para_revisao` não muda. Testes: `Supabase/test/linha_exigida.test.sql`. |
| `migrations/0114_mandato_fechado.sql` | **Fechar um mandato deixa de ser o mesmo que excluí-lo.** `caso.status` (Arquitetura do Sistema/2 Especificação/f0/04) diz onde o mandato está no TRABALHO — intake, triagem, revisão, aprovado — e não responde à pergunta operacional "ainda estamos nisso?": um caso aprovado em março e um aprovado ontem têm o mesmo status e situações opostas, e a lista crescia sem fim. `fechado_em` (NULL = ativo) carimba a saída da mesa preservando documento, linha extraída, pendência decidida e trilha — para apagar continua existindo `fn_excluir_caso` (0108). `fn_fechar_caso` é idempotente (fechar duas vezes não reescreve quem fechou) e `fn_reabrir_caso` desfaz, de propósito: ação sem volta faz a pessoa não usar, e a lista volta a crescer. Índice parcial `idx_caso_ativos` porque a barra lateral pede sempre os ativos. |
| `migrations/0115_custo_do_lote.sql` | **O custo da IA existia e ninguém conseguia ver.** `N8N/lib/custo.mjs` mede a chamada de verdade e o nó `Resumo de Custo` fecha a conta do lote — custo real, estimado, tokens e cobertura —, mas o relatório morria na saída da execução do n8n: responder "quanto gastamos neste mandato" exigia abrir o n8n e ler um JSON, e "quanto gastamos no total" ninguém respondia. `lote_execucao` guarda UMA LINHA POR EXECUÇÃO (não colunas em `caso`) porque um mandato recebe documentos mais de uma vez, e somar por cima perderia QUAL rodada saltou. A chave `(caso_id, execucao_ref)` é correção, não zelo: o `Resumo de Custo` roda uma vez por ramo do lote e as duas passadas trazem o total inteiro — sem ela, todo custo sairia 2×, que é um erro para cima e por isso não é questionado. `fn_registrar_uso_lote` recebe o resumo inteiro em jsonb (campo novo no relatório não pede migration de assinatura) e faz `on conflict do update`. |
| `migrations/0116_total_impresso_e_linha.sql` | **O total impresso passou a ser LINHA, e o papel dela precisa existir antes.** O prompt de extração deixou de aceitar que o valor impresso na linha do agrupamento ("ATIVO CIRCULANTE ... 3.961") vire só o nome da `secao` — a auditoria da v46 mostrou o balanço chegando com todas as contas e NENHUM total de topo, e sem eles a conferência do export não tem contra o que conferir. Chegando como estão, os totais novos do topo da DRE e da DVA seriam classificados `conta` por `fn_papel_linha` e receberiam premissa na Modelagem — dupla contagem. A lista continua FECHADA (rótulo, nunca semelhança): "Receita bruta", "Despesas operacionais" e os nomes de subgrupo ficaram de fora de propósito, porque em documento resumido eles SÃO a conta — quem os pega é a detecção estrutural do export, que olha o documento e não o rótulo. |
| `migrations/0117_reconciliar_mutuos.sql` | **A divergência de mútuos passa a ser acusada.** O book planta UMA divergência deliberada (R$ 240 mil a menos na planilha do controller do que no balanço da holding); a rodada v46 trouxe o erro inteiro para dentro do banco, os dois lados com os dois números certos, e nenhuma pendência abriu — as cinco checagens existentes simplesmente não olham para mútuos. Classe **B** porque a diferença pode ser legítima (aditivo, encontro de contas, conta agregada no balanço): o sistema mostra, o humano decide. A sutileza é o LADO: mútuo é ativo para quem emprestou e passivo para quem tomou, e somar os dois juntos acusaria divergência inexistente — a comparação é lado a lado, e quando o balanço tem os dois lados e a planilha não diz de qual fala, a checagem PARA e explica, em vez de chutar. |
| `migrations/0118_dedup_por_fingerprint.sql` | **A segunda metade da 0026: reenviar o mesmo arquivo com o mesmo prompt deixa de pagar a extração.** A 0026 tornou o reenvio seguro (versão nova sob o mesmo documento, sem duplicar nada) e escreveu, no próprio cabeçalho, o que faltava — um fingerprint de prompt+modelo na versão e o curto-circuito no grafo do n8n. O fingerprint (prompt de sistema + modelo + esquema, calculado no build do workflow) mora agora em `documento_versao`; quando ele e o hash batem com uma versão que JÁ TEM linha extraída, a função devolve essa versão e o workflow pula a chamada à OpenAI. **A exigência de "ter linha" é o que impede o pior erro possível aqui:** sem ela, uma extração que falhou passaria a valer como feita, e o reenvio — que é justamente o conserto — nunca mais chamaria a IA. |
| `migrations/0119_linha_exigida_por_entidade.sql` | **A linha exigida passa a ser cobrada POR ENTIDADE** (PR #135, do Ian — renumerada de `0116` por colisão de faixa com o #136). A `0113` perguntava "algum documento do tipo tem a linha?": num grupo com oito balanços, o oitavo respondia sim e as sete ausências sumiam. Agora a pergunta é "cada entidade que trouxe linhas desse tipo tem a linha NELA?" — sete pendências, cada uma nomeando a empresa, e a oitava limpa. O escopo **deriva da `granularidade` que a taxonomia já declara** (entidade/entidade_periodo cobram por entidade; caso/periodo seguem como antes); a coluna nova `escopo_entidade` é o override do dono e nasce NULL. Dois fallbacks deliberados evitam pendência falsa: nome de coluna que não casa com entidade registrada não é atribuído a ninguém, e tipo sem eixo de entidade cai no comportamento da `0113`. Traz também a guarda **seed×código**, que lê o texto vigente das funções de reconciliação no `pg_proc` e reprova quando um termo do seed deixou de existir nelas. A varredura dos casos existentes é passo OPCIONAL e à parte: `Supabase/varredura_linha_exigida.sql`. |
| `migrations/0120_banco_de_perguntas.sql` | **O banco de perguntas ao cliente vira dado, e o sistema sugere a pergunta pronta** (PR #138, do Ian). O capítulo 10 do onboarding define 36 perguntas a fazer depois que a extração roda; nenhuma era sistema, e o que perguntar saía da cabeça do analista quando ele clicava "Contatar o Cliente". Agora `fn_sugerir_perguntas` devolve a pergunta pronta, com motivo/risco/impacto e os marcadores preenchidos. O encaixe é o ponto: `exigencia_ausente` lê a MESMA `fn_exigencias_do_caso` da pendência — pendência e pergunta são duas faces da mesma avaliação e não divergem. **Sugerir não grava**; só a ação humana grava, com o texto renderizado congelado na linha (o que foi perguntado é fato histórico). Nenhum envio é automático. Escopo declarado: 11 das 36, com as outras 25 nomeadas família a família no cabeçalho. |
| `migrations/0121_diagnostico_nao_duplica_entidade.sql` | **O diagnóstico de conteúdo para de duplicar a empresa.** Achado em dado real: quatro mandatos do dono voltaram com TRÊS linhas para a mesma companhia, e uma delas — a razão social correta — era criada por esta função, em mandato novo, com o workflow já reimportado. A `0030` ensinou `fn_registrar_documento` a casar entidade pela forma canônica e **esqueceu a `fn_registrar_diagnostico`**, que é justamente a outra fonte de nome de empresa: ela comparava `lower(razao_social) = lower(nome)`. Dois efeitos, ambos reproduzidos em base limpa: cria a segunda linha da mesma empresa (documento que chega sem entidade) e abre pendência de divergência entre duas grafias dela (documento que já tem). Ficou caro depois da `0119`: a entidade virou o EIXO da cobrança, então a mesma empresa passa a ser cobrada duas vezes e a `0120` gera duas perguntas ao cliente. |
| `migrations/0122_pergunta_em_portugues.sql` | **A pergunta que vai AO CLIENTE passa a ser escrita em português.** Medido no book da Canastra: as sugestões saíam dizendo *"Na DRE de 24,25"*, *"no faturamento de L36M"* e *"informa 16060 milhar"* — chave interna num texto que sai da casa. Três consertos: `fn_periodo_por_extenso` (período como se escreve — "2023 a 2025", "2025 (1º trimestre)", "um período de 36 meses"), `fn_valor_pt_br` ("R$ 16.060 mil") e — o que não é cosmético — `fn_anos_texto` **deixa de ler `L36M` como o ano 2036**: a janela móvel vencia a escolha de período da pergunta e entraria como exercício fechado em `fn_valores_por_ano`. O período passou também a ser o DA EMPRESA de que a pergunta fala, e não o mais recente do caso. |
| `migrations/0123_mutuos_a_natureza_fora_da_linha.sql` | **A checagem de mútuos para de depender de um enfeite do fixture.** A fixture de extração do `book-canastra` — o book DIFÍCIL, no repositório desde o PR #112 e nunca exercitado pela ingestão — abriu ZERO pendência num caso que planta UMA de propósito (R$ 240 mil a menos na planilha de mútuos). Três defeitos, todos na primeira rodada: (1) o filtro procurava a palavra "mútuo" no RÓTULO de cada linha, e nenhuma planilha real a repete ali — ela diz a natureza uma vez, no título; o resultado era `documento_ausente`, o único que não abre pendência, ou seja a divergência era declarada inexistente. Passou seis sessões porque o fixture de Vertentes escreve `"A → B — Mútuo"`, um enfeite do gerador que não vem de PDF nenhum. Agora a natureza é lida na linha OU na seção, e documento `MUTUOS` que não a nomeia em lugar algum conta inteiro. (2) A guarda que o comentário da `0117` prometia não existia: `v_lados_bp` era atribuída e nunca lida. Ela entra — e não como escrita, porque medi que interromper quando há os dois lados calaria a checagem onde a evidência é mais forte: lados que CONCORDAM estabelecem o saldo por dupla evidência (uma comparação, não uma por lado); lados que DISCORDAM são eles o achado. (3) Ligada a guarda, ela achou o terceiro: mútuo com SÓCIO não tem espelho no mandato (a contraparte é o quotista) e estava somado junto com o intragrupo — 14.000 na SPE do Canastra, que esconderiam os 240 atrás de um número 60 vezes maior. `fn_mutuo_com_socio` o separa. Fica anotado: mútuo com sócio passa a não ser conferido por ninguém — o par dele é o contrato com o quotista, e ninguém cruza isso hoje. |
| `migrations/0124_intragrupo_que_nao_e_mutuo.sql` | **A conferência das linhas intragrupo que NÃO são mútuo** (conta corrente rotativa, aluguel entre coligadas, fornecimento e frete entre coligadas), aberta desde a `0117`. A primeira ideia era errada e não foi usada: comparar a planilha contra o balanço, como a `0117` faz com mútuos, é comparar FLUXO com ESTOQUE — o documento que a taxonomia tem para as outras naturezas é `FAT_INTRAGRUPO`, faturamento do exercício. No book os números coincidem por construção (nada foi pago no ano), e escrever a checagem em cima disso daria teste verde sobre comparação sem sentido. **O que se confere é o ESPELHO:** todo saldo intragrupo aparece duas vezes no mandato — a receber num balanço, a pagar no outro —, e isso não precisa de segundo documento. **E o pareamento é pelo PAR DE EMPRESAS, não pela natureza**, que é a resposta à dificuldade anotada ("cada uma casa com uma conta diferente do balanço"): quem vende chama de *Contas a receber intragrupo - Comercial* e quem compra chama de *Fornecedores intragrupo - Indústria*; pela natureza elas nunca se encontram, pelo par sempre. A contraparte sai do próprio rótulo (`fn_contraparte_intragrupo`, o sufixo depois do separador contra a lista de entidades do caso) — medido: 6 de 6 rótulos intragrupo do book casados com a empresa certa, 3 de 3 de terceiro corretamente ignorados. Ficam fora, com o motivo escrito: mútuo (é da `fn_reconciliar_mutuos` — uma linha, uma régua), mútuo com sócio (não tem espelho), o COMBINADO (as linhas intragrupo dele são eliminações, que nomeiam as duas pontas) e par em que uma das empresas não entregou balanço (aí a falta de espelho é falta de documento, e o Portão 1 já cobra). |
| `migrations/0125_proveniencia_por_linha_e_ano.sql` | **A proveniência volta ao arquivo de comitê: página, confiança e aceite.** O §2.3 do diagnóstico de 11/08 já tinha medido a perda: antes do PR #109 cada célula de dado trazia documento, página, confiança e status de aceite; o #109 separou os dois exports (decisão certa) e a camada saiu junto. Achado ao consertar: **nem o nome do arquivo estava lá** — o que a nota mostrava é `documentos`, que a `fn_linhas_para_modelagem` monta como `array_agg(distinct tipo_taxonomia)`, ou seja o TIPO. A nota dizia *"Extraído de BALANCO, DF_AUDITADA"*; num mandato com oito balanços isso é a categoria, não a peça. **A mudança é na `fn_valores_por_ano`, e não na `fn_linhas_para_modelagem`**, e isso é o ponto: a segunda devolve UMA linha por (seção, rótulo), com a proveniência da ocorrência de maior módulo ENTRE OS EXERCÍCIOS — usada na nota de uma célula de 2023, ela descreveria a de 2025 com toda a convicção, e rastreabilidade que aponta para o lugar errado é pior que rastreabilidade nenhuma. `valor` NÃO foi reescrito (em empate de módulo com sinais opostos, outra forma de "maior módulo" escolhe outro número); a proveniência vem por join de volta na ocorrência que tem aquele valor, com desempate declarado. A nota melhora nas CATORZE abas de uma vez, porque `valorNaEscala` é o caminho único por onde valor de documento entra no arquivo. |
| `migrations/0126_golden_set.sql` | **O golden set passa a existir como DADO, e a regra de ouro do `Arquitetura do Sistema/1 Visão e Doutrina/01` passa a ser EXECUTADA.** A doutrina fecha com "nada de subir o dial de autonomia de um estágio interpretativo sem golden set e concordância medida" — e `fn_mudar_dial` (0041) conferia UMA coisa: o teto. Pedir N2 num estágio de teto N2 era aceito com um `p_motivo` em texto livre, e nada olhava para medição alguma, porque não existia onde olhar. Quem fez isso primeiro foi a própria 0041, que DECLARA no cabeçalho ter feito. É a forma dos defeitos que a `0123` achou (`v_lados_bp` atribuída e nunca lida), com a diferença de que a promessa aqui é do documento fundador. **Entram:** três tabelas de ground truth (rodada que CONGELA, documento com estrato e origem, rótulo por rotulador) mais `golden_campo`, todas append-only pelo par de políticas do `evento_auditoria`; as CINCO métricas do `Arquitetura do Sistema/2 Especificação/f0/06` como função; `natureza` e `base_do_nivel` em `estagio_autonomia`, que tiram da prosa a tabela de teto do `Arquitetura do Sistema/1 Visão e Doutrina/01` e a ressalva "declarada, não medida"; e o portão em `fn_mudar_dial`. **Três decisões:** o portão morde na subida que ALCANÇA N2/N3 (N1 é sugestão com revisão de 100%, e cobrar medição para exibir sugestão travaria o caminho que a doutrina manda percorrer — descer nunca pede nada); **golden sintético não sobe dial** (`origem`), senão rotular um book cujo GABARITO.json já se conhece mediria o instrumento e não o modelo; e a decisão declarada continua possível por `p_sem_medicao_porque` — um MOTIVO, não um booleano — que grava `mudanca_dial_sem_medicao` e deixa o nível como `declarada`. **E a taxa de falso-positivo da Classe A não precisa de rotulagem nenhuma:** o rótulo dela é o estado `rejeitada` que a `0106` define como "não procede (falso positivo do motor)", produzido por analista desde 11/08 e nunca somado. |
| `migrations/0127_o_dial_obedecido.sql` | **O dial passa a ser OBEDECIDO, e dois níveis declarados eram falsos.** A `0126` cuidou de como o dial MUDA; não cuidou de ele ser LIDO. A `0041` já havia diagnosticado isso e consertado para UM estágio — os outros sete continuavam sem leitor, então mudar o nível deles era validado, cobrado, gravado na trilha e **inerte**. E dois declaravam o nível errado: `classificacao_doc_checklist` dizia N1/0,95 e operava como **N2/0,70** (o número morava em `p_threshold` e em `THRESHOLD_AUTO` do `classifier.mjs`, duas réguas e nenhuma o dial); `reconciliacao_classe_bc` dizia N0 — *"não influencia decisão"* — e **abre pendência desde a `0015`**, que entra na fila e conta no Portão 2. **Entram:** `fn_dial_permite_auto` (leitor único da regra de auto-clear) e `fn_dial_influencia` (leitor de N0), com defaults seguros OPOSTOS de propósito — sem linha no dial, auto é negado (ausência de configuração não é permissão) e influência é concedida (calar achado por falta de configuração esconde problema); a classificação tirando o limiar do dial, com o parâmetro como queda para banco sem a linha semeada; e a Classe B/C respeitando o nível. **O ramo que faltava:** silenciar um estágio com divergência presente marcaria a pendência aberta como "resolvida pelo sistema" — afirmando que o problema acabou quando o que acabou foi o direito do estágio de falar. Agora registra `reconciliacao_em_sombra` e deixa a pendência em paz. Não muda comportamento nenhum: declara o que o sistema já fazia. |
| `migrations/0128_classificacao_contabil_sombra.sql` | **A classificação contábil passa a EXISTIR, em N0 (sombra) — o oitavo estágio do MVP, que tinha zero linha de código.** O `Arquitetura do Sistema/1 Visão e Doutrina/03` o lista entre os que "existem na v1 de produção", o `Arquitetura do Sistema/2 Especificação/05` o especifica por inteiro e a `0002` o semeia no dial em N0; `grep` por `classe_contabil` devolvia UMA ocorrência, a coluna que a `0126` criou no golden set para um rótulo que ninguém produzia. É a forma INVERSA do defeito da `0127`: lá o dial subestimava a realidade, aqui ele afirmava a existência de um estágio. **Decide por regra determinística sobre rubrica** (condição 2 do `Arquitetura do Sistema/2 Especificação/05`), sem IA e sem custo por documento: catálogo versionado com `justificativa` NOT NULL por linha, e o que ele não conhece cai em `revisar_manual`. **Medido: 207 de 231 rubricas reais classificadas (89,6%)**, e o seed foi corrigido DUAS vezes pela medição (faltava a receita; faltava "matéria-prima" no singular e a chave de mês do FATURAMENTO_24M). **Três decisões:** a regra só roda em linha de RESULTADO — rodar em tudo daria 3.195 pedidos de revisão contra 527 que cabem, e ausência de sugestão é como se diz "não se aplica"; a taxonomia é TABELA e não enum, para um sexto rótulo custar uma linha de seed; e o auto-aceite do `Arquitetura do Sistema/2 Especificação/05` NÃO foi implementado porque o próprio documento o proíbe (teto N1 para sempre) — código morto que alguém ligaria por engano. **O que faz valer em sombra:** `fn_classe_contabil_concordancia` transforma o override humano no sinal de calibração da F4 e nomeia as rubricas que mais erram, sem rotulagem dedicada. Em N0 não abre pendência, não toca em `campo_extraido` e não entra em caminho de export. |
| `migrations/0129_transcricao_humana_assistida.sql` | **O fechamento nº 2 do `Arquitetura do Sistema/1 Visão e Doutrina/01`, que era o único dos oito sem código** — *"gate de captura com saída: input ilegível → transcrição humana assistida, nunca dead-end de pendência infinita"*. O gate existia e a saída existia em outra forma (reenviar, rejeitar); a transcrição em si, não. **E a mesma migration fecha a contaminação que ela criaria:** linha transcrita mora em `campo_extraido` do lado das que a IA leu, e `fn_golden_campos` mede a extração comparando essa tabela com o rótulo do golden set — sem distinção, a primeira transcrição inflaria a medição da autonomia, subindo justamente nos documentos difíceis (que são os transcritos). Medido no religamento: sem o filtro, as duas linhas transcritas voltam como `n_exato = 2`, acerto perfeito da IA sobre número que ela nunca leu. **Três decisões:** a transcrição é VERSÃO NOVA (doutrina da `0026`), com a versão ilegível preservada; as guardas de extração NÃO rodam (elas pegam alucinação de modelo, e "quatro contas com o mesmo valor" é rotina num balanço com contas zeradas) e a confiança fica NULA, porque não existe autoavaliação de pessoa; e a linha nasce ACEITA sem furar a anti-ancoragem, porque o humano é a FONTE e não quem confirma máquina. A pendência de ilegibilidade fecha com o NOME de quem transcreveu. |
| `migrations/0130_golden_set_rotulavel.sql` | **O golden set passa a ser ROTULÁVEL.** A `0126` construiu o conjunto inteiro do lado da LEITURA — quatro tabelas, as cinco métricas do `Arquitetura do Sistema/2 Especificação/f0/06`, o portão `fn_golden_suficiente`, a regra de ouro executada em `fn_mudar_dial` — e nenhuma função de escrita: abrir rodada, incluir documento ou gravar rótulo só era possível com `insert` à mão, e congelar era um `update` na coluna certa. O portão estava construído e não havia estrada até ele — o mesmo defeito que a `0126`, a `0127` e a `0128` corrigiram uma camada acima. **A decisão que governa o desenho é a rotulagem CEGA:** `fn_golden_linhas_para_rotular` devolve as rubricas que a extração achou SEM os valores. Rotulador que vê o palpite da máquina produz conferência, não ground truth, e conferência tem viés de confirmação — a métrica sobe sem nada melhorar e o dial sobe com ela, o sistema certificando a si mesmo. **E devolve as rubricas** porque a rubrica é só a chave de casamento de `fn_golden_campos`: esconde-las faria o rotulador digitar a grafia dele, o par não casaria, e a linha entraria como AUSENTE — a família de defeito mais grave do placar, cobrada da máquina por uma diferença de datilografia. **A contrapartida obrigatória:** `fn_golden_rotular_campos` ACEITA rubrica fora da lista, porque é o único caminho pelo qual a perda silenciosa chega a ser medida, e REVELA o casamento só depois de gravar — avisar durante a digitação convidaria a procurar a grafia que casa. Recusa retornada em tudo: tipo fora do catálogo (typo em rótulo append-only vira falso negativo permanente no F1), rótulo vazio (contaria na cobertura sem medir nada), rodada congelada (com o caminho de saída: rodada nova), rodada sem rótulo no congelamento. E `fn_golden_congelar` avisa quando houve **um rotulador só**: sem segundo rotulador nada é excluído do placar por "humanos discordam", o documento ambíguo conta como erro da máquina, e o número que sai é um PISO da qualidade real — conservador é o lado certo para errar, e mesmo assim precisa estar escrito. |
| `migrations/0131_instalacao_que_se_declara.sql` | **A instalação passa a se DECLARAR.** O `ESTADO.md` carregava, espalhados por 1.400 linhas, recados corretos que nada executa — *"a `0114` precisa ser aplicada no Supabase"*, *"para os três indicadores acenderem: aplicar a `0115` e **reimportar** o workflow"*. Quem abre o portal não lê o `ESTADO.md`; quem lê o `ESTADO.md` não está com o portal aberto. E o sintoma no meio é o pior possível para um sistema que promete honestidade sobre os próprios números: **a tela não quebra** — mostra um traço, ou zero, ou trata todo mandato como ativo, e parece funcionando. Mesma família do corte silencioso de leitura da `0028`. `instalacao_requisito` é o catálogo (dado, não lista dentro de função — lição do limiar 0.95 da `0041`), e `porque` guarda o **SINTOMA VISÍVEL**, não a descrição da migration: "0115 ausente" não serve para quem não tem o repositório na outra aba; "os indicadores de custo mostram um traço" serve. `fn_instalacao_conferir` sonda por `to_regclass`/`to_regproc` (resolvem pelo `search_path` e devolvem NULL em vez de erro) e **sobrevive ao objeto ausente**: sem o guarda, o `count(*)` num seed cujo tabela não existe derrubaria o painel que existe para dizer o que fazer. **O que ela NÃO promete, escrito no cabeçalho:** "o objeto existe" não é "a migration foi aplicada corretamente" — `create or replace` sobre corpo velho passa igual. O que ela garante é o contrapositivo, que é a parte útil: **objeto ausente é migration ausente.** O tipo `comportamento` é o único que não sonda catálogo: "o workflow do n8n foi reimportado" só se prova pelo EFEITO — a tabela que aquele nó grava tem linha. **A TELA SAIU EM 21/08** (decisão do dono): `/instalacao` e o aviso no topo do painel foram removidos do portal, e o catálogo, as duas funções, os `grant`s e a suíte `Supabase/test/instalacao.test.sql` ficaram intactos — a conferência passa a ser por SQL, `select * from fn_instalacao_conferir() where not presente`, feita por quem aplica migration em vez de por quem abre um mandato. |
| `migrations/0132_a_sonda_nao_cresce_com_o_dado.sql` | **A sonda de instalação para de crescer com o dado que ela mede.** A `0131` põe `fn_instalacao_resumo` no topo do painel — a tela mais carregada da casa — e trouxe dois custos, ambos meus. (1) `count(*)` por requisito de seed: barato hoje porque as tabelas semeadas são pequenas, MAS um dos requisitos é `lote_execucao`, que ganha uma linha por execução de ingestão e **nunca para de crescer**. A pergunta é "tem ao menos N linhas?" e `count(*)` varre tudo para devolver um número que ninguém usa além da comparação. **Medido com 50.000 lotes inseridos (~um ano de operação): `count(*)` sozinho 5,9 ms, a sonda inteira 7,9 ms, a forma limitada 0,218 ms — 27× e CONSTANTE, contra linear.** Depois da migration a sonda inteira caiu para **0,5 ms** com as mesmas 50 mil linhas. (2) `information_schema.columns` para requisito de coluna: view sobre `pg_attribute` com junções e checagem de privilégio por linha — **3,4 ms contra 0,25 ms** do `pg_attribute` direto, 14× para responder a mesma pergunta. **Nenhuma resposta muda:** os 13 vereditos são idênticos e os asserts de resultado do teste da `0131` rodam sem uma linha alterada — é custo, não comportamento. A forma limitada responde o mesmo porque `count(*) from (select 1 from t limit criterio)` devolve `min(real, criterio)`: igual ao critério significa "ao menos N"; menor que ele é o total EXATO (a varredura parou antes do limite, logo passou por tudo) — e é justamente no caso ausente que o número informa algo, porque "3 linha(s)" com critério 8 diz que o seed rodou pela metade. |
| `migrations/0133_a_secao_que_nao_fecha.sql` | **A seção passa a ter de fechar, e o defeito foi ABERTO por uma correção nossa.** `fn_reconciliar_ativo_passivo_pl` prefere o TOTAL IMPRESSO e só soma a seção quando o total não existe. Até a `0116` isso era conservador — o prompt não trazia os totais, a checagem SOMAVA as contas, e uma conta perdida quebrava a soma. A `0116` mandou o total impresso chegar como LINHA (e estava certa: sem ele o export não tem contra o que conferir), e com isso **os dois lados da checagem viraram totais impressos — que fecham por construção**, porque o balanço do cliente bate consigo mesmo. Hoje, apagar metade das contas do Ativo Circulante não abre pendência nenhuma: "TOTAL DO ATIVO" continua batendo com "TOTAL DO PASSIVO + PL", `lote_integro` fica verde, e a Modelagem recebe uma seção com buraco. Mesma família da `0028` e do fatiamento desligado: o dado some e o placar não muda. **O que torna a correção barata é que a árvore já está no banco:** `campo_extraido.secao` guarda o PAI IMEDIATO, então "os filhos de P" é pergunta EXATA (as linhas cuja `secao` é a `chave` de P), não casamento por semelhança — e a identidade que todo demonstrativo obedece é **pai = soma dos filhos diretos**, que a extração teve de satisfazer sem saber que seria conferida. Pega linha perdida, valor errado, linha duplicada e sinal invertido, e **localiza na seção** — quem lê "Estoques não fecha por 2.350" reextrai um bloco, não o documento. **As quatro guardas contra falso positivo** (pendência sem defeito custa mesa e não compra qualidade): rótulo duplicado vira pré-condição e fica com a `0105` (duas pendências para um defeito é dois toques onde cabe um); unidade mista não se soma, e o filho divergente NÃO é descartado em silêncio; linha derivada não é parcela; e **a tolerância é de ARREDONDAMENTO (~0,5·(n+1)), não percentual** — 0,5% de um Ativo de 95.780 é 479, deixaria passar a conta de meio milhão que a checagem existe para achar. **O que ela não faz, e está anotado:** não distingue "a extração errou" de "o documento do cliente não fecha" — as duas quebram a mesma identidade e a descrição nomeia as duas hipóteses em vez de escolher errado. Vale só nos demonstrativos, onde a árvore é completa por construção; anexo detalha PARTE de um saldo e está certo em não fechar. |
| `migrations/0134_sazonalidade_nao_e_premissa_sem_valor.sql` | **Sazonalidade deixa de ser "premissa sem valor", e o "pronto" da Modelagem para de travar para sempre.** `fn_conferir_modelagem` listava toda premissa ativa com `valores` vazio e exigia a lista VAZIA para dar `pronto`. O critério está certo para quase tudo — `SGA_PCT` sem percentual É premissa pela metade —, mas TRÊS premissas do catálogo têm `formula = 'curva_mensal'` (SAZONALIDADE, CRONOGRAMA_FISICO, PARADA_MANUTENCAO) e nelas **`valores` vazio é o estado CERTO**: a curva sai de `fn_sazonalidade_do_caso` (0040), derivada do documento mensal, não digitada. **Medido antes da migration:** vincular a sazonalidade levava `sem_valor` de `[SGA_PCT]` para `[SAZONALIDADE, SGA_PCT]` — o analista faz a coisa certa e a tela passa a cobrar uma ação que NÃO EXISTE, sem campo para preencher. A saída que sobra para quem tem pressa é desvincular a sazonalidade e perder a distribuição mensal para calar o aviso. O critério passa a ser a FÓRMULA do catálogo e não uma lista de códigos, para a quarta curva mensal não exigir editar a função — mesma lição do limiar 0.95 dentro da `fn_registrar_campos_extraidos` (0041). **E o caso ruim DE VERDADE não foi calado:** curva ativa num caso SEM documento mensal ganhou nome próprio em `sazonalidade_sem_curva`, que informa e **não bloqueia** — os números ANUAIS continuam certos, só o rateio dentro do ano fica liso, e travar o portão por isso devolveria o atrito pela porta dos fundos. |
| `migrations/0135_a_operacao_passa_a_ser_vista.sql` | **A operação passa a ser vista: o que já estava gravado deixa de ser cego.** O diagnóstico de 11/08 chamou isto de "zero observabilidade" — *"uma falha em produção só aparece quando alguém abre a tela"* —, e o portal tem oito `console.error` e nenhuma métrica. **O dado já existia:** a `0115` criou `lote_execucao` e o nó `Gravar Uso do Lote` a alimenta desde então, com documentos, falhas, custo real, custo estimado, tokens, linhas e cobertura. Nunca foi lido. Não faltava instrumentação, faltava a pergunta. `fn_operacao_lotes` devolve uma linha por execução com os **alertas já decididos NO BANCO** (repetir a regra na tela criaria duas réguas sobre a mesma quantidade), e `fn_operacao_resumo` faz o cabeçalho. **Os quatro alertas:** cobertura NULA — o mais importante e o menos óbvio, porque não é cobertura baixa e sim a guarda não ter opinado sobre o lote; documento com falha; documento sem medição (nem falha, nem sucesso); e custo acima de **1,5× a estimativa daquele lote** — a régua é razão contra a previsão, não teto em dólar, que envelheceria na primeira mudança de preço. **Duas decisões que o teste trava:** a cobertura publicada é **mediana** e não média (média mistura lote de 40 documentos com lote de 1 e não descreve nenhum dos dois); e o resumo publica `dias_desde_o_ultimo`, porque **silêncio também é estado** — "0 alertas" sem nenhuma execução afirmaria uma saúde que ninguém mediu. |
| `migrations/0136_veredito_de_producao.sql` | **O veredito que o trabalho normal já produz passa a contar para o dial, declarando que é PISO.** A saída B do B3 (decisão do dono, 21/08). O estado que ela resolve é aritmético: a `0126` pôs a regra de ouro dentro de `fn_mudar_dial` (estágio interpretativo só sobe a N2/N3 com concordância medida contra rodada de golden set **congelada**), e a sessão 53 removeu o fluxo de rotulagem manual. Sem rotulagem nenhuma rodada congela; sem rodada nenhum interpretativo sobe. O sistema passou a se recusar a certificar a si mesmo — correto, e terminal. A saída: **cada confirmação ou correção do analista na tela de revisão já é um rótulo**, e a casa já lia isso em dois lugares (`fn_golden_classe_a`, `fn_classe_contabil_concordancia`). `fn_veredito_producao` generaliza os dois numa porta só, despacha por estágio e **RECUSA o que não sabe medir** em vez de devolver zero — "não medi" e "medi e deu ruim" são frases diferentes, e a segunda não se inventa a partir da primeira. **O que ela não finge ser, e está no retorno, no comentário da coluna e na tela:** quem emite o veredito VÊ o palpite da máquina, então o viés de confirmação empurra o número para cima e o que se mede é um PISO. Por isso `base_do_nivel` ganha valor PRÓPRIO — `medida_por_veredito`, que vale menos que `medida` e mais que `declarada` — e o assert mais importante da suíte é justamente que ela **nunca** vira `medida`: no dia em que rótulo cego e rótulo enviesado ficarem indistinguíveis na coluna, a honestidade do dial acaba sem sintoma, porque o número é o mesmo. O `n_minimo_veredito` entra em **30** contra os 20 do `Arquitetura do Sistema/2 Especificação/f0/06`, porque rótulo enviesado precisa de mais massa para dizer a mesma coisa, e é dado: muda por update. O teto por natureza do estágio segue inegociável. |
| `migrations/0137_a_promocao_automatica_do_dial.sql` | **O dial passa a subir SOZINHO quando o veredito de produção alcança o critério, e isso exige quatro travas.** Decisão do dono (21/08). O que muda na doutrina, dito sem rodeio: a `0126` pôs a regra de ouro dentro de `fn_mudar_dial` para impedir exatamente que o sistema se autorizasse a si mesmo, e a `0136` abriu uma porta medida que ainda exigia mão humana. **Esta tira a mão.** É aceitável por uma razão e só por ela: o que a automação alcança é **N2** e nunca N3, e em N2 todos os fechamentos fail-safe do `Arquitetura do Sistema/1 Visão e Doutrina/01` continuam valendo — pendência abre, guarda dispara, o Portão 2 pede aceite onde a doutrina pede. **As quatro travas:** (1) sobe UM nível e para em N2, porque piso enviesado não sustenta o topo; (2) **o freio gruda** — humano que BAIXA o nível desliga a automação daquele estágio na hora, senão o freio duraria até o próximo veredito e a máquina desfaria a decisão de quem o puxou, que é o pior defeito possível num mecanismo de segurança porque ele parece funcionar; (3) interruptor por estágio em DADO (`auto_promocao`), desligável por `update`; (4) tudo na trilha com ator próprio (`sistema:auto_dial`) e a medição que autorizou anexada. A promoção passa pela própria `fn_mudar_dial` em vez de dar `update` na tabela, para não escapar de guarda nenhuma e para que guarda nova acrescentada lá passe a valer aqui sem ninguém lembrar de copiar. O gatilho é `after insert on decisao` (toda fonte de veredito grava lá) e **jamais derruba a ação de quem o disparou**: erro dentro dele vira NOTICE, porque o analista não pode perder a rejeição de uma pendência por causa do dial. |
| `migrations/0138_a_guarda_que_estourava.sql` | **`fn_veredito_producao` levantava exceção sempre que NÃO havia veredito para medir** — o estado de instalação nova e de todo estágio que ninguém revisou. A causa é ambiguidade de resolução de operador do Postgres: `v_falhas text[] := v_falhas || format(...)` funciona porque `format()` devolve `text` DEFINIDO e o planejador escolhe `anyarray || anyelement`; `v_falhas || 'frase com espaços'` tem o literal como `unknown`, aí `anyarray || anyarray` também serve, o Postgres prefere essa e morre lendo a frase como literal de array. Duas linhas de `||` no mesmo bloco, uma funciona e a outra não. **O que quebrava:** a promoção automática da 0137 roda no gatilho de `decisao` e captura exceção virando NOTICE — em banco novo ela morria em TODA inserção, em silêncio, e o dial nunca subiria; `fn_mudar_dial(..., p_por_veredito := true)` estourava em vez de recusar; a tela de autonomia quebraria no primeiro acesso de ambiente limpo. **Em produção estava DORMENTE** (medido em 22/08: 96 vereditos de classificação e 8 de classe A, então `v_conc` não era nula), e dormente não é inofensivo — bastava ambiente novo ou expurgo das decisões para acordar. A correção é o `::text`. |
| `migrations/0139_reafirmar_nao_apaga_medicao.sql` | **Reafirmar o nível que o estágio já tem apagava a medição que o autorizou.** Achado rodando o sistema, e só alcançável depois da 0138 (enquanto `fn_veredito_producao` estourava, a promoção automática nunca acontecia). Medido: `N1/nao_se_aplica` → promoção automática deixa `N2/medida_por_veredito` com `medicao_em` e `medicao_resumo` → uma chamada de `fn_mudar_dial` pedindo **o mesmo N2** devolve `N2/declarada` com os dois campos NULOS. Causa: `v_sobe_para_autonomia` exige `p_nivel > v_nivel_ant`, então reafirmar não é subir, o bloco que mede é pulado e `v_base` fica no default `'declarada'`. **Por que importa:** `base_do_nivel` é o campo que toda tela lê para dizer se o nível é MEDIDO ou só DECLARADO — trocá-lo faz o sistema subdeclarar a própria evidência, e apagar `medicao_resumo` destrói a trilha que a trava 4 da 0137 promete guardar. **Alcançável na operação normal:** `fn_mudar_dial` é também como se ajusta `limiar_auto_clear`, então mexer no limiar sem mudar o nível apagava a medição. A correção é `v_mede`: os campos de medição só são reescritos quando há base nova ou quando o nível de fato mudou. |
| `migrations/0140_a_coluna_de_dimensao_nao_e_valor.sql` | **A guarda de padrão suspeito acusou o ANO.** Achado na rodada v47 (24/08), no `19_Faturamento_Intragrupo`: a guarda abriu pendência dizendo que "4 contas diferentes, na MESMA coluna, vieram com o MESMO valor material (2023.00) — padrão típico de fabricação/alucinação". É falso positivo, e o número denuncia sozinho: 2023 é o ano, a coluna é `Exercício`, e o valor se repete nas quatro linhas de 2023 porque é assim que um exercício funciona — os valores monetários das mesmas linhas estavam CERTOS e somavam certo (1.900 + 3.400 + 720 + 1.100 = 7.120, igual ao total impresso). **Por que a guarda não viu:** a `0022`/`0034` já tinha aprendido que comparar valores de colunas diferentes gerava falso, e agrupou por (valor, entidade_coluna, periodo_coluna); o que ela não previu é que uma COLUNA pode não ser de valor nenhum — num documento tabular `Exercício`, `Quantidade`, `Natureza` e `% do total` ocupam o mesmo `periodo_coluna` que "Valor" ocupa e caem no mesmo teste de materialidade. Estava certa sobre "mesma coluna" e errada sobre o que é uma coluna de valor. Nasce `fn_coluna_de_dimensao` e `fn_contas_repetindo_valor` passa a ignorá-las. **A correção é por lista explícita, não por heurística, porque errar para cada lado custa diferente:** falso positivo manda conferir à mão um documento correto e queima a confiança na fila; falso NEGATIVO deixa passar alucinação — então coluna que não estiver na lista continua sendo checada. **Medida contra as 38 versões da v47 antes de aplicar**, em transação revertida: o único documento que muda de estado é o 19, e o maior `n_contas` do lote passa a ser 3 contra um limiar de 4 — a guarda continua com folga, não foi silenciada. |
| `migrations/0141_o_limiar_que_nunca_excluiu_nada.sql` | **O limiar de auto-aceite nunca excluiu uma linha sequer, e a trilha passa a dizer isso.** Medido em 24/08 sobre as 15.030 linhas já gravadas: a confiança auto-reportada pela IA assumiu TRÊS valores em toda a história do banco — 0,95, 0,99 e 1 — e o limiar de `extracao_linhas_financeiras` é **0,95**. O limiar é exatamente o PISO do que o modelo emite, então `confianca >= v_limiar` é satisfeito por toda linha que já existiu: 14.470 das 15.030 foram auto-aceitas, e as outras 560 foram barradas por GUARDA, nunca por confiança. A guarda de baixa confiança (Sinal 2, limiar 0,70) nunca disparou pelo mesmo motivo — zero linhas abaixo de 0,70 na história inteira. Dois mecanismos de segurança inertes, e nenhuma tela dizendo. **NÃO muda comportamento** (decisão do dono: bloquear o auto-aceite mandaria ~96% das linhas para revisão humana, e isso é decisão de operação, não de engenharia); muda que a `decisao` de auto-aceite passa a registrar `n_excluidas_pelo_limiar` e `limiar_discriminou`, e quando o limiar exclui zero o motivo diz com todas as letras que não discriminou nada. **É um patch com âncoras, não uma reemissão inteira**, e o comentário do arquivo explica: a função tem 200 linhas e mudam duas — transcrevê-la à mão trocaria um risco pequeno e barulhento (âncora não encontrada, que levanta exceção) por um grande e silencioso (um caractere errado na função que grava toda linha extraída). O patch confere o resultado depois de aplicar. |
| `migrations/0142_tipo_incorreto_precisa_de_divergencia.sql` | **A pendência `tipo_incorreto` acusava sem ter divergência para acusar.** Achado na v48 — a primeira rodada em que o diagnóstico voltou a rodar depois da correção do fio, e dois dos três achados dele eram falsos: o doc 27 dizia "sugere NOTAS_EXPL (registrado como NOTAS_EXPL)", o MESMO tipo dos dois lados, e o doc 28 dizia "sugere ? (registrado como (nenhum))", comparando nada com nada. A causa é a primeira perna da condição: `tipo_confirma = false` disparava sozinha, e o modelo diz "não confirmo" também quando reconhece o mesmo tipo com outro nome ou quando não sabe o que o documento é — nos dois casos não há nada que um humano possa fazer. Agora exige tipo sugerido DIFERENTE do registrado, ou recusa sobre documento que TEM tipo. Recusar sem sugerir, em documento sem tipo, já tem dono: `classificacao_pendente` — que o doc 28 abriu em paralelo, duas pendências para o mesmo fato. **Medida antes de aplicar** contra as três pendências reais da v48: mantém o achado verdadeiro (doc 14, BALANCO com conteúdo COMBINADO) e derruba as duas falsas. |
| `migrations/0143_hierarquia_achatada_nao_e_divergencia.sql` | **A checagem de seção acusava o DOBRO, e 100% era falso.** Achado na v48: a razão `soma_filhos / pai_valor` era exatamente **2,0000** nas quinze seções divergentes, em seis documentos. A causa não é a checagem — o balanço real tem TRÊS níveis (total da seção → subtotal de grupo → folhas) e `campo_extraido.secao` vem ACHATADA, com subtotais e folhas carregando a mesma seção; `fn_papel_linha` devolve `conta` para `Disponível`, então a soma conta os dois níveis. O fixture do `book-vertentes` tem dois níveis e por isso passava. Esta migration **não conserta a hierarquia** (isso é na extração, `secao` tem de trazer o grupo imediato): ela faz a checagem reconhecer a assinatura aritmética e declarar `hierarquia_achatada` em vez de acusar. Importa porque a pendência dizia "a extração perdeu/errou linha" sobre uma extração **perfeita** — conferida contra o `GABARITO.json`, os 38 documentos batem no centavo. Mandar o analista abrir o PDF para procurar um erro que não existe queima a confiança na fila inteira. |
| `migrations/0144_duplicidade_e_entre_documentos.sql` | **A duplicidade de rótulo acusava a hierarquia do próprio documento.** Medido na v48: dos 33 pares candidatos, **33 estavam no MESMO documento** e 32 deles em linhas vizinhas (`ordem` a distância 1) — "Disponível"="Caixa", "Empréstimos"="FINAME - longo prazo", "Provisões"="Provisão para contingências". É subtotal de grupo seguido do seu único componente, não conta transposta duas vezes. O filtro `subtotal_de` da 0105 previa exatamente isso, mas depende de `secao` trazer o grupo IMEDIATO — e ela vem achatada (mesma causa raiz da 0143). O par passa a exigir que **nenhum documento contenha os dois rótulos**: o dano que a 0105 existe para achar é interdocumental por definição (o balanço e o balancete somando o mesmo fato duas vezes), e dentro de um documento a demonstração é consistente por construção. Derruba 6 pendências falsas sem perder achado verdadeiro — o único par entre documentos distintos do caso real já caía nos filtros existentes. |
| `migrations/0145_o_conceito_que_mora_na_coluna.sql` | **Em documento matricial o conceito é a COLUNA, e o localizador só sabia olhar para a linha.** Três pendências da v48 cobravam dado que está no banco, extraído e correto: juros por contrato (14.802.000), saldo de mútuo (16.060), faturamento intragrupo. No mapa de dívida a `chave` é o contrato e `periodo_coluna` é `"Juros do exercício (R$)"` — a palavra existe, só não na linha. Acrescenta o quarto modo `contra = 'coluna'` ao localizador, casando contra `periodo_coluna` (onde o dado **já está** — coluna nova exigiria reextrair 38 documentos), e cadastra os três localizadores. Uma delas tinha consequência: `juros_por_contrato` alimenta a reconciliação `despfin_dre_vs_divida`, que ficava em `precondicao_nao_satisfeita` — a quarta pendência da v48 com a mesma raiz. |
| `migrations/0146_a_entidade_que_o_documento_nunca_declarou.sql` | **Uma entidade fantasma cobrava um balanço que não existe.** Três pendências da v48 exigiam "Ativo Total", "Caixa e equivalentes" e "Passivo + PL" da entidade `GRUPO CANASTRA` — que não é empresa: o grupo não levanta balanço, as seis operadoras levantam. Medido: os documentos 13 e 14 (balanços COMBINADOS) declaram **oito** colunas de entidade e trazem 7 linhas **sem coluna** (cabeçalhos e totais que atravessam a matriz); para elas o fallback `coalesce(entidade_coluna, ent_doc)` usava a capa do documento. Sete linhas bastaram para inscrever o grupo no eixo de quem deve um balanço. O fallback não está errado, está fora de lugar: num documento de uma empresa a capa é a única fonte; num de várias, o documento já disse de quem é cada número. Critério **estrutural** (quantas colunas de entidade o documento declara), não lista de nomes — dos 38 documentos exatamente dois têm mais de uma, e são os dois combinados. `GRUPO CANASTRA` sai de BALANCO e COMBINADO e **continua** em MUTUOS, SITUACAO_FISCAL e FAT_INTRAGRUPO, que são de fato do grupo. |
| `migrations/0147_a_sonda_enxerga_o_corpo_da_funcao.sql` | **A sonda de instalação enxergava 13 marcadores e parava na `0130` — enquanto o banco chegava na `0146`.** Dezesseis migrations sem cobertura, e ninguém foi avisado: nada acusa um catálogo que fica para trás. Pior, a fatia de fora era a CARA: das 16, só sete criam objeto novo; as outras nove apenas republicam corpo de função — a `0142`, a `0143`, a `0144`, a `0145`, a `0146` —, e todas elas mudam **o que o sistema acusa**. Um banco sem elas abre pendência falsa e parece perfeitamente instalado, porque cada função que elas corrigem existe. Acrescenta o tipo `corpo` (o requisito exige que um trecho apareça em `pg_get_functiondef`, único jeito de distinguir correção aplicada de homônima com corpo velho — a cegueira que a própria `0131` declarou de si mesma), os 20 requisitos das `0131`–`0146`, e `instalacao_cobertura`: uma linha dizendo até que migration o catálogo foi revisado, com o `Supabase/test/run.sh` reprovando quando ela fica para trás. **Medido:** num banco montado sem a `0142`, a `0143` e a `0146`, a sonda nomeia as três, com o detalhe "a função existe, mas o corpo é ANTERIOR a esta migration"; antes da `0147` o mesmo banco se declarava instalado. |
| `migrations/0148_o_fato_que_o_documento_diz_em_texto.sql` | **As Notas Explicativas e o Parecer do Auditor entravam, eram classificados e ficavam mudos.** Medido no ANEXO A.2 da v48: dos 38 documentos, quatro não produzem linha nenhuma e os quatro estão CERTOS (não têm tabela) — mas dois carregam os fatos que um comitê de crédito lê primeiro. O `33_Notas_Explicativas` declara, em texto, o covenant rompido e a reclassificação que **explica o Passivo Circulante em 112.372**; o `34_Relatorio_do_Auditor` traz **opinião com ressalva** e **incerteza sobre continuidade operacional**. Nenhum dos dois chegava ao portal — nem como linha, nem como alerta. Acrescenta `fato_tipo_catalogo` (9 tipos, com severidade e o porquê que a tela mostra), `documento_fato`, `fn_registrar_fatos` e `fn_fatos_do_caso`. **Duas decisões de produto, escritas no cabeçalho:** fato material NÃO é pendência (pendência significa "há algo a corrigir", e covenant rompido não é defeito do dado — é o dado), e o fato carrega o **trecho literal** do documento, `not null` e com mínimo de 20 caracteres — resumo do modelo é afirmação, frase copiada é evidência, e este alerta é o que vai ao comitê. Nenhuma chamada de IA nova: o modelo já lê o PDF inteiro, e passa a ter para onde mandar o que leu em prosa. |
| `migrations/0149_o_fato_material_endurecido.sql` | **Auditoria adversarial da `0148`: sete defeitos, cinco silenciosos.** (1) O RLS RECUSAVA a gravação — `documento_fato` só tinha política de `select` enquanto `campo_extraido` tem `authenticated_all`; funcionava por acidente da credencial. (2) Uma **página absurda** (`99999999999`) derrubava a função — e como ela roda na MESMA query do diagnóstico, o documento perdia o **diagnóstico inteiro**. (3) Versão inexistente, idem. (4) **Reenviar um arquivo fazia os fatos sumirem da tela**: a versão era escolhida por `n_versao desc` sem perguntar se tinha sido lida — e a correção óbvia (`fn_versao_com_extracao`) era a ERRADA, porque ela exige linha em `campo_extraido` e os documentos 33/34 extraem zero linha por natureza; daí `documento_versao.fatos_avaliados_em`. (5) A **ordem da lista era indeterminada** (três fatos no mesmo `insert` compartilham um `criado_em`). (6) `confianca` nunca recebeu valor e **sai**. (7) Fora do banco: `Juntar Blocos` descartava os fatos dos blocos 2..N em documento fatiado. |
| `migrations/0150_a_premissa_sai_do_realizado_certo.sql` | **A soma do realizado somava o que não se soma.** A rodada comparativa do Canastra gravou `PMR = 348,6 dias`, `PME = 177,5`, `CUSTO_VARIAVEL = 287,7%` e `SGA_PCT = 83,2%` como premissa, com `origem = 'historico'`. Três causas somadas: (1) o **total da DRE somando com as próprias componentes** — 177.077 do CPV mais os 177.133 das cinco componentes dele mais 56.539 de outra empresa = os 410.749 que a bolsa de custos usou; `fn_papel_linha` é `immutable` e vê um rótulo por vez, então o discriminador (o total bate com a soma das outras contas da mesma seção e exercício, dentro de 1%) passa a viver em `fn_linhas_do_realizado`, que vê o documento inteiro. (2) A **abertura analítica somando por cima da conta que ela abre** — os 312 sacados do aging, os itens da posição de estoque, os bancos do extrato, o balancete inteiro: `taxonomia_tipo_documento.abertura_analitica` passa a DECLARAR quais tipos são abertura, e o COMBINADO entra na lista pelo mesmo motivo que o `book-araucaria` existe para testar (ele é a soma das empresas). (3) O caso tem **oito empresas e o modelo projeta uma**, e a soma ignorava `caso_modelagem.entidade`. Mais `fn_exercicio_da_coluna`, que separa a coluna que nomeia exercício (`31/12/2024`) da que não nomeia (`Saldo`, `Crédito`, `Ticket médio`) — é ela que permite projetar pela MÉDIA de vários exercícios em vez do último, e o último ano de uma empresa em reestruturação é o pior dela. `fn_linhas_para_modelagem` não muda: ela alimenta a lista da tela e a conferência do `pronto`. |
| `migrations/0151_o_desempate_entre_documentos.sql` | **O desempate entre dois documentos do mesmo período já existia; ele era silencioso, e escolhia o maior.** A `0150` resolve a mesma conta vinda de duas fontes com `array_agg(... order by abs(valor) desc)` — inofensivo quando as duas concordam, e "fica com o maior" quando discordam, que num caso de reestruturação é escolher sempre o número que infla o ativo. É exatamente a armadilha central do `book-araucaria`: um combinado preliminar que infla o ativo do grupo em 32.800 (R$ mil) **e fecha**, porque ativo e passivo caem na mesma medida quando um par intragrupo deixa de ser eliminado — contra um número que fecha, `fn_reconciliar_ativo_passivo_pl` não dispara. Três movimentos: (1) `taxonomia_tipo_documento.autoridade` passa a DECLARAR o peso de evidência de cada tipo (DF auditada 60 · demonstrações 50 · notas 40 · combinado 30 · balancete 20 · razão 10 · o resto 0 = não decide), como a `0150` fez com `abertura_analitica`; (2) `fn_conflitos_do_caso` acha o conflito e nomeia vencedor, perdedor, diferença e CRITÉRIO por extenso — `fn_reconciliar_versoes_do_periodo` registra e abre pendência, sem apagar nada; (3) `fn_linhas_do_realizado` desempata por autoridade, com o maior módulo da `0042` como último recurso. No EMPATE nada muda de valor e a decisão volta para o humano — desempatar por `criado_em` seria trocar uma regra silenciosa por outra, porque ali está a hora do upload, não a data do documento. Os filtros (seção canônica, papel conta, unidade conversível, tolerância) saíram dos CINCO desacordos medidos na fixture do Canastra, dos quais três eram falsos e dois eram arredondamento. |
| `migrations/0152_a_reconciliacao_do_lote.sql` | **A reconciliação do lote não é a do documento repetida 190 vezes.** Medido na rodada real do `book-araucaria` (execução 7172): 190 documentos, 13.942 linhas, **1h52 de pé sem gravar uma única reconciliação**, cancelada à mão — e nenhum erro em lugar nenhum. Duas causas somadas. (1) As oito checagens do despachante leem `(caso, entidade, período)` e **não o documento** — o documento só entrega a chave —, então dois documentos que compartilham a chave produzem laços byte a byte idênticos: no araucária são **82 pares (entidade, período) para 190 documentos**, e a Araucária Serraria sozinha tem 80 documentos rodando as mesmas checagens 80 vezes. `fn_reconciliar_caso` passa a rodar cada checagem uma vez por chave, e `fn_reconciliar_por_documento` ganha `p_escopo` (padrão `'tudo'`, então nada que já chamava muda) para o lote poder pedir só a parte intra-documento. (2) `fn_conflitos_do_caso` pedia o **produto cartesiano**: o planner estima `rows=1` numa CTE onde há 2.619, escolhe Nested Loop, e compara 6.859.127 pares para achar 34 — 12,4 s por chamada, vezes as 123 que a 0151 dispara. O par passa a nascer DEPOIS do agrupamento, com pré-filtro conservador por construção (`max−min > tolerância_abs` nunca descarta par verdadeiro, porque o limiar do par é `greatest(tol_abs, …) ≥ tol_abs`). Mais três economias lidas no mesmo plano: a subconsulta da capa da `0146` avaliada 17.785 vezes vira CTE por versão, a autoridade sai de 2.619 chamadas para uma por documento, e `fn_papel_linha` (imutável, 4,8 s em 8.729 avaliações) passa a ser calculada uma vez por tripla distinta. |
| `migrations/0153_a_entidade_ambigua_nao_decide.sql` | **Quando o nome casa com duas empresas, ele não identifica nenhuma.** Medido na rodada real do `book-araucaria`: o `009_Balanco_Patrimonial_Araucaria_SPE_...` é da **Araucária Imobiliária SPE** — o resumo extraído do próprio documento diz isso — e foi gravado sob **Araucária Bioenergia SPE**, junto com a DRE. Balanço e DRE de cinco exercícios de uma empresa dentro de outra, e vai FECHAR: os dois são demonstrações completas, `Ativo = Passivo + PL` bate dos dois lados e nenhuma reconciliação dispara. A causa é `fn_mesma_entidade('Araucaria SPE', …)` devolvendo **true para as duas** (o casamento da `0030` é por subsequência de prefixos, e num grupo em que toda empresa é "Araucária ⟨coisa⟩ Ltda." qualquer nome parcial casa vários) somada ao `order by e.razao_social limit 1` de `fn_upsert_entidade` — **o mesmo defeito que a `0151` corrigiu em `fn_linhas_do_realizado`, num segundo lugar**: lá era "fica com o maior", aqui é "fica com a primeira do alfabeto". Determinístico não é correto. A migration NÃO aperta `fn_mesma_entidade` (a frouxidão dela é útil, e partir a mesma empresa em duas é pior que não casar): muda o que se faz com um resultado PLURAL. Casamento canônico exato primeiro; um único aproximado depois; dois ou mais aproximados e nenhum exato → não escolhe, cria entidade própria com o nome como veio e abre pendência **bloqueante** nomeando os candidatos, por gatilho em `documento` (função sem chamador é indistinguível de função que não achou nada). Mais `fn_fundir_entidade`, que dá saída à pendência e leva junto documentos, checklist, pendências e reconciliações. |
| `migrations/0154_a_pendencia_de_cobertura_diz_a_unidade.sql` | **A pendência de cobertura juntava duas unidades na mesma frase.** Lido ao investigar as 23 pendências de `extracao_falhou` do `book-araucaria`: *"Extração de 002_Balanco falhou ou veio incompleta (276 linhas gravadas). Motivo: Extração INCOMPLETA: 68 linha(s) devolvida(s)…"* — 276 e 68 na mesma frase, e os dois com o nome "linhas". Os dois estão certos e medem coisas diferentes: 276 são **pares conta × coluna** (linhas de `campo_extraido`) e 68 são **linhas do documento** (uma conta com 5 exercícios é UMA linha; 68 × ~4 colunas = 276). Pendência que parece se contradizer ensina a ignorar a fila, que é o estrago do alarme falso por outro caminho. A descrição sai para `fn_descricao_extracao_falhou` com a unidade escrita, por substituição cirúrgica que FALHA ALTO se o trecho não for achado (a 0006 regrediu funções recriando corpo por cópia). **As 23 pendências são VERDADEIRAS:** `medir-regua-cobertura.mjs` contra os 38 documentos do Canastra dá erro mediano de régua de **+3%** e pior extração perfeita em **96%**, contra razões de 40% a 78% no araucária — sub-extração real, e a guarda acertou. E a pendência passa a dizer **em quantos blocos** o documento foi lido, que é o instrumento que faltou nesta própria investigação para separar "o modelo leu pela metade" de "o fatiamento não rodou". |
| `migrations/0155_combinado_se_reconhece_pela_estrutura.sql` | **Um documento com quinze empresas nas colunas é um combinado, e o catálogo não precisa acreditar no nome dele.** Medido no `book-araucaria` conferindo a escala da `0151` contra o dado gravado: `053`, `054`, `055` e `057` (`Balanco_Patrimonial_COMBINADO_Grupo_Araucaria_YYYY`) saíram como **BALANCO** e o `056`, com o mesmo padrão de nome, como **COMBINADO** — todos classificados pela IA com confiança 1,0, e todos com **14–15 empresas nas colunas**. Não é ruído raro: é o que acontece quando se pede a um modelo que escolha entre dois rótulos que descrevem a mesma peça (um balanço combinado É um balanço e É um combinado). O estrago é sobre a `0151`: chamado de BALANCO, o combinado sobe de 30 para 50 e **empata** com o balanço individual da empresa — e empate, pela `0151`, mantém o valor de maior módulo, que é o desempate silencioso que ela existe para eliminar. E ele encosta nos individuais de verdade, porque as linhas dele trazem `entidade_coluna` por empresa e são atribuídas a cada companhia pela `0146`. A correção não ensina o classificador: usa o fato que já está no dado. `fn_documento_de_varias_empresas` responde pela estrutura (duas ou mais empresas distintas nas colunas — não "mais que zero", senão todo comparativo multi-ano de uma empresa cairia junto), e `fn_autoridade_do_documento` limita a autoridade à de COMBINADO nesse caso, com `least`, que só abaixa. |
| `migrations/0156_o_lote_existe_antes_de_terminar.sql` | **A linha de `lote_execucao` passa a nascer quando o orçamento aceita o lote, e não quando a cadeia termina.** Medido em 31/08 sobre a rodada de 190 documentos de 27/08: ela foi cancelada à mão depois de 1h52 e `lote_execucao` ficou **vazia** — e com ela foi embora `documentos_fatiados`, que era exatamente o número de que a investigação da sub-extração precisava (o n8n descarta os dados de uma execução cancelada, então não havia segunda via). A causa é de MOMENTO, não de conteúdo: `fn_registrar_uso_lote` é chamada por um nó só, o `Gravar Uso do Lote`, no fim da cadeia — ou seja, **a rodada só deixava rastro se desse certo**, e rodada que morre é justamente a que mais precisa ser explicada. Agora `fn_abrir_lote_execucao` grava o PLANO (documentos, chamadas previstas contando os blocos do fatiamento, fração da cota diária) no instante em que `Lote cabe?` aprova, e o fechamento carimba `fechado_em`. **`fechado_em` nulo é a informação:** começou e não terminou, que antes era indistinguível de nunca ter rodado. A abertura entra pela mesma chave `(caso_id, execucao_ref)` da 0115, então os dois ramos do `Precisa Fallback?` reescrevem a mesma linha em vez de criar duas. |
| `migrations/0157_o_combinado_que_travava_o_kit_basico.sql` | **O item COMBINADO do Kit Básico ficava "ausente" com o combinado presente no caso.** Medido na rodada real de 02/09 (lote 7377, mandato "teste Canastra"): dois documentos (`13_Balanco_COMBINADO...2025.pdf`, `14_Balanco_COMBINADO...2024.pdf`), confiança 1,0, 8 empresas na planilha, foram classificados de **BALANCO** pela IA — o próprio diagnóstico da mesma rodada já sugeria COMBINADO — e o passo (1) de `fn_recomputar_completude` só considera um item presente quando `documento.tipo_taxonomia` bate com o código, então o Kit Básico abriu `item_faltante: COMBINADO`, **bloqueante e NÃO-sobrepujável** (lista fechada da `0004`): sem botão no portal que destrave. Mesmo movimento da `0155` — parar de perguntar ao rótulo: `fn_documento_serve_como(documento, tipo)` encapsula a ÚNICA exceção (o código `'COMBINADO'` aparece em um lugar só) — um documento serve como COMBINADO quando está rotulado assim OU quando `fn_documento_de_varias_empresas` (0155) é verdadeiro, e a exceção **não generaliza**: um combinado continua não servindo como BALANCO, então o Kit Básico continua exigindo o balanço individual. A pendência bloqueante já aberta se resolve sozinha pelo mecanismo que o passo (1) já tinha desde a `0006` — nenhum código novo para isso. Testes: `Supabase/test/kit_basico_combinado_estrutural.test.sql`. |
| `migrations/0158_o_pronto_que_nao_provava_cobertura.sql` | **O "pronto" da Modelagem afirmava que os parâmetros existiam, não que alguma linha foi coberta.** Medido num caso real (Grupo Vertentes): parâmetros definidos, 6 premissas ativas com valor, vínculo em lote de 5 seções — `"pronto": true`, `"linhas_do_caso": 480`, `"linhas_com_premissa": 23`. O chip da tela acende verde "pronto para exportar" com 23 de 480 linhas projetando; o analista exporta e recebe um book com 95% das contas sem projeção. A condição da `0134` (parâmetros definidos, premissa ativa, nenhuma sem valor) nunca perguntava se alguma linha REAL do caso foi vinculada — um caso com zero vínculo real, só configuração órfã, já passava. A decisão sai para `fn_modelagem_esta_pronta` (função pura, no modelo do achado D da `0157`) e ganha a quarta condição `linhas_com_premissa > 0`; o retorno ganha `fracao_linhas_com_premissa` para o portal poder mostrar QUANTO está coberto, não só um booleano. `vinculos_orfaos` e `sazonalidade_sem_curva` continuam informando e não bloqueando, de propósito: nenhum dos dois deixa um número do book errado, e bloquear por eles reverteria a `0134` e o bloco 8 de `Supabase/test/premissas.test.sql`. Testes: `Supabase/test/modelagem_pronto_exige_cobertura.test.sql`. |
| `migrations/0159_o_rotulo_que_a_propria_estrutura_desmente.sql` | **O espelho exato da `0155`, do outro lado do rótulo.** Medido na rodada real do araucária de 03/09/2026 (lote 7417, 190 documentos): seis documentos classificados **COMBINADO** pela IA com confiança 1,0 e **ZERO empresas nas colunas** — o conjunto completo de demonstrações de UMA empresa (Araucária Serraria), não um combinado; o próprio diagnóstico de conteúdo (`fn_registrar_diagnostico`) abriu, sozinho, `tipo_incorreto` nos seis. Pela escala da `0151`, o `167` (COMBINADO, assinado) vale 35 contra 55 do `002_Balanco_Patrimonial` da mesma empresa — mal extraído (49% de cobertura, pendência `extracao_falhou` real) mas com autoridade de BALANCO — e o mal extraído GANHA em silêncio. A `0155` não pega este lado porque só ABAIXA (`least`): com `varias_empresas = false` ela devolve `do_tipo` intocado, e `do_tipo` do COMBINADO já é o piso da escala. Promover o documento a BALANCO inventaria um tipo que o classificador não declarou; levantar a autoridade numérica (`greatest`) não tem piso honesto, porque "não derivado" não é um conceito único como "derivado" é. Uma primeira tentativa usou o espelho ESTRUTURAL exato da `0155` (`decide_sozinho = false` quando menos de duas empresas nas colunas) e foi **derrubada por `Supabase/test/desempate.test.sql`**: um COMBINADO preliminar legítimo daquele fixture nunca marca `entidade_coluna` (mede outro eixo) e a ausência não prova que a peça não é derivada — só que o fixture não marcou. A correção final usa o sinal que o sistema já publica: `fn_autoridade_do_documento` ganha uma terceira coluna, `decide_sozinho` (via `fn_documento_decide_sozinho`, pura, exercitável por literais), falsa exatamente quando o documento é COMBINADO **e tem uma pendência `tipo_incorreto` ABERTA** — e `fn_conflitos_do_caso` passa a exigi-la dos dois lados para declarar `decidido = true`. Resolvida a pendência (humano confirma o rótulo), o documento volta a decidir sozinho pelo próprio ciclo de vida de `pendencia.estado`, sem mecanismo novo. O valor gravado não muda (como no EMPATE da `0151`), mas o conflito para de ser resolvido em silêncio pela autoridade e o critério diz "SEM DECISÃO AUTOMÁTICA" por extenso. A restrição da `0155` não é tocada: um combinado de verdade (várias empresas) rotulado BALANCO continua `decide_sozinho = true` mesmo com `tipo_incorreto` aberta — a regra só olha documentos rotulados COMBINADO. Testes: `Supabase/test/rotulo_contraditorio.test.sql`. |
| `migrations/0160_a_hierarquia_que_o_diagnostico_chama_de_erro.sql` | **Entidade registrada e nome diagnosticado que é ELE MESMO outra empresa do caso: `fn_registrar_diagnostico` não sabia responder isso.** Medido na rodada real do lote `7377` (02/09, mandato "teste Canastra", ver `ESTADO.md` seção "SESSÃO 79"): `33_Notas_Explicativas` registrado em **GRUPO CANASTRA**, diagnóstico de conteúdo aponta **Canastra Indústria** — as duas são empresas REAIS e distintas do mesmo mandato (o fixture do book Canastra já as cadastra em linhas separadas de `entidade`), e `fn_registrar_diagnostico` abriu `entidade_incorreta` como se o registro estivesse necessariamente errado. `fn_mesma_entidade('GRUPO CANASTRA', 'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.') = false`, então a `0153` (ambiguidade em `fn_upsert_entidade`, quando um nome casa com DUAS entidades ao ser procurado) não cobre este caso — é função diferente, e os nomes não casam entre si. A causa é que `fn_registrar_diagnostico` só sabia responder "mesma empresa" ou "erro" quando os nomes não casavam; agora, antes de abrir `entidade_incorreta`, confere (reaproveitando `fn_entidades_candidatas` da `0153`) se o nome diagnosticado é ELE MESMO outra empresa (ou mais de uma) já cadastrada no mesmo caso — se for, a função não sabe se o registro está certo, e nomeia TODAS as candidatas na pendência em vez de escolher uma no empate (a mesma armadilha que a `0153` corrigiu em `fn_upsert_entidade`, `order by ... limit 1` no lugar de perguntar). `entidade.papel_no_grupo` existiria para afirmar holding × subsidiária, mas esta função não o consulta — a pendência não afirma hierarquia nenhuma, só que há mais de uma empresa candidata e ninguém decide sozinho qual é a certa. A pendência clássica, se estava aberta de uma rodada anterior, fecha e nasce uma distinta pelo `motivo` (`diagnostico:entidade_grupo:`) — **mas isso só acontece quando `fn_registrar_diagnostico` roda de NOVO para aquele documento, numa rodada seguinte; aplicar esta migration sozinha não fecha pendência nenhuma já aberta em produção** (é o caso do lote `7377`, que tem a `diagnostico:entidade:<doc 33>` aberta hoje). Divergência de verdade (nome que não bate com ninguém do caso) continua abrindo `entidade_incorreta` exatamente como na `0121`. Testes: seções 16–18 de `Supabase/test/canastra.test.sql`, contra o fixture real do book Canastra (nenhuma entidade inventada) — a seção 16 mede DOIS comportamentos independentes com a correção desligada (a pendência clássica deixa de abrir sozinha, E a pendência distinta deixa de nascer — sem a correção `v_desc` some e os asserts que dependem dela reprovam pela MESMA causa, `teste_assert(null)`); a seção 17 é o controle negativo (divergência de verdade continua abrindo a clássica); a seção 18 acrescenta o candidato MÚLTIPLO (a 0153 aplicada aqui) e o caminho de TRANSIÇÃO (pendência clássica já aberta que muda de categoria numa segunda passada) — nenhum dos dois tinha assert antes desta revisão. |
| `seed/macro_carga_inicial.sql` | **Carga inicial dos índices macro** (dado REAL, gerado por `node N8N/gerar-seed-macro.mjs` das mesmas APIs e parsers que o workflow de coleta usa: BCB/SGS, IBGE/SIDRA e BCB/Focus). Existe porque o `workflow.macro.json` roda no RELÓGIO (dia 12) e **não faz carga histórica** — importar/ativar o workflow hoje não traz número nenhum até o próximo dia 12, e as médias de 3/5/10 anos e as premissas de Focus do modelo são inúteis vazias. Aplicar **depois da `0025`**, no mesmo banco. Seguro rodar mais de uma vez (as RPCs são idempotentes). É uma FOTO da data em que o arquivo foi gerado — a manutenção mês a mês continua sendo do workflow. Testes: `Supabase/test/seed_macro.test.sql`, que confere as duas fontes do IPCA entre si. |

## `schema.sql` — o estado final, materializado

`Supabase/schema.sql` é **gerado**, não escrito à mão: o `Supabase/test/run.sh` aplica as migrations num
Postgres limpo e faz o `pg_dump --schema-only` do resultado. O CI confere com
`git diff --exit-code` — mesmo portão do espelho do n8n.

**Para que serve:** responder "o que este banco faz HOJE" sem ler 51 migrations em ordem.
`fn_recomputar_completude` existe na `0004`, na `0006` e na `0036`, e só a última vale; numa
revisão de PR ninguém reconstrói isso de cabeça. Com o arquivo gerado, o efeito real de uma
migration nova aparece como uma seção alterada no diff.

**O que ele NÃO é:** um registro do que está aplicado em PRODUÇÃO. Ele descreve o que as
migrations do repositório produzem — merge continua não sendo apply (ver o aviso abaixo).

Não edite o arquivo: rode `Supabase/test/run.sh` e commite o que sair.

## Como aplicar

**Opção A — Supabase CLI (recomendado):**
```bash
supabase db push
# ou aplicar arquivo a arquivo:
supabase db execute --file Supabase/migrations/0001_schema_fatia1.sql
supabase db execute --file Supabase/migrations/0002_seed_taxonomia_e_dial.sql
supabase db execute --file Supabase/migrations/0003_rls_e_storage.sql
supabase db execute --file Supabase/migrations/0004_funcoes_e1.sql
supabase db execute --file Supabase/migrations/0005_extracao_e2.sql
supabase db execute --file Supabase/migrations/0006_reset_funcoes.sql
supabase db execute --file Supabase/migrations/0007_justificativa_pendencia.sql
supabase db execute --file Supabase/migrations/0008_portal_revisao.sql
supabase db execute --file Supabase/migrations/0009_reconciliacao_e3.sql
supabase db execute --file Supabase/migrations/0010_diagnostico_e1e2.sql
supabase db execute --file Supabase/migrations/0011_aceite_export_e4.sql
supabase db execute --file Supabase/migrations/0012_secao_canonica_e4.sql
supabase db execute --file Supabase/migrations/0013_guarda_extracao_suspeita.sql
supabase db execute --file Supabase/migrations/0014_entidade_coluna_multi_entidade.sql
supabase db execute --file Supabase/migrations/0015_reconciliacao_classe_b.sql
supabase db execute --file Supabase/migrations/0016_guarda_extracao_falhou.sql
supabase db execute --file Supabase/migrations/0017_periodo_coluna.sql
supabase db execute --file Supabase/migrations/0018_fix_revisar_documento_pendencias.sql
supabase db execute --file Supabase/migrations/0019_auto_aceite_alta_confianca.sql
supabase db execute --file Supabase/migrations/0020_periodo_canonico.sql
supabase db execute --file Supabase/migrations/0021_classe_b_checagem_unidade.sql
supabase db execute --file Supabase/migrations/0022_periodo_por_ano_e_guardas.sql
supabase db execute --file Supabase/migrations/0023_reconciliacao_sem_ruido.sql
supabase db execute --file Supabase/migrations/0024_taxonomia_dmpl_dva.sql
supabase db execute --file Supabase/migrations/0025_indices_macro.sql
supabase db execute --file Supabase/migrations/0026_reextracao_por_hash.sql
supabase db execute --file Supabase/migrations/0027_ordem_da_linha.sql
supabase db execute --file Supabase/migrations/0028_rls_e_grant_indices_macro.sql
supabase db execute --file Supabase/migrations/0029_extracao_aceite_depois_das_guardas.sql
supabase db execute --file Supabase/migrations/0030_entidade_e_periodo_canonicos.sql
supabase db execute --file Supabase/migrations/0031_caixa_por_secao.sql
supabase db execute --file Supabase/migrations/0032_cambio_perdia_janeiro.sql
supabase db execute --file Supabase/migrations/0033_precondicao_que_nomeia_o_rotulo.sql
supabase db execute --file Supabase/migrations/0034_total_do_grupo_sem_a_palavra_total.sql
supabase db execute --file Supabase/migrations/0035_moeda_por_linha.sql
supabase db execute --file Supabase/migrations/0036_completude_exige_conteudo.sql
supabase db execute --file Supabase/migrations/0037_portao2.sql
supabase db execute --file Supabase/migrations/0038_premissas_catalogo.sql
supabase db execute --file Supabase/migrations/0039_linhas_para_modelagem.sql
supabase db execute --file Supabase/migrations/0040_sazonalidade_do_caso.sql
supabase db execute --file Supabase/migrations/0041_dial_manda.sql
supabase db execute --file Supabase/migrations/0042_papel_da_linha.sql
supabase db execute --file Supabase/migrations/0043_reconferir_o_que_ja_esta_no_banco.sql
supabase db execute --file Supabase/migrations/0044_valores_por_ano.sql
# Faixa 0100+ (colaborador). O buraco 0044 → 0100 é o estado esperado, não erro:
supabase db execute --file Supabase/migrations/0100_papel_por_secao.sql
supabase db execute --file Supabase/migrations/0101_modelagem_dentro_do_tempo.sql
supabase db execute --file Supabase/migrations/0102_modelagem_versao_vigente.sql
supabase db execute --file Supabase/migrations/0103_papel_linha_tokeniza_uma_vez.sql
supabase db execute --file Supabase/migrations/0104_desativar_premissa.sql
supabase db execute --file Supabase/migrations/0105_reconciliar_duplicidade_de_rotulo.sql
supabase db execute --file Supabase/migrations/0106_rejeitar_pendencia.sql
supabase db execute --file Supabase/migrations/0107_papel_ressalva_e_tratamento.sql
supabase db execute --file Supabase/migrations/0108_falha_de_execucao.sql
supabase db execute --file Supabase/migrations/0109_pendencia_tres_botoes.sql
supabase db execute --file Supabase/migrations/0110_remove_papel_de_usuario.sql
supabase db execute --file Supabase/migrations/0111_documento_sem_dado_financeiro_nao_e_falha.sql
supabase db execute --file Supabase/migrations/0112_lote_conferido_documento_por_documento.sql
supabase db execute --file Supabase/migrations/0113_linha_exigida_por_tipo.sql
supabase db execute --file Supabase/migrations/0114_mandato_fechado.sql
supabase db execute --file Supabase/migrations/0115_custo_do_lote.sql
supabase db execute --file Supabase/migrations/0116_total_impresso_e_linha.sql
supabase db execute --file Supabase/migrations/0117_reconciliar_mutuos.sql
supabase db execute --file Supabase/migrations/0118_dedup_por_fingerprint.sql
supabase db execute --file Supabase/migrations/0119_linha_exigida_por_entidade.sql
supabase db execute --file Supabase/migrations/0120_banco_de_perguntas.sql
supabase db execute --file Supabase/migrations/0121_diagnostico_nao_duplica_entidade.sql
supabase db execute --file Supabase/migrations/0122_pergunta_em_portugues.sql
supabase db execute --file Supabase/migrations/0123_mutuos_a_natureza_fora_da_linha.sql
supabase db execute --file Supabase/migrations/0124_intragrupo_que_nao_e_mutuo.sql
supabase db execute --file Supabase/migrations/0125_proveniencia_por_linha_e_ano.sql
supabase db execute --file Supabase/migrations/0126_golden_set.sql
supabase db execute --file Supabase/migrations/0127_o_dial_obedecido.sql
supabase db execute --file Supabase/migrations/0128_classificacao_contabil_sombra.sql
supabase db execute --file Supabase/migrations/0129_transcricao_humana_assistida.sql
supabase db execute --file Supabase/migrations/0130_golden_set_rotulavel.sql
supabase db execute --file Supabase/migrations/0131_instalacao_que_se_declara.sql
supabase db execute --file Supabase/migrations/0132_a_sonda_nao_cresce_com_o_dado.sql
supabase db execute --file Supabase/migrations/0133_a_secao_que_nao_fecha.sql
supabase db execute --file Supabase/migrations/0134_sazonalidade_nao_e_premissa_sem_valor.sql
supabase db execute --file Supabase/migrations/0135_a_operacao_passa_a_ser_vista.sql
supabase db execute --file Supabase/migrations/0136_veredito_de_producao.sql
supabase db execute --file Supabase/migrations/0137_a_promocao_automatica_do_dial.sql
supabase db execute --file Supabase/migrations/0138_a_guarda_que_estourava.sql
supabase db execute --file Supabase/migrations/0139_reafirmar_nao_apaga_medicao.sql
supabase db execute --file Supabase/migrations/0140_a_coluna_de_dimensao_nao_e_valor.sql
supabase db execute --file Supabase/migrations/0141_o_limiar_que_nunca_excluiu_nada.sql
supabase db execute --file Supabase/migrations/0142_tipo_incorreto_precisa_de_divergencia.sql
supabase db execute --file Supabase/migrations/0143_hierarquia_achatada_nao_e_divergencia.sql
supabase db execute --file Supabase/migrations/0144_duplicidade_e_entre_documentos.sql
supabase db execute --file Supabase/migrations/0145_o_conceito_que_mora_na_coluna.sql
supabase db execute --file Supabase/migrations/0146_a_entidade_que_o_documento_nunca_declarou.sql
supabase db execute --file Supabase/migrations/0147_a_sonda_enxerga_o_corpo_da_funcao.sql
supabase db execute --file Supabase/migrations/0148_o_fato_que_o_documento_diz_em_texto.sql
supabase db execute --file Supabase/migrations/0149_o_fato_material_endurecido.sql
supabase db execute --file Supabase/migrations/0150_a_premissa_sai_do_realizado_certo.sql
supabase db execute --file Supabase/migrations/0151_o_desempate_entre_documentos.sql
supabase db execute --file Supabase/migrations/0152_a_reconciliacao_do_lote.sql
supabase db execute --file Supabase/migrations/0153_a_entidade_ambigua_nao_decide.sql
supabase db execute --file Supabase/migrations/0154_a_pendencia_de_cobertura_diz_a_unidade.sql
supabase db execute --file Supabase/migrations/0155_combinado_se_reconhece_pela_estrutura.sql
supabase db execute --file Supabase/migrations/0156_o_lote_existe_antes_de_terminar.sql
supabase db execute --file Supabase/migrations/0157_o_combinado_que_travava_o_kit_basico.sql
supabase db execute --file Supabase/migrations/0158_o_pronto_que_nao_provava_cobertura.sql
supabase db execute --file Supabase/migrations/0159_o_rotulo_que_a_propria_estrutura_desmente.sql
supabase db execute --file Supabase/migrations/0160_a_hierarquia_que_o_diagnostico_chama_de_erro.sql
supabase db execute --file Supabase/migrations/0161_a_justificativa_que_o_periodo_perdia.sql
supabase db execute --file Supabase/migrations/0162_o_balcao_que_nao_escuta_a_resposta.sql
supabase db execute --file Supabase/migrations/0163_a_ancora_que_o_crlf_desalinhou.sql
supabase db execute --file Supabase/migrations/0164_a_estimativa_que_o_filtro_opaco_escondia.sql
supabase db execute --file Supabase/migrations/0165_o_passivo_que_ja_inclui_o_patrimonio.sql
supabase db execute --file Supabase/migrations/0166_a_exigencia_que_nao_conhecia_o_passivo_bare.sql
supabase db execute --file Supabase/migrations/0167_o_faturamento_que_somava_a_coluna_total.sql
supabase db execute --file Supabase/migrations/0168_o_apelido_truncado_nao_e_ambiguidade.sql
supabase db execute --file Supabase/migrations/0169_o_cnpj_e_a_identidade_que_o_nome_nao_e.sql
supabase db execute --file Supabase/migrations/0170_o_cnpj_atravessa_a_porta_de_entrada.sql
supabase db execute --file Supabase/migrations/0171_o_cnpj_tambem_renomeia.sql
supabase db execute --file Supabase/migrations/0172_o_cnpj_pelo_caminho_que_roda_sempre.sql
supabase db execute --file Supabase/migrations/0173_o_renomeio_pelo_caminho_que_roda_sempre.sql
supabase db execute --file Supabase/migrations/0174_aprender_cnpj_que_ja_tinha_dona_funde.sql
supabase db execute --file Supabase/migrations/0175_o_cnpj_tambem_resolve_o_balcao.sql
supabase db execute --file Supabase/migrations/0176_o_balcao_nao_absorve_quem_e_confirmado.sql
supabase db execute --file Supabase/migrations/0177_a_guarda_do_balcao_ia_so_num_sentido.sql
supabase db execute --file Supabase/migrations/0178_o_titulo_da_planilha_nao_e_pessoa_juridica.sql
supabase db execute --file Supabase/migrations/0179_o_papel_no_grupo_que_nunca_foi_escrito.sql
supabase db execute --file Supabase/migrations/0180_o_perimetro_que_o_combinado_nao_tinha.sql
supabase db execute --file Supabase/migrations/0181_o_controle_que_a_entidade_nunca_registrava.sql
supabase db execute --file Supabase/migrations/0182_o_grupo_horizontal_que_a_controladora_nao_alcancava.sql
# ATENÇÃO — a 0183 precisa dos MESMOS DOIS PASSOS que a 0179 precisou, e pela mesma razão.
# Ela faz `alter type pendencia_tipo add value 'forma_de_controle_indefinida'` e USA o rótulo no
# mesmo arquivo. No `psql` isso funciona (cada statement de topo aplica em autocommit, e o
# cabeçalho da migration explica isso), mas o CAMINHO REAL DE PRODUÇÃO não é o psql: a porta do
# Postgres não é alcançável do container, aplica-se pela API de gerenciamento do Supabase, e ela
# envolve o lote numa TRANSAÇÃO IMPLÍCITA — onde o Postgres recusa com "unsafe use of new value of
# enum type". Foi exatamente o que aconteceu com a 0179 (registrado no ESTADO.md), e quem aplicar
# esta lista de uma vez vai receber o mesmo erro no meio, com a 0182 já aplicada.
# Aplique a 0183 em dois envios: PRIMEIRO SÓ a linha `alter type pendencia_tipo add value if not
# exists 'forma_de_controle_indefinida';`, DEPOIS o arquivo inteiro com essa linha comentada (o
# mesmo roteiro do topo do ESTADO.md — antes daqui havia dois roteiros diferentes, e os dois
# funcionavam, o que é pior: quem lê os dois não sabe qual o outro seguiu).
# E ANTES do segundo envio: a 0183 reemite `fn_fundir_entidade` (0153). Compare o corpo de produção
# com o da 0153 — a diferença para o da 0183 tem de ser só os blocos marcados `0183`.
supabase db execute --file Supabase/migrations/0183_a_forma_de_controle_que_ninguem_declarava.sql

# A 0185 NÃO EXISTE, e o buraco é deliberado. (A 0182 e a 0183, da F1.7, estão logo acima e SÃO
# aplicáveis; a 0184 foi reservada pela F1.7 e NÃO usada — lacuna declarada, nada a aplicar.) Ela propunha exigência LEXICAL para nove tipos de
# relatório itemizado e foi REPROVADA na medição contra produção em 21/09/2026:
# 17 de 17 pendências que abriria eram falsas — em relatório itemizado o rótulo é
# o ITEM, não o conceito (.claude/memory/conceito-nao-esta-no-rotulo-de-relatorio-itemizado.md).
# Foi descartada em 22/09/2026 sem nunca ter sido aplicada em banco nenhum; o que
# ela tentava responder (D6) é respondido pela 0187, por DECLARAÇÃO, não por termo.

# A 0186 acrescenta reconciliacao.motivo_precondicao e reemite
# fn_registrar_reconciliacao para gravá-la — resultado NÃO muda de
# vocabulário (continua 'precondicao_nao_satisfeita'), só passa a existir uma
# coluna nova com o motivo que o emissor passou antes do achatamento. Ela
# também: (a) VALIDA o vocabulário de p_resultado e levanta exceção para
# valor desconhecido (achado da revisão: um erro de digitação fabricava
# precondicoes_ok = true); (b) faz um BACKFILL a partir de evento_auditoria
# para as linhas de reconciliacao já gravadas com precondicoes_ok = false.
#
# CORRIGIDO após revisão independente: a consulta que este README mandava
# rodar ANTES de aplicar usava a coluna motivo_precondicao — que só existe
# DEPOIS que esta mesma migration roda ("column does not exist" para quem
# tentasse medir antes, e aplicar sem medir é o que a 0179 custou caro,
# .claude/memory/aplicar-migration-em-producao-pela-api.md — 365 pendências
# onde se previam 13). Meça o alcance com as duas consultas abaixo, que RODAM
# ANTES do apply:
#   -- (a) o total que a migration mexe:
#   select count(*) from reconciliacao where precondicoes_ok = false;
#   -- (b) quantas o backfill alcançaria e quantas ficariam de fora, por tipo
#   -- (mesma junção do UPDATE da migration, com o de-para de
#   -- caixa_bp_vs_fluxo → caixa_bp_fluxo — ver o cabeçalho da 0186):
#   select r.tipo, count(*) as total, count(ea.id) as alcancaria_o_backfill,
#          count(*) filter (where ea.id is null) as ficaria_null
#     from reconciliacao r
#     left join evento_auditoria ea
#       on ea.entidade_ref = 'reconciliacao:' || r.id
#      and ea.ator = 'sistema:reconciliacao'
#      and ea.acao = 'reconciliacao_' ||
#          case when r.tipo = 'caixa_bp_vs_fluxo' then 'caixa_bp_fluxo' else r.tipo end
#    where r.precondicoes_ok = false
#    group by r.tipo order by 1;
# No banco de TESTE (recém-migrado, sem fixture) o total é ZERO — a tabela
# reconciliacao está vazia no instante em que a migration roda. Em PRODUÇÃO
# é desconhecido: a medição de 21/09/2026 que abriu esta fatia contou 1.926
# linhas com precondicoes_ok = false (ESTADO.md, topo), então o backfill tem
# chance real de tocar milhares de linhas. NÃO há "rodar como está ou em
# lote" para escolher em tempo de apply — o backfill é um único UPDATE
# dentro do arquivo da migration, aplicado inteiro por
# `supabase db execute --file`; ir em lote significaria editar o ARQUIVO
# antes de aplicar, não uma opção que a migration ofereça.
#
#   (c) E A TERCEIRA CONSULTA, QUE É A QUE PODE MANDAR NÃO APLICAR. A 0186
#   acrescenta um `raise exception` quando `p_resultado` está fora de um
#   vocabulário fixo. Esse vocabulário foi levantado por varredura do
#   REPOSITÓRIO e conferido contra o banco de teste — mas produção é o único
#   lugar onde uma função criada fora do repositório apareceria, e a
#   reconciliação roda DENTRO do fluxo de ingestão, sem `exception when others`
#   em nenhum ponto do caminho (conferido). Um décimo valor em produção vira
#   exceção que aborta a transação do caso na ingestão — muito pior que o
#   defeito que a 0186 corrige. Rode ANTES de aplicar; qualquer valor fora dos
#   nove aceitos significa NÃO APLICAR e voltar ao desenho:
#     select ea.depois->>'resultado' as motivo_emitido, count(*)
#       from evento_auditoria ea
#      where ea.ator = 'sistema:reconciliacao'
#        and ea.acao like 'reconciliacao\_%'
#      group by 1 order by 2 desc;
supabase db execute --file Supabase/migrations/0186_o_motivo_que_o_achatamento_engolia.sql
# DEPOIS DESTA, confira o backfill — o `raise notice` dele é EFÊMERO e some
# em qualquer apply cuja saída seja capturada (UI, pipeline). Sem esta
# consulta, "preencheu 1.926" e "preencheu 0 porque a junção não bateu" ficam
# indistinguíveis, com a coluna instalada e a sonda verde:
#   select count(*) filter (where motivo_precondicao is not null) as preenchidas,
#          count(*) filter (where motivo_precondicao is null)     as continuam_null
#     from reconciliacao where not precondicoes_ok;

# A 0187 (portão D6) cria taxonomia_tipo_cobertura + fn_cobertura_de_tipos,
# DESATIVA as exigências lexicais proposta de MUTUOS e FAT_INTRAGRUPO,
# acrescenta localizador por SEÇÃO a CONTRATO_SOCIAL/capital_social, reemite
# fn_sugerir_perguntas e RESOLVE pendências linha_exigida_ausente ABERTAS
# desses três tipos que ficaram falsas (resolvida_por = 'sistema:0187'). Não
# chama fn_recomputar_completude. Meça o alcance ANTES, somente leitura:
#   select split_part(motivo, ':', 3) as tipo, estado, count(*)
#     from pendencia
#    where tipo = 'linha_exigida_ausente'
#      and split_part(motivo, ':', 3) in ('MUTUOS','FAT_INTRAGRUPO','CONTRATO_SOCIAL')
#      and estado <> 'resolvida'
#    group by 1, 2 order by 1, 2;
# Esperado em 22/09/2026: 1 MUTUOS + 3 FAT_INTRAGRUPO + 1 CONTRATO_SOCIAL
# abertas, 1 MUTUOS aceita_com_ressalva (esta NÃO é tocada pela migration —
# mas o próximo recompute daquele caso a resolve, como faz com toda exigência
# desativada; ver o cabeçalho). A do CONTRATO_SOCIAL dependia de a versão
# VIGENTE do documento ter a seção "…Capital social" preenchida — MEDIDO em
# produção (22/09/2026, somente leitura): na versão vigente do documento
# 9ae9ca0b-7b6a-4fa1-bf23-ef3cc8805ffc (GLOBAL STORE), 4 das 6 linhas têm
# `secao` com 'capital' e 'social'. Previsão: 5 resolvidas, 0 abertas.
#
# CORRIGIDA após revisão independente (22/09/2026, antes de qualquer apply):
#   (a) o {saldo_mutuos} da pergunta 5.1 deixou de ler léxico: o documento
#       MUTUOS é o conceito — coluna do exercício mais recente, linha de total
#       geral se houver, senão a soma dos itens; quando não dá para apurar, a
#       pergunta diz "não foi possível apurar o saldo" e o porquê. Sonda por
#       COMPORTAMENTO: instalacao_sonda_saldo_mutuos (4 linhas);
#   (b) taxonomia_tipo_cobertura ganhou marcador/marcador_em: o trecho que faz a
#       leitura precisa estar no corpo publicado (\r removido), senão
#       DECLARACAO_QUEBRADA — o nome em pg_proc sozinho não prova a leitura;
#   (c) DF_AUDITADA passou a sem_consumidor (só é lida como balanço substituto);
#       consumidores nomeados: MUTUOS e BALANCETE;
#   (d) o motivo de cada tipo diz o que foi medido PARA ELE (zero documentos =
#       nada medido; os demais = parte dos 17 da medição agregada da 0185).
supabase db execute --file Supabase/migrations/0187_o_tipo_que_chegava_sem_leitor_declarado.sql
# DEPOIS DESTA (o raise notice é efêmero):
#   select resolvida_por, count(*) from pendencia
#    where tipo = 'linha_exigida_ausente' and resolvida_por = 'sistema:0187' group by 1;
#   select * from fn_cobertura_de_tipos()
#    where veredito in ('SEM_COBERTURA', 'DECLARACAO_QUEBRADA');   -- D6 estrito: ZERO linhas
#   select * from instalacao_sonda_saldo_mutuos;                   -- QUATRO linhas

# A 0188 EXIGE A 0186 APLICADA ANTES, e desde a revisão de 22/09/2026 ela
# mesma diz isso: o bloco (0) aborta a instalação com "0188 exige a 0186
# aplicada antes" se a coluna reconciliacao.motivo_precondicao não existir OU
# se fn_registrar_reconciliacao não tiver o corpo da 0186. Sem essa guarda a
# 0188 instalava LIMPA sobre um banco sem a 0186 (plpgsql só resolve coluna
# quando roda) e toda fn_reconciliar_* morria depois, em runtime — e o n8n
# (PG_RETRY continueRegularOutput) seguia com ZERO reconciliações, sem erro
# visível. Provado num banco descartável (22/09/2026): até a 0181 + 0187, SEM
# a 0186 → a 0188 aborta com a mensagem e não deixa nada (0 das funções
# novas); com a guarda desligada, a mesma 0188 instalava com rc=0; aplicada a
# 0186 → a 0188 passa, e reaplicá-la também passa. Para refazer a prova:
#   createdb tdf_guarda; <aplicar os pré-requisitos do run.sh e as migrations
#   0001..0181 e a 0187>; psql -d tdf_guarda -f Supabase/migrations/0188_*.sql
#   → ERROR: 0188 exige a 0186 aplicada antes: …; dropdb tdf_guarda
#
# E A TOLERÂNCIA DA DESPFIN (revisão, 22/09/2026): a 0188 reemite
# fn_reconciliar_despfin_dre_vs_divida, e a reemissão corrige
# `p_tolerancia_abs * fator` (R$ 50 MILHÕES numa DRE em milhar) para a
# tolerância na BASE, greatest(R$ 50.000, 5%). Medido em produção: 1 das 33
# despfin 'ok' era falsa (R$ 12.400.000 saindo "confere"); na próxima rodada
# daquele caso ela vira zona_cinzenta e abre pendência. Receita (0023) e caixa
# (0031) têm o mesmo `× fator` e NÃO foram corrigidas (não medidas) — ver o
# cabeçalho, parte 4. O alcance, somente leitura, ANTES (fonte_a/fonte_b guardam
# o ÚLTIMO exercício comparado, então isto é aproximado para linha de vários
# anos; esperado em 22/09/2026: 1 de 33):
#   select count(*) as ok_hoje, count(*) filter (where abs(a - b) > greatest(50000, 0.05 * a)) as viram_zona
#     from (select abs(fn_valor_em_base((fonte_a->>'valor')::numeric, fonte_a->>'unidade')) as a,
#                  abs(fn_valor_em_base((fonte_b->>'soma_juros')::numeric, fonte_b->>'unidade')) as b
#             from reconciliacao where tipo = 'despfin_dre_vs_divida' and resultado = 'ok') x;
# E o mesmo para as duas NÃO corrigidas (troque tipo, as chaves de fonte e o piso):
# receita_dre_vs_faturamento (greatest(50000, 5%)) e caixa_bp_fluxo (greatest(100, 0,5%)).
#
# A 0188 (depois da 0186 — ela usa os três motivos reservados pelo CONTRATO da
# 0186, e a guarda de vocabulário da 0186 os aceita) faz as quatro checagens que
# emitiam a precondição genérica passarem o motivo ESPECÍFICO quando o código o
# sabe (linha_nao_localizada / unidade_divergente / sem_periodo_par), com
# MOTIVO e REMÉDIO na frente da descrição; reemite fn_registrar_reconciliacao só
# para DEVOLVER o resultado achatado (o laço de períodos lê esse valor — sem
# isso o laço pararia no primeiro período); cria taxonomia_linha_alternativa
# (DRE/despesa_financeira: "resultado financeiro" sem "antes"); reemite
# fn_exigencias_do_caso (DROP + CREATE: duas colunas novas, grant refeito) e
# fn_recomputar_completude (texto pela alternativa + a descrição passa a ser
# atualizada na pendência que já existe); acrescenta o localizador
# ["juros","bancari"] na exigência E na checagem de despesa financeira. NÃO roda
# reconciliação nem recompute: o motivo específico aparece na PRÓXIMA rodada de
# cada caso, e as linhas já gravadas continuam com o genérico.
#
# O único UPDATE dela é dirigido: fn_reescrever_recado_linha_exigida('DRE',
# 'despesa_financeira') reescreve SÓ a descrição das pendências ABERTAS dessa
# exigência cuja entidade tem a alternativa. Meça o alcance ANTES, somente
# leitura (a atribuição de entidade abaixo é a aproximada — a migration usa a de
# fn_exigencias_do_caso; esperado em 22/09/2026: ~50 de 52):
#   select count(*) as abertas,
#          count(*) filter (where exists (
#            select 1 from documento d
#              join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
#             where d.caso_id = p.caso_id and d.tipo_taxonomia = 'DRE'
#               and (p.entidade_id is null or d.entidade_id = p.entidade_id)
#               and ce.valor_num is not null
#               and fn_normalizar_texto(ce.chave) like '%resultado%'
#               and fn_normalizar_texto(ce.chave) like '%financeiro%'
#               and fn_normalizar_texto(ce.chave) not like '%antes%')) as com_resultado_financeiro
#     from pendencia p
#    where p.tipo = 'linha_exigida_ausente' and p.estado = 'aberta'
#      and p.motivo like 'completude:linha_exigida:DRE:despesa\_financeira%';
# E o alcance do localizador novo (a pendência FALSA que o próximo recompute do
# caso resolve — a migration não a resolve; esperado: 1):
#   select count(*) from pendencia p
#    where p.tipo = 'linha_exigida_ausente' and p.estado <> 'resolvida'
#      and p.motivo like 'completude:linha_exigida:DRE:despesa\_financeira%'
#      and exists (
#        select 1 from documento d
#          join campo_extraido ce on ce.documento_versao_id = fn_versao_com_extracao(d.id)
#         where d.caso_id = p.caso_id and d.tipo_taxonomia = 'DRE'
#           and (p.entidade_id is null or d.entidade_id = p.entidade_id)
#           and ce.valor_num is not null
#           and fn_normalizar_texto(ce.chave) like '%juros%'
#           and fn_normalizar_texto(ce.chave) like '%bancari%'
#           and fn_normalizar_texto(ce.chave) not like '%receita%'
#           and fn_normalizar_texto(ce.chave) not like '%aplicac%');
supabase db execute --file Supabase/migrations/0188_o_motivo_que_a_checagem_sabia_e_nao_dizia.sql
# DEPOIS DESTA (o raise notice com a contagem é efêmero):
#   select descricao like '%não existe como tal%' as com_recado, count(*) from pendencia
#    where tipo = 'linha_exigida_ausente' and estado = 'aberta'
#      and motivo like 'completude:linha_exigida:DRE:despesa\_financeira%' group by 1;
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0188' and not presente;                 -- ZERO linhas
# E, depois da próxima rodada de um caso, o motivo específico aparecendo:
#   select motivo_precondicao, count(*) from reconciliacao
#    where not precondicoes_ok and criado_em > '<data do apply>' group by 1 order by 2 desc;

# A 0189 DEPOIS DA 0183: ela cataloga os três gatilhos da F1.7, que só existem
# com a 0182 e a 0183 aplicadas — sem a 0183, a sonda acusa dois deles
# ausentes, o que é verdade (a guarda não está lá). IDEMPOTENTE: só catálogo
# (instalacao_requisito_tipo_check + DEZ requisitos: nove de tipo gatilho e
# o `sonda_ve_gatilho`, de tipo corpo) e a reemissão de fn_instalacao_conferir — sem efeito
# em dado. Testes: Supabase/test/sonda_ve_gatilho.test.sql (via run.sh).
supabase db execute --file Supabase/migrations/0189_o_gatilho_que_a_sonda_nao_via.sql
# DEPOIS DE APLICAR, confira que nenhum gatilho está DE FATO desligado em
# produção — se este select devolver linha, é informação sobre o banco
# (um `drop trigger`/`disable trigger` real), não um erro desta migration:
#   select chave, objeto, detalhe from fn_instalacao_conferir()
#    where tipo = 'gatilho' and not presente;

# A 0190 NÃO DEPENDE DA 0189 (que segue pendente do dono nesta lista) — só
# reemite fn_reconciliar_arvore, que já usa o vocabulário 'documento_ausente'
# desde a 0186/0188. Corrige o ramo em que TODAS as seções de um documento
# caem em pré-condição: antes gravava resultado='ok' (afirmando que a árvore
# fechou quando nada foi de fato conferido); passa a gravar 'documento_ausente'
# — mesmo motivo do ramo "sem árvore", sem abrir pendência nova. IDEMPOTENTE.
# Testes: Supabase/test/secao_fecha.test.sql, bloco 8 (via run.sh).
supabase db execute --file Supabase/migrations/0190_a_arvore_que_nao_conferiu_nada.sql
# DEPOIS DE APLICAR, as 12 linhas já erradas (medidas em 25/09/2026) NÃO se
# corrigem sozinhas — só a próxima rodada de cada caso grava com o ramo novo.
# Para achar as antigas sem escrever nada:
#   select id, caso_id, tipo, criado_em from reconciliacao
#    where tipo = 'secao_fecha' and resultado = 'ok'
#      and fonte_a->>'secoes_conferidas' = '0';
# E que o requisito novo está presente:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where chave = 'reconciliar_arvore_nao_mente_ok';               -- presente = true

# A 0191 REEMITE fn_reconciliar_despfin_dre_vs_divida: só compara o ano da DRE
# contra o Mapa de Dívida quando o PERÍODO DO DOCUMENTO do mapa cobre esse ano
# (fn_anos_periodo do período do mapa) — o Mapa é um retrato de UMA data
# (MEDIDO EM PRODUÇÃO, 25/09/2026: todo MAPA_DIVIDA hoje tem período de um ano
# só), e antes desta migration a checagem comparava CADA ano da DRE contra a
# soma de juros do documento inteiro, sem recorte — inclusive anos que o mapa
# não cobre. Ano fora do período do mapa: sem_periodo_par (CONTRATO da 0186),
# não ok nem zona_cinzenta. Mapa sem período, ou período que não ancora ano
# nenhum: comportamento antigo, sem filtro. IDEMPOTENTE — não roda
# reconciliação nem recompute em caso nenhum. Testes: Supabase/test/despfin_-
# ano_par_do_mapa.test.sql (via run.sh).
supabase db execute --file Supabase/migrations/0191_o_mapa_de_um_ano_contra_a_dre_de_dois.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0191' and not presente;                 -- ZERO linhas
# E, depois da próxima rodada de um caso com DRE multi-ano e Mapa de Dívida de
# um ano só, o ano fora do período do mapa parando de comparar:
#   select motivo_precondicao, count(*) from reconciliacao
#    where tipo = 'despfin_dre_vs_divida' and motivo_precondicao = 'sem_periodo_par'
#      and criado_em > '<data do apply>' group by 1;

# 0192: dentro da MESMA rodada (fn_reconciliar_caso, uma transação), um achado
# que CONCLUIU divergente/divergencia/zona_cinzenta prevalece sobre um ok ou
# uma pré-condição de OUTRO período compatível — antes, a ORDEM em que a
# rodada visitava as chaves decidia se a divergência terminava aberta ou
# resolvida (medido em produção 25/09/2026: 4 pendências divergencia_-
# reconciliacao criadas e resolvidas no MESMO instante). fn_reconciliar_caso
# ganha `order by` — determinismo de qual período a pendência carrega.
# IDEMPOTENTE (reemissão de função + catálogo).
# Testes: Supabase/test/divergencia_prevalece_na_rodada.test.sql (via run.sh).
supabase db execute --file Supabase/migrations/0192_o_ok_que_matava_a_divergencia_irma.sql
# DEPOIS DE APLICAR, as pendências já nascidas-e-mortas na mesma rodada (4
# medidas em 25/09/2026) NÃO se corrigem sozinhas — só a próxima rodada de
# cada caso resolve/mantém com a guarda nova. Para achar as antigas:
#   select id, caso_id, motivo, criada_em, resolvida_em from pendencia
#    where motivo like 'reconciliacao:%' and tipo = 'divergencia_reconciliacao'
#      and criada_em = resolvida_em;
# E que o requisito novo está presente:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where chave = 'ok_nao_mata_divergencia_irma';                  -- presente = true

# A 0193 REEMITE fn_reconciliar_caixa_bp_fluxo e fn_reconciliar_receita_-
# dre_vs_faturamento: a mesma correção que a 0188 aplicou na despfin — a
# tolerância absoluta passa a estar em moeda BASE, não multiplicada pelo
# fator de escala do documento (numa DRE/Balanço em 'milhar', o piso virava
# 1000× maior que o default). MEDIDO EM PRODUÇÃO (25/09/2026, somente
# leitura): efeito ZERO hoje — 0 das 33 caixa_bp_fluxo e 0 das 30 receita_-
# dre_vs_faturamento com resultado 'ok' mudariam de resultado com a
# tolerância na base. Correção LATENTE (mesmo vício estrutural da despfin,
# ainda sem caso real que o exercite). IDEMPOTENTE — não roda reconciliação
# nem recompute em caso nenhum; as assinaturas não mudam.
# Testes: Supabase/test/tolerancia_na_base.test.sql (via run.sh).
supabase db execute --file Supabase/migrations/0193_a_tolerancia_que_crescia_com_a_escala.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0193' and not presente;                 -- ZERO linhas
# E, se algum dia esta correção DEIXAR de ser latente (uma checagem em milhar
# muda de 'ok' para 'divergente'/'zona_cinzenta' na próxima rodada de um
# caso), a diferença aparece nas linhas novas de reconciliacao — não há nada
# para reprocessar à mão, e nada muda sozinho nas linhas já gravadas.

# A 0194 REEMITE fn_reconciliar_mutuos: a planilha de mútuos de PRODUÇÃO é um
# RETRATO de uma data (conceito na coluna — 0145), não uma demonstração
# comparativa. MEDIDO EM PRODUÇÃO (25/09/2026, somente leitura): os 12 casos
# com planilha MUTUOS nunca concluem — resultado documento_ausente, inclusive
# nos 7 que TÊM conta de mútuo no balanço, com um texto de descrição FALSO
# ("nenhum balanço traz conta de mútuo"). Causa: fn_coluna_periodo_do_ano
# devolve a sentinela para um retrato (nenhuma coluna é "ano"), e o filtro do
# lado da planilha, escrito para NULL, zerava a soma. Agora, quando o
# documento escolhido para o ano cobre de fato o ano, a coluna do saldo é
# achada pelo localizador que a 0145 já cadastrou para este conceito
# (MUTUOS/saldo_de_mutuo, termo 'saldo'). Sem coluna de saldo, ou planilha
# sem linha para o lado do balanço: linha_nao_localizada; escala
# incomparável: unidade_divergente — abrem pendência (0186), diferente de
# documento_ausente, que continua reservado a "nenhum balanço tem conta de
# mútuo" OU "planilha deste exercício não entregue" (comportamento desenhado
# da 0117/0123, preservado). IDEMPOTENTE — não roda reconciliação em caso
# nenhum; as fixtures dos dois books gravam periodo_coluna como o ANO (não o
# cabeçalho), então o ramo novo nunca dispara sobre elas — nenhum assert
# existente muda.
#
# A REVISÃO DE FIDELIDADE (28/09/2026, ANTES de aplicar) mediu três achados
# sobreviventes na primeira versão desta migration, corrigidos NO MESMO
# arquivo (nunca foi aplicada, então corrigir no lugar é permitido — como a
# 0187/0188 já fizeram):
#   1. o balanço por entidade era escolhido só por `criado_em`, sem olhar o
#      ANO — um documento "multi 24,25" sem coluna nem linha de mútuo vencia
#      o "anual 2025" que TEM a linha. Agora é por ANO: o que TRAZ dado do
#      exercício vence.
#   2. fn_lado_do_mutuo era aplicada à CHAVE da planilha-retrato, que é o
#      PAR de empresas, não um lado — "administr**ativo**s" casava "ativo" e
#      derrubava linha boa. Agora o filtro de lado só vale para planilha
#      COMPARATIVA (0123); numa planilha-retrato ele não se aplica.
#   3. a planilha era escolhida UMA vez para a checagem inteira — o ano que
#      ela não cobria virava sem_periodo_par mesmo quando o caso tinha a
#      planilha certa de OUTRO ano. Agora é por ANO: sem planilha própria de
#      um ano é "não entregue" (documento_ausente, cobrança de checklist),
#      não pendência falsa.
#   ACOMPANHAMENTO (28/09/2026, tarde): o achado 1 foi ESTENDIDO — um
#   documento SEM `periodo_coluna` (retrato/anual de um ano só) só conta para
#   `v_ano` quando o PRÓPRIO PERÍODO do documento ancora esse ano, não para
#   qualquer ano perguntado (o "anual 2025" de uma entidade não pode contar
#   para 2023). MEDIDO em produção só-leitura: corrigiu "Teste 00"/2023, que
#   tinha ficado SUSPEITO na primeira medição — ver a nota completa (com o
#   número final, não mais "suspeito") no cabeçalho da migration. TAMBÉM
#   ACHADO, e NÃO CORRIGIDO aqui (fora do escopo, é outra função):
#   fn_reconciliar_intragrupo (0124) tem o MESMO vício de linha — medido em
#   7 casos de produção, praticamente 100% das linhas `intragrupo_espelho`
#   incluídas por ano vêm de um documento que não ancora aquele ano.
# Testes: Supabase/test/mutuos_retrato_de_uma_data.test.sql (via run.sh) — 9
# blocos, com os cenários dos três achados + o acompanhamento (5 casos base +
# 4 novos).
supabase db execute --file Supabase/migrations/0194_a_planilha_de_mutuos_que_nunca_foi_lida.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0194' and not presente;                 -- ZERO linhas
# E, na próxima rodada de cada caso com planilha MUTUOS, o efeito MEDIDO
# (28/09/2026, somente leitura, REMEDIDO depois do acompanhamento acima —
# não estimado; ver a tabela completa no cabeçalho da migration):
#   - teste - Canastra / teste Canastra / Teste comparativo - Grupo Canastra /
#     teste v48: 2025 passa a CONCLUIR zona_cinzenta, diff R$ 240 mil (a
#     divergência plantada do book Canastra, finalmente acusada); 2023/2024
#     ficam documento_ausente (a planilha do caso é só de 2025 — cobrança de
#     checklist, não achado).
#   - Teste 00: 2025 idem (zona_cinzenta, 240 mil); 2023 CONTINUA
#     zona_cinzenta (diff ~32 mi), mas o número agora está EXPLICADO: os
#     balanços comparativos de 2023 do caso simplesmente não têm linha de
#     mútuo (0 linhas, conferido nos campo_extraido) — só 2 entidades têm
#     documento próprio de 2023. Não é bug da checagem; é achado real de
#     dado incompleto no balanço.
#   - teste alto volume - grupo araucária: 2021/2022 MUDARAM depois do
#     acompanhamento (o vazamento saindo da conta) e 2023/2024/2025 passam a
#     FECHAR (240 mil, como os outros casos) — antes ficavam presos em "os
#     dois lados não se espelham" por causa do mesmo vazamento.
#     CORREÇÃO (30/09/2026): o que sobrava em 2021/2022 (409 e 890 mil de
#     "divergência real" entre os lados do balanço) NÃO era divergência: era a
#     mesma conta "Mútuos a pagar - controladora" somada na face e na nota
#     "Partes Relacionadas" do doc 2f17a7ba. Corrigido na 0195 (deduplicação
#     da conta repetida no mesmo documento): os cinco anos fecham exatos, cada
#     um com os 240 mil da planilha.
#   - Araucária teste: mesma leitura — anos que se espelham reproduzem 240
#     mil; 2021/2025 continuam "os dois lados não se espelham" (achado real
#     dos balanços, não da planilha, comportamento já desenhado pela 0123).
# Para achar as linhas antigas (gravadas ANTES desta migration, que não se
# corrigem sozinhas):
#   select id, caso_id, criado_em from reconciliacao
#    where tipo = 'mutuos_planilha_vs_balanco' and resultado = 'precondicao_nao_satisfeita'
#      and motivo_precondicao = 'documento_ausente';

# A 0195 FATORA fn_linha_vale_para_ano (a conta que a 0194 escreveu duas
# vezes dentro de fn_reconciliar_mutuos) e reemite fn_reconciliar_mutuos
# usando-a — SEM MUDAR COMPORTAMENTO nisso (só o mecanismo; nenhum assert de
# canastra.test.sql/reconciliacao.test.sql/mutuos_retrato_de_uma_data.test.sql
# muda). GRUPO A DA REVISÃO (30/09/2026, no mesmo arquivo): mútuos deixa de
# somar duas vezes a mesma conta na face e na nota do mesmo documento (doc
# 2f17a7ba: as 'divergências' de 409 e 890 mil eram essa duplicata); `d.id`
# fecha o desempate de criado_em (44 grupos, 160 documentos, 14 casos
# empatam); o 'tem dado intragrupo' exige contraparte/lado/escala. Teste:
# Supabase/test/espelho_grupo_a.test.sql. fn_reconciliar_intragrupo (0124) ganha os DOIS consertos que a 0194
# já tinha aplicado a mútuos e registrado, sem corrigir, no próprio
# cabeçalho: o balanço de cada entidade agora é escolhido POR ANO (o que TEM
# dado intragrupo do exercício vence o que só ancora o ano sem trazer
# linha), e uma linha de documento sem periodo_coluna só vale para o ano que
# o PRÓPRIO PERÍODO do documento ancora — não para qualquer ano perguntado.
# MEDIDO EM PRODUÇÃO (28/09/2026, somente leitura, réplica fiel do filtro da
# 0124): nos 7 casos com intragrupo, praticamente 100% das linhas incluídas
# por (caso, ano) vinham de um documento que não ancora aquele ano ("teste -
# Canastra"/2023: 4 de 4; "teste alto volume"/2025: 5 de 5; "Araucária
# teste", os 5 anos, sempre 100%). Historicamente `reconciliacao` tem 52
# linhas intragrupo_espelho ok e 117 documento_ausente, ZERO zona_cinzenta —
# consistente com "ok" por SORTE (o mesmo saldo vazando para todo ano), não
# com o defeito não existir (ver a tabela completa no cabeçalho da
# migration). IDEMPOTENTE — não roda reconciliação em caso nenhum; as
# fixtures dos dois books não exercitam o vício (cada entidade só tem UM
# documento BALANCO no Canastra, e a única entidade com dois no Vertentes já
# tinha o documento certo vencendo pela prioridade de tipo) — nenhum assert
# existente muda.
# Testes: Supabase/test/intragrupo_le_o_ano_certo.test.sql e
# Supabase/test/espelho_grupo_a.test.sql (via run.sh).
supabase db execute --file Supabase/migrations/0195_o_espelho_que_lia_o_balanco_de_outro_ano.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0195' and not presente;                 -- ZERO linhas
# E, na próxima rodada de cada caso com intragrupo, o efeito PREVISTO
# (réplica da lógica corrigida, somente leitura — ver a tabela completa no
# cabeçalho da migration): os 52 ok históricos continuam ok (mesmos números,
# menos anos por caso); os anos sem balanço próprio do par passam de "ok"
# fabricado para documento_ausente, honesto. Para achar as linhas antigas
# (gravadas ANTES desta migration, que não se corrigem sozinhas):
#   select id, caso_id, criado_em from reconciliacao
#    where tipo = 'intragrupo_espelho' and resultado = 'ok';

# A 0196 REEMITE fn_reconciliar_caixa_bp_fluxo, fn_reconciliar_receita_dre_vs_faturamento,
# fn_reconciliar_despfin_dre_vs_divida e fn_somar_faturamento_ano. O DEFEITO (30/09/2026,
# caso bb37f726, book-vertentes): a DFC ANUAL 2025 (sem periodo_coluna) era lida como saldo
# final de 2024 e o Balanço "multi 24,25" (Disponível 2024 = 4.840) saía `divergente` — pendência
# Classe A FALSA de R$ 4,34 mi. É o MESMO R$ 4,34 mi do "Teste v33/v35" que o cabeçalho da 0192
# descreveu como divergência real: era falso positivo (a 0192, já aplicada, não foi editada).
# A causa é a da 0194/0195 (linha sem periodo_coluna vale para qualquer ano); a correção usa
# fn_linha_vale_para_ano nos dois lados, e o ano sem linha válida vira `sem_periodo_par`, com a
# frase "Não comparado — 2024: ..." na descrição (regra 1). MESMO VÍCIO, provado por teste, na
# receita (DRE de um ano só) e na despesa financeira (latente: 0 de 17 em produção); NÃO têm:
# ativo_passivo_pl (compara dentro do mesmo documento). SEGUNDO DEFEITO, mesmo caso: o faturamento
# "jan/2024 — jan/2025" com colunas 2024, 2025 e 'Variação %' somava as três (321.579,6 em vez dos
# 183.480 de 2024); agora o ano sai da coluna e percentual nunca entra na soma.
# MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): 5 pendências abertas de caixa com o arranjo, em 4
# casos (4 só com o 2024 falso; a 5ª, caso 03c8804c, tem também 2025 = 320 contra 500, real);
# 3 de 25 receitas; 1 documento de faturamento com 'Variação %'. SEM BACKFILL: vale na próxima
# rodada de cada caso, e as 4 pendências falsas se resolvem sozinhas quando a checagem rodar.
# Teste: Supabase/test/caixa_dfc_de_um_ano.test.sql (21 asserts; 17 reprovam com as 4 funções
# de volta ao corpo anterior). ACHADO NÃO CORRIGIDO: fn_reconciliar_ativo_passivo_pl ainda
# multiplica a tolerância absoluta pelo fator de escala (vício da 0188/0193).
supabase db execute --file Supabase/migrations/0196_o_caixa_que_lia_a_dfc_de_outro_ano.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0196' and not presente;                 -- ZERO linhas
# E para achar as pendências de caixa que a correção vai fechar na próxima rodada:
#   select id, caso_id from pendencia where motivo = 'reconciliacao:caixa_bp_fluxo'
#    and estado = 'aberta' and descricao like '%2024: Caixa no Balanço%';

# A 0197 REEMITE fn_somar_faturamento_ano (achado da revisão da 0196). (1) Faturamento com o mês na
# COLUNA (chave "Faturamento", colunas "jan/2024"…) somava 0 meses, porque a 0196 exigia que o
# RÓTULO parecesse um mês, e a receita ficava sem conferência com um motivo FALSO ("não traz linha
# mensal deste ano"); agora a coluna "mês/ano" do ano pedido conta como mês. (2) O `not like '%médi%'`
# era código morto (o texto normalizado é "medio"): "Ticket médio por pedido 2024" entrava na soma.
# Coluna-INTERVALO "jan/2024 — jan/2025" (uma célula) NÃO é atribuída a ano: segue 0 meses.
# MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): 84 documentos de faturamento; 9 com mês na coluna somavam 0 meses (v20-v23, v27, v28, v29, v40, Canastra) e passam a somar; v24 somava o ticket (38,2) e passa a 0 meses; v33/v35/v39 têm coluna-INTERVALO e seguem 0 (conserto na extração); 76 dos 90 pares com soma não mudam.
# SEM BACKFILL: vale na próxima rodada de cada caso.
# Teste: Supabase/test/faturamento_mes_na_coluna.test.sql (13 asserts; 9 reprovam sem a 0197).
supabase db execute --file Supabase/migrations/0197_o_faturamento_que_nao_via_o_mes_na_coluna.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0197' and not presente;                 -- ZERO linhas

# A 0198 REEMITE fn_anos_periodo: a FAIXA "AAAA-AAAA" perdia o ano do meio ("multi 2024-2026" = 2024 e
# 2026). MEDIDO EM PRODUÇÃO (30/09/2026, só-leitura): 1 período muda de conjunto, o do Mapa de Dívida do
# Krauspenhar (4 reconciliações gravadas, todas sem_periodo_par, não regravadas); sem backfill. Não expande
# faixa ambígua (fim antes do início, >10 anos, 2 dígitos) nem data. ACHADO NÃO CORRIGIDO: listas de 2
# dígitos que não são anos ("multi 02,25" = 2002 e 2025; 5+5+5+5 períodos em produção).
# Teste: Supabase/test/faixa_de_anos_do_periodo.test.sql (9 asserts; 4 reprovam sem a 0198).
supabase db execute --file Supabase/migrations/0198_a_faixa_de_anos_que_perdia_o_ano_do_meio.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0198' and not presente;                 -- ZERO linhas

# A 0199 REEMITE fn_valores_por_ano (mesma assinatura): a série por ano lia "Débito"/"Crédito" do balancete
# como saldo, "Saldo Inicial"/"Saldo anterior" como o ano do documento, o saldo de 30/06 como o de 31/12 e o
# CONTRATO_SOCIAL como PL. MEDIDO EM PRODUÇÃO (05/10/2026, só-leitura, Fw Valtra 03a66ab6): ATIVO 2025 =
# 125.859.727,84 (Débito) onde o balanço diz 38.483.404,04; o balanço do modelo não fechava em ~90,5 mi.
# Sem backfill: o modelo muda no PRÓXIMO export de cada caso. fn_ano_da_coluna e fn_linhas_do_realizado NÃO mudam.
# Teste: Supabase/test/serie_por_ano_movimento_e_abertura.test.sql (21 asserts; 19 reprovam sem a 0199).
supabase db execute --file Supabase/migrations/0199_a_serie_por_ano_que_lia_movimento_e_abertura_como_saldo.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0199' and not presente;                 -- ZERO linhas

# A 0200 REEMITE fn_valores_por_ano (mesma assinatura): a 0199 decidia "o parcial entra se for a única fonte"
# POR RÓTULO, e as centenas de contas analíticas do BALANCETE semestral (código no rótulo) não existem no
# BALANCO anual — para cada uma o balancete era a "única fonte" e entrava POR CIMA do balanço do mesmo ano.
# MEDIDO EM PRODUÇÃO (05/10/2026, depois da 0199, Fw Valtra 03a66ab6): resíduo do ATIVO CIRCULANTE de
# -36.014.142 (2024) e -46.902.843 (2025). Agora a decisão é do ANO: parcial só entra se a entidade não tem
# ocorrência ANUAL da mesma família (patrimonial / resultado / fluxo / seção própria) naquele ano.
# Sem backfill: o modelo muda no PRÓXIMO export de cada caso.
# Teste: Supabase/test/serie_por_ano_balancete_sob_balanco_anual.test.sql (17 asserts; 6 reprovam sem a 0200, 10 com a regra ao contrário).
supabase db execute --file Supabase/migrations/0200_o_balancete_semestral_que_entrava_por_cima_do_balanco_anual.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0200' and not presente;                 -- ZERO linhas

# A 0201 ENSINA fn_linhas_do_realizado A LER "Saldo Final"/"Saldo atual"/"Saldo Inicial"/"Saldo anterior". A 0150 só achava
# exercício com ANO NO TEXTO da coluna; o documento anual do Fw Valtra (BALANCO e DRE ref "2025") rotula as colunas sem ano, e
# o documento INTEIRO ficava fora: a função devolvia só as linhas do DFC e a tela de modelagem mostrava TODAS as sugestões do
# realizado vazias (CUSTO_VARIAVEL, SGA_PCT, PMR, PME, PMP, ALIQUOTA, PARCELA_ONEROSA, TAXA_DIVIDA). MEDIDO EM PRODUÇÃO (05/10/2026).
# A conta de classificar coluna/período sai de fn_valores_por_ano para cinco funções puras que as DUAS chamam (fn_coluna_e_abertura,
# fn_coluna_e_movimento, fn_coluna_e_saldo, fn_periodo_e_parcial, fn_familia_da_secao); fn_valores_por_ano é reemitida com o mesmo
# comportamento. O requisito da 0199 no catálogo é REAPONTADO para fn_coluna_e_abertura (mesmo marcador).
# Sem backfill: a tela muda no próximo carregamento. Teste: Supabase/test/realizado_le_saldo_final_e_atual.test.sql (27 asserts; 18 reprovam sem a 0201).
supabase db execute --file Supabase/migrations/0201_o_realizado_que_nao_lia_saldo_final_e_saldo_atual.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration in ('0199', '0201') and not presente;      -- ZERO linhas

# A 0202 REEMITE fn_papel_linha (mesma assinatura): o código contábil do ERP na frente do rótulo ("2.3.71 TOTAL — saldo devedor")
# escondia o prefixo total/subtotal/soma e os grupos estruturais, e a linha de TOTAL do Mapa de Dívida virava uma tranche a mais.
# MEDIDO no arnês de variações (codigo_contabil_no_rotulo): dívida de 102.600 onde o documento diz 51.300; CP 2024 46.924 contra
# 23.462. Nova função fn_sem_codigo_de_conta (a mesma definição de CODIGO_DE_CONTA_NO_INICIO do portal). Sem backfill: o papel é
# calculado na leitura. Teste: Supabase/test/papel_total_com_codigo_contabil.test.sql (21 asserts; 13 reprovam sem a 0202).
supabase db execute --file Supabase/migrations/0202_o_total_com_codigo_contabil_que_virava_conta.sql
# DEPOIS DE APLICAR, confira o catálogo:
#   select chave, presente, detalhe from fn_instalacao_conferir()
#    where migration = '0202' and not presente;                 -- ZERO linhas

# ---------------------------------------------------------------------------
# DEPOIS DE APLICAR, CONFIRA — e a conferência não é reler esta lista.
#
# Em 02/09/2026 um banco parado na 0150 foi medido: `fn_instalacao_conferir()`
# NÃO acusava nada, e três chamadas de nó do workflow de ingestão não resolviam
# nele (`fn_abrir_lote_execucao`, `fn_reconciliar_caso` e o
# `fn_reconciliar_por_documento` que existe com a assinatura ANTIGA). O `Abrir
# Lote` é o primeiro nó depois de o orçamento aprovar o lote: a rodada morreria
# no começo. A sonda não podia ver — o catálogo dela mora dentro do banco, e um
# banco na 0150 tem o catálogo da 0150.
#
# Este comando faz a outra pergunta, a que só o repositório sabe fazer: o que o
# código que vai rodar chama existe AQUI? Ele nomeia o nó de cada chamada
# quebrada. 0 = tudo resolve · 1 = achei · 2 = não consegui perguntar.
CONFERIR_PSQL="psql 'postgresql://…@…supabase.co:5432/postgres'" \
  node Supabase/test/conferir-chamadas.mjs
# ---------------------------------------------------------------------------

# OPCIONAL, e só depois da 0119: migra as pendências dos casos JÁ GRAVADOS para
# o formato por entidade agora, em vez de esperar o próximo recomputo natural
# de cada um. Faz aparecer uma leva de pendências novas na fila do painel — é
# por isso que ela é um passo à parte, e não um bloco dentro da migration.
# supabase db execute --file Supabase/varredura_linha_exigida.sql

# Carga inicial dos índices macro (depois da 0025; não é migration, é dado):
supabase db execute --file Supabase/seed/macro_carga_inicial.sql
```

> 🔎 **MERGE NÃO É APPLY — e da tela os dois são iguais.** O PR entrar no `main` não
> muda uma linha do Supabase; a migration só existe quando o comando acima roda. Foi
> exatamente aqui que a rodada da `0101` se perdeu: a migration estava na tabela deste
> arquivo e **não** na lista de comandos acima, o dono aplicou o que a lista mandava, e a
> tela de Modelagem seguiu mostrando o defeito antigo — parecendo que o PR não tinha
> funcionado. Para não precisar adivinhar, a `0102` traz um diagnóstico; rode no SQL
> Editor:
>
> ```sql
> select jsonb_pretty(fn_diagnostico_modelagem('<caso_id>'));
> ```
>
> **Se o diagnóstico vier tudo `true` e a tela AINDA mostrar timeout**, o problema não é
> mais SQL — a lógica foi medida em 490 ms como `authenticated`, com RLS, e com as sete
> chamadas da página concorrentes. Aí rode **`Supabase/diagnostico_modelagem.sql`**, que separa as
> quatro causas de ambiente que sobram: portal apontando para outro projeto Supabase,
> `statement_timeout` do papel `authenticated` menor que os 8 s presumidos, instância
> estrangulada de CPU, ou render anterior ao apply.
>
> `correcoes_instaladas` responde direto se as funções em pé no banco são as da
> `0101`/`0102`; `ocorrencias_superadas` diz quantas ocorrências vinham de versão
> superada de documento; `linhas` e `linhas_por_papel` dizem o que a tela **deve**
> mostrar, para comparar com o que ela está mostrando. `Supabase/test/run.sh` agora reprova
> migration que exista e não esteja na lista acima, para o esquecimento não repetir.

> ⚠️ **DEPOIS DE APLICAR QUALQUER MIGRATION QUE CRIE OU DERRUBE FUNÇÃO, recarregue o
> cache de schema do PostgREST:**
>
> ```sql
> notify pgrst, 'reload schema';
> ```
>
> O PostgREST (a API que o portal usa) guarda um catálogo próprio das funções expostas.
> Função recém-criada **não existe para ele** até esse `notify` — e função derrubada
> continua existindo. Enquanto o cache está velho, a chamada volta erro de "função não
> encontrada", e a tela que não lê o `.error` mostra isso como **lista vazia**: foi
> exatamente assim que a Modelagem anunciou "este caso ainda não tem linha extraída"
> num caso com 203 linhas, logo depois da `0100`. A tela agora denuncia o erro em vez
> de engoli-lo, mas o `notify` continua sendo parte de aplicar a migration, não um
> extra.

> ⚠️ **Se o N8N reportar `function ... does not exist` mesmo com a função existindo no banco**
> (ex.: após aplicar migrations parcialmente/mais de uma vez), a `0006` derruba qualquer versão
> divergente das 4 funções RPC e recria do zero — mas ela recria os corpos **da época dela**, e
> desde então quase todas foram redefinidas. Rodar a `0006` sozinha **REGRIDE o schema**: some a
> idempotência por hash (`0026`), somem `confianca`/`fonte`/`justificativa` no documento (`0008`),
> somem as guardas de extração (`0013`/`0016`) e o auto-aceite (`0019`), e volta o overload morto de
> 14 args que a `0026` removeu. Se precisar do reset, **continue aplicando 0007 → 0031 em ordem**
> logo depois: cada migration posterior redefine o que é dela, e só a sequência completa devolve o
> estado atual. Não precisa reaplicar 0001-0005 antes (a `0006` assume as tabelas já criadas).
> (Achado da auditoria: `reset-0006-regride-funcoes`.)

**Opção B — psql direto** (usar o **Session Pooler**; herdar a pegadinha do `clipping-news`:
IPv4 + SSL, usuário do pooler com sufixo `.projectref`):
```bash
psql "$SUPABASE_DB_URL" -f Supabase/migrations/0001_schema_fatia1.sql
psql "$SUPABASE_DB_URL" -f Supabase/migrations/0002_seed_taxonomia_e_dial.sql
psql "$SUPABASE_DB_URL" -f Supabase/migrations/0003_rls_e_storage.sql
```

## O teto de 1000 linhas do PostgREST (`db-max-rows`) — o que é, e onde ele mora

O Supabase serve a API por **PostgREST**, e ele devolve no máximo `db-max-rows` linhas por
requisição — **1000 por padrão**, cortando acima disso **em silêncio, sem erro nenhum**. Não é
configuração deste repositório: é do PROJETO, e só o dono a alcança.

**Onde mudar:** painel do Supabase → *Project Settings* → *API* → **Max rows**. O valor vale para
toda a API do projeto (portal e n8n). Subir para 100000, ou para o maior número que o projeto
aceitar, remove o teto na prática; salvar recarrega o PostgREST sozinho.

**O portal não depende mais desse ajuste, e essa é a parte que importa.** Toda leitura que pode
crescer passa por `portal/src/lib/supabase/paginar.ts`, que lê em janelas até o banco não ter mais
o que dar — **qualquer que seja o teto do servidor**, alto, baixo ou removido. Subir o `Max rows`
deixa cada leitura mais barata (menos idas ao banco); não subir não corta nada.

**O que continua exigindo atenção:** consulta nova que devolva lista e não passe pelo `paginar`
volta a estar sujeita ao teto — e o sintoma é um número redondo (exatamente 1000) ou uma lista que
"termina" cedo, nunca um erro. Ficam fora de propósito, porque não crescem com a mesa: catálogos
(taxonomia, premissas, séries macro, banco de perguntas), consultas de linha única (`.single()`,
`.maybeSingle()`) e as duas listas com `limit` deliberado (barra lateral, trilha de autonomia).

## Notas de segurança (LGPD) — ler antes de conectar clientes

- **service_role ignora RLS** (é o que o N8N usa como orquestrador). O portal Vercel **nunca**
  deve usar a service_role — só chave `anon`/`authenticated`, que respeita RLS.
- Bucket `documentos` é **privado**; nunca gerar URL pública — usar signed URLs.
- **TODO de fatia posterior:** restringir RLS por caso (membership) e reforço para documentos
  `pii_sensivel` (`DOCS_SOCIOS`, `AVAIS_FIANCAS`, `HEADCOUNT`).

## Testes locais

```bash
PGHOST=/tmp PGPORT=5432 PGUSER=postgres Supabase/test/run.sh
```

Recria um banco descartável, aplica as **23 migrations em ordem**, carrega o fixture do book
Vertentes (`Supabase/test/fixture_book_vertentes.sql` — extração FIEL dos 14 documentos) e roda
`Supabase/test/reconciliacao.test.sql`. A invariante central: **extração fiel não abre nenhuma pendência
de reconciliação**; cada checagem tem também um caso negativo provando que continua pegando o erro
real (balanço que não fecha, escala desconhecida, caixa que não bate, faturamento que não amarra,
rótulo irreconhecível). O fixture é gerado por `Supabase/test/gerar_fixture.py` a partir do próprio
gerador do book — para regerá-lo:

```bash
cd "Dados de Teste"/book-vertentes
PYTHONPATH=. python3 ../../Supabase/test/gerar_fixture.py > ../../Supabase/test/fixture_book_vertentes.sql
```

## Verificação rápida (após aplicar)

```sql
-- Taxonomia populada? (esperado: 8 obrigatórios do Kit Básico)
select obrigatoriedade, count(*) from taxonomia_tipo_documento group by obrigatoriedade;

-- Dial de autonomia inicial? (esperado: 8 estágios)
select estagio, nivel_atual, teto from estagio_autonomia order by estagio;

-- RLS ligado em todas as tabelas de dados?
select relname, relrowsecurity from pg_class
where relname in ('caso','documento','pendencia','evento_auditoria') order by relname;
```

## O que NÃO está aqui (entra em fatias seguintes)

O refinamento de RLS por caso, e as Classes B/C de reconciliação (`Arquitetura do Sistema/2 Especificação/04_RECONCILIACAO.md`
— continuam N1/aproximação, não têm engine determinística ainda). O Portão 2 formal
(`Arquitetura do Sistema/3 Estado e Execução/07_STATUS_E_PENDENCIAS.md`: bloqueantes não-sobrepujáveis, teto/expiração de ressalva)
também não está aqui — `fn_aceitar_extracao` (0011) é só o aceite mínimo por linha extraída,
não a regra de portão do caso inteiro. Ver o plano da F1 e `Arquitetura do Sistema/2 Especificação/f0/05_schema_conceitual.md`.
(`campo_extraido` entrou em `0005`; `reconciliacao` — Classe A — entrou em `0009`; aceite/E4
entrou em `0011`.)

## Consultas de leitura (não são migration, não mudam nada)

Ficam na raiz de `Supabase/` e se rodam no SQL Editor do Supabase. Cada uma responde uma pergunta
que, sem ela, é uma tarde clicando no portal — e que não deixa rastro nenhum depois.

| Arquivo | Responde |
|---|---|
| `diagnostico_rodada.sql` | O raio-X de um mandato depois de uma rodada: uma linha por documento, com tipo, confiança, quem classificou, contas e colunas extraídas, escala, moeda, seções canônicas e pendências |
| `pendencias_do_mandato.sql` | Toda pendência aberta do mandato, por severidade, com descrição e motivo |
| `diagnostico_modelagem.sql` | O estado da modelagem de um caso |
| `varredura_linha_exigida.sql` | As linhas exigidas pelo modelo institucional |

Em todas, o nome do mandato vai na primeira linha.
