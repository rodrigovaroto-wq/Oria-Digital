-- =============================================================================
-- 0212 — O BLOCO FAMILIAR CONTA COMO CONTROLE COMUM, SÓ SE DECLARADO
--
-- MEDIÇÃO NÃO-VAZIA (regra 2 do CLAUDE.md) — Supabase/test/controlador_familia.test.sql: 38 asserts; o número
-- por guarda desligada está no cabeçalho de Supabase/migrations/0212_o_bloco_familiar_que_o_controle_comum_nao_via.sql.
--
-- O ARRANJO REPRODUZ O MEDIDO NO MANDATO REAL (memória grupo-por-controle-comum-sem-holding), só com dados SINTÉTICOS
-- (nomes inventados): dois grupos de dois, cada um ligado por um sócio pessoa física. O sócio do grupo 1 (Carla) e o
-- do grupo 2 (Ícaro) são irmãos NO MUNDO, e levam o mesmo sobrenome, mas isso só existe para o banco se alguém
-- DECLARAR. Regra 4: o arranjo real (4 de 8 contratos) não permite afirmar mais que isto.
--
-- O QUE ESTE ARQUIVO AFIRMA (comportamento):
--   1. sem vínculo: 2 grupos, e o MESMO sobrenome entre sócios não os junta (nunca inferir por sobrenome);
--   2. com o irmão declarado: 1 grupo, com motivo vinculo_familiar e o vínculo (com a fonte) no veredito;
--   3. o fecho: A-cônjuge-B, B controla X, A controla Y: X e Y no mesmo grupo;
--   4. o par é simétrico (a ordem dos argumentos não importa), idempotente, e outro parentesco para o mesmo par
--      vigente é recusado;
--   5. recusas: auto-vínculo, pessoa jurídica, outro caso, fonte vazia, edição do declarado, delete direto;
--   6. encerrar não apaga: o grupo volta a 2, o registro fica, o motivo é obrigatório, e se pode declarar de novo;
--   7. eventos de declaração e de encerramento; e tudo isso como authenticated.
-- =============================================================================

create or replace function teste_assert_0212(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

delete from caso where nome in ('0212 — bloco familiar', '0212 — outro caso');

do $$
declare
  v_caso uuid; v_outro uuid;
  e1 uuid; e2 uuid; e3 uuid; e4 uuid; ex uuid; ey uuid; ez uuid;
  carla uuid; renato uuid; icaro uuid; leandro uuid; ana uuid; bruno uuid; clara uuid; pj uuid; de_outro uuid;
  v_vinc uuid; v_vinc2 uuid; v_n int; v_g int; v_err text; v_v record; v_gr jsonb;
begin
  v_caso  := fn_upsert_caso('0212 — bloco familiar');
  v_outro := fn_upsert_caso('0212 — outro caso');
  e1 := fn_upsert_entidade(v_caso, 'ALFA COMERCIO SA (0212)');
  e2 := fn_upsert_entidade(v_caso, 'BETA INDUSTRIA SA (0212)');
  e3 := fn_upsert_entidade(v_caso, 'GAMA VAREJO SA (0212)');
  e4 := fn_upsert_entidade(v_caso, 'DELTA MARCAS SA (0212)');
  carla   := fn_controlador_registrar(v_caso, 'Carla Mendes Prado', null, 'fisica', 'setup@0212');
  renato  := fn_controlador_registrar(v_caso, 'Renato Alves', null, 'fisica', 'setup@0212');
  icaro   := fn_controlador_registrar(v_caso, 'Ícaro Mendes Prado', null, 'fisica', 'setup@0212');
  leandro := fn_controlador_registrar(v_caso, 'Leandro Moraes', null, 'fisica', 'setup@0212');
  -- grupo 1: ALFA (Carla 50 + Renato 50) e GAMA (Renato 100); grupo 2: BETA (Ícaro 100) e DELTA (Ícaro 60 + Leandro 40)
  perform fn_entidade_definir_controlador(e1, carla, 50, 'setup@0212');
  perform fn_entidade_definir_controlador(e1, renato, 50, 'setup@0212');
  perform fn_entidade_definir_controlador(e3, renato, 100, 'setup@0212');
  perform fn_entidade_definir_controlador(e2, icaro, 100, 'setup@0212');
  perform fn_entidade_definir_controlador(e4, icaro, 60, 'setup@0212');
  perform fn_entidade_definir_controlador(e4, leandro, 40, 'setup@0212');

  raise notice '--- 1. sem vínculo declarado: 2 grupos, e o sobrenome igual NÃO junta ---';
  select count(distinct grupo_id) into v_g from fn_grupo_por_controle_comum(v_caso);
  perform teste_assert_0212(v_g = 2, 'sem vínculo: DOIS grupos (o do Renato e o do Ícaro)', v_g::text);
  perform teste_assert_0212((select count(*) from fn_grupo_por_controle_comum(v_caso)) = 4, 'e as 4 entidades aparecem');
  perform teste_assert_0212(split_part('Carla Mendes Prado', ' ', 2) = split_part('Ícaro Mendes Prado', ' ', 2)
    and (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = e1)
        <> (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = e2),
    'Carla e Ícaro têm o MESMO sobrenome e as empresas deles continuam em grupos separados (nunca por sobrenome)');
  perform teste_assert_0212((select count(*) from fn_grupo_por_controle_comum_motivo(v_caso) where motivo = 'controlador_comum') = 2,
    'sem vínculo, os 2 grupos têm motivo controlador_comum');

  raise notice '--- 2. com o irmão declarado, COMO authenticated ---';
  perform teste_como_admin_0216();
  set local role authenticated;
  v_err := null;
  begin v_vinc := fn_controlador_vincular_familia(v_caso, icaro, carla, 'irmao', 'declaração do cliente (teste)', 'portal@0212');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_0212(v_err is null and v_vinc is not null, 'o authenticated declara o vínculo de irmão', v_err);
  select count(distinct grupo_id) into v_g from fn_grupo_por_controle_comum(v_caso);
  perform teste_assert_0212(v_g = 1, 'com Ícaro irmão de Carla declarado: UM grupo', v_g::text);
  perform teste_assert_0212((select count(*) from fn_grupo_por_controle_comum(v_caso, false)) = 4
    and (select count(distinct grupo_id) from fn_grupo_por_controle_comum(v_caso, false)) = 2,
    'p_com_familia = false ignora o vínculo e devolve os 2 grupos da 0182');
  select * into v_v from fn_grupo_por_controle_comum_motivo(v_caso);
  perform teste_assert_0212(v_v.motivo = 'vinculo_familiar' and v_v.entidades = 4,
    'o motivo do grupo único é vinculo_familiar (4 entidades)', format('%s/%s', v_v.motivo, v_v.entidades));
  perform teste_assert_0212(jsonb_array_length(v_v.vinculos) = 1
    and v_v.vinculos->0->>'parentesco' = 'irmao' and v_v.vinculos->0->>'fonte' like 'declaração do cliente%'
    and v_v.vinculos->0->>'declarado_por' = 'portal@0212',
    'e traz o vínculo com parentesco, fonte e quem declarou', v_v.vinculos::text);
  select grupos into v_gr from fn_perimetro_veredito(v_caso);
  perform teste_assert_0212(jsonb_array_length(v_gr) = 1 and v_gr->0->>'motivo' = 'vinculo_familiar'
    and (v_gr->0->>'quantas')::int = 4 and jsonb_array_length(v_gr->0->'entidades') = 4
    and jsonb_array_length(v_gr->0->'vinculos') = 1,
    'o veredito do perímetro expõe o motivo e os vínculos do grupo', v_gr::text);

  raise notice '--- 3. simetria, idempotência e parentesco diferente ---';
  v_vinc2 := fn_controlador_vincular_familia(v_caso, carla, icaro, 'irmao', 'outra fonte', 'portal@0212');
  select count(*) into v_n from controlador_vinculo where caso_id = v_caso;
  perform teste_assert_0212(v_vinc2 = v_vinc and v_n = 1,
    'declarar na ordem inversa devolve o MESMO vínculo e não cria um segundo', format('%s linhas', v_n));
  v_err := null;
  begin perform fn_controlador_vincular_familia(v_caso, carla, icaro, 'conjuge_companheiro', 'fonte', 'portal@0212');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%Encerre o vigente%', 'outro parentesco para o par vigente é recusado, dizendo o que fazer', v_err);
  select count(*) into v_n from evento_auditoria where acao = 'controlador_vinculo_declarado' and entidade_ref like 'controlador:%'
    and (depois->>'vinculo_id')::uuid = v_vinc;
  perform teste_assert_0212(v_n = 1, 'a declaração gravou UM evento (a repetição idempotente não grava outro)', v_n::text);

  raise notice '--- 4. o fecho transitivo: A-cônjuge-B, B controla X, A controla Y ---';
  ana := fn_controlador_registrar(v_caso, 'Ana Ribeiro', null, 'fisica', 'setup@0212');
  bruno := fn_controlador_registrar(v_caso, 'Bruno Cardoso', null, 'fisica', 'setup@0212');
  ex := fn_upsert_entidade(v_caso, 'XIS PARTICIPACOES SA (0212)');
  ey := fn_upsert_entidade(v_caso, 'YPSILON PARTICIPACOES SA (0212)');
  ez := fn_upsert_entidade(v_caso, 'ZETA PARTICIPACOES SA (0212)');
  perform fn_entidade_definir_controlador(ex, bruno, 100, 'setup@0212');
  perform fn_entidade_definir_controlador(ey, ana, 100, 'setup@0212');
  perform fn_entidade_definir_controlador(ez, fn_controlador_registrar(v_caso, 'Pessoa Sem Parente', null, 'fisica', 'setup@0212'), 100, 'setup@0212');
  perform teste_assert_0212((select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ex)
    <> (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ey),
    'controle: X (de Bruno) e Y (de Ana) estão em grupos separados enquanto não há vínculo');
  perform fn_controlador_vincular_familia(v_caso, ana, bruno, 'conjuge_companheiro', 'contrato social (teste)', 'portal@0212');
  perform teste_assert_0212((select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ex)
    = (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ey),
    'A-cônjuge-B: a empresa de B e a de A caem no MESMO grupo');
  perform teste_assert_0212((select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ez)
    not in (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id in (ex, ey, e1)),
    'e uma empresa de um sócio sem parente declarado fica de fora');
  perform teste_assert_0212((select motivo from fn_grupo_por_controle_comum_motivo(v_caso)
      where grupo_id = (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ex)) = 'vinculo_familiar',
    'o grupo de X e Y tem motivo vinculo_familiar');
  perform teste_assert_0212((select motivo from fn_grupo_por_controle_comum_motivo(v_caso)
      where grupo_id = (select grupo_id from fn_grupo_por_controle_comum(v_caso) where entidade_id = ez)) = 'controlador_comum',
    'o grupo de Z (um só sócio) tem motivo controlador_comum');

  raise notice '--- 5. recusas ---';
  pj := fn_controlador_registrar(v_caso, 'Empresa Sócia Externa Ltda', '12.345.678/0001-95', 'juridica', 'setup@0212');
  de_outro := fn_controlador_registrar(v_outro, 'Pessoa de Outro Caso', null, 'fisica', 'setup@0212');
  clara := fn_controlador_registrar(v_caso, 'Clara Souza', null, 'fisica', 'setup@0212');
  v_err := null; begin perform fn_controlador_vincular_familia(v_caso, clara, clara, 'irmao', 'f', 'a');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%com ele mesmo%', 'auto-vínculo é recusado', v_err);
  v_err := null; begin perform fn_controlador_vincular_familia(v_caso, clara, pj, 'irmao', 'f', 'a');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%pessoas físicas%', 'pessoa jurídica é recusada', v_err);
  v_err := null; begin perform fn_controlador_vincular_familia(v_caso, clara, de_outro, 'irmao', 'f', 'a');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%não cruza casos%', 'controlador de outro caso é recusado', v_err);
  v_err := null; begin perform fn_controlador_vincular_familia(v_caso, clara, ana, 'irmao', '   ', 'a');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%p_fonte não pode ser vazia%', 'fonte vazia é recusada: o parentesco só vale declarado', v_err);
  v_err := null; begin perform fn_controlador_vincular_familia(v_caso, clara, ana, 'irmao', 'f', '');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%p_autor não pode ser vazio%', 'autor vazio é recusado', v_err);
  v_err := null; begin insert into controlador_vinculo (caso_id, controlador_a, controlador_b, parentesco, fonte, declarado_por)
    values (v_caso, greatest(clara, ana), least(clara, ana), 'irmao', 'f', 'a');
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0212(v_err = '23514', 'escrita direta com o par fora de ordem (a > b) é recusada pelo check', v_err);
  v_err := null; begin insert into controlador_vinculo (caso_id, controlador_a, controlador_b, parentesco, fonte, declarado_por)
    values (v_caso, least(clara, pj), greatest(clara, pj), 'irmao', 'f', 'a');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%pessoas físicas%', 'escrita direta com pessoa jurídica é recusada pelo gatilho', v_err);
  v_err := null; begin update controlador_vinculo set fonte = 'reescrita' where id = v_vinc;
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%não se edita%', 'o que foi declarado não se edita (fonte)', v_err);
  perform teste_assert_0212((select count(*) from fn_grupo_por_controle_comum_motivo(v_caso)) = 3
    and (select count(*) from controlador_vinculo where caso_id = v_caso) = 2,
    'controle: nenhuma recusa mudou nada (3 grupos: o do bloco dos irmãos, o de X e Y, o de Z; 2 vínculos)');

  raise notice '--- 6. encerrar não apaga ---';
  perform teste_como_admin_0216();
  set local role authenticated;
  v_err := null; begin delete from controlador_vinculo where id = v_vinc;
  exception when others then v_err := sqlstate; end;
  perform teste_assert_0212(v_err = '42501', 'delete direto é negado ao authenticated (permission denied)', v_err);
  v_err := null; begin perform fn_controlador_desvincular_familia(v_vinc, '   ', 'portal@0212');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%p_motivo não pode ser vazio%', 'encerrar sem motivo é recusado', v_err);
  v_err := null;
  begin perform fn_controlador_desvincular_familia(v_vinc, 'declaração do cliente retificada', 'portal@0212');
  exception when others then v_err := sqlstate || ' ' || sqlerrm; end;
  reset role;
  perform teste_fim_admin_0216();
  perform teste_assert_0212(v_err is null, 'o authenticated encerra o vínculo', v_err);
  select count(distinct grupo_id) into v_g from fn_grupo_por_controle_comum(v_caso) where entidade_id in (e1, e2, e3, e4);
  perform teste_assert_0212(v_g = 2, 'encerrado o vínculo de irmão, as 4 voltam a 2 grupos', v_g::text);
  perform teste_assert_0212(exists (select 1 from controlador_vinculo where id = v_vinc and encerrado_em is not null
        and encerrado_por = 'portal@0212' and motivo_encerramento = 'declaração do cliente retificada'),
    'e o registro continua, com quem encerrou e o motivo');
  perform teste_assert_0212(exists (select 1 from evento_auditoria where acao = 'controlador_vinculo_encerrado'
        and (depois->>'vinculo_id')::uuid = v_vinc and ator = 'portal@0212' and depois->>'motivo' like 'declaração%'),
    'e há o evento controlador_vinculo_encerrado');
  v_err := null; begin perform fn_controlador_desvincular_familia(v_vinc, 'de novo', 'portal@0212');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%não se encerra de novo%', 'encerrar duas vezes é recusado pela função', v_err);
  v_err := null; begin update controlador_vinculo set motivo_encerramento = 'outro' where id = v_vinc;
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%já foi encerrado%', 'vínculo encerrado não se edita', v_err);
  v_vinc2 := fn_controlador_vincular_familia(v_caso, icaro, carla, 'irmao', 'nova declaração', 'portal@0212');
  perform teste_assert_0212(v_vinc2 <> v_vinc and (select count(*) from controlador_vinculo where caso_id = v_caso
        and controlador_a = least(icaro, carla) and controlador_b = greatest(icaro, carla)) = 2
    and (select count(distinct grupo_id) from fn_grupo_por_controle_comum(v_caso) where entidade_id in (e1, e2, e3, e4)) = 1,
    'depois de encerrado se pode declarar de novo (novo registro, histórico de 2) e o grupo volta a ser um');
  v_err := null; begin perform fn_controlador_desvincular_familia(gen_random_uuid(), 'x', 'a');
  exception when others then v_err := sqlerrm; end;
  perform teste_assert_0212(v_err like '%não encontrado%', 'vínculo inexistente é recusado', v_err);

  raise notice '--- 7. a sonda enxerga o que a 0212 instalou ---';
  select count(*) into v_n from fn_instalacao_conferir() where migration = '0212' and not presente;
  perform teste_assert_0212(v_n = 0, 'nenhum requisito da 0212 está ausente na sonda', v_n::text);

  raise notice 'BLOCO FAMILIAR OK — só vale declarado, com fonte; o sobrenome nunca une; o grupo diz por quê; encerrar não apaga';
end $$;
