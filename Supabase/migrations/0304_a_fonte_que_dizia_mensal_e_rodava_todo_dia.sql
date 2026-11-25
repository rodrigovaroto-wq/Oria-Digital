-- =============================================================================
-- 0304 — A FONTE QUE DIZIA "MENSAL" E RODAVA TODO DIA: o catálogo `fonte_externa` acompanha o macro da A3 (Fase A, fatia A3)
-- (Só UPDATE de 3 linhas do catálogo semeado pela 0303 + 1 view de sonda + 1 requisito. Nenhum objeto existente muda de corpo; nenhum backfill além dessas 3 linhas.)
--
-- O DEFEITO. A 0303 semeou o catálogo com `on conflict do nothing` e descreveu o macro como ele era no dia 24/11: mensal, dia 12. Em 25/11/2026 o workflow do
-- macro mudou (commits b87dd18 e f102a92): roda TODO DIA às 06h e registra cada chamada em `consulta_externa` (bcb_sgs: uma por série; bcb_focus: uma por
-- indicador; ibge_sidra). O catálogo ficou contando o passado: `observacao` de bcb_sgs e bcb_focus ainda diz "busca mensal (dia 12)" (falso, e é o texto que o
-- dono lê ao abrir o catálogo), e `bcb_juros_modalidade` continua com url nula, cadência nula e o prazo mínimo de 1 dia, embora o macro já a leia.
--
-- A CAUSA É DE PROCESSO, NÃO DE UM ERRO: o seed é `on conflict do nothing` (de propósito, para a reaplicação da 0303 não pisar numa linha ajustada à mão), então
-- mudar o catálogo exige migration nova; editar a 0303 não chegaria ao banco, que já a tem. Aqui está ela.
--
-- O QUE MUDA (medido contra o seed da 0303, 22 linhas; o WHERE alcança exatamente 3 chaves, 1 cada):
--   bcb_juros_modalidade — url = a base do SGS (a mesma de bcb_sgs), cadência 'mensal', validade 30 dias, origem 'cadencia', nome e observação novos.
--   bcb_sgs, bcb_focus   — SÓ a observação. A cadência delas continua nula e o prazo, o mínimo de 1 dia: a de BUSCA virou diária, mas a de PUBLICAÇÃO (a que
--                          manda no prazo, decisão 8 do dono, 24/11/2026) segue variando por série (SGS) ou desconhecida (Focus). Buscar todo dia não vira prazo.
--
-- A DECISÃO: JUROS POR MODALIDADE É MENSAL, 30 DIAS (não o mínimo de 1 dia). Decisão do dono em 25/11/2026: a média ponderada do MERCADO por modalidade PJ vem do
-- SGS (19 séries mensais, % a.a.; a lista mora em JUROS_PJ_SGS, N8N/lib/macro.mjs), não da Olinda (taxa banco a banco: fatia futura, outra fonte). Todas as 19
-- séries são mensais, então a cadência de PUBLICAÇÃO é conhecida: o prazo é "até a próxima publicação" (decisão 8) = 30 dias, origem 'cadencia', e o CHECK
-- `fonte_externa_validade_coerente` (0303) confere o número. Efeito de errar para menos (manter 1 dia): a taxa de maio "vence" no dia seguinte e o painel pinta de
-- velho um dado que ainda é o mais novo que o BCB publicou. Efeito de errar para mais: não há 30 dias que o SGS passe sem publicar sem que isso já seja uma falha da
-- fonte — e essa vem como consulta `falhou` (mais nova que a boa), nunca como prazo esticado. O desfecho de cada chamada continua sendo classificado por
-- fn_registrar_consulta_externa; esta migration não toca nele.
--
-- A SÉRIE NOVA DO SGS (índices de preço e de atividade, crédito, inadimplência, câmbio) entra na fonte `bcb_sgs`, e a observação diz ONDE a lista mora
-- (N8N/lib/macro.mjs), não QUAIS são: uma lista de códigos aqui envelheceria a cada série acrescentada (a mesma doença que esta migration cura).
--
-- A SONDA (a catalogação mora no banco, e é o que impede o catálogo de envelhecer calado). Um UPDATE de dado de catálogo merece requisito porque, sem ele, a
-- 0304 não aplicada é indistinguível da aplicada: `fn_instalacao_conferir()` ficaria verde com o catálogo ainda dizendo "dia 12" e juros sem url. A view
-- `instalacao_sonda_fontes_do_macro_conectadas` devolve 1 linha quando bcb_sgs, bcb_focus e bcb_juros_modalidade têm url E a de juros tem cadência mensal com prazo
-- de 30 dias de origem 'cadencia'. Ela afirma o ESTADO, não o texto (a observação pode ser reescrita; url nula numa fonte que o macro lê, não). Quando a A3
-- ligar outra fonte, o requisito cresce por migration, não por edição desta.
--
--   select chave, presente, detalhe from fn_instalacao_conferir() where migration = '0304' and not presente;   -- ZERO linhas (1 requisito)
-- Reaplicável: UPDATE por chave é idempotente; a view é `create or replace`; o requisito, `on conflict do update`.
-- =============================================================================
begin;

update fonte_externa
   set url = 'https://api.bcb.gov.br/dados/serie/bcdata.sgs',
       nome = 'BCB — Taxas de juros por modalidade (SGS, média de mercado PJ)',
       cadencia = 'mensal', validade_dias = 30, validade_origem = 'cadencia',
       observacao = 'Conectada na A3 (macro, N8N/lib/macro.mjs). Decisão do dono, 25/11/2026: a média ponderada do MERCADO por modalidade PJ vem do SGS (19 séries mensais, % a.a.; lista em JUROS_PJ_SGS), não da Olinda: a taxa banco a banco é outra fonte, fatia futura. O BCB publica estas séries todo mês, então a cadência de publicação é mensal e o prazo, 30 dias (decisão 8). O macro busca todo dia às 06h, mas a busca não é o prazo.'
 where chave = 'bcb_juros_modalidade';

update fonte_externa
   set observacao = 'Conectada no macro (0025, N8N/lib/macro.mjs). O workflow BUSCA todo dia às 06h (até 25/11/2026 era mensal, dia 12) e grava uma consulta_externa por série chamada; a lista de séries mora em N8N/lib/macro.mjs e cresce com a A3, por isso não é repetida aqui. O SGS tem série diária e mensal: a cadência de PUBLICAÇÃO varia por série, então fica nula e o prazo é o mínimo de 1 dia (a busca diária não vira prazo).'
 where chave = 'bcb_sgs';

update fonte_externa
   set observacao = 'Conectada no macro (N8N/lib/macro.mjs). O workflow BUSCA todo dia às 06h (até 25/11/2026 era mensal, dia 12, junto com o SGS) e grava uma consulta_externa por indicador. A cadência de PUBLICAÇÃO do Focus o repositório não diz: nula e prazo mínimo de 1 dia.'
 where chave = 'bcb_focus';

-- A sonda: o estado do catálogo para as fontes que o macro lê. Uma linha = as três têm url e a de juros tem prazo mensal de 30 dias por cadência.
create or replace view instalacao_sonda_fontes_do_macro_conectadas as
  select 1 as ok
   where (select count(*) from fonte_externa
           where chave in ('bcb_sgs', 'bcb_focus', 'bcb_juros_modalidade') and url is not null) = 3
     and exists (select 1 from fonte_externa
                  where chave = 'bcb_juros_modalidade' and cadencia = 'mensal' and validade_dias = 30 and validade_origem = 'cadencia');
comment on view instalacao_sonda_fontes_do_macro_conectadas is
  'Sonda da 0304: uma linha = bcb_sgs, bcb_focus e bcb_juros_modalidade têm url e a de juros é mensal, 30 dias, origem cadencia. Zero linhas = a 0304 não foi aplicada (o catálogo ainda descreve o macro mensal e os juros sem url e com prazo de 1 dia) ou uma fonte que o macro lê ficou sem endereço.';
grant select on instalacao_sonda_fontes_do_macro_conectadas to authenticated, service_role;

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('fontes_do_macro_conectadas', '0304', 'comportamento', 'instalacao_sonda_fontes_do_macro_conectadas', null, 1,
   'As três fontes que o macro lê (bcb_sgs, bcb_focus, bcb_juros_modalidade) têm url, e os juros por modalidade são mensais com prazo de 30 dias. Zero linhas = 0304 não aplicada: o catálogo ainda diz "busca mensal, dia 12" e os juros vencem em 1 dia sem url.', 'importante', 1456)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = greatest(ate_migration, '0304'), revisado_em = current_date,
       observacao = 'A 0304 atualiza 3 linhas do catálogo fonte_externa (o macro virou diário às 06h; juros por modalidade conectada via SGS, mensal, 30 dias) e acrescenta 1 view de sonda e 1 requisito (ordem 1456). Não toca nenhuma função, tabela ou constraint.'
 where id = true;

commit;
