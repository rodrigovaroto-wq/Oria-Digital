-- =============================================================================
-- 0216 — O ACESSO QUE SÓ O PORTAL DECIDIA: papéis Sócio · Analista · Leitura e RLS POR MANDATO, no banco (portal, Fase 5, parte 1)
-- (Cria 2 tabelas, 18 funções (mais 4 de gatilho), 5 gatilhos de guarda e TROCA toda policy `to authenticated` (65 em public + 1 em storage.objects,
--  todas `using (true)`/`with check (true)` exceto `caso_pergunta_reapontar`) por policy por mandato. Muda o que o navegador do portal
--  enxerga; NÃO muda o que o n8n e o SQL Editor fazem (ver "Quem escreve"). Backfill: o BOOTSTRAP abaixo.)
--
-- >>> ATENÇÃO — BOOTSTRAP (leia antes de aplicar) <<<
-- >>> ESTA MIGRATION PROMOVE A SÓCIO **TODOS OS USUÁRIOS QUE EXISTEM EM auth.users NO MOMENTO DE APLICAR** (o time atual da Oria).
-- >>> Sócio vê e escreve TUDO, inclusive aprovar, fechar e excluir mandato e gerir a equipe. Abra Authentication > Users antes
-- >>> e remova/desative quem não deve ver tudo (convidado externo, conta de teste): quem estiver lá vira Sócio. Sem isto ninguém
-- >>> acessaria nada depois da migration (RLS sem papel nega tudo).
-- >>> USUÁRIO CRIADO DEPOIS NASCE SEM PAPEL e NÃO VÊ NADA (nem o catálogo de taxonomia) até um Sócio chamar
-- >>> fn_definir_papel(<uuid>, 'analista'|'leitura'|'socio') e, para Analista/Leitura, fn_alocar(<caso>, <uuid>).
-- >>> A sonda tem o requisito `acesso_socio_seed` (>= 1 linha em `membro`): banco sem Sócio acusa bloqueante.
-- >>> Quantos usuários o bootstrap alcança em PRODUÇÃO eu NÃO medi (sem conexão): `select count(*) from auth.users`.
--
-- A DECISÃO DO DONO (29/10/2026):
--   Sócio    tudo, em todos os mandatos: aprovar, fechar/reabrir/excluir mandato, mudar o dial, gerir equipe (papéis e alocações).
--   Analista lê e ESCREVE só nos mandatos em que está alocado; cria mandato (e fica alocado nele).
--   Leitura  só LÊ os mandatos em que está alocado.
--   (sem papel: nada.)
--
-- O DEFEITO. `Supabase/migrations/0003` deixou escrito "TODO (fatia posterior): restringir por caso (membership)", e 213 migrations
-- depois toda policy de `authenticated` ainda era `using (true)`: qualquer usuário logado lia e escrevia TODOS os mandatos, e o
-- portal só escondia o que a interface não mostrava (`Arquitetura do Sistema/7 Marca/PRODUCT.md`: "RLS por caso não existe ainda"). Interface que sugere separação
-- de acesso que o banco não garante é pior que nenhuma interface, e a tela de equipe (resto da Fase 5) não pode existir antes disto.
--
-- ===== 1. O MAPA — as tabelas com RLS e como cada uma chega ao `caso_id` (medido em 29/10/2026 no banco de teste migrado até a 0215) =====
-- 51 tabelas em public (50 com RLS e policy; `golden_criterio` SEM RLS — qualquer authenticated lia e escrevia) + storage.objects.
--   direto, coluna `caso_id` (19): arquivo_oficial, caso_apresentacao_campo, caso_linha_premissa, caso_modelagem, caso_pergunta,
--     caso_premissa, checklist_item_status, controlador, controlador_vinculo, decisao, documento, entidade, entidade_controlador,
--     execucao_falha (caso_id pode ser NULL), lote_execucao, pendencia, perimetro, periodo, reconciliacao.
--   o próprio `caso` (id).
--   por join (7): documento_versao -> documento (documento_id); campo_extraido e documento_fato -> documento_versao
--     (documento_versao_id); arquivo_oficial_registro e arquivo_oficial_lancamento_mes -> arquivo_oficial (arquivo_oficial_id);
--     campo_classe_override e campo_classe_sugerida -> campo_extraido (campo_extraido_id).
--   evento_auditoria: NÃO tem caso_id; o caso vem do PREFIXO de `entidade_ref` (medido: reconciliacao, documento, caso, entidade,
--     documento_versao, estagio, controlador, golden_rodada, pendencia). Prefixo sem caso (estagio:, golden_rodada:, membro:) ou
--     entidade que já não existe (a absorvida de uma fusão) resolve para NULL, e então só o Sócio lê.
--   storage.objects (bucket `documentos`): a chave é `<caso_id>/<sha256>.<ext>` (N8N/lib/hash.mjs); o primeiro segmento é o caso.
--   globais, só leitura (14): classe_contabil_catalogo, fato_tipo_catalogo, indice_macro_{expectativa,obs,serie}, instalacao_cobertura,
--     instalacao_requisito, pergunta_catalogo, rubrica_classe, taxonomia_linha_{alternativa,exigida,localizador},
--     taxonomia_tipo_cobertura, taxonomia_tipo_documento -> qualquer papel lê; sem papel, não.
--   globais que só o Sócio escreve (4; qualquer papel lê): estagio_autonomia (o dial), premissa_catalogo, golden_criterio, golden_rodada.
--   golden_documento, golden_campo, golden_rotulo: os rótulos citam documentos de QUALQUER mandato -> só o Sócio lê e escreve
--     (append-only, como antes). Consequência: fn_golden_cobertura devolve zero ao Analista (tela de administração é do Sócio).
--   NOVAS: membro (usuario_id -> auth.users; papel) e alocacao (caso_id, usuario_id). O authenticated só LÊ as duas; a escrita é por
--     fn_definir_papel/fn_alocar/fn_desalocar (security definer, só Sócio, com evento_auditoria) e pelo gatilho de criador (abaixo).
--   As 10 views `instalacao_sonda_*` (owner postgres) só expõem booleano/taxonomia, não dado de mandato: não mudam.
--
-- ===== 2. QUEM ESCREVE COM QUAL PAPEL =====
--   * n8n: Postgres NATIVO pelo Session Pooler (usuário postgres, BYPASSRLS) e Storage com a chave service_role (também ignora RLS) —
--     `Supabase/README.md` (notas de segurança) e `N8N/README.md` (credencial dos nós Postgres). CONFIRMADO NO REPOSITÓRIO, NÃO
--     EM PRODUÇÃO (sem conexão): confira `select rolname, rolbypassrls from pg_roles where rolname in ('postgres','service_role')`.
--     As guardas abaixo deixam passar a conexão de serviço (`fn_conexao_de_servico`: sem JWT E sem `set role authenticated/anon`).
--   * Portal: PostgREST como `authenticated` com o JWT do usuário; `auth.uid()` identifica quem é. Nunca service_role.
--   * FUNÇÕES: até a 0215 NENHUMA função de public era `security definer` ("a casa não usa", 0207/0213) — logo a RLS vale DENTRO de toda
--     RPC que o portal chama, e a policy da tabela é a checagem. A 0216 acrescenta funções security definer SÓ para ler `membro`/
--     `alocacao` sem recursão de RLS (fn_meu_papel, fn_eh_socio, fn_tem_papel, fn_pode_*, fn_casos_*, fn_caso_da_versao, fn_caso_do_evento,
--     fn_pode_escrever_evento, fn_alocado_agora, fn_exige_socio, fn_conexao_de_servico) e para as três de gestão (que checam fn_exige_socio
--     DENTRO, a primeira linha) e o gatilho de criador. Nenhuma função de NEGÓCIO virou definer.
--   As `.rpc(` do portal (grep em portal/src) e a decisão por função:
--     leitura, stable (herdam RLS; sem checagem): fn_avaliar_portao2, fn_documento_serve_como, fn_versao_com_extracao, fn_sazonalidade_do_caso,
--       fn_linhas_para_modelagem, fn_valores_por_ano, fn_sugerir_perguntas, fn_premissas_sugeridas, fn_perimetro_veredito,
--       fn_perimetro_situacao, fn_linhas_para_transcrever, fn_indice_macro_anual, fn_historico_do_caso, fn_golden_cobertura,
--       fn_fatos_do_caso, fn_falhas_abertas, fn_conferir_modelagem, fn_classe_contabil_concordancia.
--     escrita de TRABALHO (Analista alocado e Sócio; Leitura leva 42501; sem checagem própria, a RLS decide): fn_upsert_caso (criar mandato),
--       fn_aceitar_extracao, fn_revisar_documento, fn_registrar_transcricao_humana, fn_registrar_classe_override, fn_decidir_pendencia,
--       fn_registrar_pergunta_acao, fn_definir_modelagem, fn_vincular_linha_premissa, fn_ativar_premissa, fn_desativar_premissa,
--       fn_aplicar_premissa_em_lote, fn_controlador_registrar/_vincular_familia/_desvincular_familia, fn_entidade_definir_*, fn_perimetro_definir_escopo/
--       _encerrar_escopo, fn_resumo_iniciar/_anexar/_concluir, fn_fundir_entidade.
--     RESERVADAS AO SÓCIO (checagem por GATILHO, que vale também para o UPDATE/DELETE direto pelo PostgREST): fn_aprovar_caso (status ->
--       aprovado/pronto_para_base ou saindo deles), fn_fechar_caso e fn_reabrir_caso (fechado_em/fechado_por/motivo_fechamento),
--       fn_excluir_caso (DELETE em caso), fn_mudar_dial (qualquer escrita em estagio_autonomia). Nenhuma das cinco foi reescrita: o gatilho
--       sobre a tabela pega a função e o acesso direto. Por que gatilho e não policy: UPDATE/DELETE negado por policy afeta 0 LINHAS SEM
--       ERRO, e fn_excluir_caso responderia "excluído" (e gravaria o evento) depois de apagar nada — medido na primeira versão desta
--       migration com fn_mudar_dial, que gravava `mudanca_dial` na trilha sem mudar o dial.
--     gestão da equipe (novas, só Sócio): fn_definir_papel, fn_alocar, fn_desalocar — todas com evento_auditoria.
--
-- ===== 3. O MODELO FINAL =====
--   membro(usuario_id pk -> auth.users on delete cascade, papel in (socio, analista, leitura), criado_em, criado_por)
--   alocacao(caso_id -> caso, usuario_id -> auth.users, pk(caso_id, usuario_id), criado_em, criado_por) — FK de caso DEFERIDA (ver gatilho de criador)
--   fn_pode_ler_caso(caso) / fn_pode_escrever_caso(caso) / fn_pode_criar_caso() / fn_eh_socio() / fn_tem_papel() / fn_meu_papel()
--   fn_casos_legiveis() / fn_casos_escreviveis(): os MESMOS dois conjuntos como SETOF (ver o desempenho)
--   fn_exige_socio(acao), fn_conexao_de_servico()
--   fn_definir_papel(usuario, papel|NULL, motivo), fn_alocar(caso, usuario), fn_desalocar(caso, usuario)
--   gatilhos: trg_caso_reservado_ao_socio, trg_caso_aloca_criador, trg_estagio_autonomia_so_socio, trg_premissa_catalogo_so_socio,
--             trg_membro_ultimo_socio (nunca zero Sócio: pela função, por DELETE/UPDATE direto e pela cascata de auth.users)
--   Rebaixar/retirar o papel não apaga as alocações (voltam se o papel voltar); alocação de quem não tem papel não vale.
--   `fn_definir_papel(u, NULL)` retira o acesso. Alocar Sócio é recusado (ele já vê tudo); alocar quem não tem papel também.
--
-- ===== 4. AS POLICIES (resumo; o texto está nos laços abaixo) =====
--   por tabela com caso: SELECT `sócio OR <caso> in fn_casos_legiveis()` (por join: em CASCATA, `fk in (select id from <pai>)`, que herda a
--   policy do pai); INSERT with check de ESCREVER; UPDATE using de LER + with check de ESCREVER (a Leitura leva 42501, não "0 linhas" calado; e
--   ninguém move linha para mandato em que não escreve); DELETE using de ESCREVER (a Leitura apaga 0 linhas — o que existia: perimetro,
--   controlador, caso_pergunta etc. seguem SEM as operações que a 0210/0212/0213 e a 0214 tiraram, e `reapontar` de caso_pergunta fica).
--   `caso`: INSERT só Sócio ou Analista; SELECT inclui fn_alocado_agora (volatile, só para o `insert ... returning` do criador).
--   evento_auditoria: SELECT por mandato do `entidade_ref`; INSERT exige poder escrever o mandato (ou ser Sócio/Analista se o evento não tem
--   mandato); append-only como antes.  storage.objects: as quatro operações por `<caso_id>/` da chave.
--
-- O DESEMPENHO E O QUE FOI TROCADO POR ELE. A primeira forma da policy era `fn_pode_ler_caso(caso_id)`: uma função por LINHA e, em
-- campo_extraido, um join de três tabelas por linha. Medido em 29/10/2026 numa cópia com 198.543 linhas de campo_extraido: `count(*)` como
-- Analista alocada em 1 mandato levava 4.011 ms (20 µs/linha) contra 17 ms sem RLS, e um DELETE de 39.270 linhas levava 3,9 s. Trocado
-- por SubPlan hash (`caso_id in (select c from fn_casos_legiveis() c)`, uncorrelated, uma execução por consulta): o mesmo `count(*)` leva
-- 17 ms para o Analista e 14 ms para o Sócio (initplan), o DELETE de 64.719 linhas 656 ms e o UPDATE 1.289 ms. O teste afirma que a forma por
-- linha (fn_pode_*) e a por conjunto (fn_casos_*) concordam para cada usuário e cada mandato. NÃO medido: evento_auditoria (o
-- resolvedor `fn_caso_do_evento` corre por linha para quem não é Sócio; consultas com filtro em entidade_ref, que são as do portal, não sentem).
--
-- O QUE PODE QUEBRAR EM PRODUÇÃO AO APLICAR (e por quê)
--   1. Se `auth.users` estiver VAZIO ou não tiver o Sócio certo, ninguém acessa nada (acesso_socio_seed acusa). Promova à mão (README).
--   2. Quem hoje usa o portal e NÃO deveria ver tudo vira Sócio (bootstrap). É decisão do dono, não da migration; confira os usuários antes.
--   3. fn_upsert_caso procura o mandato por NOME sob RLS: um Analista que digita o nome de um mandato em que NÃO está alocado não o
--      encontra e CRIA outro de mesmo nome (não há UNIQUE em caso.nome; o Sócio passa a ver dois). Para a Leitura e quem não tem papel dá 42501.
--      A tela de upload (portal/src/components/upload-form.tsx) trata o erro como falha de criar mandato.
--   4. Marcar falha de processamento como vista (execucao_falha.visto_em) é UPDATE: a Leitura leva 42501 e o sino de avisos mostra erro.
--   5. /administracao lê estagio_autonomia (qualquer papel) mas os eventos `estagio:` e o golden set só o Sócio vê: o Analista vê o dial sem a
--      trilha e a cobertura do golden zerada. fn_historico_do_caso do Analista perde os eventos de entidade ABSORVIDA por fusão (a entidade
--      não existe mais, o prefixo não resolve para caso): só o Sócio os vê.
--   6. Policies em storage.objects (schema do Supabase Storage, não nosso): a 0003 já criava uma e foi aplicada, mas o DROP/CREATE aqui
--      exige o mesmo privilégio — se a migration morrer em `documentos_read`, é isto.
--   7. As funções do portal que ESCREVEM passam a falhar com 42501 para a Leitura (e a Analista fora do mandato vê "não existe"):
--      a interface ainda não esconde os botões (Fase 5, parte 2); o erro chega como mensagem de falha da ação.
--   8. fn_mudar_dial/fn_aprovar_caso/fn_fechar_caso/fn_reabrir_caso/fn_excluir_caso: o ator gravado continua sendo o TEXTO `p_autor` que o
--      portal passa (e-mail); a identidade de verdade (auth.uid()) só entra nos eventos da gestão da equipe. Não reescrevi as funções antigas.
--
-- O QUE NÃO VERIFIQUEI
--   * Produção: nada foi aplicado nem consultado. `rolbypassrls` de postgres/service_role, o número de usuários, o privilégio sobre
--     storage.objects e a forma real de `auth.users` são afirmações do repositório, não medições.
--   * O portal: nenhuma tela foi aberta nem o supabase-js exercitado; o que se provou é o banco com `request.jwt.claims` + `set local role
--     authenticated`, que é o que o PostgREST faz, mas o PostgREST em si não rodou. Nenhum arquivo de portal/ foi tocado.
--   * `evento_auditoria` e o Storage com volume; as policies de `storage.objects` só no stub do `run.sh` (tabela mínima).
--   * Concorrência: dois Sócios rebaixando-se ao mesmo tempo (o gatilho é por linha; sob READ COMMITTED a corrida entre dois UPDATE de
--     linhas distintas pode deixar zero Sócio). Improvável com um time de poucas pessoas; não medido.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/acesso_por_caso.test.sql — 99 chamadas de assert, 124 execuções (dois laços: 3 chamadas executadas 15 vezes na
-- seção 2, 1 chamada executada 14 vezes na seção 7), medidas em 29/10/2026 com `PGOPTIONS='-c acesso.medindo=on'` (o assert vira `raise warning` e CONTA; sem a variável
-- é `raise exception`, e o `run.sh` completo foi relido inteiro sem nenhum FALHOU) e a migration conferida como APLICADA em cada variante
-- (`instalacao_cobertura.ate_migration = 0216`, 23 requisitos da 0216 presentes). Controle intacto: 124 ok, 0 falhas. Cada guarda desligada
-- UMA por vez numa cópia do banco migrado (reprovações / 124 execuções; o último item de cada linha é a sonda quando ela também acusa):
--   * fn_pode_ler_caso (por linha) sempre true: 15 · fn_casos_legiveis (por conjunto) devolvendo todos os mandatos: 12 ·
--     fn_casos_legiveis vazio (ninguém lê): 15 (positivos de controle)
--   * fn_pode_escrever_caso sempre true: 5 · fn_casos_escreviveis devolvendo todos: 9
--   * sem trg_caso_reservado_ao_socio: 8 (6 pelo efeito — aprovar, fechar, UPDATE de fechado_em, excluir, DELETE direto —, 1 colateral
--     porque o mandato descartável foi apagado, 1 da sonda) · sem trg_estagio_autonomia_so_socio e trg_premissa_catalogo_so_socio: 2 (o
--     DELETE do dial/premissa, e a sonda; o UPDATE já é barrado pelo WITH CHECK da policy: defesa em duas camadas) ·
--     sem trg_membro_ultimo_socio: 6 (5 pelo efeito + sonda) · sem trg_caso_aloca_criador: 4
--   * fn_exige_socio sem efeito: 15 · fn_conexao_de_servico sempre true: 15 · fn_definir_papel sem a guarda: 7 · fn_alocar e fn_desalocar sem
--     a guarda: 5 · fn_alocado_agora sem exigir papel (o defeito que achei na primeira versão): 1
--   * policies: evento_auditoria_read true 4 · evento_auditoria_insert true 3 · storage documentos_read só pelo bucket 2 · membro_read e
--     alocacao_read true 4 · pendencia_update sem with check de escrita 2 · caso_insert true 3 · campo_extraido_read true 5 ·
--     campo_extraido_insert true (tabela por join) 3 · pendencia_insert true 3 · documento_delete true 1 · golden_rotulo_read true 2 ·
--     taxonomia_tipo_documento_read true 2 · golden_criterio sem RLS 1
--   Limites que a medição revelou: policy `true` em UMA tabela é pega por 1 a 5 execuções (a tabela exercitada + o assert estrutural da seção 12
--   que varre pg_policies); o que o teste NÃO exercita por tabela (as 51 tabelas) só é pego pelo assert estrutural, que mede forma, não
--   comportamento (regra 3): "nenhuma policy true", "toda tabela com caso_id lê pelos conjuntos", "toda tabela tem RLS".
-- =============================================================================

-- =============================================================================
-- 1. O MODELO: quem é o quê (membro) e quem trabalha em qual mandato (alocacao)
-- =============================================================================
-- `auth.users` é do Supabase (em todo projeto). Nos harnesses locais (`run.sh`, `Verificação/*.mts`) um stub mínimo é
-- criado ANTES das migrations; aqui só se referencia.
create table membro (
  usuario_id uuid primary key references auth.users (id) on delete cascade,
  papel      text not null check (papel in ('socio', 'analista', 'leitura')),
  criado_em  timestamptz not null default now(),
  criado_por uuid          -- quem concedeu/alterou (auth.uid() de quem chamou fn_definir_papel); NULL = bootstrap da 0216
);
comment on table membro is
  '0216: o papel de cada usuário do portal (socio | analista | leitura). Usuário SEM linha aqui não vê nada. A escrita só passa por fn_definir_papel (security definer, só Sócio, com evento_auditoria); o authenticated tem só SELECT. O gatilho trg_membro_ultimo_socio impede ficar sem nenhum Sócio.';

create table alocacao (
  -- FK DEFERIDA: o gatilho trg_caso_aloca_criador grava a alocação num BEFORE INSERT de caso (ver seção 3).
  caso_id    uuid not null references caso (id) on delete cascade deferrable initially deferred,
  usuario_id uuid not null references auth.users (id) on delete cascade,
  criado_em  timestamptz not null default now(),
  criado_por uuid,
  primary key (caso_id, usuario_id)
);
create index alocacao_usuario_idx on alocacao (usuario_id);
comment on table alocacao is
  '0216: em quais mandatos um Analista (escreve) ou Leitura (só lê) está alocado. Sócio não precisa de linha: vê e escreve tudo. A escrita só passa por fn_alocar/fn_desalocar (security definer, só Sócio, com evento_auditoria) e, para o mandato que um Analista acabou de criar, pelo gatilho trg_caso_aloca_criador.';

alter table membro   enable row level security;
alter table alocacao enable row level security;

-- Convenção da 0214: o que o portal e o service_role usam, NA MESMA migration. O authenticated só LÊ estas duas tabelas
-- (a escrita é pelas funções security definer abaixo); a sonda exige só o SELECT dele.
grant select on membro, alocacao to authenticated;
grant select, insert, update, delete on membro, alocacao to service_role;

-- BOOTSTRAP. Sem ele ninguém acessa nada depois de aplicar. Todo usuário que existe em auth.users AGORA é o time atual da
-- Oria e vira Sócio; quem for criado depois nasce SEM papel. Medido pela sonda/produção: ver cabeçalho.
insert into membro (usuario_id, papel, criado_por)
select u.id, 'socio', null from auth.users u
on conflict (usuario_id) do nothing;

-- =============================================================================
-- 2. AS PERGUNTAS DE ACESSO — security definer (leem membro/alocacao sem recursão de RLS), stable, search_path fixo
-- =============================================================================
create function fn_meu_papel() returns text
language sql stable security definer set search_path = public, pg_temp as $$
  select m.papel from membro m where m.usuario_id = auth.uid()
$$;

create function fn_eh_socio() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select m.papel = 'socio' from membro m where m.usuario_id = auth.uid()), false)
$$;

create function fn_tem_papel() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (select 1 from membro m where m.usuario_id = auth.uid())
$$;

-- Sócio lê tudo (inclusive linha sem caso: p_caso NULL); os outros dois leem o mandato em que estão alocados.
create function fn_pode_ler_caso(p_caso uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from membro m
     where m.usuario_id = auth.uid()
       and (m.papel = 'socio'
            or (p_caso is not null
                and exists (select 1 from alocacao a where a.caso_id = p_caso and a.usuario_id = m.usuario_id))))
$$;

-- Sócio escreve tudo; Analista escreve onde está alocado; Leitura nunca.
create function fn_pode_escrever_caso(p_caso uuid) returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select exists (
    select 1 from membro m
     where m.usuario_id = auth.uid()
       and (m.papel = 'socio'
            or (m.papel = 'analista' and p_caso is not null
                and exists (select 1 from alocacao a where a.caso_id = p_caso and a.usuario_id = m.usuario_id))))
$$;

-- OS MESMOS DOIS CONJUNTOS, em forma de CONJUNTO. Uma policy `fn_pode_ler_caso(caso_id)` chama a função UMA VEZ POR LINHA e, em
-- campo_extraido (a tabela grande), por join de três tabelas: medido em 29/10/2026 em 198.543 linhas, o Analista levava
-- 4,0 s num `count(*)` (20 µs por linha) contra 17 ms sem RLS. `caso_id in (select c from fn_casos_legiveis() c)` é um SubPlan
-- uncorrelated: o Postgres o executa UMA vez por consulta e a linha vira consulta a uma tabela hash. As duas formas têm de dar a
-- MESMA resposta, e o teste (seção 12) afirma isso para cada usuário e cada mandato.
create function fn_casos_legiveis() returns setof uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select a.caso_id from alocacao a
   where a.usuario_id = auth.uid() and exists (select 1 from membro m where m.usuario_id = a.usuario_id)
  union all
  select c.id from caso c
   where exists (select 1 from membro m where m.usuario_id = auth.uid() and m.papel = 'socio')
$$;

create function fn_casos_escreviveis() returns setof uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select a.caso_id from alocacao a
   where a.usuario_id = auth.uid()
     and exists (select 1 from membro m where m.usuario_id = a.usuario_id and m.papel = 'analista')
  union all
  select c.id from caso c
   where exists (select 1 from membro m where m.usuario_id = auth.uid() and m.papel = 'socio')
$$;

-- VOLATILE DE PROPÓSITO, e só a policy de leitura de `caso` a usa. `insert into caso ... returning id` (fn_upsert_caso) checa a
-- policy de SELECT na linha nova NO MESMO COMANDO em que o gatilho trg_caso_aloca_criador acabou de gravar a alocação, e uma
-- função STABLE (ou uma subconsulta) usa o snapshot do comando, que ainda não vê essa linha: medido, o Analista levava
-- "new row violates row-level security policy for table caso" ao criar o próprio mandato. Função volatile toma snapshot novo.
-- Só é avaliada para a linha que as duas outras condições (Sócio, fn_pode_ler_caso) não liberaram, e `caso` é a tabela pequena.
create function fn_alocado_agora(p_caso uuid) returns boolean
language sql volatile security definer set search_path = public, pg_temp as $$
  select exists (select 1 from membro m join alocacao a on a.usuario_id = m.usuario_id
                  where m.usuario_id = auth.uid() and a.caso_id = p_caso)   -- com papel: alocação de quem perdeu o papel não vale
$$;

-- Criar mandato: Sócio ou Analista (Leitura não). O Analista que cria fica alocado (trg_caso_aloca_criador).
create function fn_pode_criar_caso() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select m.papel in ('socio', 'analista') from membro m where m.usuario_id = auth.uid()), false)
$$;

-- CONEXÃO DE SERVIÇO NÃO É USUÁRIO. n8n (Postgres nativo pelo Session Pooler, role postgres) e o SQL Editor chegam sem
-- JWT e sem `set role authenticated`; `current_setting('role')` é 'none' (ou 'service_role' pelo PostgREST). Essas conexões
-- ignoram RLS e as guardas abaixo as deixam passar: senão o pipeline pararia no primeiro `update caso`. Quem chega como
-- `authenticated`/`anon` — o navegador — nunca passa por aqui sem ser Sócio, ainda que o JWT venha sem `sub`.
create function fn_conexao_de_servico() returns boolean
language sql stable security definer set search_path = public, pg_temp as $$
  select auth.uid() is null and coalesce(current_setting('role', true), 'none') not in ('authenticated', 'anon')
$$;

create function fn_exige_socio(p_acao text default 'esta operação') returns void
language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if fn_conexao_de_servico() or fn_eh_socio() then return; end if;
  raise exception '% é reservado a Sócio (seu papel: %)', p_acao, coalesce(fn_meu_papel(), 'nenhum')
    using errcode = '42501';
end $$;

-- Resolvedor versão -> caso (só a trilha o usa: o prefixo `documento_versao:` de entidade_ref). Security definer de propósito:
-- não reentra nas policies de documento_versao e documento. Devolve só o uuid do caso.
create function fn_caso_da_versao(p_versao uuid) returns uuid
language sql stable security definer set search_path = public, pg_temp as $$
  select d.caso_id from documento_versao v join documento d on d.id = v.documento_id where v.id = p_versao
$$;
-- evento_auditoria não tem caso_id: o caso vem do PREFIXO de `entidade_ref` ('caso:<uuid>', 'documento:<uuid>', ...).
-- Prefixo sem caso (estagio:, golden_rodada:, membro:) ou entidade que já não existe (a absorvida de uma fusão) -> NULL,
-- e então só Sócio lê.
create function fn_caso_do_evento(p_ref text) returns uuid
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare
  v_tipo text := split_part(p_ref, ':', 1);
  v_id   uuid;
begin
  if p_ref !~ '^[a-z_]+:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then return null; end if;
  v_id := split_part(p_ref, ':', 2)::uuid;
  return case v_tipo
    when 'caso'             then (select c.id from caso c where c.id = v_id)
    when 'documento'        then (select x.caso_id from documento x where x.id = v_id)
    when 'documento_versao' then fn_caso_da_versao(v_id)
    when 'entidade'         then (select x.caso_id from entidade x where x.id = v_id)
    when 'pendencia'        then (select x.caso_id from pendencia x where x.id = v_id)
    when 'reconciliacao'    then (select x.caso_id from reconciliacao x where x.id = v_id)
    when 'controlador'      then (select x.caso_id from controlador x where x.id = v_id)
    else null end;
end $$;

-- Quem pode ESCREVER um evento: o evento de um caso exige escrever nele; o que não resolve para caso (estagio:, ...)
-- exige Sócio ou Analista.
create function fn_pode_escrever_evento(p_ref text) returns boolean
language plpgsql stable security definer set search_path = public, pg_temp as $$
declare v_caso uuid := fn_caso_do_evento(p_ref);
begin
  if v_caso is not null then return fn_pode_escrever_caso(v_caso); end if;
  return coalesce(fn_meu_papel() in ('socio', 'analista'), false);
end $$;

-- A chave do original no Storage é `<caso_id>/<sha256>.<ext>` (N8N/lib/hash.mjs). Chave que não começa com uuid -> NULL.
create function fn_caso_da_chave_do_storage(p_nome text) returns uuid
language sql immutable set search_path = public, pg_temp as $$
  select case when split_part(p_nome, '/', 1) ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
              then split_part(p_nome, '/', 1)::uuid end
$$;

do $$
declare f text;
begin
  foreach f in array array[
    'fn_meu_papel()', 'fn_eh_socio()', 'fn_tem_papel()', 'fn_pode_ler_caso(uuid)', 'fn_pode_escrever_caso(uuid)',
    'fn_pode_criar_caso()', 'fn_conexao_de_servico()', 'fn_exige_socio(text)',
    'fn_caso_da_versao(uuid)', 'fn_caso_do_evento(text)',
    'fn_pode_escrever_evento(text)', 'fn_caso_da_chave_do_storage(text)', 'fn_alocado_agora(uuid)',
    'fn_casos_legiveis()', 'fn_casos_escreviveis()']
  loop
    execute format('revoke all on function %s from public', f);
    execute format('grant execute on function %s to authenticated, service_role', f);
  end loop;
end $$;

-- =============================================================================
-- 3. AS GUARDAS QUE A POLICY NÃO SABE FAZER (reservado a Sócio) — gatilho, porque policy por linha não distingue
--    "mudar status para aprovado" de "mudar status para em_triagem", e porque UPDATE/DELETE negado por policy afeta 0 linhas
--    SEM ERRO (fn_excluir_caso diria "excluído" sem ter excluído).
-- =============================================================================
create function fn_trg_caso_reservado_ao_socio() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  if tg_op = 'DELETE' then
    perform fn_exige_socio('Excluir mandato');
    return old;
  end if;
  -- aprovar/desfazer aprovação (Portão 2) e fechar/reabrir. As demais transições (intake -> em_triagem -> ... -> em_revisao,
  -- que fn_recomputar_completude faz a partir do trabalho do Analista) seguem livres.
  if new.status is distinct from old.status
     and (new.status in ('aprovado', 'pronto_para_base') or old.status in ('aprovado', 'pronto_para_base')) then
    perform fn_exige_socio('Aprovar mandato');
  end if;
  if new.fechado_em is distinct from old.fechado_em
     or new.fechado_por is distinct from old.fechado_por
     or new.motivo_fechamento is distinct from old.motivo_fechamento then
    perform fn_exige_socio('Fechar ou reabrir mandato');
  end if;
  return new;
end $$;
create trigger trg_caso_reservado_ao_socio
  before update or delete on caso
  for each row execute function fn_trg_caso_reservado_ao_socio();

-- O Analista que cria um mandato fica alocado nele. BEFORE INSERT + FK deferida: a policy de SELECT do `insert ... returning`
-- (fn_upsert_caso) roda ANTES de qualquer gatilho AFTER, e sem a alocação o Analista não enxergaria o mandato que acabou de criar.
create function fn_trg_caso_aloca_criador() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if auth.uid() is not null and fn_meu_papel() = 'analista' then
    insert into alocacao (caso_id, usuario_id, criado_por) values (new.id, auth.uid(), auth.uid())
    on conflict do nothing;
  end if;
  return new;
end $$;
create trigger trg_caso_aloca_criador
  before insert on caso
  for each row execute function fn_trg_caso_aloca_criador();

-- Estágios do dial e catálogo de premissas: globais, só Sócio escreve. O gatilho dá o ERRO (a policy daria 0 linhas calado;
-- fn_mudar_dial registraria 'mudanca_dial' sem ter mudado nada).
create function fn_trg_so_socio() returns trigger
language plpgsql set search_path = public, pg_temp as $$
begin
  perform fn_exige_socio(tg_argv[0]);
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger trg_estagio_autonomia_so_socio
  before insert or update or delete on estagio_autonomia
  for each row execute function fn_trg_so_socio('Mudar o dial de autonomia');

create trigger trg_premissa_catalogo_so_socio
  before insert or update or delete on premissa_catalogo
  for each row execute function fn_trg_so_socio('Alterar o catálogo de premissas');

-- Nunca ficar sem Sócio.
create function fn_trg_membro_ultimo_socio() returns trigger
language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if old.papel = 'socio' and (tg_op = 'DELETE' or new.papel <> 'socio')
     and not exists (select 1 from membro m where m.papel = 'socio' and m.usuario_id <> old.usuario_id) then
    raise exception 'Não dá para deixar o portal sem Sócio: % é o último. Promova outro Sócio antes.', old.usuario_id
      using errcode = 'P0001';
  end if;
  return case when tg_op = 'DELETE' then old else new end;
end $$;
create trigger trg_membro_ultimo_socio
  before update or delete on membro
  for each row execute function fn_trg_membro_ultimo_socio();

-- =============================================================================
-- 4. AS POLICIES POR CASO — troca de TODAS as `to authenticated` (menos as de membro/alocacao, criadas depois)
-- =============================================================================
do $$
declare p record;
begin
  for p in select schemaname, tablename, policyname from pg_policies
            where 'authenticated' = any (roles)
              and (schemaname = 'public' or (schemaname = 'storage' and tablename = 'objects'))
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

alter table golden_criterio enable row level security;

create policy membro_read on membro for select to authenticated
  using (usuario_id = auth.uid() or (select fn_eh_socio()));
create policy alocacao_read on alocacao for select to authenticated
  using (usuario_id = auth.uid() or (select fn_eh_socio()));

-- tabela, operações (i=insert, u=update, d=delete; select sempre), a leitura e a escrita.
--   LEITURA  direta: `caso_id in (fn_casos_legiveis)`; por join, em CASCATA: `<fk> in (select id from <pai>)` herda a policy do pai (RLS
--            vale dentro da subconsulta).
--   ESCRITA  direta: `caso_id in (fn_casos_escreviveis)`; por join, a subconsulta desce até o caso e exige que ele seja escrevível.
-- Todas as subconsultas são uncorrelated: um SubPlan hash por consulta, e não uma função por linha (ver fn_casos_legiveis). Medido
-- num DELETE de 39.270 linhas de campo_extraido como Analista: a forma por linha levava 3,9 s.
-- Sócio entra pelo initplan `(select fn_eh_socio())`: a consulta paga UMA chamada, o OR não avalia o resto, e linha SEM caso
-- (execucao_falha.caso_id nulo) continua visível a ele.
do $$
declare
  t record;
  v_cw text := 'select c from fn_casos_escreviveis() c';
  v_ler text; v_esc text;
begin
  for t in
    select * from (values
      -- direto: o caso é a coluna
      ('arquivo_oficial',           'iud', 'caso_id'), ('caso_apresentacao_campo', 'iud', 'caso_id'),
      ('caso_linha_premissa',       'iud', 'caso_id'), ('caso_modelagem',          'iud', 'caso_id'),
      ('caso_premissa',             'iud', 'caso_id'), ('checklist_item_status',   'iud', 'caso_id'),
      ('decisao',                   'iud', 'caso_id'), ('documento',               'iud', 'caso_id'),
      ('entidade',                  'iud', 'caso_id'), ('execucao_falha',          'iud', 'caso_id'),
      ('lote_execucao',             'iud', 'caso_id'), ('pendencia',               'iud', 'caso_id'),
      ('periodo',                   'iud', 'caso_id'), ('reconciliacao',           'iud', 'caso_id'),
      ('controlador',               'i',   'caso_id'), ('caso_pergunta',           'i',   'caso_id'),
      ('controlador_vinculo',       'iu',  'caso_id'), ('entidade_controlador',    'iu',  'caso_id'),
      ('perimetro',                 'iu',  'caso_id'),
      -- por join: documento_versao -> documento; campo_extraido e documento_fato -> documento_versao; arquivo_oficial_* ->
      -- arquivo_oficial; campo_classe_* -> campo_extraido
      ('documento_versao',          'iud', 'documento_id'),
      ('campo_extraido',            'iud', 'documento_versao_id'),
      ('documento_fato',            'iud', 'documento_versao_id'),
      ('arquivo_oficial_lancamento_mes', 'iud', 'arquivo_oficial_id'),
      ('arquivo_oficial_registro',  'iud', 'arquivo_oficial_id'),
      ('campo_classe_override',     'i',   'campo_extraido_id'),
      ('campo_classe_sugerida',     'i',   'campo_extraido_id')
    ) as x(tabela, ops, fk)
  loop
    v_ler := case t.fk
      when 'caso_id'             then 'caso_id in (select c from fn_casos_legiveis() c)'
      when 'documento_id'        then 'documento_id in (select id from documento)'
      when 'documento_versao_id' then 'documento_versao_id in (select id from documento_versao)'
      when 'arquivo_oficial_id'  then 'arquivo_oficial_id in (select id from arquivo_oficial)'
      when 'campo_extraido_id'   then 'campo_extraido_id in (select id from campo_extraido)' end;
    v_esc := case t.fk
      when 'caso_id'             then format('caso_id in (%s)', v_cw)
      when 'documento_id'        then format('documento_id in (select d.id from documento d where d.caso_id in (%s))', v_cw)
      when 'documento_versao_id' then format('documento_versao_id in (select v.id from documento_versao v join documento d on d.id = v.documento_id where d.caso_id in (%s))', v_cw)
      when 'arquivo_oficial_id'  then format('arquivo_oficial_id in (select a.id from arquivo_oficial a where a.caso_id in (%s))', v_cw)
      when 'campo_extraido_id'   then format('campo_extraido_id in (select c.id from campo_extraido c join documento_versao v on v.id = c.documento_versao_id join documento d on d.id = v.documento_id where d.caso_id in (%s))', v_cw) end;
    v_ler := '(select fn_eh_socio()) or ' || v_ler;
    v_esc := '(select fn_eh_socio()) or ' || v_esc;
    execute format('create policy %I on %I for select to authenticated using (%s)', t.tabela || '_read', t.tabela, v_ler);
    -- inserir: exige poder escrever no caso da linha NOVA
    if t.ops like '%i%' then
      execute format('create policy %I on %I for insert to authenticated with check (%s)', t.tabela || '_insert', t.tabela, v_esc);
    end if;
    -- atualizar: acha a linha se PODE LER, aceita o resultado só se PODE ESCREVER. Leitura que tenta atualizar leva 42501
    -- (e não "0 linhas" calado). A escrita não pode MOVER a linha para um caso em que o autor não escreve.
    if t.ops like '%u%' then
      execute format('create policy %I on %I for update to authenticated using (%s) with check (%s)',
                     t.tabela || '_update', t.tabela, v_ler, v_esc);
    end if;
    -- apagar
    if t.ops like '%d%' then
      execute format('create policy %I on %I for delete to authenticated using (%s)', t.tabela || '_delete', t.tabela, v_esc);
    end if;
  end loop;
end $$;

-- caso_pergunta: o único UPDATE é o do GRANT de coluna da 0213 (entidade_id), e a entidade tem de ser do MESMO caso.
create policy caso_pergunta_reapontar on caso_pergunta for update to authenticated
  using ((select fn_eh_socio()) or caso_id in (select c from fn_casos_legiveis() c))
  with check (((select fn_eh_socio()) or fn_pode_escrever_caso(caso_id))
              and entidade_id is not null
              and exists (select 1 from entidade e where e.id = caso_pergunta.entidade_id and e.caso_id = caso_pergunta.caso_id));

-- caso
create policy caso_read on caso for select to authenticated
  using ((select fn_eh_socio()) or fn_pode_ler_caso(id) or fn_alocado_agora(id));
create policy caso_insert on caso for insert to authenticated
  with check (fn_pode_criar_caso());
create policy caso_update on caso for update to authenticated
  using ((select fn_eh_socio()) or fn_pode_ler_caso(id))
  with check ((select fn_eh_socio()) or fn_pode_escrever_caso(id));
-- DELETE enxerga por poder LER e o gatilho trg_caso_reservado_ao_socio recusa quem não é Sócio com ERRO: policy de DELETE que
-- escondesse a linha faria fn_excluir_caso responder "excluído" depois de apagar 0 linhas.
create policy caso_delete on caso for delete to authenticated
  using ((select fn_eh_socio()) or fn_pode_ler_caso(id));

-- evento_auditoria: append-only (sem UPDATE/DELETE). Ler: o caso do evento; sem caso -> só Sócio.
create policy evento_auditoria_read on evento_auditoria for select to authenticated
  using ((select fn_eh_socio()) or fn_pode_ler_caso(fn_caso_do_evento(entidade_ref)));
create policy evento_auditoria_insert on evento_auditoria for insert to authenticated
  with check (fn_pode_escrever_evento(entidade_ref));

-- Globais, só leitura: qualquer papel. Sem papel não lê nem o catálogo.
do $$
declare t text;
begin
  foreach t in array array[
    'classe_contabil_catalogo', 'fato_tipo_catalogo', 'indice_macro_expectativa', 'indice_macro_obs', 'indice_macro_serie',
    'instalacao_cobertura', 'instalacao_requisito', 'pergunta_catalogo', 'rubrica_classe', 'taxonomia_linha_alternativa',
    'taxonomia_linha_exigida', 'taxonomia_linha_localizador', 'taxonomia_tipo_cobertura', 'taxonomia_tipo_documento']
  loop
    execute format('create policy %I on %I for select to authenticated using ((select fn_tem_papel()))', t || '_read', t);
  end loop;
end $$;

-- Globais que só Sócio escreve (qualquer papel lê): dial, catálogo de premissas, critério e rodada do golden set.
do $$
declare t text;
begin
  foreach t in array array['estagio_autonomia', 'premissa_catalogo', 'golden_criterio', 'golden_rodada']
  loop
    execute format('create policy %I on %I for select to authenticated using ((select fn_tem_papel()))', t || '_read', t);
    execute format('create policy %I on %I for insert to authenticated with check ((select fn_eh_socio()))', t || '_insert', t);
    -- USING deixa QUALQUER papel achar a linha e o WITH CHECK recusa quem não é Sócio: UPDATE negado vira 42501, e não "0 linhas"
    -- calado (fn_mudar_dial gravaria `mudanca_dial` na trilha sem ter mudado nada — medido na primeira versão desta migration).
    execute format('create policy %I on %I for update to authenticated using ((select fn_tem_papel())) with check ((select fn_eh_socio()))',
                   t || '_update', t);
  end loop;
end $$;
-- estagio_autonomia e premissa_catalogo tinham `for all` (inclui DELETE); golden_* nunca tiveram DELETE e continuam sem.
-- DELETE: o gatilho (trg_estagio_autonomia_so_socio, trg_premissa_catalogo_so_socio) é quem recusa, com erro; a policy só deixa achar a linha.
create policy estagio_autonomia_delete on estagio_autonomia for delete to authenticated using ((select fn_tem_papel()));
create policy premissa_catalogo_delete on premissa_catalogo for delete to authenticated using ((select fn_tem_papel()));

-- Golden set: os rótulos citam documentos de QUALQUER mandato; só Sócio os lê e escreve (append-only, como antes: sem UPDATE/DELETE).
do $$
declare t text;
begin
  foreach t in array array['golden_documento', 'golden_campo', 'golden_rotulo']
  loop
    execute format('create policy %I on %I for select to authenticated using ((select fn_eh_socio()))', t || '_read', t);
    execute format('create policy %I on %I for insert to authenticated with check ((select fn_eh_socio()))', t || '_insert', t);
  end loop;
end $$;

-- Storage: a chave é `<caso_id>/<hash>.<ext>`.
create policy documentos_read on storage.objects for select to authenticated
  using (bucket_id = 'documentos'
         and ((select fn_eh_socio()) or fn_pode_ler_caso(fn_caso_da_chave_do_storage(name))));
create policy documentos_insert on storage.objects for insert to authenticated
  with check (bucket_id = 'documentos'
              and ((select fn_eh_socio()) or fn_pode_escrever_caso(fn_caso_da_chave_do_storage(name))));
create policy documentos_update on storage.objects for update to authenticated
  using (bucket_id = 'documentos'
         and ((select fn_eh_socio()) or fn_pode_ler_caso(fn_caso_da_chave_do_storage(name))))
  with check (bucket_id = 'documentos'
              and ((select fn_eh_socio()) or fn_pode_escrever_caso(fn_caso_da_chave_do_storage(name))));
create policy documentos_delete on storage.objects for delete to authenticated
  using (bucket_id = 'documentos'
         and ((select fn_eh_socio()) or fn_pode_escrever_caso(fn_caso_da_chave_do_storage(name))));

-- =============================================================================
-- 5. A GESTÃO DA EQUIPE — só Sócio, security definer, sempre com evento_auditoria
-- =============================================================================
create function fn_definir_papel(p_usuario uuid, p_papel text, p_motivo text default null) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_antes text;
  v_ator  text := coalesce('usuario:' || auth.uid()::text, 'sistema:sql');
begin
  perform fn_exige_socio('Gerir a equipe');
  if p_papel is not null and p_papel not in ('socio', 'analista', 'leitura') then
    raise exception 'Papel "%" não existe (socio, analista ou leitura; NULL retira o acesso)', p_papel using errcode = '22023';
  end if;
  if not exists (select 1 from auth.users u where u.id = p_usuario) then
    raise exception 'Usuário % não existe no Supabase Auth — a pessoa precisa entrar uma vez (ou ser convidada) antes de receber papel', p_usuario
      using errcode = '23503';
  end if;
  select papel into v_antes from membro where usuario_id = p_usuario;
  if v_antes is not distinct from p_papel then
    return jsonb_build_object('papel', p_papel, 'mudou', false);
  end if;

  if p_papel is null then
    delete from membro where usuario_id = p_usuario;                  -- o gatilho recusa se for o último Sócio
  else
    insert into membro (usuario_id, papel, criado_por) values (p_usuario, p_papel, auth.uid())
    on conflict (usuario_id) do update set papel = excluded.papel, criado_por = excluded.criado_por, criado_em = now();
  end if;

  insert into evento_auditoria (ator, acao, entidade_ref, antes, depois)
  values (v_ator, case when p_papel is null then 'papel_removido' else 'papel_definido' end, 'membro:' || p_usuario,
          jsonb_build_object('papel', v_antes),
          jsonb_build_object('papel', p_papel, 'motivo', nullif(btrim(p_motivo), '')));
  return jsonb_build_object('papel', p_papel, 'papel_anterior', v_antes, 'mudou', true);
end $$;

create function fn_alocar(p_caso uuid, p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_papel text;
  v_n int;
begin
  perform fn_exige_socio('Alocar na equipe do mandato');
  if not exists (select 1 from caso where id = p_caso) then
    raise exception 'Mandato % não existe', p_caso using errcode = '23503';
  end if;
  select papel into v_papel from membro where usuario_id = p_usuario;
  if v_papel is null then
    raise exception 'Usuário % não tem papel — defina um (fn_definir_papel) antes de alocar', p_usuario using errcode = 'P0001';
  end if;
  if v_papel = 'socio' then
    raise exception 'Sócio já vê e escreve em todos os mandatos — alocação não se aplica' using errcode = 'P0001';
  end if;
  insert into alocacao (caso_id, usuario_id, criado_por) values (p_caso, p_usuario, auth.uid())
  on conflict do nothing;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('alocado', true, 'mudou', false); end if;
  insert into evento_auditoria (ator, acao, entidade_ref, depois)
  values (coalesce('usuario:' || auth.uid()::text, 'sistema:sql'), 'alocado', 'caso:' || p_caso,
          jsonb_build_object('usuario_id', p_usuario, 'papel', v_papel));
  return jsonb_build_object('alocado', true, 'mudou', true);
end $$;

create function fn_desalocar(p_caso uuid, p_usuario uuid) returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_n int;
begin
  perform fn_exige_socio('Retirar da equipe do mandato');
  delete from alocacao where caso_id = p_caso and usuario_id = p_usuario;
  get diagnostics v_n = row_count;
  if v_n = 0 then return jsonb_build_object('alocado', false, 'mudou', false); end if;
  insert into evento_auditoria (ator, acao, entidade_ref, antes)
  values (coalesce('usuario:' || auth.uid()::text, 'sistema:sql'), 'desalocado', 'caso:' || p_caso,
          jsonb_build_object('usuario_id', p_usuario));
  return jsonb_build_object('alocado', false, 'mudou', true);
end $$;

revoke all on function fn_definir_papel(uuid, text, text), fn_alocar(uuid, uuid), fn_desalocar(uuid, uuid) from public;
grant execute on function fn_definir_papel(uuid, text, text), fn_alocar(uuid, uuid), fn_desalocar(uuid, uuid)
  to authenticated, service_role;

comment on function fn_definir_papel(uuid, text, text) is
  '0216: só Sócio. Define o papel de um usuário do Auth (socio|analista|leitura); NULL retira o acesso. Recusa deixar o portal sem Sócio. Grava evento_auditoria papel_definido/papel_removido (entidade_ref membro:<uuid>).';
comment on function fn_alocar(uuid, uuid) is
  '0216: só Sócio. Aloca Analista ou Leitura num mandato. Idempotente. Grava evento_auditoria alocado (caso:<id>).';
comment on function fn_desalocar(uuid, uuid) is
  '0216: só Sócio. Retira a alocação. Idempotente. Grava evento_auditoria desalocado (caso:<id>).';

-- =============================================================================
-- 6. A SONDA
-- =============================================================================
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('acesso_membro_tabela', '0216', 'tabela', 'membro', null, null,
   'Sem `membro` o portal não sabe quem é Sócio, Analista ou Leitura: as policies por caso (0216) negam tudo a todos.',
   'bloqueante', 930),
  ('acesso_alocacao_tabela', '0216', 'tabela', 'alocacao', null, null,
   'Sem `alocacao` nenhum Analista ou Leitura enxerga mandato algum (só o Sócio entra).',
   'bloqueante', 931),
  ('acesso_socio_seed', '0216', 'seed', 'membro', null, 1,
   'Nenhum Sócio no banco: depois da 0216 NINGUÉM acessa nada. O bootstrap promove a Sócio os usuários que já existiam em auth.users; se esta linha reprova, o banco foi migrado sem usuário algum ou o Sócio foi removido por SQL. Promova um: insert into membro (usuario_id, papel) select id, ''socio'' from auth.users where email = ''<um sócio>''.',
   'bloqueante', 932),
  ('acesso_fn_pode_ler', '0216', 'corpo', 'fn_pode_ler_caso', 'a.caso_id = p_caso', null,
   'A pergunta que toda policy de leitura faz. Se o corpo perder a consulta a `alocacao` (marcador: `a.caso_id = p_caso`), ou volta ao `using (true)` ou Analista e Leitura não leem mais nada.',
   'bloqueante', 933),
  ('acesso_fn_pode_escrever', '0216', 'corpo', 'fn_pode_escrever_caso', 'm.papel = ''analista''', null,
   'A pergunta que toda policy de escrita faz. O marcador é o papel que escreve só onde está alocado: sem ele Leitura passaria a escrever.',
   'bloqueante', 934),
  ('acesso_fn_eh_socio', '0216', 'funcao', 'fn_eh_socio', null, null,
   'Sócio vê e escreve tudo; as policies o consultam pelo initplan `(select fn_eh_socio())`.',
   'bloqueante', 935),
  ('acesso_fn_exige_socio', '0216', 'corpo', 'fn_exige_socio', 'conexao_de_servico', null,
   'A guarda de aprovar/fechar/excluir mandato, mudar o dial e gerir a equipe. O marcador é a passagem da conexão de serviço (n8n, SQL Editor): sem ela o pipeline para no primeiro update de caso.',
   'bloqueante', 936),
  ('acesso_fn_definir_papel', '0216', 'corpo', 'fn_definir_papel', 'fn_exige_socio', null,
   'Gerir a equipe é só de Sócio. Sem a guarda no corpo, qualquer usuário se promoveria a Sócio.',
   'bloqueante', 937),
  ('acesso_fn_alocar', '0216', 'corpo', 'fn_alocar', 'fn_exige_socio', null,
   'Alocar é só de Sócio. Sem a guarda, o Analista se alocaria em qualquer mandato.',
   'bloqueante', 938),
  ('acesso_fn_desalocar', '0216', 'corpo', 'fn_desalocar', 'fn_exige_socio', null,
   'Desalocar é só de Sócio.',
   'importante', 939),
  ('acesso_gatilho_caso_reservado', '0216', 'gatilho', 'caso.trg_caso_reservado_ao_socio', null, null,
   'Aprovar, fechar, reabrir e excluir mandato são de Sócio. É este gatilho que barra o UPDATE direto do Analista (a policy de linha não distingue transição de status).',
   'bloqueante', 940),
  ('acesso_gatilho_caso_aloca', '0216', 'gatilho', 'caso.trg_caso_aloca_criador', null, null,
   'O Analista que cria um mandato fica alocado nele. Sem o gatilho ele cria o mandato e não o enxerga.',
   'importante', 941),
  ('acesso_gatilho_ultimo_socio', '0216', 'gatilho', 'membro.trg_membro_ultimo_socio', null, null,
   'Sem o gatilho dá para remover/rebaixar o último Sócio e ninguém mais gere a equipe.',
   'bloqueante', 942),
  ('acesso_gatilho_dial', '0216', 'gatilho', 'estagio_autonomia.trg_estagio_autonomia_so_socio', null, null,
   'O dial de autonomia é decisão de Sócio. Sem o gatilho um Analista o move por UPDATE direto.',
   'bloqueante', 943),
  ('acesso_gatilho_premissa_catalogo', '0216', 'gatilho', 'premissa_catalogo.trg_premissa_catalogo_so_socio', null, null,
   'O catálogo de premissas é decisão de Sócio. Sem o gatilho um Analista o altera por UPDATE direto (a policy deixa achar a linha para dar o erro).',
   'importante', 952),
  ('acesso_policy_caso_ler', '0216', 'policy', 'caso.caso_read', null, null,
   'Policy de leitura por caso. Sem ela (e com a antiga `using (true)` removida) o authenticated não lê mandato; com a antiga de volta, todos leem todos.',
   'bloqueante', 944),
  ('acesso_policy_caso_inserir', '0216', 'policy', 'caso.caso_insert', null, null,
   'Criar mandato: Sócio ou Analista.', 'bloqueante', 945),
  ('acesso_policy_caso_atualizar', '0216', 'policy', 'caso.caso_update', null, null,
   'Atualizar mandato: ler para achar, escrever para aceitar.', 'bloqueante', 946),
  ('acesso_policy_caso_apagar', '0216', 'policy', 'caso.caso_delete', null, null,
   'Apagar mandato (o gatilho restringe a Sócio).', 'bloqueante', 947),
  ('acesso_policy_documento_ler', '0216', 'policy', 'documento.documento_read', null, null,
   'Leitura de documento por caso.', 'bloqueante', 948),
  ('acesso_policy_campo_ler', '0216', 'policy', 'campo_extraido.campo_extraido_read', null, null,
   'Leitura dos campos extraídos (por documento_versao -> documento -> caso): a tabela de números financeiros.',
   'bloqueante', 949),
  ('acesso_policy_evento_ler', '0216', 'policy', 'evento_auditoria.evento_auditoria_read', null, null,
   'A trilha lê por caso (prefixo da entidade_ref); sem caso, só Sócio.', 'bloqueante', 950),
  ('acesso_policy_membro_ler', '0216', 'policy', 'membro.membro_read', null, null,
   'Cada um lê o próprio papel; Sócio lê todos. Sem ela o portal não sabe qual é o papel de quem entrou.',
   'bloqueante', 951)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0216', revisado_em = current_date,
       observacao = 'A 0216 cria o modelo de acesso (membro, alocacao), as funções fn_pode_*/fn_eh_socio/fn_exige_socio, as de gestão (fn_definir_papel, fn_alocar, fn_desalocar), quatro gatilhos de guarda e troca TODA policy `to authenticated using (true)` por policy por caso. Catalogada: tabelas, seed (>=1 Sócio), corpos, gatilhos e as policies-chave. Bootstrap: todo usuário de auth.users vira Sócio.'
 where id = true;
