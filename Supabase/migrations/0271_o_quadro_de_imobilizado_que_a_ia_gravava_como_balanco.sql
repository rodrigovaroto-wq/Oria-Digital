-- 0271 — O QUADRO DE IMOBILIZADO QUE A IA GRAVAVA COMO BALANÇO: tipo novo COMPOSICAO_IMOBILIZADO na taxonomia, para o quadro de bens do ativo imobilizado deixar de cair em BALANCO e abrir pendência "sem período par"
-- (Seed de 1 tipo em taxonomia_tipo_documento e da declaração dele em taxonomia_tipo_cobertura; 1 view e 1 requisito novo na sonda. Sem função, sem gatilho, sem tabela. Idempotente: on conflict do nothing.)
--
-- O DEFEITO. O Canastra sintético tinha 2 pendências "sem período par" (`ativo_passivo_pl` e `caixa_bp_fluxo`, anual 2025) que a 0234 não alcançou. O documento é
-- `27_Composicao_do_Imobilizado_Canastra_Industria_2025.pdf`: a IA o gravou como BALANCO ("Embora não seja um balanço completo, é um demonstrativo patrimonial") e as únicas linhas "TOTAL" dele
-- estão nas colunas Custo, Depreciação acumulada e Valor líquido; as duas checagens tomam o quadro como balanço e não acham exercício nenhum. O balanço verdadeiro da mesma entidade
-- (`01_Balanco_Patrimonial_..._2025x2024x2023`, 307 linhas) dá `ativo_passivo_pl: ok`. Ficha: .claude/conhecimento/fichas/quadro-de-imobilizado-classificado-como-balanco.md (S127, 11/11/2026, leitura de produção).
--
-- A CAUSA. A taxonomia tem 36 tipos e nenhum é "composição do imobilizado": `tipo_sugerido` é um enum fechado com os códigos que EXISTEM (a mesma causa da 0024, que criou DMPL e DVA), e a IA escolheu o
-- mais próximo. Não é erro de período nem de classificação da IA: ela não tinha onde pôr o quadro. Conferido por grep em Supabase/ N8N/ portal/src/ que o código COMPOSICAO_IMOBILIZADO não existia no banco
-- (nem em seed, nem em teste, nem em função); N8N/lib/taxonomia.mjs ganha o apelido na mesma P11 (lado do n8n, outro agente), e o seed daqui TEM de ter o MESMO código.
--
-- A CORREÇÃO, E CADA COLUNA PELO QUE O TIPO É (quadro de bens do ativo imobilizado: custo, depreciação acumulada e valor líquido; é um anexo da demonstração, não uma demonstração):
--   * categoria `Contábil/Demonstrações`, a mesma de NOTAS_EXPL, DMPL, DVA e BALANCETE: é demonstrativo contábil. NÃO é `Societário/Legal`, então fn_tipo_sem_dado_por_natureza (0231) devolve false
--     e zero linha com tem_dado_financeiro = false abre extracao_falhou (o quadro sem número é falha, não normalidade).
--   * obrigatoriedade `complementar` (Nível 2): o Kit Básico é a lista de 8 obrigatórios e mexer nele muda a completude de todo caso aberto (0024) — decisão de produto do dono, não efeito de seed.
--   * granularidade `entidade_periodo`, vigência `acompanha DF`, sensibilidade `nenhuma`: o quadro é de uma empresa e de um exercício e acompanha a demonstração, como NOTAS_EXPL.
--   * `abertura_analitica = true` (0150): o quadro REAFIRMA, bem a bem, a conta Imobilizado que o balanço já declara — o critério da própria coluna ("este documento reafirma, aberta, uma conta que outro
--     documento do mesmo caso já declara?"). Com `false` (o padrão), as linhas dele entrariam na soma do realizado (fn_linhas_do_realizado) junto do balanço: a mesma conta contada duas vezes.
--     Efeito aceito, na própria doutrina da coluna: linha que só existe nesse documento não entra na soma do realizado.
--   * `autoridade = 0` e `nao_sobrepujavel = false` (os padrões): ele não decide conflito de número entre documentos (fn_conflitos_do_caso) — é anexo, o balanço manda.
--   * a DECLARAÇÃO de cobertura (0187, portão D6): `sem_consumidor`. Nenhuma função lê o tipo (procurado como literal 'COMPOSICAO_IMOBILIZADO' em todo corpo vigente: nenhuma); o motivo e o EFEITO ficam escritos.
--     Sem a declaração, fn_cobertura_de_tipos acusa SEM_COBERTURA e a sonda D6 (instalacao_sonda_cobertura_de_tipos) fica vermelha.
--
-- O QUE ESTA MIGRATION NÃO FAZ (nem pode, e é por isso que o número de produção não muda sozinho):
--   1. Só afeta classificações NOVAS (como a 0024). O quadro já gravado como BALANCO continua BALANCO até ser reextraído ou corrigido na fila de revisão (fn_revisar_documento); as 2 pendências do Canastra
--      continuam abertas até lá. Não há backfill: reclassificar documento é decisão humana (não se reabre nem se reescreve por migration, a lição da 0183).
--   2. O tipo só passa a ser OFERECIDO à IA quando o n8n é republicado: o enum do prompt de classificação e do extractionSchema muda, o FINGERPRINT_EXTRACAO muda junto, e o próximo envio de cada mandato
--      re-extrai e paga todos os documentos (ficha acima). Esse custo e a republicação são decisão do dono.
--
-- MEDIÇÃO NÃO-VAZIA (regra 2): Supabase/test/o_quadro_de_imobilizado_que_a_ia_gravava_como_balanco.test.sql — 23 asserts (contagem de execuções = chamadas: o arquivo não tem laço; run.sh inteiro, rc 0).
-- O arranjo reproduz o de produção: o MESMO quadro como BALANCO (CONTROLE) dá ativo_passivo_pl e caixa_bp_fluxo "sem_periodo_par" com as 2 pendências abertas (como no Canastra), e como COMPOSICAO_IMOBILIZADO não abre nenhuma.
-- Medido em 11/11/2026 com `raise exception` trocado por `raise warning` (p271.medindo = on), o log lido atrás de FALHOU:, cada cópia da migration aplicada de fato com a decisão DESLIGADA (o banco tinha a linha do tipo apagada antes):
--   `abertura_analitica` false: 3 dos 23 asserts reprovam (a flag, a linha do quadro entrando no realizado e a view da sonda).
--   categoria Societário/Legal: 3 dos 23 (a categoria, "sem dado por natureza" virando true e a view da sonda).
--   sem a declaração do D6: 4 dos 23 (veredito SEM_COBERTURA, o portão D6 estrito, a declaração em uma linha e a sonda).
--   obrigatório em vez de complementar: 2 dos 23 (complementar e o Kit Básico com 9 em vez de 8).
--   sem o tipo (nenhuma linha do seed): o teste reprova os asserts de (A) e MORRE ao registrar o documento (violação da chave estrangeira documento_tipo_taxonomia_fkey, rc 3) — é o defeito: a IA não tinha onde pôr o quadro.
--   Controle (migration intacta): 0 dos 23.
--   Conferido em cada rodada que a migration aplicou e que o teste aparece no log. Achado de arranjo da própria medição: a primeira versão do arranjo punha uma coluna "2025" no quadro e escondia o defeito (o BALANCO achava exercício);
--   a linha do realizado ficou num caso à parte.
-- =============================================================================

begin;

insert into taxonomia_tipo_documento
  (codigo, categoria, documento, obrigatoriedade, granularidade, vigencia, sensibilidade, versao, abertura_analitica)
values
  ('COMPOSICAO_IMOBILIZADO', 'Contábil/Demonstrações',
   'Composição do ativo imobilizado (quadro de bens: custo, depreciação acumulada e valor líquido)',
   'complementar', 'entidade_periodo', 'acompanha DF', 'nenhuma', 1, true)
on conflict (codigo) do nothing;

-- A DECLARAÇÃO do portão D6 (0187): ninguém confere o número deste tipo, e o que passa sem aviso fica escrito (regra 1). Idempotente.
insert into taxonomia_tipo_cobertura
  (tipo_taxonomia, estado, consumidor, motivo, efeito, declarado_em, marcador, marcador_em)
values
  ('COMPOSICAO_IMOBILIZADO', 'sem_consumidor', null,
   'Quadro auxiliar que abre, bem a bem, a conta Imobilizado do balanço (abertura_analitica = true, 0150/0271). Nenhuma função SQL lê COMPOSICAO_IMOBILIZADO: procurado como literal em todo corpo vigente na criação do tipo. '
   'Nenhuma checagem de balanço o toma de propósito (o tipo existe justamente para o quadro não ser lido como balanço).',
   'Imobilizado líquido do quadro que não bate com a conta Imobilizado do BP, e depreciação acumulada do quadro que não bate com a do BP, passam sem aviso. As linhas do quadro não entram na soma do realizado (abertura analítica).',
   '2026-11-11', null, null)
on conflict (tipo_taxonomia) do nothing;

-- A VIEW DA SONDA: o tipo `seed` só conta linhas na tabela, não prova ESTE código. Uma linha somente se o tipo existe, está ativo, é complementar e de categoria que não é Societário/Legal,
-- tem abertura analítica e tem a declaração de cobertura.
create or replace view instalacao_sonda_tipo_composicao_imobilizado as
  select t.codigo::text as codigo
    from taxonomia_tipo_documento t
    join taxonomia_tipo_cobertura c on c.tipo_taxonomia = t.codigo
   where t.codigo = 'COMPOSICAO_IMOBILIZADO'
     and t.ativo
     and t.abertura_analitica
     and t.categoria <> 'Societário/Legal';

comment on view instalacao_sonda_tipo_composicao_imobilizado is
  'Sonda da 0271: uma linha = o tipo COMPOSICAO_IMOBILIZADO existe na taxonomia, ativo, com abertura analítica e fora da categoria Societário/Legal, e declarado no portão D6. Zero linhas: a IA volta a gravar o quadro de imobilizado como BALANCO.';

grant select on instalacao_sonda_tipo_composicao_imobilizado to authenticated, service_role;  -- service_role: o requisito grant_views_service_role (0214) cobra toda view de public

-- ---------------------------------------------------------------------------
-- A SONDA.
-- ---------------------------------------------------------------------------
insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, criterio_seed, porque, severidade, ordem) values
  ('tipo_composicao_imobilizado', '0271', 'comportamento', 'instalacao_sonda_tipo_composicao_imobilizado', null, 1,
   'O tipo COMPOSICAO_IMOBILIZADO existe, com abertura analítica e declarado no D6. Zero linhas = a IA não tem onde pôr o quadro de bens e o grava como BALANCO (2 pendências "sem período par" no Canastra, 11/11/2026); e sem abertura analítica as linhas do quadro entrariam na soma do realizado junto do balanço.',
   'importante', 1280)
on conflict (chave) do update set
  migration = excluded.migration, tipo = excluded.tipo, objeto = excluded.objeto,
  marcador = excluded.marcador, criterio_seed = excluded.criterio_seed,
  porque = excluded.porque, severidade = excluded.severidade, ordem = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0271', revisado_em = current_date,
       observacao = 'A 0271 cadastra o tipo COMPOSICAO_IMOBILIZADO (quadro de bens do imobilizado; complementar, abertura analítica, declarado no D6 como sem_consumidor) para a IA não o gravar como BALANCO. 1 requisito novo (ordem 1280); o D6 já tinha o dele (0187).'
 where id = true;

commit;
