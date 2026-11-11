-- 0242 — A SEÇÃO QUE SÓ EXISTIA EM CÓDIGO: o catálogo `conta_canonica` (P26, Fase 3, etapa 3.1) — a árvore de demonstração → grupo → seção → subgrupo que o banco não tinha, com a guarda de raiz (todo nó sobe até a raiz da própria demonstração) e a régua contra `SECAO_CANONICA_ENUM`.
-- (Cria 1 tabela, conta_canonica, 2 funções (a das órfãs e a do gatilho), 1 gatilho de instrução e 3 views da sonda. Seed de 27 nós. Sem backfill: nenhuma linha existente é tocada. 9 requisitos novos na sonda (ordem 1096-1104). Idempotente: pode ser reaplicada.)
--
-- O DEFEITO. As 15 seções canônicas (`ativo_circulante` … `dva`) são a coluna vertebral do book — é por elas que a linha vai para a aba, que a cascata da DRE fecha e que o balanço soma — e a lista
-- delas só existia em CÓDIGO: `N8N/lib/extract.mjs` (`SECAO_CANONICA_ENUM`, a que a IA devolve) e `portal/src/lib/statement-templates.ts` (`FAMILIA_POR_SECAO_CANONICA`, a que roteia a aba), duas cópias
-- que o próprio cabeçalho do extract.mjs manda "manter IDÊNTICAS" sem nenhum portão. No banco `campo_extraido.secao_canonica` é `text` livre (0012): qualquer string grava. Medido nas fixtures que o run.sh carrega
-- (vertentes e canastra): 14 das 15 seções aparecem em `campo_extraido` (dva ausente) e NENHUMA tabela as descrevia — não havia onde pendurar a conta canônica (caixa, clientes…) que a Fase 3 precisa
-- resolver (P27), nem onde dizer que "imobilizado" é filho de "ativo não circulante". O roadmap (ARQUITETURA_ALVO_E_ROADMAP §1.1 e F4) define o catálogo como
-- `conta_canonica(codigo, nome, secao_canonica, classe_recorrencia, pai, natureza)`; `secao_canonica` vira ATRIBUTO da conta, não um plano de contas paralelo.
--
-- O QUE ENTRA, E SÓ A TAXONOMIA ATUAL (27 nós): 5 raízes (as demonstrações: balanço, DRE, fluxo de caixa, DMPL, DVA), os 2 grupos do balanço (ATIVO, PASSIVO E PL), as 15 seções e, debaixo do ANC, os 4 subgrupos (realizável
-- a LP, investimentos, imobilizado, intangível) MAIS o balde "Outros ativos não circulantes" — os 5 filhos de `ativo_nao_circulante_grp` na `BALANCO_OUTLINE` do portal. O nó com `secao_canonica = 'ativo_nao_circulante'` é o
-- GRUPO ANC (é o que a IA quer dizer: ANC em geral), não o balde: o portal tem as duas coisas (o total `ativo_nao_circulante_grp` e o balde "Outros", chave `ativo_nao_circulante`) e a primeira versão desta migration as fundia num
-- nó só — o "Outros" e o "Total do ANC" de um documento resolveriam no mesmo nó não-folha (P27: o Outros some ou o total soma em dobro). NÃO entra conta-folha (caixa, clientes…): resolver a linha para uma conta é a P27, e semear folha agora seria inventar o plano de contas antes de haver o que o valide.
--
-- AS DECISÕES, E O PORQUÊ DE CADA UMA
--   1. TABELA, não enum (a razão da 0128 e da 0038): conta nova custa uma linha de seed, não um `alter type` que não volta atrás.
--   2. A RAIZ É DECLARADA, NÃO INFERIDA: `codigo = 'demo_' || demonstracao` ⇔ `pai is null` (check). "Nenhuma conta sem pai, exceto as raízes" deixa de ser convenção: um nó solto não existe. O prefixo `demo_` existe
--      porque `dmpl` e `dva` são ao mesmo tempo uma demonstração INTEIRA e uma seção (0024) — o mesmo código não pode ser raiz e filho.
--   3. A DEMONSTRAÇÃO DO FILHO É A DO PAI por FK composta `(pai, demonstracao) → (codigo, demonstracao)`, e não por gatilho: o gatilho de linha não enxerga a linha-pai inserida na MESMA instrução
--      (o seed é um insert só), então a guarda calaria justamente no seed.
--   4. RAIZ ALCANÇÁVEL, UMA GUARDA SÓ: todo nó tem de subir até `demo_<demonstracao>`. É um gatilho AFTER de INSTRUÇÃO (insert, ou update de pai/codigo/demonstracao) que anda DESCENDO das raízes sobre a tabela inteira
--      (`union`, não `union all`: termina mesmo com ciclo) e recusa se sobrar nó fora. A primeira versão era um gatilho de LINHA `before update of pai` que subia a partir do pai novo — e a revisão REPRODUZIU dois ciclos que ele não
--      via: `insert ('x_a' pai 'x_b'), ('x_b' pai 'x_a')` em lote (INSERT 0 2: o gatilho nem disparava no insert) e dois `pai` trocados num UPDATE só (cada linha olha a outra ainda com o pai antigo). O predicado "todo nó alcança a
--      raiz" subsume ciclo e pai solto, e por isso NÃO há check `pai <> codigo` (o nó que é pai de si mesmo não sobe até a raiz e o gatilho o recusa: um mecanismo só). Teto: a guarda lê a tabela inteira a cada instrução que toca pai/codigo; com ~27 nós é sem custo, e se a P27
--      levar a tabela a dezenas de milhares de folhas ela passa a olhar só a subárvore dos nós tocados (tabela de transição).
--   5. NATUREZA = O SALDO NORMAL DO GRUPO, pela convenção contábil. Conta REDUTORA (deduções da receita, depreciação/amortização acumulada, prejuízos acumulados) tem natureza PRÓPRIA e é coisa da FOLHA (P27): a folha
--      NUNCA herda a natureza do pai. Por isso `receita_bruta` é credora (o grupo é receita; as deduções são folhas redutoras), e ativo, passivo e PL idem pelo saldo normal. Só é 'mista' o grupo que tem componentes PRÓPRIOS
--      dos dois lados: resultado financeiro (receitas e despesas financeiras), despesas operacionais (inclui "outras receitas operacionais", 0128), impostos sobre o lucro (IR/CS corrente e diferido), as seções do fluxo, DMPL, DVA e
--      as demonstrações-raiz. A primeira versão misturava os dois critérios (receita bruta 'mista' por causa das deduções, o ativo 'devedora' apesar da depreciação). Medido pelo revisor nas fixtures: valor NEGATIVO em 68 linhas do PL,
--      47 do ANC, 29 do AC e 28 de receita_bruta — redutora existe em todo grupo, e é por isso que o sinal da linha NÃO é a natureza do grupo e a natureza do grupo não é herdada.
--   6. `classe_recorrencia` (FK para `classe_contabil_catalogo`, 0128) fica NULL em todo nó: classificar recorrência por seção seria inventar — a recorrência é da RUBRICA (rubrica_classe), não da seção.
--      NULL aqui é "não determinado", nunca "recorrente".
--   7. `secao_canonica` é `unique` e NULL nos nós de agrupamento (raízes, ATIVO, PASSIVO_PL, os 4 subgrupos do ANC e o balde Outros, que não existem em `SECAO_CANONICA_ENUM`). `NAO_CLASSIFICAVEL`, o escape do enum, NÃO é conta: "não sei a seção" não é seção. O extrator o grava como NULL (extract.mjs:612/1410), mas as fixtures carregadas pelo run.sh têm 466 linhas com o literal em
--      `campo_extraido.secao_canonica` (medido), e as migrations 0105/0144/0151/0152/0159/0240 o comparam como valor: o catálogo recusa o literal (check) e o teste SQL o exclui da conferência com esse número.
--   `taxonomia_tipo_documento` NÃO é tocada (a lista de tipos de documento é outro eixo).
--
-- A SEGUNDA RÉGUA (e a do portal). O catálogo e `SECAO_CANONICA_ENUM` têm de ser o mesmo conjunto, e o banco não importa .mjs: o portão é `Supabase/test/conta_canonica_regua.test.mjs` (entra no `node --test 'Supabase/test/*.test.mjs'`
-- do CI), que lê o enum de extract.mjs, o mapa `FAMILIA_POR_SECAO_CANONICA` do portal e as linhas de seed DESTA migration e reprova quando UM lado muda sozinho; ele compara também os filhos do ANC com os filhos de `ativo_nao_circulante_grp` na `BALANCO_OUTLINE`. Teto: ele lê as migrations que inserem em
-- conta_canonica; mudança feita por UPDATE/DELETE numa migration futura não é vista — quem alterar o catálogo por esses comandos atualiza o enum no mesmo commit (o portão do outro lado, o teste SQL, mede o banco
-- montado). O book DISTRESS não tem fixture no banco: o teste SQL cobre as seções que as fixtures de vertentes e canastra trazem (14 de 15) e NÃO finge cobrir o terceiro book (regra 4).
--
-- ACESSO. Catálogo global, só leitura para o portal (como as 14 tabelas da 0216: policy `(select fn_tem_papel())`); a escrita é de migration e do service_role (o grant mínimo da 0214, que o Supabase deixou de dar).
--
-- A SONDA. A tabela e a policy pelos tipos de sempre; o GATILHO com a função que ele tem de chamar; as constraints estruturais, o seed e a ausência de nó órfão por view (o padrão da 0224: tipo `comportamento`/`seed` sobre uma view que
-- devolve linhas só quando o estado é o certo). Medido na primeira versão: com `conta_canonica_raiz_ck`, `conta_canonica_pai_fk` e o check do NAO_CLASSIFICAVEL dropados a sonda dava 6 de 6
-- presentes (nenhum requisito olhava constraint), e o seed era `count(*) >= 26`, que a P27 (folhas) esconderia. Agora o seed é conferido pela PRESENÇA dos códigos esperados (com o pai), não pela contagem.
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/conta_canonica.test.sql — 49 asserts (49 execuções), medidos em 11/11/2026 com `PGOPTIONS='-c cc.medindo=on'` (o assert vira `raise warning` e CONTA). Controle (migration intacta): 0 dos 49 asserts reprovam.
-- Cada sabotagem é a migration reemitida sobre o banco montado pelo run.sh (cópia por template, teste rodado inteiro, aviso MEDIDO lido). Por parte (a 1ª versão, de 40 asserts, está no commit dab8bfa; os números abaixo são os da revisão):
--   * o gatilho de raiz: dropado 7 dos 49 asserts (ciclo de 2 nós, de 3 nós, o INSERT em lote, os dois pais trocados num UPDATE, o pai igual ao próprio, a sonda com 8 dos 9 requisitos, e o do gatilho); desabilitado (`disable trigger`) 7 dos 49;
--     só a função esvaziada (`return null`) 6 dos 49; a função das órfãs esvaziada (`where false`) 7 dos 49 (os 4 ciclos, o pai próprio, a sonda 8 dos 9, e o nó órfão que a sonda não acusa mais);
--   * o gatilho só em `update of pai` (a cobertura da v1): 2 dos 49 (o INSERT em lote e o pai igual ao próprio); o gatilho de LINHA da v1 reinstalado: 3 dos 49 (o INSERT em lote, a sonda, o gatilho) — e os dois pais trocados num UPDATE só
--     PASSARAM nele no banco de teste, ou seja, o assert desse cenário depende da ordem física das linhas e prova a guarda nova, não discrimina sozinho a v1 (o do INSERT em lote discrimina);
--   * natureza: `receita_bruta` marcada mista 1 dos 49;
--   * ANC: o balde `outros_ativos_nao_circulantes` removido 5 dos 49; a `secao_canonica` tirada do nó do grupo ANC 3 dos 49;
--   * a sonda: a view do seed trocada por contagem (`select codigo from conta_canonica`) 1 dos 49 (a folha a mais esconde o nó que falta); a view de órfãos fixa em "ok" 1 dos 49; a view das constraints fixa em 9 linhas 1 dos 49;
--   * cada constraint estrutural dropada deixa o requisito `conta_canonica_constraints` ausente (o assert "a sonda acusa cada uma das 9" reprova em todas): pkey 1 dos 49; a unique da chave composta (leva a FK junto) 4; a unique da seção 2; o check da raiz 2;
--     a FK da demonstração do pai 4; a FK da classe 2; o check de demonstração 2; o de natureza 2; o do escape NAO_CLASSIFICAVEL 2 (as demais reprovações são o comportamento que cada guarda dá: a sonda NÃO é o único alarme).
-- O portão node (Supabase/test/conta_canonica_regua.test.mjs, 8 testes, controle 8 de 8 passam), com o arquivo REAL adulterado e restaurado: um subgrupo a mais no `ativo_nao_circulante_grp` do outline do portal reprova 2 dos 8; um subgrupo a menos 2 dos 8
-- (nos dois, o teste que compara as seções e o que compara os filhos do ANC); uma seção a mais no enum 2 dos 8; o nó `dva` tirado do seed 2 dos 8; `custos: "balanco"` no mapa do portal 1 dos 8 (medidos na 1ª versão, 6 testes).
-- ACHADOS DA MEDIÇÃO (não do desenho): (1) o seed da sonda da 1ª versão saiu com `26` na coluna `marcador` em vez de `criterio_seed`, e a sonda dava `presente` para o seed pela metade; (2) a 1ª versão do teste tinha asserts DENTRO do bloco que desfaz (o rollback
-- desfaz o contador) e usava o mesmo sqlstate do assert (P0001) como sentinel, engolindo a falha dele — agora o sentinel é X0242 e a leitura é feita fora do bloco; (3) a view da sonda chama `fn_conta_canonica_orfas`, e o Postgres confere o EXECUTE da função com
-- quem LÊ a view: a sonda chamada como service_role (conferir_envio.test.sql) deu `permission denied for function` até a função virar security definer com grant.

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
  -- a raiz é DECLARADA (decisão 2): sem pai ⇔ o código é o da própria demonstração
  constraint conta_canonica_raiz_ck check ((pai is null) = (codigo = 'demo_' || demonstracao)),
  -- a chave-alvo da FK composta (decisão 3)
  constraint conta_canonica_codigo_demonstracao_uq unique (codigo, demonstracao),
  constraint conta_canonica_pai_fk foreign key (pai, demonstracao) references conta_canonica (codigo, demonstracao)
);

comment on table conta_canonica is
  'A árvore canônica demonstração > grupo > seção > subgrupo (0242, P26). `secao_canonica` é ATRIBUTO da conta (null nos nós de agrupamento), não um plano de contas paralelo. Só a taxonomia atual (27 nós): sem '
  'conta-folha (caixa, clientes…), que é a P27. Raiz declarada (codigo = demo_<demonstracao> ⇔ pai null); o filho tem a demonstração do pai (FK composta); todo nó sobe até a raiz (gatilho de instrução). Mesmo conjunto de '
  'SECAO_CANONICA_ENUM (N8N/lib/extract.mjs), conferido por Supabase/test/conta_canonica_regua.test.mjs.';
comment on column conta_canonica.natureza is
  'O SALDO NORMAL DO GRUPO pela convenção contábil (devedora | credora | mista). Conta REDUTORA (deduções da receita, depreciação/amortização acumulada, prejuízos acumulados) tem natureza PRÓPRIA e é da FOLHA (P27): a folha '
  'NUNCA herda a natureza do pai. ''mista'' só onde o grupo tem componentes PRÓPRIOS dos dois lados: resultado financeiro, despesas operacionais (inclui outras receitas), impostos sobre o lucro (corrente e diferido), as seções do fluxo, '
  'DMPL, DVA e as demonstrações-raiz. Redutora existe em todo grupo (valor negativo medido nas fixtures: 68 linhas do PL, 47 do ANC, 29 do AC, 28 de receita_bruta), e por isso o sinal da linha não é a natureza do grupo (regra 1: '
  'não fabricar um sinal que o dado não tem).';
comment on column conta_canonica.classe_recorrencia is
  'NULL = não determinado, nunca "recorrente": a recorrência é da rubrica (rubrica_classe, 0128), não da seção. Nenhum nó a preenche na 0242.';

-- -----------------------------------------------------------------------------
-- A guarda de raiz (decisão 4): uma função das órfãs (descendo das raízes) e um gatilho de INSTRUÇÃO que a chama.
-- -----------------------------------------------------------------------------
create or replace function fn_conta_canonica_orfas()
returns setof text language sql stable security definer set search_path = public, pg_temp as $$
  with recursive alcanca(codigo, demonstracao) as (
    select c.codigo, c.demonstracao from conta_canonica c where c.pai is null and c.codigo = 'demo_' || c.demonstracao
    union
    select c.codigo, c.demonstracao from conta_canonica c join alcanca a on c.pai = a.codigo and c.demonstracao = a.demonstracao
  )
  select c.codigo from conta_canonica c where not exists (select 1 from alcanca a where a.codigo = c.codigo) order by 1
$$;

create or replace function fn_conta_canonica_alcanca_a_raiz()
returns trigger language plpgsql as $$
declare v_orfas text;
begin
  select string_agg(o, ', ') into v_orfas from fn_conta_canonica_orfas() o;
  if v_orfas is not null then
    raise exception 'conta_canonica: nó(s) que não sobem até a raiz da própria demonstração (ciclo ou pai solto): %', v_orfas
      using errcode = 'check_violation';
  end if;
  return null;
end $$;

-- DEFINER + grant: a view da sonda chama esta função e o Postgres confere o EXECUTE de função com quem LÊ a view, não com o dono dela (medido: a sonda chamada como service_role dava `permission denied for function
-- fn_conta_canonica_orfas` na primeira versão); e definer porque, como invoker, o usuário sem papel enxergaria a tabela vazia pela RLS e a sonda daria "sem órfão" sobre o nada. Só lê.
revoke all on function fn_conta_canonica_orfas() from public, anon;
grant execute on function fn_conta_canonica_orfas() to authenticated, service_role;
-- E ao leitor só-leitura da API de gerenciamento, como a 0233 e a 0234 fazem. MEDIDO em produção em
-- 11/11/2026, logo depois de aplicar a 0242 sem este bloco: `select ... from fn_instalacao_conferir()`
-- pela API (`supabase_read_only_user`) passou a falhar inteira com "permission denied for function
-- fn_conta_canonica_orfas" — a view da sonda chama a função com o privilégio de quem LÊ, e a sonda
-- inteira (377 requisitos) ficou ilegível para quem lê produção sem escrever. O teste local não pega:
-- o papel não existe quando as migrations rodam no `run.sh`.
do $$ begin
  if exists (select 1 from pg_roles where rolname = 'supabase_read_only_user') then
    execute 'grant execute on function fn_conta_canonica_orfas() to supabase_read_only_user';
  end if;
end $$;
revoke all on function fn_conta_canonica_alcanca_a_raiz() from public, anon, authenticated;

drop trigger if exists trg_conta_canonica_alcanca_a_raiz on conta_canonica;
create trigger trg_conta_canonica_alcanca_a_raiz
  after insert or update of pai, codigo, demonstracao on conta_canonica
  for each statement
  execute function fn_conta_canonica_alcanca_a_raiz();

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
  ('receita_bruta', 'Receita Bruta e Deduções', 'demo_dre', 'dre', 'credora', 'receita_bruta', 210),
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
  ('intangivel', 'Intangível', 'ativo_nao_circulante', 'balanco', 'devedora', null, 1124),
  ('outros_ativos_nao_circulantes', 'Outros Ativos Não Circulantes', 'ativo_nao_circulante', 'balanco', 'devedora', null, 1125)
on conflict (codigo) do nothing;

-- -----------------------------------------------------------------------------
-- As VIEWS da sonda (padrão da 0224): uma linha = uma garantia presente. Rodam com os privilégios do dono (a RLS da tabela não as esvazia para quem lê a sonda).
-- -----------------------------------------------------------------------------
-- O SEED: um nó esperado por linha, achado pelo CÓDIGO e pelo PAI (nunca pela contagem: a P27 acrescenta folhas e a contagem passaria a mentir).
create or replace view instalacao_sonda_conta_canonica_seed as
  select c.codigo::text as codigo
    from conta_canonica c
    join (values
      ('demo_balanco', null), ('demo_dre', null), ('demo_fluxo_caixa', null), ('demo_dmpl', null), ('demo_dva', null),
      ('ativo', 'demo_balanco'), ('passivo_pl', 'demo_balanco'),
      ('receita_bruta', 'demo_dre'), ('custos', 'demo_dre'), ('despesas_operacionais', 'demo_dre'), ('resultado_financeiro', 'demo_dre'), ('impostos_lucro', 'demo_dre'),
      ('atividades_operacionais', 'demo_fluxo_caixa'), ('atividades_investimento', 'demo_fluxo_caixa'), ('atividades_financiamento', 'demo_fluxo_caixa'),
      ('dmpl', 'demo_dmpl'), ('dva', 'demo_dva'),
      ('ativo_circulante', 'ativo'), ('ativo_nao_circulante', 'ativo'),
      ('passivo_circulante', 'passivo_pl'), ('passivo_nao_circulante', 'passivo_pl'), ('patrimonio_liquido', 'passivo_pl'),
      ('realizavel_lp', 'ativo_nao_circulante'), ('investimentos', 'ativo_nao_circulante'), ('imobilizado', 'ativo_nao_circulante'),
      ('intangivel', 'ativo_nao_circulante'), ('outros_ativos_nao_circulantes', 'ativo_nao_circulante')
    ) e(codigo, pai) on e.codigo = c.codigo and e.pai is not distinct from c.pai;
comment on view instalacao_sonda_conta_canonica_seed is
  'Sonda da 0242: uma linha = um dos 27 nós esperados da taxonomia atual existe com o pai certo. Menos de 27: o seed rodou pela metade ou um nó foi movido. Folha acrescentada pela P27 não conta nem atrapalha.';

-- AS CONSTRAINTS ESTRUTURAIS: pelo NOME e pelo fragmento da definição (uma constraint recriada com o mesmo nome e outro predicado não passa).
create or replace view instalacao_sonda_conta_canonica_constraints as
  select c.conname::text as constraint_nome
    from (values
      ('conta_canonica_pkey', 'p', 'PRIMARY KEY (codigo)'),
      ('conta_canonica_codigo_demonstracao_uq', 'u', 'UNIQUE (codigo, demonstracao)'),
      ('conta_canonica_secao_canonica_key', 'u', 'UNIQUE (secao_canonica)'),
      ('conta_canonica_raiz_ck', 'c', '''demo_''::text'),
      ('conta_canonica_pai_fk', 'f', 'FOREIGN KEY (pai, demonstracao) REFERENCES conta_canonica(codigo, demonstracao)'),
      ('conta_canonica_classe_recorrencia_fkey', 'f', 'REFERENCES classe_contabil_catalogo(codigo)'),
      ('conta_canonica_demonstracao_check', 'c', '''fluxo_caixa''::text'),
      ('conta_canonica_natureza_check', 'c', '''mista''::text'),
      ('conta_canonica_secao_canonica_check', 'c', '''NAO_CLASSIFICAVEL''::text')
    ) e(conname, contype, frag)
    join pg_constraint c on c.conrelid = 'public.conta_canonica'::regclass and c.conname = e.conname and c.contype = e.contype::"char"
   where pg_get_constraintdef(c.oid) like '%' || e.frag || '%';
comment on view instalacao_sonda_conta_canonica_constraints is
  'Sonda da 0242: uma linha = uma das 9 constraints estruturais de conta_canonica existe com o predicado esperado. Menos de 9: uma guarda (raiz declarada, FK da demonstração do pai, check dos valores, unique da seção) foi dropada ou trocada.';

-- NENHUM NÓ ÓRFÃO: uma linha somente se todo nó sobe até a raiz da própria demonstração.
create or replace view instalacao_sonda_conta_canonica_sem_orfao as
  select 1 as ok
   where exists (select 1 from conta_canonica) and not exists (select 1 from fn_conta_canonica_orfas());
comment on view instalacao_sonda_conta_canonica_sem_orfao is
  'Sonda da 0242: uma linha = o catálogo não está vazio e nenhum nó fica fora da árvore das cinco raízes (ciclo ou pai solto). Zero linhas: a árvore está quebrada, ou vazia.';

grant select on instalacao_sonda_conta_canonica_seed, instalacao_sonda_conta_canonica_constraints, instalacao_sonda_conta_canonica_sem_orfao to authenticated, service_role;  -- service_role: o requisito grant_views_service_role (0214)

-- -----------------------------------------------------------------------------
-- A SONDA. Marcadores em CÓDIGO, nunca de comentário.
-- -----------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('conta_canonica_tabela', '0242', 'tabela', 'conta_canonica', null, null,
   'O catálogo de contas canônicas não existe: as 15 seções do book voltam a viver só em código (extract.mjs e statement-templates.ts) e a P27 (resolver a linha para uma conta) não tem onde gravar.',
   'importante', 1096),
  ('conta_canonica_seed', '0242', 'seed', 'instalacao_sonda_conta_canonica_seed', null, 27,
   'Algum dos 27 nós esperados (5 raízes, 2 grupos, 15 seções, 4 subgrupos e o balde Outros do ANC) falta ou está com outro pai: seção do book sem conta canônica. Conferido por código e pai, não por contagem.',
   'importante', 1097),
  ('conta_canonica_policy_leitura', '0242', 'policy', 'conta_canonica.conta_canonica_read', null, null,
   'Com a RLS ligada e sem a policy, o portal (authenticated) lê zero linhas do catálogo — a árvore some da tela sem erro.',
   'importante', 1098),
  ('conta_canonica_gatilho_raiz', '0242', 'gatilho', 'conta_canonica.trg_conta_canonica_alcanca_a_raiz', 'fn_conta_canonica_alcanca_a_raiz', null,
   'Sem o gatilho (ou com ele chamando outra função) um insert em lote ou um update fecha um ciclo, ou solta um nó, e a subida até a raiz gira ou não chega: nenhuma conta resolve a demonstração.',
   'importante', 1099),
  ('conta_canonica_gatilho_chama_as_orfas', '0242', 'corpo', 'fn_conta_canonica_alcanca_a_raiz', 'from fn_conta_canonica_orfas() o', null,
   'A função do gatilho precisa perguntar quem é órfão. Corpo sem isto = o gatilho existe, liga e não olha nada.',
   'importante', 1100),
  ('conta_canonica_gatilho_recusa', '0242', 'corpo', 'fn_conta_canonica_alcanca_a_raiz', 'raise exception ''conta_canonica: nó(s)', null,
   'A função do gatilho precisa RECUSAR. Corpo sem a exceção = a guarda mede e cala.',
   'importante', 1101),
  ('conta_canonica_orfas_descem_das_raizes', '0242', 'corpo', 'fn_conta_canonica_orfas', 'with recursive alcanca(codigo, demonstracao) as (', null,
   'As órfãs são o que as cinco raízes NÃO alcançam descendo. Corpo sem a recursão = o predicado "todo nó sobe até a raiz" vira outra pergunta e o ciclo passa.',
   'importante', 1102),
  ('conta_canonica_constraints', '0242', 'comportamento', 'instalacao_sonda_conta_canonica_constraints', null, 9,
   'Faltam constraints estruturais de conta_canonica (raiz declarada, FK da demonstração do pai, unique da seção, checks de demonstração/natureza/escape, FK da classe): o catálogo aceita nó solto, pai de outra demonstração, natureza inventada.',
   'importante', 1103),
  ('conta_canonica_sem_no_orfao', '0242', 'comportamento', 'instalacao_sonda_conta_canonica_sem_orfao', null, 1,
   'Há nó que não sobe até a raiz da própria demonstração (ciclo ou pai solto), ou o catálogo está vazio: a conta canônica não resolve a demonstração.',
   'importante', 1104)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0242', revisado_em = current_date,
       observacao = 'A 0242 cria conta_canonica (a árvore demonstração > grupo > seção > subgrupo, 27 nós, só a taxonomia atual) com a guarda de raiz (gatilho de instrução), 3 views de sonda e 9 requisitos novos (ordem 1096-1104).'
 where id = true;

commit;
