-- =============================================================================
-- 0205 — OS CAMPOS DA APRESENTAÇÃO QUE NÃO TINHAM ONDE MORAR
-- (Era 0199 no branch da apresentação, depois 0201; renumerada para 0205 em 05/10/2026: o PR #252 ocupa 0199–0204 — inclusive a sua própria 0201 —, e a ordem do catálogo 855 era dele também, por isso esta usa 865.)
--
-- O DEFEITO. Toda lacuna da apresentação de crédito é o texto fixo "[a preencher]" gerado no
-- código (Arquitetura do Sistema/6 Referência/apresentacao-credito/ARQUITETURA.md, "O próximo
-- encaixe estrutural"): o analista que descobre o valor não tem onde registrá-lo, e a próxima
-- geração do deck volta a escrever "[a preencher]". Cada lacuna ganha uma CHAVE estável
-- (ex.: `xiv.ajuste.nao_recorrentes`) e uma linha aqui.
--
-- POR QUE VALOR VAZIO É RECUSADO (regra 1). Um valor "" ou "   " num campo preenchido seria
-- indistinguível de um dado informado: o deck deixaria de dizer "[a preencher]" e imprimiria um
-- branco como se fosse o número. Ausência é a AUSÊNCIA de linha, nunca uma linha em branco —
-- por isso o check. `btrim(valor)` sozinho só tira ESPAÇO: medido, tab+espaço passava como valor; o check tira também tab, CR e LF. A chave tem formato fixo (capítulo.grupo.campo,
-- minúsculas) para que um erro de digitação não crie um campo órfão que nenhum slide lê.
--
-- `fonte` (documento, URL, "analista") alimenta a nota de fonte do slide: número sem fonte não
-- entra. Fica anulável porque a tela de preenchimento por SQL precede o fluxo de pesquisa.
--
-- RLS e GRANT no padrão de `caso_premissa` (0038: policy `for all to authenticated`) e do que a
-- 0028 ensinou: policy sem GRANT de tabela devolve "permission denied" ao portal. Em produção o
-- Supabase concede por default privilege; aqui o grant explícito torna o acesso independente
-- disso. NÃO há backfill: a tabela nasce vazia, e vazia significa "tudo [a preencher]".
-- =============================================================================

create table if not exists caso_apresentacao_campo (
  caso_id        uuid not null references caso(id) on delete cascade,
  chave          text not null check (chave ~ '^[a-z0-9]+(\.[a-z0-9_]+)+$'),
  valor          text not null check (length(btrim(valor, E' \t\r\n')) > 0),
  fonte          text,
  preenchido_por text,
  preenchido_em  timestamptz not null default now(),
  primary key (caso_id, chave)
);

comment on table caso_apresentacao_campo is
  'Valor dos campos "[a preencher]" da apresentação de crédito, por caso e chave estável. Ausência de linha = o deck escreve "[a preencher]"; valor em branco é recusado (regra 1: vazio não é valor). 0205.';
comment on column caso_apresentacao_campo.chave is
  'Capítulo.grupo.campo em minúsculas, ex.: xiv.ajuste.nao_recorrentes. Formato travado por check para que typo não vire campo órfão.';
comment on column caso_apresentacao_campo.fonte is
  'De onde veio o valor (documento, URL, "analista"). Vai para a nota de fonte do slide.';

alter table caso_apresentacao_campo enable row level security;
create policy caso_apresentacao_campo_authenticated_all on caso_apresentacao_campo
  for all to authenticated using (true) with check (true);
grant select, insert, update, delete on caso_apresentacao_campo to authenticated;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('caso_apresentacao_campo_tabela_existe', '0205', 'tabela', 'caso_apresentacao_campo',
   null, null,
   'Onde moram os campos "[a preencher]" da apresentação de crédito. Ausente (banco anterior à 0205), '
   'o portal não tem de onde ler e o deck sai com todas as lacunas, sem aviso de que havia valor a preencher.',
   'importante', 865)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0205', revisado_em = current_date,
       observacao = 'A 0205 cria caso_apresentacao_campo (tabela nova, vazia). Catalogada pela tabela (caso_apresentacao_campo_tabela_existe).'
 where id = true;
