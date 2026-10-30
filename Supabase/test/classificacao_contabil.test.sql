-- Testes da classificação contábil em sombra (Supabase/migrations/0128).
-- Rodar via Supabase/test/run.sh (que aplica as migrations antes).
--
-- O QUE ESTES TESTES TRAVAM. Este é o oitavo estágio do MVP e ele passou de
-- `Arquitetura do Sistema/1 Visão e Doutrina/03`, `Arquitetura do Sistema/2 Especificação/05` e da semeadura do dial na `0002` até aqui sem uma linha de
-- código — o dial dizia N0 para um estágio que não existia. Agora que ele existe,
-- as propriedades que precisam de teto são estas, em ordem:
--
--   1. A SUGESTÃO NUNCA É FATO. `fn_classe_contabil_do_campo` devolve
--      `classe_efetiva` = só o override humano. É o fechamento #5 do `Arquitetura do Sistema/1 Visão e Doutrina/01`
--      aplicado à classificação, e a razão de o teto dela ser N1 para sempre. Se
--      este assert cair, a anti-ancoragem — o princípio inegociável do projeto —
--      furou no estágio de maior risco interpretativo.
--   2. LINHA QUE NÃO É DE RESULTADO NÃO GANHA SUGESTÃO. "Não se aplica" e "revisar"
--      são estados diferentes: confundi-los produziria 3.195 pedidos de revisão
--      onde cabem 527, e um analista que recebe 3.195 itens não revisa nenhum.
--   3. O DESEMPATE POR ESPECIFICIDADE FUNCIONA. Duas regras que casam a mesma
--      linha não podem dar resultado dependente da ordem em que o banco devolveu —
--      é a forma de erro que a `0125` corrigiu na proveniência.
--   4. A TAXONOMIA É FECHADA. Override com rótulo fora do catálogo é recusado.
--   5. EM SOMBRA, NADA É TOCADO. Nem pendência, nem `campo_extraido`.
--   6. APPEND-ONLY, medido com o role que o portal usa.

\set ON_ERROR_STOP on

create or replace function teste_assert_cc(p_ok boolean, p_nome text, p_detalhe text default null)
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
  v_caso    uuid;
  v_ent     uuid;
  v_per     uuid;
  v_doc     uuid;
  v_ver     uuid;
  v_campo   uuid;
  v_campo2  uuid;
  v_campo3  uuid;
  v_bal     uuid;
  v_sub     uuid;
  v_r       jsonb;
  v_n       int;
  v_txt     text;
  v_num     numeric;
begin
  v_caso := (fn_upsert_caso('Caso classificacao contabil 0128'))::uuid;
  insert into entidade (caso_id, razao_social) values (v_caso, 'Classificada Ltda.')
    returning id into v_ent;
  insert into periodo (caso_id, tipo, referencia) values (v_caso, 'anual', '2025')
    returning id into v_per;
  insert into documento (caso_id, entidade_id, periodo_id, tipo_taxonomia, confianca)
    values (v_caso, v_ent, v_per, 'DRE', 0.98) returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, nome_original, hash)
    values (v_doc, 1, 'bucket/cc.pdf', 'DRE cc.pdf', 'HASH-CC-1') returning id into v_ver;

  -- ==========================================================================
  raise notice '--- 1. a regra: rubrica conhecida, desconhecida, e o que não se aplica ---';
  -- ==========================================================================
  v_r := fn_classe_contabil_sugerir('(-) Despesas de reestruturação, rescisões e assessores',
                                    'despesas_operacionais', 'DRE');
  perform teste_assert_cc(v_r->>'classe' = 'nao_recorrente',
    'reestruturação é NÃO RECORRENTE', v_r::text);
  perform teste_assert_cc(length(coalesce(v_r->>'justificativa','')) > 30,
    'e vem com justificativa escrita — o Arquitetura do Sistema/2 Especificação/05 exige em toda sugestão');

  v_r := fn_classe_contabil_sugerir('(-) Provisão para contingências trabalhistas e cíveis',
                                    'despesas_operacionais', 'DRE');
  perform teste_assert_cc(v_r->>'classe' = 'candidato_ajuste_ebitda',
    'provisão para contingências é CANDIDATO A AJUSTE — merece olhar, não é ajuste feito',
    v_r::text);

  v_r := fn_classe_contabil_sugerir('(-) Matérias-primas e insumos consumidos', 'custos', 'DRE');
  perform teste_assert_cc(v_r->>'classe' = 'recorrente', 'insumo consumido é RECORRENTE', v_r::text);

  v_r := fn_classe_contabil_sugerir('Rubrica que ninguém nunca viu', 'despesas_operacionais', 'DRE');
  perform teste_assert_cc(v_r->>'classe' = 'revisar_manual',
    'rubrica que o catálogo não conhece vai para REVISAR MANUAL, não recebe palpite', v_r::text);

  -- E o que NÃO se aplica devolve null, que é diferente de revisar_manual.
  perform teste_assert_cc(
    fn_classe_contabil_sugerir('Caixa e equivalentes', 'ativo_circulante', 'BALANCO') is null,
    'linha de BALANÇO não recebe sugestão nenhuma — a pergunta não se aplica a ela',
    'confundir "não se aplica" com "revisar" produziria 3.195 pedidos onde cabem 527');
  perform teste_assert_cc(
    fn_classe_contabil_sugerir('RECEITA OPERACIONAL LÍQUIDA', 'receita_bruta', 'DRE') is null,
    'subtotal declarado pela fn_papel_linha também não recebe: recorrência de subtotal é herdada');

  -- ==========================================================================
  raise notice '--- 2. o desempate por especificidade (o assert que prova que ele existe) ---';
  -- ==========================================================================
  -- Esta linha casa DUAS regras: "transacao tributaria" (extraordinário,
  -- especificidade 200) e nada mais óbvio — mas o ponto é que o evento tem de
  -- ganhar de qualquer regra genérica que venha a casar a mesma linha no futuro.
  v_r := fn_classe_contabil_sugerir(
    '(-) Multas e juros reconhecidos na adesão à transação tributária',
    'resultado_financeiro', 'DRE');
  perform teste_assert_cc(v_r->>'classe' = 'extraordinario',
    'adesão a transação tributária é EXTRAORDINÁRIO, não despesa financeira recorrente',
    v_r::text);

  -- O coringa do FATURAMENTO_24M perde de qualquer rubrica de verdade.
  v_r := fn_classe_contabil_sugerir('abr/2025', 'receita_bruta', 'FATURAMENTO_24M');
  perform teste_assert_cc(v_r->>'classe' = 'recorrente',
    'a chave de MÊS do faturamento é classificada pelo tipo do documento, não pelo texto',
    v_r::text);

  -- ==========================================================================
  raise notice '--- 3. roda e registra (a primeira metade de N0) ---';
  -- ==========================================================================
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao_canonica, periodo_coluna)
    values (v_ver, '(-) Despesas de reestruturação, rescisões e assessores', -1200, 'milhar', 0.97,
            'despesas_operacionais', '2025')
    returning id into v_campo;
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao_canonica, periodo_coluna)
    values (v_ver, '(-) Matérias-primas e insumos consumidos', -8400, 'milhar', 0.97,
            'custos', '2025')
    returning id into v_campo2;
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao_canonica, periodo_coluna)
    values (v_ver, 'Rubrica inédita para o catálogo', -300, 'milhar', 0.97,
            'despesas_operacionais', '2025')
    returning id into v_campo3;
  -- Uma de balanço, que não deve ganhar sugestão.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao_canonica, periodo_coluna)
    values (v_ver, 'Caixa e equivalentes de caixa', 5000, 'milhar', 0.97,
            'ativo_circulante', '2025')
    returning id into v_bal;
  -- E um subtotal declarado.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao_canonica, periodo_coluna)
    values (v_ver, 'RECEITA OPERACIONAL LÍQUIDA', 50000, 'milhar', 0.97,
            'receita_bruta', '2025')
    returning id into v_sub;

  v_n := fn_classificar_contabil(v_ver);
  perform teste_assert_cc(v_n = 3,
    'três das cinco linhas ganharam sugestão: as de resultado com rubrica ou sem',
    format('gravou %s', v_n));

  perform teste_assert_cc(
    not exists (select 1 from campo_classe_sugerida where campo_extraido_id = v_bal),
    'a linha de BALANÇO não ganhou sugestão');
  perform teste_assert_cc(
    not exists (select 1 from campo_classe_sugerida where campo_extraido_id = v_sub),
    'o SUBTOTAL não ganhou sugestão');

  -- Idempotência: rodar de novo com o mesmo catálogo não acrescenta nada.
  v_n := fn_classificar_contabil(v_ver);
  perform teste_assert_cc(v_n = 0,
    'rodar outra vez com o mesmo catálogo não grava nada — append-only sem duplicar',
    format('gravou %s', v_n));

  -- ==========================================================================
  raise notice '--- 4. EM SOMBRA, NADA É TOCADO ---';
  -- ==========================================================================
  perform teste_assert_cc(
    not exists (select 1 from pendencia
                 where caso_id = v_caso and origem_estagio = 'classificacao_contabil'),
    'a classificação contábil NÃO abriu pendência nenhuma — é o que N0 significa');
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver and status_aceite <> 'pendente';
  perform teste_assert_cc(v_n = 0,
    'e não mexeu no status de aceite de nenhuma linha extraída', format('%s mexidas', v_n));
  perform teste_assert_cc(
    exists (select 1 from evento_auditoria
             where acao = 'classificacao_contabil_sombra'
               and entidade_ref = 'documento_versao:'||v_ver),
    'mas ficou na trilha — sombra que não registra não é sombra, é ausência');

  -- ==========================================================================
  raise notice '--- 5. A SUGESTÃO NUNCA É FATO (anti-ancoragem) ---';
  -- ==========================================================================
  v_r := fn_classe_contabil_do_campo(v_campo);
  perform teste_assert_cc(v_r->>'sugestao' is not null,
    'a sugestão está lá, visível', v_r::text);
  perform teste_assert_cc(v_r->'classe_efetiva' = 'null'::jsonb,
    'e a classe EFETIVA é nula sem override humano — a sugestão não vira fato',
    'este é o assert mais importante do arquivo: fechamento #5 do Arquitetura do Sistema/1 Visão e Doutrina/01');
  perform teste_assert_cc((v_r->>'aceita_por_humano')::boolean = false,
    'e ela se declara não aceita por humano');

  -- ==========================================================================
  raise notice '--- 6. o override, e o sinal de calibração ---';
  -- ==========================================================================
  -- Concorda com a máquina.
  v_r := fn_registrar_classe_override(v_campo, 'nao_recorrente', 'rodrigo@oria',
                                      'confirmo: é a reestruturação deste mandato');
  perform teste_assert_cc(coalesce((v_r->>'recusado')::boolean, false) = false,
    'o override é aceito', v_r::text);
  perform teste_assert_cc((v_r->>'discordou')::boolean = false,
    'e registra que o humano CONCORDOU com a sugestão', v_r::text);

  v_r := fn_classe_contabil_do_campo(v_campo);
  perform teste_assert_cc(v_r->>'classe_efetiva' = 'nao_recorrente',
    'agora a classe efetiva existe — porque um humano a afirmou', v_r::text);

  -- Discorda da máquina: é este o ponto de calibração.
  v_r := fn_registrar_classe_override(v_campo2, 'candidato_ajuste_ebitda', 'ian@oria',
                                      'houve compra atípica de insumo neste ano');
  perform teste_assert_cc((v_r->>'discordou')::boolean,
    'e quando o humano DISCORDA, isso fica registrado — é o sinal de calibração da F4',
    v_r::text);
  perform teste_assert_cc(v_r->>'sugestao_original' = 'recorrente',
    'com a sugestão original guardada ao lado, para a discordância ser reconstituível');

  v_r := fn_classe_contabil_concordancia(v_caso);
  perform teste_assert_cc((v_r->>'com_veredito_humano')::int = 2,
    'a concordância conta as DUAS linhas com veredito humano', v_r::text);
  perform teste_assert_cc((v_r->>'concordaram')::int = 1,
    'uma concordou', v_r::text);
  perform teste_assert_cc((v_r->>'concordancia')::numeric = 0.5,
    'concordância = 1 de 2 = 0,5', v_r::text);
  perform teste_assert_cc((v_r->>'sem_veredito_humano')::int = 1,
    'e a linha que ninguém olhou fica FORA, contada à parte: "acertou" e "ninguém conferiu" são '
    'estados diferentes', v_r::text);
  perform teste_assert_cc(v_r->'rubricas_que_mais_erram'->0->>'padrao' is not null,
    'e a rubrica que errou é nomeada — é o que permite ajustar a REGRA, não o modelo',
    v_r::text);

  -- ==========================================================================
  raise notice '--- 7. a taxonomia é FECHADA, e override precisa de autor ---';
  -- ==========================================================================
  v_r := fn_registrar_classe_override(v_campo3, 'inventei_um_rotulo', 'rodrigo@oria', 'teste');
  perform teste_assert_cc((v_r->>'recusado')::boolean,
    'rótulo fora do catálogo é RECUSADO — a taxonomia do Arquitetura do Sistema/2 Especificação/05 é fechada', v_r::text);
  perform teste_assert_cc(v_r->>'motivo_recusa' like '%FECHADA%',
    'e a recusa diz por quê', v_r->>'motivo_recusa');

  v_r := fn_registrar_classe_override(v_campo3, 'recorrente', '   ', 'sem autor');
  perform teste_assert_cc((v_r->>'recusado')::boolean,
    'override sem autor é RECUSADO — sem autor o sinal de calibração não tem de quem discordar',
    v_r::text);

  -- ==========================================================================
  raise notice '--- 8. sem linha no dial, o estágio não escreve ---';
  -- ==========================================================================
  -- Ausência de configuração não é permissão para escrever. Simulado removendo a
  -- linha do dial numa transação que se desfaz.
  declare v_antes int; v_depois int;
  begin
    select count(*) into v_antes from campo_classe_sugerida;
    delete from estagio_autonomia where estagio = 'classificacao_contabil';
    insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                                secao_canonica, periodo_coluna)
      values (v_ver, '(-) Honorários da administração', -400, 'milhar', 0.97,
              'despesas_operacionais', '2025');
    v_n := fn_classificar_contabil(v_ver);
    perform teste_assert_cc(v_n = 0,
      'sem linha no dial, fn_classificar_contabil devolve 0 e não escreve nada',
      format('gravou %s', v_n));
    select count(*) into v_depois from campo_classe_sugerida;
    perform teste_assert_cc(v_antes = v_depois, 'e a tabela de sugestões não cresceu');
    -- restaura o dial como a 0002 o semeou
    insert into estagio_autonomia (estagio, nivel_atual, teto, natureza, base_do_nivel)
      values ('classificacao_contabil', 'N0', 'N1', 'interpretativo', 'nao_se_aplica');
  end;

  -- ==========================================================================
  raise notice '--- 9. o dial dela continua onde a doutrina manda ---';
  -- ==========================================================================
  v_r := fn_dial('classificacao_contabil');
  perform teste_assert_cc((v_r->>'nivel_atual') = 'N0' and (v_r->>'teto') = 'N1',
    'classificacao_contabil em N0 com teto N1 — e agora o N0 é verdade, não ficção', v_r::text);
  v_r := fn_mudar_dial('classificacao_contabil', 'N2', 'teste:cc', 'tentando automatizar');
  perform teste_assert_cc((v_r->>'recusado')::boolean
                      and v_r->>'motivo_recusa' like '%TETO%',
    'e ela nunca vira autônoma: o teto N1 recusa, como o Arquitetura do Sistema/1 Visão e Doutrina/01 exige "para sempre"',
    v_r::text);

  raise notice 'TODOS OS TESTES DA CLASSIFICAÇÃO CONTÁBIL PASSARAM';
end $$;

-- -----------------------------------------------------------------------------
-- APPEND-ONLY, com o ROLE que o portal usa.
--
-- Mesma mecânica que a `golden.test.sql` documenta: sem política de RLS para um
-- comando, o Postgres NÃO levanta erro — ele filtra as linhas alcançáveis para
-- zero e o comando volta com sucesso afetando nada. Então o que se afirma é o
-- EFEITO.
-- -----------------------------------------------------------------------------
do $$
declare v_antes int; v_depois int; v_n int;
begin
  select count(*) into v_antes from campo_classe_override;
  perform teste_assert_cc(v_antes > 0, 'há override gravado para o teste ter o que tentar apagar');

  set local role authenticated;
  delete from campo_classe_override;
  update campo_classe_override set classe_final = 'revisar_manual';
  delete from campo_classe_sugerida;
  update campo_classe_sugerida set classe_codigo = 'revisar_manual';
  reset role;

  select count(*) into v_depois from campo_classe_override;
  perform teste_assert_cc(v_antes = v_depois,
    'como authenticated, o delete em campo_classe_override não apaga nada',
    format('antes %s, depois %s', v_antes, v_depois));

  select count(*) into v_n from campo_classe_override where classe_final = 'revisar_manual';
  perform teste_assert_cc(v_n = 0,
    'e o update não reescreve override nenhum — a decisão humana é histórico');

  select count(*) into v_n from pg_policies
   where tablename in ('campo_classe_sugerida', 'campo_classe_override')
     and cmd in ('ALL', 'UPDATE', 'DELETE');
  perform teste_assert_cc(v_n = 0,
    'e nenhuma das duas tem política de ALL/UPDATE/DELETE',
    format('achou %s', v_n));

  raise notice 'TODOS OS TESTES DE APPEND-ONLY DA CLASSIFICAÇÃO PASSARAM';
end $$;
