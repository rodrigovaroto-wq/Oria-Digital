-- Testes da 0030 — entidade e período canônicos no caminho de ESCRITA.
--
-- Os três defeitos que isto cobre são silenciosos por natureza: nenhum deles gera
-- erro, todos geram uma linha a mais (ou um "não achei") que só aparece no export.
-- Sem estes asserts, a correção é indistinguível de nenhuma correção.
\set ON_ERROR_STOP on

-- Mesmo helper de reextracao.test.sql, redeclarado aqui para este arquivo poder
-- rodar sozinho (`psql -f Supabase/test/canonico.test.sql`) sem depender da ordem.
create or replace function teste_assert_rx(p_ok boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_ok then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

do $$
declare
  v_caso uuid; v_r jsonb; v_n int; v_ent uuid; v_col text; v_ver uuid;
begin
  insert into caso (nome) values ('canonico') returning id into v_caso;

  -- ---- 1. ENTIDADE: as duas grafias que o pipeline produz de verdade --------
  -- Depois do PR #65 a entidade vem de DUAS fontes que escrevem diferente:
  -- o nome do arquivo (sem acento, porque normalize.mjs remove diacríticos) e o
  -- diagnóstico da IA (com acento e sufixo societário). Antes da 0030,
  -- `lower(razao_social)` não aproximava as duas e nascia UMA EMPRESA A MAIS.
  v_r := fn_registrar_documento(v_caso, 'Vertentes Metalurgica', 'anual', '12M25', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/bp.pdf', 'BP.pdf', null, 'H-CANON-1', 'ok');
  v_r := fn_registrar_documento(v_caso, 'Vertentes Metalúrgica Ltda.', 'anual', '12M25', 'DRE', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/dre.pdf', 'DRE.pdf', null, 'H-CANON-2', 'ok');

  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_rx(v_n = 1,
    format('as duas grafias da mesma empresa viram UMA entidade (achei %s)', v_n),
    'entidade: sem acento + com acento e sufixo => 1 linha');

  -- E empresas DIFERENTES continuam diferentes — é o risco oposto, e fundir duas
  -- empresas é pior que duplicar uma (duplicar aparece no export; fundir mente).
  v_r := fn_registrar_documento(v_caso, 'Vertentes Componentes Ltda.', 'anual', '12M25', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/bp2.pdf', 'BP2.pdf', null, 'H-CANON-3', 'ok');
  v_r := fn_registrar_documento(v_caso, 'Vertentes Participações S.A.', 'anual', '12M25', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/bp3.pdf', 'BP3.pdf', null, 'H-CANON-4', 'ok');
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_rx(v_n = 3,
    format('Metalúrgica, Componentes e Participações seguem sendo 3 empresas (achei %s)', v_n),
    'entidade: prefixo comum "Vertentes" NAO funde empresas distintas');

  -- ---- 2. PERÍODO: '2025' e '12M25' são o MESMO exercício ------------------
  -- Antes da 0030 a referência era gravada CRUA, então as duas notações viravam
  -- duas linhas em `periodo`. A 0022 já as tratava como equivalentes na
  -- COMPARAÇÃO — o dashboard, o checklist e o export é que viam dois períodos.
  v_r := fn_registrar_documento(v_caso, 'Vertentes Metalurgica', 'anual', '2025', 'FLUXO_CAIXA', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/dfc.pdf', 'DFC.pdf', null, 'H-CANON-5', 'ok');
  select count(*) into v_n from periodo where caso_id = v_caso;
  perform teste_assert_rx(v_n = 1,
    format('"2025" e "12M25" viram UM período (achei %s)', v_n),
    'periodo: notacoes equivalentes nao fragmentam o exercicio');

  -- Exercício DIFERENTE continua diferente.
  v_r := fn_registrar_documento(v_caso, 'Vertentes Metalurgica', 'anual', '12M24', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/bp24.pdf', 'BP24.pdf', null, 'H-CANON-6', 'ok');
  select count(*) into v_n from periodo where caso_id = v_caso;
  perform teste_assert_rx(v_n = 2, format('2024 e 2025 seguem sendo dois períodos (achei %s)', v_n),
    'periodo: exercicios distintos continuam distintos');

  -- ---- 3. fn_coluna_entidade: apelido de coluna × razão social -------------
  -- A causa da pendência "não foi possível localizar Ativo Total / Passivo+PL"
  -- do teste v31. No combinado o cabeçalho é apelido curto e `razao_social` é a
  -- razão completa; a igualdade exata nunca casava e a função devolvia o
  -- sentinela E'\x01', que faz fn_valor_conceito_col e fn_soma_secao não
  -- retornarem NADA — daí v_n_anos = 0 e a pré-condição.
  select id into v_ent from entidade
    where caso_id = v_caso and razao_social = 'Vertentes Metalurgica' limit 1;
  v_r := fn_registrar_documento(v_caso, 'Grupo Vertentes', 'anual', '12M25', 'COMBINADO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/comb.pdf', 'COMBINADO.pdf', null, 'H-CANON-7', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave','TOTAL DO ATIVO','entidade_coluna','Metalúrgica','valor_num','56300','confianca','0.9'),
    jsonb_build_object('chave','TOTAL DO ATIVO','entidade_coluna','Componentes','valor_num','21400','confianca','0.9')
  ), 'N0', null);

  v_col := fn_coluna_entidade(v_ver, v_ent);
  perform teste_assert_rx(v_col = 'Metalúrgica',
    format('apelido de coluna casa a razão social (devolveu %s)', coalesce(v_col, 'null')),
    'fn_coluna_entidade: "Metalurgica" casa "Vertentes Metalurgica"');
  perform teste_assert_rx(v_col <> E'\x01',
    'a função não devolve o sentinela de "não achei"',
    'fn_coluna_entidade: sentinela era a causa da pre-condicao do v31');

  -- E o apelido de OUTRA empresa não casa esta entidade.
  select id into v_ent from entidade
    where caso_id = v_caso and razao_social like 'Vertentes Participa%' limit 1;
  v_col := fn_coluna_entidade(v_ver, v_ent);
  perform teste_assert_rx(v_col = E'\x01',
    format('empresa sem coluna no combinado devolve sentinela (devolveu %s)', coalesce(v_col, 'null')),
    'fn_coluna_entidade: nao inventa coluna para quem nao esta no documento');

  -- ---- 4. fn_mesma_entidade: os casos de borda que importam ----------------
  perform teste_assert_rx(fn_mesma_entidade('Metalúrgica', 'VERTENTES METALÚRGICA LTDA.'),
    'apelido curto casa razão social completa', 'fn_mesma_entidade');
  perform teste_assert_rx(fn_mesma_entidade('Vertentes Part.', 'Vertentes Participações S.A.'),
    'abreviação com ponto casa por prefixo', 'fn_mesma_entidade');
  perform teste_assert_rx(not fn_mesma_entidade('Vertentes Componentes', 'Vertentes Participações'),
    'empresas distintas do mesmo grupo NÃO casam', 'fn_mesma_entidade');
  perform teste_assert_rx(not fn_mesma_entidade('AB', 'Alfa Beta Ltda.'),
    'sigla de 2 letras não casa nada (fundir é pior que não achar)', 'fn_mesma_entidade');
  -- SPE NÃO é tratado como sufixo societário descartável: em "Vertentes Imóveis
  -- SPE" a sigla faz parte do nome da sociedade de propósito específico, e
  -- descartá-la fundiria SPEs do mesmo empreendimento.
  perform teste_assert_rx(fn_entidade_canonica('Vertentes Imóveis SPE') = 'vertentes imoveis spe',
    'SPE sobrevive à canonicalização (não é sufixo descartável como Ltda/S.A.)',
    format('canonica = %s', fn_entidade_canonica('Vertentes Imóveis SPE')));
  perform teste_assert_rx(fn_entidade_canonica('Vertentes Imóveis Ltda.') = 'vertentes imoveis',
    'Ltda É descartado (varia entre fontes e não identifica a empresa)',
    format('canonica = %s', fn_entidade_canonica('Vertentes Imóveis Ltda.')));

  -- LIMITAÇÃO CONHECIDA, fixada aqui de propósito para ficar VISÍVEL em vez de
  -- ser descoberta num book: um nome mais curto é absorvido por um mais longo que
  -- o contenha por prefixo. "Vertentes Imóveis" casa "Vertentes Imóveis SPE", e
  -- numerais romanos não desempatam ("SPE I" casa "SPE II", porque 'i' é prefixo
  -- de 'ii'). É o MESMO comportamento de `consolidarNomesDeEntidade` no portal —
  -- que está em produção — e é o preço de fazer "Metalúrgica" casar "VERTENTES
  -- METALÚRGICA LTDA.", que é o caso que a reconciliação do combinado precisa.
  -- O viés é para CONSOLIDAR. Se aparecer um caso real de duas empresas fundidas
  -- indevidamente, a saída é exigir CNPJ como desempate — a coluna já existe em
  -- `entidade` e hoje ninguém preenche.
  perform teste_assert_rx(fn_mesma_entidade('Vertentes Imóveis', 'Vertentes Imóveis SPE'),
    'nome curto é absorvido pelo longo (limitação conhecida e fixada por teste)',
    'fn_mesma_entidade: viés deliberado para consolidar');

  -- ---- 5. fn_valor_conceito_secao (0031): rótulo que não nomeia o conceito ----
  -- Os dois rótulos do book que NENHUMA das quatro tentativas por `chave` casava,
  -- e que produziram a pendência "não foi possível localizar o Caixa/Disponível"
  -- no teste v31. Para a VT Logística o dado estava na SEÇÃO todo esse tempo.
  v_r := fn_registrar_documento(v_caso, 'VT Logistica', 'anual', '12M25', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/vt.pdf', 'BP VT.pdf', null, 'H-CANON-8', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave','Bancos Conta Movimento','secao','Disponível','valor_num','320','confianca','0.9'),
    jsonb_build_object('chave','Duplicatas a receber','secao','Contas a Receber','valor_num','1180','confianca','0.9')
  ), 'N0', null);
  perform teste_assert_rx(
    (fn_valor_conceito_secao(v_ver, array['disponivel'], array['circulante'], null, null)).valor_num = 320,
    '"Bancos Conta Movimento" é achado pela SEÇÃO "Disponível"',
    'fn_valor_conceito_secao: era a causa da 2a pre-condicao do v31');
  -- E não confunde: a seção "Contas a Receber" não vira caixa.
  perform teste_assert_rx(
    (fn_valor_conceito_secao(v_ver, array['disponivel'], array['circulante'], null, null)).chave = 'Bancos Conta Movimento',
    'e escolhe a linha certa, não qualquer linha do documento', 'fn_valor_conceito_secao');
  -- "Caixa" puro (o caso da SPE): as tentativas antigas exigiam 'equivalentes' ou
  -- 'bancos' junto, então um rótulo de uma palavra não casava nenhuma.
  v_r := fn_registrar_documento(v_caso, 'Vertentes Imoveis SPE', 'anual', '12M25', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/spe.pdf', 'BP SPE.pdf', null, 'H-CANON-9', 'ok');
  v_ver := (v_r->>'documento_versao_id')::uuid;
  perform fn_registrar_campos_extraidos(v_ver, jsonb_build_array(
    jsonb_build_object('chave','Caixa','secao','Ativo Circulante','valor_num','90','confianca','0.9')
  ), 'N0', null);
  perform teste_assert_rx(
    (fn_valor_conceito_col(v_ver, array['caixa'], array['circulante','fluxo','inicio','inicial','equivalente'], null, null)).valor_num = 90,
    '"Caixa" puro é achado (as tentativas antigas exigiam equivalentes ou bancos)',
    'cascata do caixa: rotulo de uma palavra');

  -- ---- 4. A OUTRA FONTE DE NOME: o diagnóstico de conteúdo (0121) -----------
  -- O comentário do bloco 1 diz que a entidade vem de DUAS fontes que escrevem
  -- diferente — o nome do arquivo e o diagnóstico da IA. A 0030 canonizou a
  -- primeira (`fn_registrar_documento`) e deixou a SEGUNDA para trás: até a
  -- 0121, `fn_registrar_diagnostico` casava por `lower(razao_social) =
  -- lower(nome)`. Achado em dado real: quatro mandatos do dono com TRÊS linhas
  -- para a mesma empresa, uma delas criada por aqui — em mandato novo, com o
  -- workflow já reimportado. Depois da 0119 isso deixou de ser cosmético: a
  -- entidade virou o EIXO da cobrança de linha exigida, então a mesma empresa
  -- passa a ser cobrada duas vezes e a 0120 manda duas perguntas ao cliente.
  v_caso := (fn_upsert_caso('canonico diagnostico'))::uuid;
  insert into entidade (caso_id, razao_social) values (v_caso, 'Canastra Industria');

  -- (a) documento SEM entidade (o classificador se abstém quando o nome do
  --     arquivo não carrega empresa — 6 dos 38 do book) + diagnóstico com a
  --     razão social completa: reaproveita, não cria outra.
  v_r := fn_registrar_documento(v_caso, null, 'anual', '2025', 'BALANCO', 0.9, 'nome_arquivo',
           'supabase_storage', 'b/diag-a.pdf', 'BP.pdf', true, 'H-DIAG-A', 'ok');
  perform fn_registrar_diagnostico((v_r->>'documento_id')::uuid, (v_r->>'documento_versao_id')::uuid,
            'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', true, 'BALANCO', 'anual', '2025', 'ok', null, 'r', 'j');
  select count(*) into v_n from entidade where caso_id = v_caso;
  perform teste_assert_rx(v_n = 1,
    'o diagnóstico REAPROVEITA a empresa que já existe, com outra grafia (0121)',
    format('entidades no caso: %s', v_n));

  -- (b) documento COM entidade + diagnóstico com outra grafia da MESMA empresa:
  --     não é divergência, e não pode virar pendência.
  v_r := fn_registrar_documento(v_caso, 'Canastra Industria', 'anual', '2025', 'DRE', 0.9, 'nome_arquivo',
           'supabase_storage', 'b/diag-b.pdf', 'DRE.pdf', true, 'H-DIAG-B', 'ok');
  perform fn_registrar_diagnostico((v_r->>'documento_id')::uuid, (v_r->>'documento_versao_id')::uuid,
            'CANASTRA INDÚSTRIA DE EMBALAGENS LTDA.', true, 'DRE', 'anual', '2025', 'ok', null, 'r', 'j');
  select count(*) into v_n from pendencia
   where caso_id = v_caso and tipo = 'entidade_incorreta' and estado <> 'resolvida';
  perform teste_assert_rx(v_n = 0,
    'duas grafias da MESMA empresa não abrem pendência de divergência (0121)',
    format('pendências: %s', v_n));

  -- (c) e a divergência de VERDADE continua acusada — o conserto não pode ter
  --     transformado a guarda em peneira.
  v_r := fn_registrar_documento(v_caso, 'Canastra Industria', 'anual', '2025', 'FLUXO_CAIXA', 0.9, 'nome_arquivo',
           'supabase_storage', 'b/diag-c.pdf', 'DFC.pdf', true, 'H-DIAG-C', 'ok');
  perform fn_registrar_diagnostico((v_r->>'documento_id')::uuid, (v_r->>'documento_versao_id')::uuid,
            'Vertentes Metalurgica Ltda.', true, 'FLUXO_CAIXA', 'anual', '2025', 'ok', null, 'r', 'j');
  select count(*) into v_n from pendencia
   where caso_id = v_caso and tipo = 'entidade_incorreta' and estado <> 'resolvida';
  perform teste_assert_rx(v_n = 1,
    'empresa DIFERENTE continua abrindo pendência — o conserto não virou peneira',
    format('pendências: %s', v_n));

  -- ---- 5. A JUSTIFICATIVA QUE O PERÍODO PERDIA (0161) ------------------------
  -- `tipo_incorreto` já cita `p_justificativa` na própria mensagem desde antes
  -- desta migration. `periodo_incorreto` nunca citou — mesma função, mesma
  -- chamada, mesmo parâmetro pronto, só faltando no format(). Medido no lote
  -- 7377 (02/09): as duas pendências de período abertas naquela rodada não
  -- diziam POR QUE o diagnóstico propôs aquele período.
  v_r := fn_registrar_documento(v_caso, 'Vertentes Metalurgica Ltda.', 'anual', '2024', 'BALANCO', 0.9,
    'nome_arquivo', 'supabase_storage', 'b/diag-periodo.pdf', 'BP-periodo.pdf', true, 'H-DIAG-PERIODO', 'ok');
  perform fn_registrar_diagnostico((v_r->>'documento_id')::uuid, (v_r->>'documento_versao_id')::uuid,
            'Vertentes Metalurgica Ltda.', true, 'BALANCO', 'anual', '2025', 'ok', null, 'r',
            'MOTIVO-TESTE-0161: as colunas são de 2025, não de 2024.');
  -- 0234: o fixture era 'multi 22,23,24' contra 'anual 2024', par que a 0234 declara o MESMO exercício (mesmo ano mais recente, contido, contíguo) e que por isso
  -- já não abre pendência. O que este teste afirma é que a pendência CITA a justificativa quando abre; 2025 contra 2024 segue divergente (ano mais recente diferente).
  select descricao into v_col from pendencia
   where caso_id = v_caso and tipo = 'periodo_incorreto' and estado <> 'resolvida'
   order by criada_em desc limit 1;
  perform teste_assert_rx(v_col ilike '%MOTIVO-TESTE-0161%',
    'a pendência de PERÍODO agora cita a justificativa do diagnóstico, como o tipo já fazia (0161)',
    coalesce(v_col, '(nenhuma pendência periodo_incorreto aberta)'));

  delete from caso where id = v_caso;
  raise notice 'TODOS OS TESTES DE CANONICALIZAÇÃO PASSARAM';
end
$$;
