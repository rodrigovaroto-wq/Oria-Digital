-- 0242 — A SEÇÃO QUE SÓ EXISTIA EM CÓDIGO: o catálogo `conta_canonica` (P26, Fase 3, etapa 3.1) — a árvore de demonstração → grupo → seção → subgrupo que o banco não tinha, com a guarda de pai/ciclo e a régua contra `SECAO_CANONICA_ENUM`.
-- (Cria 1 tabela, conta_canonica, 1 função de gatilho e 1 gatilho. Seed de 26 nós. Sem backfill: nenhuma linha existente é tocada. 6 requisitos novos na sonda (ordem 1096-1101). Idempotente: pode ser reaplicada.)
--
-- O DEFEITO. As 15 seções canônicas (`ativo_circulante` … `dva`) são a coluna vertebral do book — é por elas que a linha vai para a aba, que a cascata da DRE fecha e que o balanço soma — e a lista
-- delas só existia em CÓDIGO: `N8N/lib/extract.mjs` (`SECAO_CANONICA_ENUM`, a que a IA devolve) e `portal/src/lib/statement-templates.ts` (`FAMILIA_POR_SECAO_CANONICA`, a que roteia a aba), duas cópias
-- que o próprio cabeçalho do extract.mjs manda "manter IDÊNTICAS" sem nenhum portão. No banco `campo_extraido.secao_canonica` é `text` livre (0012): qualquer string grava. Medido nas fixtures que o run.sh carrega
-- (vertentes e canastra): 14 das 15 seções aparecem em `campo_extraido` (dva ausente) e NENHUMA tabela as descrevia — não havia onde pendurar a conta canônica (caixa, clientes…) que a Fase 3 precisa
-- resolver (P27), nem onde dizer que "imobilizado" é filho de "ativo não circulante". O roadmap (ARQUITETURA_ALVO_E_ROADMAP §1.1 e F4) define o catálogo como
-- `conta_canonica(codigo, nome, secao_canonica, classe_recorrencia, pai, natureza)`; `secao_canonica` vira ATRIBUTO da conta, não um plano de contas paralelo.
--
-- O QUE ENTRA, E SÓ A TAXONOMIA ATUAL (26 nós): 5 raízes (as demonstrações: balanço, DRE, fluxo de caixa, DMPL, DVA), os 2 grupos do balanço (ATIVO, PASSIVO E PL), as 15 seções e os 4 subgrupos do
-- Ativo Não Circulante (realizável a LP, investimentos, imobilizado, intangível — os da `BALANCO_OUTLINE` do portal, filhos de `ativo_nao_circulante`; a própria `ativo_nao_circulante` é o balde "Outros" do
-- portal). NÃO entra conta-folha (caixa, clientes…): resolver a linha para uma conta é a P27, e semear folha agora seria inventar o plano de contas antes de haver o que o valide.
--
-- AS DECISÕES, E O PORQUÊ DE CADA UMA
--   1. TABELA, não enum (a razão da 0128 e da 0038): conta nova custa uma linha de seed, não um `alter type` que não volta atrás.
--   2. A RAIZ É DECLARADA, NÃO INFERIDA: `codigo = 'demo_' || demonstracao` ⇔ `pai is null` (check). "Nenhuma conta sem pai, exceto as raízes" deixa de ser convenção: um nó solto não existe. O prefixo `demo_` existe
--      porque `dmpl` e `dva` são ao mesmo tempo uma demonstração INTEIRA e uma seção (0024) — o mesmo código não pode ser raiz e filho.
--   3. A DEMONSTRAÇÃO DO FILHO É A DO PAI por FK composta `(pai, demonstracao) → (codigo, demonstracao)`, e não por gatilho: o gatilho de linha não enxerga a linha-pai inserida na MESMA instrução
--      (o seed é um insert só), então a guarda calaria justamente no seed.
--   4. CICLO: um nó solto com pai em si mesmo é recusado por check; o ciclo de dois ou mais nós só nasce por UPDATE de `pai` e é recusado por gatilho (caminha para cima a partir do pai novo; `union`, não
--      `union all`, para a própria guarda não girar se algum dia encontrar um ciclo que já existe).
--   5. NATUREZA 'mista' EXISTE, NÃO FABRICADA (regra 1): receita bruta (receita credora + deduções devedoras — o portal a chama "Receita Bruta e Deduções"), despesas operacionais (contém "outras receitas
--      (despesas) operacionais, líquidas", 0128), resultado financeiro (receita e despesa), impostos sobre o lucro (corrente e diferido), as seções do fluxo, a DMPL e a DVA não têm sinal único. Cravar
--      'devedora' ou 'credora' ali seria a ausência de informação apresentada como dado. As demonstrações-raiz também são 'mista'. Só entra devedora/credora onde o sinal é o da própria seção (ativo,
--      custos devedoras; passivo e PL credoras).
--   6. `classe_recorrencia` (FK para `classe_contabil_catalogo`, 0128) fica NULL em todo nó: classificar recorrência por seção seria inventar — a recorrência é da RUBRICA (rubrica_classe), não da seção.
--      NULL aqui é "não determinado", nunca "recorrente".
--   7. `secao_canonica` é `unique` e NULL nos nós de agrupamento (raízes, ATIVO, PASSIVO_PL, os 4 subgrupos, que não existem em `SECAO_CANONICA_ENUM`). `NAO_CLASSIFICAVEL`, o escape do enum, NÃO é conta: "não sei a seção" não é seção. O extrator o grava como NULL (extract.mjs:612/1410), mas as fixtures carregadas pelo run.sh têm 466 linhas com o literal em
--      `campo_extraido.secao_canonica` (medido), e as migrations 0105/0144/0151/0152/0159/0240 o comparam como valor: o catálogo recusa o literal (check) e o teste SQL o exclui da conferência com esse número.
--   `taxonomia_tipo_documento` NÃO é tocada (a lista de tipos de documento é outro eixo).
--
-- A SEGUNDA RÉGUA. O catálogo e `SECAO_CANONICA_ENUM` têm de ser o mesmo conjunto, e o banco não importa .mjs: o portão é `Supabase/test/conta_canonica_regua.test.mjs` (entra no `node --test 'Supabase/test/*.test.mjs'`
-- do CI), que lê o enum de extract.mjs, o mapa `FAMILIA_POR_SECAO_CANONICA` do portal e as linhas de seed DESTA migration e reprova quando UM lado muda sozinho. Teto: ele lê as migrations que inserem em
-- conta_canonica; mudança feita por UPDATE/DELETE numa migration futura não é vista — quem alterar o catálogo por esses comandos atualiza o enum no mesmo commit (o portão do outro lado, o teste SQL, mede o banco
-- montado). O book DISTRESS não tem fixture no banco: o teste SQL cobre as seções que as fixtures de vertentes e canastra trazem (14 de 15) e NÃO finge cobrir o terceiro book (regra 4).
--
-- ACESSO. Catálogo global, só leitura para o portal (como as 14 tabelas da 0216: policy `(select fn_tem_papel())`); a escrita é de migration e do service_role (o grant mínimo da 0214, que o Supabase deixou de dar).
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/conta_canonica.test.sql — 40 asserts (40 execuções), medidos em 11/11/2026 com `PGOPTIONS='-c cc.medindo=on'` (o assert vira `raise warning` e CONTA). Controle (migration intacta): 0 dos 40 asserts reprovam.
-- Por parte desligada (cada sabotagem é a migration reemitida sobre o banco montado pelo run.sh, copiado por template, teste rodado inteiro, aviso MEDIDO lido; `tdf_p26`):
--   * o check da raiz declarada (`conta_canonica_raiz_ck`): 2 dos 40 asserts (conta sem pai que não é raiz entra; raiz com pai passa a ser barrada só pela FK, com outro código);
--   * a FK composta (pai, demonstracao) inteira: 3 dos 40 (pai de outra demonstração no insert e no update, pai inexistente); trocada por FK simples só no código: 2 dos 40 (as duas de outra demonstração);
--   * o check pai <> codigo: 1 dos 40;
--   * o gatilho de ciclo: dropado 4 dos 40 (ciclo de 2 e de 3 nós, a sonda com 5 dos 6 requisitos, e o requisito do gatilho); desabilitado (`disable trigger`): os mesmos 4 dos 40; só a função esvaziada (`return new`): 3 dos 40 (os dois ciclos
--     e a sonda com 4 dos 6, porque o corpo perde os dois marcadores);
--   * o check de natureza: 1 dos 40; o de demonstração: 1 dos 40 (a recusa passa a vir da FK, com outro código); o unique de secao_canonica: 1 dos 40; o check do escape NAO_CLASSIFICAVEL: 1 dos 40; a FK de classe_recorrencia: 1 dos 40;
--   * o seed: sem o nó `dmpl` 5 dos 40 (a seção que as fixtures gravam sem conta, as 15 seções, os 26 nós, a leitura dos 26, a sonda); sem o subgrupo `intangivel` 4 dos 40; `receita_bruta` marcada credora 1 dos 40; `atividades_operacionais`
--     marcada devedora 1 dos 40 (sinal fabricado); `classe_recorrencia` preenchida em `custos` 1 dos 40; `custos` na demonstração errada (pelo `session_replication_role = replica`, o único jeito de driblar a FK) 3 dos 40;
--   * a policy de leitura dropada: 2 dos 40 (o portal lê 0 linhas, a sonda); o `grant select` ao authenticated revogado: o teste ABORTA com `permission denied` (42501) no primeiro select da parte 4 — o assert 1 dessa parte nem executa, e a
--     rodada para (o aborto, não o aviso, é o sinal); o `grant insert` + policy de insert concedidos ao authenticated: 1 dos 40.
-- O portão node (Supabase/test/conta_canonica_regua.test.mjs, 6 testes, controle 6 de 6 passam), com o arquivo REAL adulterado e restaurado: uma seção a mais no enum de N8N/lib/extract.mjs reprova 2 dos 6 testes; o nó `dva` tirado do seed
-- 2 dos 6; `custos: "balanco"` no mapa do portal 1 dos 6. Os 3 últimos testes do arquivo provam o comparador com cópias adulteradas, sem tocar nenhum arquivo.
-- ACHADO DA MEDIÇÃO (não do desenho): o seed da sonda saiu primeiro com `26` na coluna `marcador` em vez de `criterio_seed`; o assert "a sonda acusa o seed com 25 dos 26 nós" reprovou, e a sonda dava `presente` para o seed pela metade.
-- ACHADO DA MEDIÇÃO 2: a primeira versão do teste tinha dois asserts DENTRO do bloco que desfaz (o rollback desfaz o contador de asserts) e usava `raise exception` com o mesmo sqlstate (P0001) do assert, de modo que a falha dele era engolida pelo
-- `exception when`; agora o sentinel é X0242 e a leitura é feita fora do bloco.

begin;

-- -----------------------------------------------------------------------------
-- A tabela.
-- -----------------------------------------------------------------------------
create table if not exists conta_canonica (
  codigo             text primary key,
  nome               text not null,
  pai                text,
  demonstracao       text not null check (demonstracao in ('balanco', 'dre', 'fluxo_caixa', 'dmpl', 'dva')),
  natureza           text not null check (natureza in ('devedora', 'credora', 'mista')),
  secao_canonica     text unique check (secao_canonica is null or secao_canonica <> 'NAO_CLASSIFICAVEL'),
  classe_recorrencia text references classe_contabil_catalogo(codigo),
  ordem              int  not null,
  ativo              boolean not null default true,
  -- a raiz é DECLARADA (decisão 2): sem pai ⇔ o código é o da própria demonstração
  constraint conta_canonica_raiz_ck check ((pai is null) = (codigo = 'demo_' || demonstracao)),
  constraint conta_canonica_pai_nao_e_ela_ck check (pai is distinct from codigo),
  -- a chave-alvo da FK composta (decisão 3)
  constraint conta_canonica_codigo_demonstracao_uq unique (codigo, demonstracao),
  constraint conta_canonica_pai_fk foreign key (pai, demonstracao) references conta_canonica (codigo, demonstracao)
);

comment on table conta_canonica is
  'A árvore canônica demonstração > grupo > seção > subgrupo (0242, P26). `secao_canonica` é ATRIBUTO da conta (null nos nós de agrupamento), não um plano de contas paralelo. Só a taxonomia atual (26 nós): sem '
  'conta-folha (caixa, clientes…), que é a P27. Raiz declarada (codigo = demo_<demonstracao> ⇔ pai null); o filho tem a demonstração do pai (FK composta); ciclo recusado por gatilho. Mesmo conjunto de '
  'SECAO_CANONICA_ENUM (N8N/lib/extract.mjs), conferido por Supabase/test/conta_canonica_regua.test.mjs.';
comment on column conta_canonica.natureza is
  '''mista'' = sem sinal único, e NÃO um default: receita bruta (receita + deduções), despesas operacionais (inclui outras receitas), resultado financeiro, impostos sobre o lucro, as seções do fluxo, DMPL, DVA e as '
  'demonstrações-raiz. Devedora/credora só onde o sinal é o da própria seção (regra 1: não fabricar um sinal que o dado não tem).';
comment on column conta_canonica.classe_recorrencia is
  'NULL = não determinado, nunca "recorrente": a recorrência é da rubrica (rubrica_classe, 0128), não da seção. Nenhum nó a preenche na 0242.';

-- -----------------------------------------------------------------------------
-- O ciclo (decisão 4). Só nasce por UPDATE de pai; `union` para a própria guarda não girar.
-- -----------------------------------------------------------------------------
create or replace function fn_conta_canonica_sem_ciclo()
returns trigger language plpgsql as $$
declare v_n int;
begin
  if new.pai is null then
    return new;
  end if;
  with recursive sobe(codigo, pai) as (
    select c.codigo, c.pai from conta_canonica c where c.codigo = new.pai
    union
    select c.codigo, c.pai from conta_canonica c join sobe s on c.codigo = s.pai
  )
  select count(*) into v_n from sobe where codigo = new.codigo;
  if v_n > 0 then
    raise exception 'conta_canonica: % como pai de % fecha um ciclo (% é ancestral de %)', new.pai, new.codigo, new.codigo, new.pai
      using errcode = 'check_violation';
  end if;
  return new;
end $$;

revoke all on function fn_conta_canonica_sem_ciclo() from public, anon, authenticated;

drop trigger if exists trg_conta_canonica_sem_ciclo on conta_canonica;
create trigger trg_conta_canonica_sem_ciclo
  before update of pai on conta_canonica
  for each row when (new.pai is distinct from old.pai)
  execute function fn_conta_canonica_sem_ciclo();

-- -----------------------------------------------------------------------------
-- RLS e grants: catálogo global, leitura para quem tem papel (0216), escrita só do service_role (0214).
-- -----------------------------------------------------------------------------
alter table conta_canonica enable row level security;
drop policy if exists conta_canonica_read on conta_canonica;
create policy conta_canonica_read on conta_canonica for select to authenticated using ((select fn_tem_papel()));
grant select on conta_canonica to authenticated;
grant select, insert, update, delete on conta_canonica to service_role;

-- -----------------------------------------------------------------------------
-- O seed: a taxonomia ATUAL, um nó por linha (o portão node lê estas linhas: manter o formato
-- ('codigo', 'Nome', pai|null, 'demonstracao', 'natureza', secao_canonica|null, ordem)).
-- -----------------------------------------------------------------------------
insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, secao_canonica, ordem) values
  ('demo_balanco', 'Balanço Patrimonial', null, 'balanco', 'mista', null, 100),
  ('demo_dre', 'Demonstração do Resultado', null, 'dre', 'mista', null, 200),
  ('demo_fluxo_caixa', 'Demonstração do Fluxo de Caixa', null, 'fluxo_caixa', 'mista', null, 300),
  ('demo_dmpl', 'Demonstração das Mutações do Patrimônio Líquido', null, 'dmpl', 'mista', null, 400),
  ('demo_dva', 'Demonstração do Valor Adicionado', null, 'dva', 'mista', null, 500)
on conflict (codigo) do nothing;

insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, secao_canonica, ordem) values
  ('ativo', 'Ativo', 'demo_balanco', 'balanco', 'devedora', null, 110),
  ('passivo_pl', 'Passivo e Patrimônio Líquido', 'demo_balanco', 'balanco', 'credora', null, 120),
  ('receita_bruta', 'Receita Bruta e Deduções', 'demo_dre', 'dre', 'mista', 'receita_bruta', 210),
  ('custos', 'Custos', 'demo_dre', 'dre', 'devedora', 'custos', 220),
  ('despesas_operacionais', 'Despesas Operacionais', 'demo_dre', 'dre', 'mista', 'despesas_operacionais', 230),
  ('resultado_financeiro', 'Resultado Financeiro', 'demo_dre', 'dre', 'mista', 'resultado_financeiro', 240),
  ('impostos_lucro', 'Impostos sobre o Lucro', 'demo_dre', 'dre', 'mista', 'impostos_lucro', 250),
  ('atividades_operacionais', 'Atividades Operacionais', 'demo_fluxo_caixa', 'fluxo_caixa', 'mista', 'atividades_operacionais', 310),
  ('atividades_investimento', 'Atividades de Investimento', 'demo_fluxo_caixa', 'fluxo_caixa', 'mista', 'atividades_investimento', 320),
  ('atividades_financiamento', 'Atividades de Financiamento', 'demo_fluxo_caixa', 'fluxo_caixa', 'mista', 'atividades_financiamento', 330),
  ('dmpl', 'Mutações do Patrimônio Líquido', 'demo_dmpl', 'dmpl', 'mista', 'dmpl', 410),
  ('dva', 'Valor Adicionado', 'demo_dva', 'dva', 'mista', 'dva', 510)
on conflict (codigo) do nothing;

insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, secao_canonica, ordem) values
  ('ativo_circulante', 'Ativo Circulante', 'ativo', 'balanco', 'devedora', 'ativo_circulante', 111),
  ('ativo_nao_circulante', 'Ativo Não Circulante', 'ativo', 'balanco', 'devedora', 'ativo_nao_circulante', 112),
  ('passivo_circulante', 'Passivo Circulante', 'passivo_pl', 'balanco', 'credora', 'passivo_circulante', 121),
  ('passivo_nao_circulante', 'Passivo Não Circulante', 'passivo_pl', 'balanco', 'credora', 'passivo_nao_circulante', 122),
  ('patrimonio_liquido', 'Patrimônio Líquido', 'passivo_pl', 'balanco', 'credora', 'patrimonio_liquido', 123)
on conflict (codigo) do nothing;

insert into conta_canonica (codigo, nome, pai, demonstracao, natureza, secao_canonica, ordem) values
  ('realizavel_lp', 'Realizável a Longo Prazo', 'ativo_nao_circulante', 'balanco', 'devedora', null, 1121),
  ('investimentos', 'Investimentos', 'ativo_nao_circulante', 'balanco', 'devedora', null, 1122),
  ('imobilizado', 'Imobilizado', 'ativo_nao_circulante', 'balanco', 'devedora', null, 1123),
  ('intangivel', 'Intangível', 'ativo_nao_circulante', 'balanco', 'devedora', null, 1124)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('conta_canonica_tabela', '0242', 'tabela', 'conta_canonica', null, null,
   'O catálogo de contas canônicas não existe: as 15 seções do book voltam a viver só em código (extract.mjs e statement-templates.ts) e a P27 (resolver a linha para uma conta) não tem onde gravar.',
   'importante', 1096),
  ('conta_canonica_seed', '0242', 'seed', 'conta_canonica', null, 26,
   'O catálogo existe vazio ou pela metade (critério 26 = 5 raízes + 2 grupos + 15 seções + 4 subgrupos): seção do book sem conta canônica, e o critério "toda seção tem conta" deixa de valer.',
   'importante', 1097),
  ('conta_canonica_policy_leitura', '0242', 'policy', 'conta_canonica.conta_canonica_read', null, null,
   'Com a RLS ligada e sem a policy, o portal (authenticated) lê zero linhas do catálogo — a árvore some da tela sem erro.',
   'importante', 1098),
  ('conta_canonica_gatilho_ciclo', '0242', 'gatilho', 'conta_canonica.trg_conta_canonica_sem_ciclo', 'fn_conta_canonica_sem_ciclo', null,
   'Sem o gatilho (ou com ele chamando outra função) um UPDATE de pai fecha um ciclo e a subida até a raiz gira para sempre: nenhuma conta chega à demonstração.',
   'importante', 1099),
  ('conta_canonica_ciclo_sobe_ate_a_raiz', '0242', 'corpo', 'fn_conta_canonica_sem_ciclo', 'with recursive sobe(codigo, pai) as (', null,
   'A função do gatilho precisa caminhar de fato até a raiz. Corpo sem isto = o gatilho existe e liga, e deixa passar o ciclo de dois nós (a pergunta "o novo filho é ancestral do novo pai?" nunca é feita).',
   'importante', 1100),
  ('conta_canonica_ciclo_recusa', '0242', 'corpo', 'fn_conta_canonica_sem_ciclo', 'raise exception ''conta_canonica: %', null,
   'A função do gatilho precisa RECUSAR o ciclo. Corpo sem a exceção = a guarda mede e cala.',
   'importante', 1101)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0242', revisado_em = current_date,
       observacao = 'A 0242 cria conta_canonica (a árvore demonstração > grupo > seção > subgrupo, 26 nós, só a taxonomia atual) com a guarda de pai/ciclo. 6 requisitos novos (ordem 1096-1101).'
 where id = true;

commit;
