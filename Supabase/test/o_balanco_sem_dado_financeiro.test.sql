-- Testes da 0231: o BALANCO que a IA declarou sem dado financeiro e ninguém via.
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTE ARQUIVO PROVA (comportamento, não mecanismo): zero linha + `tem_dado_financeiro = false` só é "normal" para o documento que não tem número por natureza
-- (certidão, organograma, contrato social). Para qualquer outro tipo — e para tipo nulo, e para CONTINGENCIAS — abre `extracao_falhou`, com o motivo que começa por
-- "a leitura declarou que este documento não tem dado financeiro, mas ". Tudo o mais continua como era: linha gravada, `null`, `true`, falha explícita.
-- O BACKFILL é provado reaplicando a própria migration (ela é reaplicável) sobre documentos postos no estado que a produção tinha: sem pendência nenhuma.
--
-- Cada cenário roda no seu próprio DO (a sua transação): dois eventos da mesma versão na MESMA transação empatam em criado_em (ver 0230).
-- ARRANJO MONTADO À MÃO (e só ele): `delete from pendencia` para recolocar o documento no estado "sem pendência" que a produção tinha ANTES da 0231; os eventos vêm
-- de fn_registrar_campos_extraidos de verdade.

\set ON_ERROR_STOP on

create or replace function teste_assert_0231(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_doc_0231(p_caso uuid, p_tipo text, p_nome text, p_hash text) returns uuid language sql as $$
  select (fn_registrar_documento(p_caso, 'Beta Ltda.', 'anual', '2025', p_tipo, 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/' || p_nome, p_nome, true, p_hash, 'ok')->>'documento_versao_id')::uuid $$;

-- p_linha: grava uma linha. p_tem: null = chamador antigo (5º argumento no default).
create or replace function teste_extrai_0231(p_versao uuid, p_linha boolean, p_falha text, p_tem boolean) returns void language plpgsql as $$
begin
  perform fn_registrar_campos_extraidos(p_versao,
    case when p_linha then jsonb_build_array(jsonb_build_object('ordem', 0, 'chave', 'Caixa', 'valor_num', 100, 'unidade', 'unidade', 'confianca', 0.99))
         else '[]'::jsonb end,
    'N0', p_falha, p_tem);
end $$;

create or replace function teste_abertas_0231(p_versao uuid) returns int language sql as $$
  select count(*)::int from pendencia pe join documento_versao dv on dv.documento_id = pe.documento_id
   where dv.id = p_versao and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida' $$;

create or replace function teste_descricao_0231(p_versao uuid) returns text language sql as $$
  select pe.descricao from pendencia pe join documento_versao dv on dv.documento_id = pe.documento_id
   where dv.id = p_versao and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida' limit 1 $$;

-- ---------------------------------------------------------------------------
do $$
begin
  raise notice '--- 1. a função do tipo ---';
  perform teste_assert_0231(fn_tipo_sem_dado_por_natureza('CERTIDOES') and fn_tipo_sem_dado_por_natureza('CONTRATO_SOCIAL')
                            and fn_tipo_sem_dado_por_natureza('ORGANOGRAMA'),
    'certidão, contrato social e organograma não têm dado financeiro por natureza');
  perform teste_assert_0231(not fn_tipo_sem_dado_por_natureza('BALANCO') and not fn_tipo_sem_dado_por_natureza('DRE')
                            and not fn_tipo_sem_dado_por_natureza('DF_AUDITADA'),
    'balanço, DRE e DF auditada têm');
  perform teste_assert_0231(not fn_tipo_sem_dado_por_natureza('CONTINGENCIAS'),
    'CONTINGENCIAS (mesma categoria) traz valor de causa e provisão: tem');
  perform teste_assert_0231(fn_tipo_sem_dado_por_natureza(null) is not null and not fn_tipo_sem_dado_por_natureza(null),
    'tipo nulo = false, nunca nulo');
  perform teste_assert_0231(fn_tipo_sem_dado_por_natureza('TIPO_QUE_NAO_EXISTE') is not null and not fn_tipo_sem_dado_por_natureza('TIPO_QUE_NAO_EXISTE'),
    'tipo desconhecido = false, nunca nulo');
end $$;

do $$
declare
  v_caso uuid; v_ver uuid; v_t text; v_d text;
begin
  raise notice '--- 2. (a) BALANCO com zero linha e false abre extracao_falhou, com o prefixo ---';
  v_caso := (fn_upsert_caso('Caso 0231 balanco'))::uuid;
  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'BP Beta.pdf', 'H0231-BP');
  perform teste_extrai_0231(v_ver, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1, 'BALANCO zero linha + false abre UMA extracao_falhou', teste_abertas_0231(v_ver)::text);
  v_d := teste_descricao_0231(v_ver);
  perform teste_assert_0231(v_d like '%Motivo: a leitura declarou que este documento não tem dado financeiro, mas ele é do tipo BALANCO. %',
    'o motivo começa pelo prefixo combinado e diz o tipo', v_d);
  perform teste_assert_0231(v_d like '%reenvie%' and v_d like '%resolva%', 'o motivo diz o que fazer (resolver ou reenviar)', v_d);
  perform teste_extrai_0231(v_ver, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1, 'repetir a chamada não duplica a pendência');
  perform teste_assert_0231((select count(*) from pendencia where motivo = 'extracao:falhou:' ||
      (select documento_id from documento_versao where id = v_ver)) = 1, 'o motivo da pendência é extracao:falhou:<documento>');
end $$;

do $$
declare
  v_caso uuid; v_ver uuid; v_t text; v_i int := 0;
begin
  raise notice '--- 3. (b) certidão, contrato social e organograma continuam calados ---';
  v_caso := (fn_upsert_caso('Caso 0231 societario'))::uuid;
  foreach v_t in array array['CERTIDOES', 'CONTRATO_SOCIAL', 'ORGANOGRAMA'] loop
    v_i := v_i + 1;
    v_ver := teste_doc_0231(v_caso, v_t, v_t || '.pdf', 'H0231-S' || v_i);
    perform teste_extrai_0231(v_ver, false, null, false);
    perform teste_assert_0231(teste_abertas_0231(v_ver) = 0, v_t || ' com zero linha e false não abre extracao_falhou');
  end loop;
end $$;

do $$
declare
  v_caso uuid; v_ver uuid; v_d text;
begin
  raise notice '--- 4. (c) CONTINGENCIAS abre; (d) tipo nulo abre ---';
  v_caso := (fn_upsert_caso('Caso 0231 contingencias e nulo'))::uuid;
  v_ver := teste_doc_0231(v_caso, 'CONTINGENCIAS', 'Processos.pdf', 'H0231-CT');
  perform teste_extrai_0231(v_ver, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1, 'CONTINGENCIAS com zero linha e false abre extracao_falhou');
  perform teste_assert_0231(teste_descricao_0231(v_ver) like '%ele é do tipo CONTINGENCIAS. %', 'e diz o tipo');

  v_ver := teste_doc_0231(v_caso, null, 'Sem tipo.pdf', 'H0231-NULO');
  perform teste_extrai_0231(v_ver, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1, 'documento sem tipo, zero linha e false abre extracao_falhou');
  v_d := teste_descricao_0231(v_ver);
  perform teste_assert_0231(v_d like '%Motivo: a leitura declarou que este documento não tem dado financeiro, mas ele não tem tipo. %',
    'e diz "ele não tem tipo"', v_d);
end $$;

do $$
declare
  v_caso uuid; v_ver uuid; v_n int;
begin
  raise notice '--- 5. (e) com linha gravada e false nada muda; (h) null/true continuam como antes ---';
  v_caso := (fn_upsert_caso('Caso 0231 como antes'))::uuid;

  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'Com linha.pdf', 'H0231-LINHA');
  perform teste_extrai_0231(v_ver, true, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 0, 'BALANCO com linha gravada e false: nenhuma extracao_falhou');
  select count(*) into v_n from campo_extraido where documento_versao_id = v_ver;
  perform teste_assert_0231(v_n = 1, 'e a linha foi gravada', v_n::text);

  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'Nulo.pdf', 'H0231-TEMNULO');
  perform teste_extrai_0231(v_ver, false, null, null);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1 and teste_descricao_0231(v_ver) like '%a chamada respondeu sem erro, mas não trouxe NENHUMA linha%'
    and teste_descricao_0231(v_ver) not like '%a leitura declarou%', 'tem_dado_financeiro nulo (chamador antigo): abre com o motivo de sempre');

  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'Verdadeiro.pdf', 'H0231-TEMTRUE');
  perform teste_extrai_0231(v_ver, false, null, true);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1 and teste_descricao_0231(v_ver) like '%a chamada respondeu sem erro, mas não trouxe NENHUMA linha%'
    and teste_descricao_0231(v_ver) not like '%a leitura declarou%', 'tem_dado_financeiro true: abre com o motivo de sempre');

  v_ver := teste_doc_0231(v_caso, 'CERTIDOES', 'Certidao nula.pdf', 'H0231-CERTNULO');
  perform teste_extrai_0231(v_ver, false, null, null);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1, 'certidão com tem_dado_financeiro nulo: abre, como desde a 0111');

  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'Falha explicita.pdf', 'H0231-FALHA');
  perform teste_extrai_0231(v_ver, false, 'Resposta truncada', false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1 and teste_descricao_0231(v_ver) like '%Motivo: Resposta truncada'
    and teste_descricao_0231(v_ver) not like '%a leitura declarou%', 'p_falha_motivo explícito vence e mantém o texto dele');
end $$;

do $$
declare
  v_caso uuid; v_ver uuid; v_st text; v_por text;
begin
  raise notice '--- 6. (f) a reextração que traz linha resolve a pendência ---';
  v_caso := (fn_upsert_caso('Caso 0231 reextracao'))::uuid;
  v_ver := teste_doc_0231(v_caso, 'DRE', 'DRE Beta.pdf', 'H0231-DRE');
  perform teste_extrai_0231(v_ver, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 1, 'DRE zero linha + false abre');
end $$;
do $$
declare
  v_caso uuid; v_ver uuid; v_st text; v_por text;
begin
  v_caso := (fn_upsert_caso('Caso 0231 reextracao'))::uuid;
  select dv.id into v_ver from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_caso and dv.hash = 'H0231-DRE';
  perform teste_extrai_0231(v_ver, true, null, true);
  perform teste_assert_0231(teste_abertas_0231(v_ver) = 0, 'a reextração com linha fecha a pendência aberta');
  select pe.estado::text, pe.resolvida_por into v_st, v_por from pendencia pe join documento_versao dv on dv.documento_id = pe.documento_id
   where dv.id = v_ver and pe.tipo = 'extracao_falhou';
  perform teste_assert_0231(v_st = 'resolvida' and v_por = 'sistema:extracao', 'resolvida pelo sistema, com a trilha de sempre', v_st || '/' || coalesce(v_por, '?'));
end $$;

-- ---------------------------------------------------------------------------
-- 6b. DECISÃO DE PESSOA NÃO SE DESFAZ NO REENVIO (achado de revisão: DF_AUDITADA/NOTAS_EXPL de produção)
-- ---------------------------------------------------------------------------
create or replace function teste_reenvia_0231(p_caso uuid, p_hash text) returns jsonb language sql as $$
  select fn_registrar_documento(p_caso, 'Beta Ltda.', 'anual', '2025', 'DF_AUDITADA', 0.95, 'nome_arquivo',
    'supabase_storage', 'bucket/parecer.pdf', 'Parecer.pdf', true, p_hash, 'ok', p_fingerprint_extracao => 'FP-0231') $$;

do $$
declare
  v_caso uuid; v_r jsonb;
begin
  raise notice '--- 6b. a pessoa resolve a extracao_falhou do parecer sem número ---';
  v_caso := (fn_upsert_caso('Caso 0231 decisao humana'))::uuid;
  v_r := teste_reenvia_0231(v_caso, 'H0231-HUM');
  perform teste_extrai_0231((v_r->>'documento_versao_id')::uuid, false, null, false);
  perform teste_assert_0231(teste_abertas_0231((v_r->>'documento_versao_id')::uuid) = 1, 'DF_AUDITADA zero linha + false abre (parecer sem número)');
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'usuario:analista-teste'
   where caso_id = v_caso and tipo = 'extracao_falhou';
end $$;
do $$
declare
  v_caso uuid; v_r jsonb; v_v1 uuid; v_v2 uuid; v_n int;
begin
  v_caso := (fn_upsert_caso('Caso 0231 decisao humana'))::uuid;
  select dv.id into v_v1 from documento_versao dv join documento d on d.id = dv.documento_id where d.caso_id = v_caso and dv.hash = 'H0231-HUM';
  perform teste_assert_0231(fn_versao_extracao_concluida(v_v1), 'resolvida por PESSOA: a versão conta como concluída (não paga de novo)');
  v_r := teste_reenvia_0231(v_caso, 'H0231-HUM');
  perform teste_assert_0231((v_r->>'reaproveitou_extracao')::boolean, 'o reenvio do mesmo arquivo reaproveita a extração');
  -- se mesmo assim chegar uma versão nova (arquivo ou prompt mudou) e voltar sem número de novo
  v_v2 := (teste_doc_0231(v_caso, 'DF_AUDITADA', 'Parecer.pdf', 'H0231-HUM'));
  perform teste_extrai_0231(v_v2, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_v2) = 0, 'a nova leitura sem número NÃO reabre o que a pessoa resolveu');
  select count(*) into v_n from pendencia where caso_id = v_caso and tipo = 'extracao_falhou';
  perform teste_assert_0231(v_n = 1, 'e não cria outra pendência (continua a única, resolvida)', v_n::text);
end $$;
do $$
declare
  v_caso uuid; v_r jsonb; v_v1 uuid; v_v2 uuid; v_n int;
begin
  raise notice '--- 6c. resolvida pelo SISTEMA não é decisão humana ---';
  v_caso := (fn_upsert_caso('Caso 0231 decisao do sistema'))::uuid;
  v_r := teste_reenvia_0231(v_caso, 'H0231-SIS');
  v_v1 := (v_r->>'documento_versao_id')::uuid;
  perform teste_extrai_0231(v_v1, false, null, false);
  -- o MESMO registro, só trocando quem resolveu (arranjo à mão): contraste limpo entre sistema e pessoa
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'sistema:extracao'
   where caso_id = v_caso and tipo = 'extracao_falhou';
  perform teste_assert_0231(not fn_versao_extracao_concluida(v_v1), 'resolvida pelo sistema: a versão NÃO conta como concluída (paga de novo)');
  update pendencia set resolvida_por = 'usuario:analista-teste' where caso_id = v_caso and tipo = 'extracao_falhou';
  perform teste_assert_0231(fn_versao_extracao_concluida(v_v1), 'trocado só o autor para uma pessoa: conta como concluída');
  update pendencia set resolvida_por = 'sistema:extracao' where caso_id = v_caso and tipo = 'extracao_falhou';
  v_v2 := teste_doc_0231(v_caso, 'DF_AUDITADA', 'Parecer.pdf', 'H0231-SIS');
  perform teste_extrai_0231(v_v2, false, null, false);
  perform teste_assert_0231(teste_abertas_0231(v_v2) = 1, 'nova leitura sem número, com a anterior resolvida só pelo sistema: abre de novo');
end $$;
do $$
declare
  v_caso uuid; v_v1 uuid;
begin
  raise notice '--- 6d. a decisão de pessoa vale mesmo com a régua tendo contado conta ---';
  v_caso := (fn_upsert_caso('Caso 0231 decisao com conta'))::uuid;
  v_v1 := ((teste_reenvia_0231(v_caso, 'H0231-CNT'))->>'documento_versao_id')::uuid;
  -- a régua contou 9 (CPF/OAB da procuração do book-espelho, medido em 09/11): leitura zero + false
  perform fn_registrar_campos_extraidos(v_v1, '[]'::jsonb, 'N0', null, false, '{"contas_no_documento": 9, "linhas_devolvidas": 0}'::jsonb);
  perform teste_assert_0231(not fn_versao_extracao_concluida(v_v1), 'com 9 contas na régua e sem decisão de ninguém: NÃO concluída (paga de novo)');
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'usuario:analista-teste'
   where caso_id = v_caso and tipo = 'extracao_falhou';
  perform teste_assert_0231(fn_versao_extracao_concluida(v_v1), 'resolvida por pessoa: concluída mesmo com 9 contas na régua (não paga de novo)');
end $$;

-- ---------------------------------------------------------------------------
-- 7. (g) O BACKFILL. Estado de produção antes da 0231: documentos com extracao_sombra e SEM pendência.
-- ---------------------------------------------------------------------------
do $$
declare
  v_caso uuid; v_ver uuid; v_i int := 0; v_t text;
begin
  raise notice '--- 7. (g) backfill: monta o estado que a produção tinha ---';
  v_caso := (fn_upsert_caso('Caso 0231 backfill'))::uuid;
  -- financeiros calados pelo desenho antigo: o alvo
  foreach v_t in array array['DRE', 'MAPA_DIVIDA'] loop
    v_i := v_i + 1;
    v_ver := teste_doc_0231(v_caso, v_t, 'Alvo ' || v_t || '.pdf', 'H0231-BF-A' || v_i);
    perform teste_extrai_0231(v_ver, false, null, false);
  end loop;
  -- societário: não é alvo
  v_ver := teste_doc_0231(v_caso, 'CERTIDOES', 'Certidao BF.pdf', 'H0231-BF-S');
  perform teste_extrai_0231(v_ver, false, null, false);
  -- com linha: não é alvo
  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'Com linha BF.pdf', 'H0231-BF-L');
  perform teste_extrai_0231(v_ver, true, null, false);
  -- declarou true (não false): não é alvo
  v_ver := teste_doc_0231(v_caso, 'BALANCO', 'True BF.pdf', 'H0231-BF-T');
  perform teste_extrai_0231(v_ver, false, null, true);
  -- v1 zero + false, depois v2 com linha: a versão mais nova manda, não é alvo
  v_ver := teste_doc_0231(v_caso, 'DRE', 'Duas versoes BF.pdf', 'H0231-BF-V');
  perform teste_extrai_0231(v_ver, false, null, false);
end $$;
do $$
declare
  v_caso uuid; v_ver uuid;
begin
  v_caso := (fn_upsert_caso('Caso 0231 backfill'))::uuid;
  v_ver := teste_doc_0231(v_caso, 'DRE', 'Duas versoes BF.pdf', 'H0231-BF-V');  -- mesmo hash: versão 2
  perform teste_extrai_0231(v_ver, true, null, true);
  -- recolhe TODA pendência de extração do caso: o estado "sem pendência nenhuma" da produção antes da 0231 (arranjo à mão)
  delete from pendencia where caso_id = v_caso and tipo = 'extracao_falhou';
  perform teste_assert_0231((select count(*) from pendencia where caso_id = v_caso and tipo = 'extracao_falhou') = 0, 'antes do backfill: nenhuma extracao_falhou no caso');
  -- DECISÃO DE PESSOA: DRE zero + false cuja extracao_falhou um analista já resolveu. O backfill não pode reabri-la (0183).
  v_ver := teste_doc_0231(v_caso, 'DRE', 'Resolvida por pessoa BF.pdf', 'H0231-BF-P');
  perform teste_extrai_0231(v_ver, false, null, false);
  update pendencia set estado = 'resolvida', resolvida_em = now(), resolvida_por = 'usuario:analista-teste'
   where caso_id = v_caso and tipo = 'extracao_falhou';
end $$;

\i Supabase/migrations/0231_o_balanco_sem_dado_financeiro_que_ninguem_via.sql

do $$
declare
  v_caso uuid; v_n int; v_ev int; v_tipos text;
begin
  v_caso := (fn_upsert_caso('Caso 0231 backfill'))::uuid;
  select string_agg(d.tipo_taxonomia, ',' order by d.tipo_taxonomia) into v_tipos
    from pendencia pe join documento d on d.id = pe.documento_id
   where pe.caso_id = v_caso and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida';
  perform teste_assert_0231(v_tipos = 'DRE,MAPA_DIVIDA',
    'o backfill abre só para DRE e MAPA_DIVIDA (não toca societário, nem documento com linha, nem true, nem versão mais nova com linha)', coalesce(v_tipos, '(nenhuma)'));
  perform teste_assert_0231((select count(*) from pendencia pe where pe.caso_id = v_caso and pe.estado <> 'resolvida' and pe.descricao like '%Motivo: a leitura declarou que este documento não tem dado financeiro, mas ele é do tipo %') = 2,
    'e com a mesma descrição que o Sinal 3 daria');
  select (depois->>'pendencias_abertas')::int into v_n from evento_auditoria
   where acao = 'extracao_pendencia_backfill' order by criado_em desc limit 1;
  perform teste_assert_0231(v_n >= 2, 'o evento de auditoria leva a contagem (inclui as 2 deste cenário)', coalesce(v_n::text, '?'));
  perform teste_assert_0231((select count(*) from pendencia pe join documento_versao dv on dv.documento_id = pe.documento_id
      where pe.caso_id = v_caso and dv.nome_original = 'Resolvida por pessoa BF.pdf' and pe.tipo = 'extracao_falhou' and pe.estado <> 'resolvida') = 0,
    'a extracao_falhou que uma pessoa resolveu continua resolvida (o backfill não reabre decisão humana)');
  raise notice 'backfill no banco de teste: % pendencia(s) aberta(s) na reaplicação (2 do cenário, o resto de fixtures de outros testes)', v_n;
end $$;

\i Supabase/migrations/0231_o_balanco_sem_dado_financeiro_que_ninguem_via.sql

do $$
declare
  v_caso uuid; v_n int; v_total int;
begin
  raise notice '--- 8. o backfill é idempotente ---';
  v_caso := (fn_upsert_caso('Caso 0231 backfill'))::uuid;
  select count(*) into v_n from pendencia where caso_id = v_caso and tipo = 'extracao_falhou' and estado <> 'resolvida';
  perform teste_assert_0231(v_n = 2, 'reaplicar não duplica: continuam 2 pendências no caso', v_n::text);
  perform teste_assert_0231((select (depois->>'pendencias_abertas')::int from evento_auditoria
      where acao = 'extracao_pendencia_backfill' order by criado_em desc limit 1) = 0, 'a segunda aplicação abriu zero');
  select count(*) into v_total from (select documento_id from pendencia where motivo like 'extracao:falhou:%' and estado <> 'resolvida'
                                      group by documento_id having count(*) > 1) x;
  perform teste_assert_0231(v_total = 0, 'nenhum documento do banco tem duas extracao_falhou abertas', v_total::text);
end $$;

drop function teste_assert_0231(boolean, text, text);
drop function teste_doc_0231(uuid, text, text, text);
drop function teste_extrai_0231(uuid, boolean, text, boolean);
drop function teste_abertas_0231(uuid);
drop function teste_descricao_0231(uuid);
drop function teste_reenvia_0231(uuid, text);
