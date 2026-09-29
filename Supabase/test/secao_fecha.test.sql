-- =============================================================================
-- A ÁRVORE DA SEÇÃO (0133) — e o teste que importa aqui é o RELIGAMENTO.
--
-- Uma checagem verde sobre extração fiel não prova NADA sobre poder de detecção:
-- `select 'ok'` passaria em todos os asserts positivos deste arquivo. O que
-- prova é apagar uma linha e exigir que ela seja pega — e, no caso desta
-- migration, exigir ao mesmo tempo que a checagem ANTIGA continue verde, porque
-- é a cegueira dela que justifica a nova existir.
--
-- O bloco 2 é o coração do arquivo: ele mede a cegueira em vez de afirmá-la.
-- =============================================================================

create or replace function teste_assert(p_cond boolean, p_nome text, p_detalhe text default null)
returns void language plpgsql as $$
begin
  if p_cond then
    raise notice 'ok    %', p_nome;
  else
    raise exception 'FALHOU: % %', p_nome, coalesce(' — ' || p_detalhe, '');
  end if;
end $$;

create or replace function teste_reconciliar_tudo(p_caso uuid)
returns void language plpgsql as $$
declare r record;
begin
  for r in select id from documento where caso_id = p_caso order by id loop
    perform fn_reconciliar_por_documento(r.id);
  end loop;
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000001';
  v_n    int;
  v_txt  text;
begin
  raise notice '--- 1. POSITIVO: o book fiel fecha, e fecha com NÚMERO ---';

  -- PRÉ-CONDIÇÃO DE ORDEM, e ela falha ALTO de propósito. O bloco 6 do
  -- reconciliacao.test.sql renomeia toda chave desta versão para "XPTO <uuid>"
  -- e toda seção para "BLOCO SEM NOME", e não desfaz. Este arquivo tem de rodar
  -- ANTES dele; sem este assert, uma reordenação faria os asserts abaixo
  -- falharem com "0 seções ok", que não diz a ninguém o que aconteceu.
  select count(*) into v_n from campo_extraido
   where documento_versao_id = v_ver and chave = 'ATIVO';
  perform teste_assert(v_n > 0,
    'PRÉ-CONDIÇÃO: o fixture está intacto (este arquivo roda ANTES do reconciliacao.test.sql, '
    || 'cujo bloco 6 renomeia toda chave desta versão para XPTO e não desfaz)',
    format('%s linha(s) "ATIVO" — zero significa que a ordem do run.sh mudou', v_n));

  select count(*) into v_n from fn_conferir_arvore(v_ver) where resultado = 'ok';
  perform teste_assert(v_n >= 10,
    'o balanço do book tem dezenas de seções conferidas, não duas',
    format('%s seções ok', v_n));

  select count(*) into v_n from fn_conferir_arvore(v_ver) where resultado = 'divergente';
  perform teste_assert(v_n = 0,
    'extração FIEL não produz divergência nenhuma na árvore',
    format('%s divergente(s)', v_n));

  -- A REAFIRMAÇÃO É RECONHECIDA, e este assert é o que impede a regressão que
  -- a primeira versão desta migration teve: "TOTAL DO ATIVO" contado como
  -- parcela fazia a soma dar EXATAMENTE 2x o pai, em 31 seções do book.
  select count(*) into v_n from fn_conferir_arvore(v_ver)
   where resultado = 'ok' and n_reafirmacoes > 0;
  perform teste_assert(v_n > 0,
    'o total reafirmado pelo documento ("TOTAL DO ATIVO") é reconhecido, não somado como parcela',
    format('%s seção(ões) com reafirmação conferida', v_n));

  select soma_filhos into v_txt from fn_conferir_arvore(v_ver)
   where fn_normalizar_texto(pai) = 'ativo' and periodo_coluna = '2025';
  perform teste_assert(v_txt::numeric = 95780,
    'e a soma das parcelas do ATIVO dá o próprio ATIVO (não o dobro dele)',
    format('soma = %s', v_txt));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0,
    'e nenhuma pendência de seção abre sobre o book fiel', format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_caso   uuid := '11111111-1111-1111-1111-111111111111';
  v_ver    uuid := '55555555-0000-0000-0000-000000000001';
  v_id     uuid;
  v_valor  numeric;
  v_n_arv  int;
  v_n_apl  int;
  v_desc   text;
begin
  raise notice '--- 2. LINHA PERDIDA: o defeito que a checagem antiga NÃO vê ---';

  -- "Produtos acabados" (6.400) é parcela de "Estoques" (17.130). Apagá-la é
  -- exatamente o que uma extração que pula uma linha produz.
  select id, valor_num into v_id, v_valor from campo_extraido
   where documento_versao_id = v_ver and chave = 'Produtos acabados'
     and periodo_coluna = '2025' limit 1;
  perform teste_assert(v_id is not null, 'a linha alvo do religamento existe no fixture');
  delete from campo_extraido where id = v_id;

  perform teste_reconciliar_tudo(v_caso);

  -- A PROVA DE CEGUEIRA — e é medida, não afirmada. Ativo = Passivo + PL
  -- continua VERDE com uma conta de 6.400 faltando no meio, porque desde a 0116
  -- os dois lados dela são totais impressos e o documento bate consigo mesmo.
  select count(*) into v_n_apl from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:ativo_passivo_pl' and estado <> 'resolvida';
  perform teste_assert(v_n_apl = 0,
    'CEGUEIRA MEDIDA: com a linha apagada, ativo_passivo_pl continua verde',
    format('%s pendência(s) — se isto virar 1, a 0133 perdeu o motivo de existir', v_n_apl));

  select count(*) into v_n_arv from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n_arv = 1,
    '…e a árvore da seção PEGA, que é a única que pega',
    format('%s pendência(s)', v_n_arv));

  select descricao into v_desc from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida' limit 1;
  perform teste_assert(v_desc like '%Estoques%',
    '…e nomeia a SEÇÃO, para quem lê reextrair um bloco e não o documento inteiro',
    coalesce(v_desc, '(nula)'));
  perform teste_assert(v_desc like '%6400%',
    '…com o tamanho do buraco, que é o número que decide se é material',
    coalesce(v_desc, '(nula)'));

  -- UMA pendência por documento, não uma por seção: "Estoques" quebrado também
  -- quebra "Ativo Circulante" e "ATIVO" acima dele, e três pendências para um
  -- defeito é o oposto do que fazer com o tempo de quem lê a fila.
  perform teste_assert(v_n_arv = 1,
    'o defeito sobe a árvore (Estoques → Ativo Circulante → ATIVO) e mesmo assim é UMA pendência');

  -- Desfaz.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao, secao_canonica, periodo_coluna, status_aceite)
    values (v_ver, 'Produtos acabados', v_valor, 'milhar', 0.97,
            'Estoques', 'ativo_circulante', '2025', 'aceito');
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n_arv from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n_arv = 0, 'recolocada a linha, a pendência auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000001';
  v_n    int;
begin
  raise notice '--- 3. VALOR ERRADO e SINAL INVERTIDO ---';

  -- Dígito trocado: 9.200 -> 9.900 em "Matérias-primas e insumos".
  update campo_extraido set valor_num = 9900
   where documento_versao_id = v_ver and chave = 'Matérias-primas e insumos'
     and periodo_coluna = '2025';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 1, 'dígito trocado numa parcela quebra o pai e é pego',
    format('%s pendência(s)', v_n));
  update campo_extraido set valor_num = 9200
   where documento_versao_id = v_ver and chave = 'Matérias-primas e insumos'
     and periodo_coluna = '2025';

  -- Sinal invertido: a provisão de obsolescência é NEGATIVA (-2.350). Lida
  -- positiva, o total não muda de ordem de grandeza — é o erro mais fácil de
  -- não ver a olho, e o que mais estraga a Modelagem.
  update campo_extraido set valor_num = 2350
   where documento_versao_id = v_ver
     and chave = '(-) Provisão para obsolescência de estoques' and periodo_coluna = '2025';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 1, 'sinal invertido numa dedutora é pego (4.700 de diferença)',
    format('%s pendência(s)', v_n));
  update campo_extraido set valor_num = -2350
   where documento_versao_id = v_ver
     and chave = '(-) Provisão para obsolescência de estoques' and periodo_coluna = '2025';

  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'corrigidos os dois, a pendência auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000001';
  v_n    int;
  v_res  text;
  v_ach  text;
begin
  raise notice '--- 4. O TOTAL DECLARADO DUAS VEZES QUE DISCORDA ---';

  -- "ATIVO" e "TOTAL DO ATIVO" são a mesma quantidade impressa duas vezes.
  -- Ler uma delas errado NÃO é "a seção não fecha" — é um defeito de outra
  -- natureza, e o diagnóstico certo poupa o analista de procurar uma parcela
  -- perdida que não existe.
  update campo_extraido set valor_num = 95000
   where documento_versao_id = v_ver and chave = 'TOTAL DO ATIVO' and periodo_coluna = '2025';

  select resultado, achado into v_res, v_ach from fn_conferir_arvore(v_ver)
   where fn_normalizar_texto(pai) = 'ativo' and periodo_coluna = '2025';
  perform teste_assert(v_res = 'divergente',
    'total reafirmado que discorda do próprio pai é divergência', coalesce(v_res, 'nulo'));
  perform teste_assert(v_ach = 'total_declarado_diverge',
    '…e o ACHADO o distingue de "a seção não fecha" — são investigações diferentes',
    coalesce(v_ach, 'nulo'));

  update campo_extraido set valor_num = 95780
   where documento_versao_id = v_ver and chave = 'TOTAL DO ATIVO' and periodo_coluna = '2025';
  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'corrigido o total reafirmado, auto-resolve');
end $$;

-- =============================================================================
do $$
declare
  v_caso uuid := '11111111-1111-1111-1111-111111111111';
  v_ver  uuid := '55555555-0000-0000-0000-000000000001';
  v_n     int;
  v_res   text;
  v_ach   text;
  v_dup   uuid;
begin
  raise notice '--- 5. AS GUARDAS: o que ela se RECUSA a acusar ---';

  -- UNIDADE MISTA. Uma parcela em reais sob um pai em milhar daria divergência
  -- de 1000x. Não é achado — é comparação que não se pode fazer.
  update campo_extraido set unidade = 'unidade'
   where documento_versao_id = v_ver and chave = 'Produtos acabados' and periodo_coluna = '2025';
  select resultado, achado into v_res, v_ach from fn_conferir_arvore(v_ver)
   where fn_normalizar_texto(pai) = 'estoques' and periodo_coluna = '2025';
  perform teste_assert(v_res = 'precondicao_nao_satisfeita',
    'parcela em unidade diferente do pai NÃO vira divergência', coalesce(v_res, 'nulo'));
  perform teste_assert(v_ach = 'unidade_mista',
    '…e diz por quê, em vez de calar', coalesce(v_ach, 'nulo'));
  update campo_extraido set unidade = 'milhar'
   where documento_versao_id = v_ver and chave = 'Produtos acabados' and periodo_coluna = '2025';

  -- PARCELA DUPLICADA. A soma passaria do pai e esta checagem acusaria — mas
  -- quem cobra rótulo repetido é a 0105, e duas pendências para um defeito são
  -- dois toques humanos onde cabe um.
  insert into campo_extraido (documento_versao_id, chave, valor_num, unidade, confianca,
                              secao, secao_canonica, periodo_coluna, status_aceite)
    values (v_ver, 'Produtos acabados', 6400, 'milhar', 0.97,
            'Estoques', 'ativo_circulante', '2025', 'aceito')
    returning id into v_dup;
  select resultado, achado into v_res, v_ach from fn_conferir_arvore(v_ver)
   where fn_normalizar_texto(pai) = 'estoques' and periodo_coluna = '2025';
  perform teste_assert(v_res = 'precondicao_nao_satisfeita',
    'parcela com rótulo repetido NÃO abre a segunda pendência', coalesce(v_res, 'nulo'));
  perform teste_assert(v_ach = 'rotulo_duplicado',
    '…e aponta a checagem que manda (0105), em vez de somar ruído',
    coalesce(v_ach, 'nulo'));

  delete from campo_extraido where id = v_dup;

  perform teste_reconciliar_tudo(v_caso);
  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'desfeitas as duas, o fixture volta a fechar');
end $$;

-- =============================================================================
do $$
declare
  v_n int;
begin
  raise notice '--- 6. A FRONTEIRA: cascata não é partição ---';

  -- A DRE é CASCATA: os filhos de "RESULTADO ANTES DOS TRIBUTOS" são o IRPJ e o
  -- IR diferido, que levam ao lucro líquido — não são parcelas que somam ao pai.
  -- Medido no book: a checagem, se rodasse sobre DRE, acusaria 3 seções que
  -- estão CERTAS. Este assert trava o gate para que ninguém "conserte" isso
  -- acrescentando DRE de volta e inundando a fila.
  select count(*) into v_n from documento d
    join documento_versao dv on dv.documento_id = d.id
    cross join lateral fn_conferir_arvore(dv.id) a
   where d.tipo_taxonomia = 'DRE' and a.resultado = 'divergente';
  perform teste_assert(v_n > 0,
    'a DRE do book REALMENTE não fecha por soma de filhos (a cascata é real, não hipótese)',
    format('%s seção(ões) divergiriam', v_n));

  select count(*) into v_n from pendencia p
    join documento d on d.caso_id = p.caso_id
   where p.motivo = 'reconciliacao:secao_fecha' and p.estado <> 'resolvida'
     and d.tipo_taxonomia = 'DRE';
  perform teste_assert(v_n = 0,
    '…e mesmo assim NENHUMA pendência abre sobre DRE — o gate é o que separa',
    format('%s pendência(s)', v_n));
end $$;

-- =============================================================================
do $$
declare
  v_caso   uuid;
  v_doc    uuid;
  v_achat  uuid;   -- o MESMO documento com a hierarquia achatada
  v_hier   uuid;   -- …e com o agrupador imediato
  v_n      int;
  v_soma   numeric;
  v_res    text;
begin
  raise notice '--- 7. TRÊS ALTURAS: o caso que este arquivo não tinha ---';

  -- POR QUE ESTE BLOCO EXISTE, e é a lição mais cara da v48. O gate da seção
  -- passou desde a 0133 e continuou passando enquanto a rodada real abria DOZE
  -- pendências falsas — porque o fixture do `book-vertentes` tem DOIS níveis
  -- (seção → contas) e o defeito só aparece com TRÊS (seção → subgrupo →
  -- contas). O teste media o que sabia medir; a rodada real trouxe outra coisa.
  --
  -- O documento abaixo é o `01_Balanco` reduzido ao osso, com os números que a
  -- análise da v48 mediu:
  --
  --     ATIVO CIRCULANTE ........ 44.022
  --       Disponível ............     825      ← subgrupo: tem filhos E é filho
  --         Caixa ...............     800
  --         Bancos ..............      25
  --       Contas a receber ...... 12.795
  --       Estoques .............. 15.605
  --       Outros ................ 14.797
  --
  --     825 + 12.795 + 15.605 + 14.797 = 44.022  ✓
  --     800 + 25                       =    825  ✓
  --
  -- As duas versões carregam AS MESMAS SETE LINHAS e os MESMOS valores. A única
  -- diferença é para quem `secao` aponta — e é isso que este bloco isola.
  insert into caso (nome) values ('gate: três alturas') returning id into v_caso;
  insert into documento (caso_id, tipo_taxonomia)
    values (v_caso, 'BALANCO') returning id into v_doc;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, hash)
    values (v_doc, 1, 'tres_alturas_achatado.pdf', 'test-3n-achatado') returning id into v_achat;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, hash)
    values (v_doc, 2, 'tres_alturas_hierarquico.pdf', 'test-3n-hierarquico') returning id into v_hier;

  -- (A) ACHATADO — o que a extração produzia antes desta rodada: TODA linha
  -- aponta para a seção de topo, inclusive as que pertencem ao subgrupo.
  insert into campo_extraido
    (documento_versao_id, ordem, secao, chave, valor_num, unidade, periodo_coluna) values
    (v_achat, 0, 'Ativo Circulante', 'Disponível',          825, 'milhar', '2024'),
    (v_achat, 1, 'Ativo Circulante', 'Caixa',               800, 'milhar', '2024'),
    (v_achat, 2, 'Ativo Circulante', 'Bancos',               25, 'milhar', '2024'),
    (v_achat, 3, 'Ativo Circulante', 'Contas a receber',  12795, 'milhar', '2024'),
    (v_achat, 4, 'Ativo Circulante', 'Estoques',          15605, 'milhar', '2024'),
    (v_achat, 5, 'Ativo Circulante', 'Outros',            14797, 'milhar', '2024'),
    (v_achat, 6, null,               'Ativo Circulante',  44022, 'milhar', '2024');

  -- (B) HIERÁRQUICO — o agrupador IMEDIATO, que é o que o prompt passa a exigir.
  insert into campo_extraido
    (documento_versao_id, ordem, secao, chave, valor_num, unidade, periodo_coluna) values
    (v_hier, 0, 'Ativo Circulante', 'Disponível',          825, 'milhar', '2024'),
    (v_hier, 1, 'Disponível',       'Caixa',               800, 'milhar', '2024'),
    (v_hier, 2, 'Disponível',       'Bancos',               25, 'milhar', '2024'),
    (v_hier, 3, 'Ativo Circulante', 'Contas a receber',  12795, 'milhar', '2024'),
    (v_hier, 4, 'Ativo Circulante', 'Estoques',          15605, 'milhar', '2024'),
    (v_hier, 5, 'Ativo Circulante', 'Outros',            14797, 'milhar', '2024'),
    (v_hier, 6, null,               'Ativo Circulante',  44022, 'milhar', '2024');

  -- ---- o achatado: UMA conferência, e ela acusa o que está certo ------------
  select count(*)::int into v_n from fn_conferir_arvore(v_achat);
  perform teste_assert(v_n = 1,
    'achatado: sai UMA conferência só — o subgrupo não existe como pai',
    format('%s conferência(s)', v_n));

  select soma_filhos, resultado into v_soma, v_res
    from fn_conferir_arvore(v_achat) where pai = 'Ativo Circulante';
  perform teste_assert(v_soma = 44847,
    'achatado: a soma dá 44.847 — o Disponível é contado DUAS vezes (44.022 + 825)',
    format('soma=%s', v_soma));
  perform teste_assert(v_res = 'divergente',
    '…e a conferência acusa "divergente" sobre um documento que fecha ao centavo');

  -- E A GUARDA DA 0143 NÃO SALVA ESTE CASO, o que é o achado próprio deste
  -- bloco. Ela reconhece a assinatura "soma ≈ 2× o pai", que é o que acontece
  -- quando TODOS os subgrupos estão achatados. Aqui só um está: a razão é
  -- 1,0187, e a pendência sai como divergência normal. O piso honesto da 0143 é
  -- mais estreito do que a análise da v48 sugeria, e o conserto de verdade
  -- continua sendo a hierarquia na extração — que é o que este bloco mede.
  perform teste_assert(v_soma <> 2 * 44022,
    '…e a razão NÃO é 2,0000, então a guarda de hierarquia_achatada (0143) não a reconhece',
    format('razão = %s', round(v_soma / 44022, 4)));

  -- ---- o hierárquico: DUAS conferências, as duas fechando -------------------
  select count(*)::int into v_n from fn_conferir_arvore(v_hier);
  perform teste_assert(v_n = 2,
    'hierárquico: saem DUAS conferências — o subgrupo passa a ser conferido também',
    format('%s conferência(s)', v_n));

  select soma_filhos, resultado into v_soma, v_res
    from fn_conferir_arvore(v_hier) where pai = 'Ativo Circulante';
  perform teste_assert(v_soma = 44022 and v_res = 'ok',
    'hierárquico: a seção fecha ao centavo (44.022 = 44.022)',
    format('soma=%s resultado=%s', v_soma, v_res));

  select soma_filhos, resultado into v_soma, v_res
    from fn_conferir_arvore(v_hier) where pai = 'Disponível';
  perform teste_assert(v_soma = 825 and v_res = 'ok',
    '…e o SUBGRUPO fecha também (800 + 25 = 825) — uma conferência que antes não existia',
    format('soma=%s resultado=%s', v_soma, v_res));

  select count(*)::int into v_n from fn_conferir_arvore(v_hier) where resultado = 'divergente';
  perform teste_assert(v_n = 0,
    'hierárquico: NENHUMA divergência — as mesmas sete linhas, a mesma aritmética',
    format('%s divergente(s)', v_n));

  -- O QUE ESTE BLOCO PROVA, dito por inteiro: `fn_conferir_arvore` não precisou
  -- mudar. Ela já é recursiva por construção (todo rótulo que aparece como
  -- `secao` de alguém vira pai), e o defeito nunca esteve nela. Estava no
  -- insumo. É por isso que a correção é de PROMPT, e é por isso que ela só se
  -- confirma numa rodada real — este bloco prova a aritmética, não o modelo.
  delete from campo_extraido where documento_versao_id in (v_achat, v_hier);
  delete from documento_versao where id in (v_achat, v_hier);
  delete from documento where id = v_doc;
  delete from caso where id = v_caso;
end $$;

-- =============================================================================
do $$
declare
  v_caso        uuid;
  v_doc_achat   uuid;
  v_doc_dup     uuid;
  v_doc_mista   uuid;
  v_ver_achat   uuid;
  v_ver_dup     uuid;
  v_ver_mista   uuid;
  v_json        jsonb;
  v_rec_id      uuid;
  v_ok          boolean;
  v_res         text;
  v_mot         text;
  v_fonte_a     jsonb;
  v_fonte_b     jsonb;
  v_n           int;
begin
  raise notice '--- 8. A ÁRVORE QUE NÃO CONFERIU NADA (0190): resultado deixa de mentir ---';

  -- POR QUE ESTE BLOCO EXISTE. Medido em produção (25/09/2026, somente
  -- leitura): 12 linhas de `reconciliacao` com `tipo='secao_fecha'`,
  -- `resultado='ok'` e `fonte_a->>'secoes_conferidas'='0'` — a árvore não
  -- conferiu NADA e mesmo assim afirmou que fechou. Os três documentos abaixo
  -- espelham as três formas que produção mostrou: hierarquia achatada
  -- sozinha, rótulo duplicado sozinho, e uma árvore MISTA que prova que o
  -- ramo 'ok' parcial (pelo menos uma seção de verdade) não muda.
  insert into caso (nome) values ('gate: arvore que nao conferiu nada') returning id into v_caso;

  -- ---- (A) A ÁRVORE INTEIRA CAI NA GUARDA DA 0143 (hierarquia achatada) -----
  -- Uma seção só, e ela sozinha decide o documento inteiro: soma = 2× o pai
  -- (50 + 25 + 25 = 100 = 2×50), exatamente a assinatura que a 0143 reconhece.
  insert into documento (caso_id, tipo_taxonomia) values (v_caso, 'BALANCO')
    returning id into v_doc_achat;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, hash)
    values (v_doc_achat, 1, 'arvore_achatada.pdf', 'test-0190-achatada')
    returning id into v_ver_achat;
  insert into campo_extraido
    (documento_versao_id, ordem, secao, chave, valor_num, unidade, periodo_coluna) values
    (v_ver_achat, 0, null,                 'ATIVO CIRCULANTE', 50, 'milhar', '2024'),
    (v_ver_achat, 1, 'ATIVO CIRCULANTE',   'Disponível',       50, 'milhar', '2024'),
    (v_ver_achat, 2, 'ATIVO CIRCULANTE',   'Caixa',            25, 'milhar', '2024'),
    (v_ver_achat, 3, 'ATIVO CIRCULANTE',   'Bancos',           25, 'milhar', '2024');

  select resultado, achado into v_res, v_mot from fn_conferir_arvore(v_ver_achat);
  perform teste_assert(v_res = 'precondicao_nao_satisfeita' and v_mot = 'hierarquia_achatada',
    'PRÉ-CONDIÇÃO: a ÚNICA seção deste documento cai na guarda da 0143 (soma = 2× o pai)',
    format('resultado=%s achado=%s', coalesce(v_res, 'nulo'), coalesce(v_mot, 'nulo')));

  v_json   := fn_reconciliar_arvore(v_doc_achat);
  v_rec_id := (v_json ->> 'reconciliacao_id')::uuid;
  select precondicoes_ok, resultado, motivo_precondicao, fonte_a, fonte_b
    into v_ok, v_res, v_mot, v_fonte_a, v_fonte_b
  from reconciliacao where id = v_rec_id;

  perform teste_assert(v_ok = false,
    'ANTES DA 0190 esta linha saía precondicoes_ok=TRUE — o defeito medido em produção (12 '
    'linhas assim, 4 casos). Com a correção, false: a linha para de afirmar que conferiu',
    format('precondicoes_ok=%s', v_ok));
  perform teste_assert(v_res = 'precondicao_nao_satisfeita',
    'e o resultado gravado NÃO é ''ok'' quando zero seções foram de fato conferidas',
    coalesce(v_res, 'nulo'));
  perform teste_assert(v_mot = 'documento_ausente',
    'o motivo é o MESMO do ramo "sem árvore" — não abre pendência nova (o achado, quando tem '
    'dono, já tem: hierarquia achatada é decisão da própria 0143 de não acusar)',
    coalesce(v_mot, 'nulo'));
  perform teste_assert(v_fonte_a ->> 'secoes_conferidas' = '0' and v_fonte_b ->> 'sem_conferir' = '1',
    'fonte_a/fonte_b continuam nomeando a contagem real: 0 conferidas, 1 sem conferir',
    format('fonte_a=%s fonte_b=%s', v_fonte_a, v_fonte_b));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0,
    'A FILA NÃO MUDA: documento_ausente não abre pendência, exatamente como no ramo "sem árvore"',
    format('%s pendência(s)', v_n));

  -- ---- (B) SÓ RÓTULO DUPLICADO: a mesma forma, achado diferente -------------
  insert into documento (caso_id, tipo_taxonomia) values (v_caso, 'BALANCO')
    returning id into v_doc_dup;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, hash)
    values (v_doc_dup, 1, 'arvore_rotulo_duplicado.pdf', 'test-0190-duplicado')
    returning id into v_ver_dup;
  insert into campo_extraido
    (documento_versao_id, ordem, secao, chave, valor_num, unidade, periodo_coluna) values
    (v_ver_dup, 0, null,                  'PASSIVO CIRCULANTE', 100, 'milhar', '2024'),
    (v_ver_dup, 1, 'PASSIVO CIRCULANTE',  'Fornecedores',        50, 'milhar', '2024'),
    (v_ver_dup, 2, 'PASSIVO CIRCULANTE',  'Fornecedores',        50, 'milhar', '2024');

  select resultado, achado into v_res, v_mot from fn_conferir_arvore(v_ver_dup);
  perform teste_assert(v_res = 'precondicao_nao_satisfeita' and v_mot = 'rotulo_duplicado',
    'PRÉ-CONDIÇÃO: a ÚNICA seção cai na guarda de rótulo duplicado (0105 já cobra)',
    format('resultado=%s achado=%s', coalesce(v_res, 'nulo'), coalesce(v_mot, 'nulo')));

  v_json   := fn_reconciliar_arvore(v_doc_dup);
  v_rec_id := (v_json ->> 'reconciliacao_id')::uuid;
  select precondicoes_ok, resultado, motivo_precondicao into v_ok, v_res, v_mot
  from reconciliacao where id = v_rec_id;
  perform teste_assert(v_ok = false and v_res = 'precondicao_nao_satisfeita'
                        and v_mot = 'documento_ausente',
    'mesmo comportamento com a causa trocada: rótulo duplicado sozinho também não afirma ok',
    format('precondicoes_ok=%s resultado=%s motivo=%s', v_ok, v_res, v_mot));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'e continua sem abrir pendência nova', format('%s pendência(s)', v_n));

  -- ---- (C) O 'OK' PARCIAL NÃO MUDA: ≥1 seção conferida continua 'ok' --------
  -- A MESMA árvore tem uma seção que fecha de verdade (ATIVO CIRCULANTE) e
  -- outra que cai em pré-condição (PASSIVO CIRCULANTE, rótulo duplicado) —
  -- v_n_ok=1, v_n_div=0, v_n_prec=1, o ramo que este bloco prova que NÃO muda.
  insert into documento (caso_id, tipo_taxonomia) values (v_caso, 'BALANCO')
    returning id into v_doc_mista;
  insert into documento_versao (documento_id, n_versao, arquivo_ref, hash)
    values (v_doc_mista, 1, 'arvore_mista.pdf', 'test-0190-mista')
    returning id into v_ver_mista;
  insert into campo_extraido
    (documento_versao_id, ordem, secao, chave, valor_num, unidade, periodo_coluna) values
    -- fecha de verdade:
    (v_ver_mista, 0, null,                  'ATIVO CIRCULANTE',  100, 'milhar', '2024'),
    (v_ver_mista, 1, 'ATIVO CIRCULANTE',    'Caixa',              60, 'milhar', '2024'),
    (v_ver_mista, 2, 'ATIVO CIRCULANTE',    'Bancos',             40, 'milhar', '2024'),
    -- cai em pré-condição (rótulo duplicado), na MESMA árvore:
    (v_ver_mista, 3, null,                  'PASSIVO CIRCULANTE', 50, 'milhar', '2024'),
    (v_ver_mista, 4, 'PASSIVO CIRCULANTE',  'Fornecedores',       30, 'milhar', '2024'),
    (v_ver_mista, 5, 'PASSIVO CIRCULANTE',  'Fornecedores',       30, 'milhar', '2024');

  v_json   := fn_reconciliar_arvore(v_doc_mista);
  v_rec_id := (v_json ->> 'reconciliacao_id')::uuid;
  select precondicoes_ok, resultado, fonte_a, fonte_b into v_ok, v_res, v_fonte_a, v_fonte_b
  from reconciliacao where id = v_rec_id;

  perform teste_assert(v_ok = true and v_res = 'ok',
    'com PELO MENOS uma seção conferida (ATIVO CIRCULANTE fecha), o resultado CONTINUA ok — '
    'este ramo é o que este bloco prova que NÃO muda de comportamento',
    format('precondicoes_ok=%s resultado=%s', v_ok, v_res));
  perform teste_assert(v_fonte_a ->> 'secoes_conferidas' = '1' and v_fonte_b ->> 'sem_conferir' = '1',
    'e a contagem parcial continua correta: 1 seção conferida, 1 sem conferir',
    format('fonte_a=%s fonte_b=%s', v_fonte_a, v_fonte_b));

  select count(*) into v_n from pendencia
   where caso_id = v_caso and motivo = 'reconciliacao:secao_fecha' and estado <> 'resolvida';
  perform teste_assert(v_n = 0, 'ok parcial também não abre pendência (comportamento herdado, '
    'não mudou)', format('%s pendência(s)', v_n));

  -- limpeza
  delete from campo_extraido where documento_versao_id in (v_ver_achat, v_ver_dup, v_ver_mista);
  delete from reconciliacao where caso_id = v_caso;
  delete from documento_versao where documento_id in (v_doc_achat, v_doc_dup, v_doc_mista);
  delete from documento where caso_id = v_caso;
  delete from caso where id = v_caso;
end $$;

-- =============================================================================
do $$ begin raise notice 'TODOS OS TESTES DA ÁRVORE DA SEÇÃO (0133) PASSARAM'; end $$;

drop function teste_assert(boolean, text, text);
drop function teste_reconciliar_tudo(uuid);
