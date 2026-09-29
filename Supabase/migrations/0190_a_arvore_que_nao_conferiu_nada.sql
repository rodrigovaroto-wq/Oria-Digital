-- =============================================================================
-- 0190 — A ÁRVORE QUE NÃO CONFERIU NADA, E CONFERIA
--
-- O DEFEITO, e ele é uma REGRESSÃO da 0143 sobre a 0133. `fn_reconciliar_arvore`
-- (corpo vigente desde a 0133, `Supabase/migrations/0133_a_secao_que_nao_fecha.sql:328`,
-- nunca reemitida depois) conta `v_n_ok`, `v_n_div`, `v_n_prec` a partir de
-- `fn_conferir_arvore` e decide em dois ramos:
--
--     if v_n_ok + v_n_div + v_n_prec = 0 then          -- nenhum pai com filho
--       ... 'documento_ausente' ...
--     end if;
--     v_resultado := case when v_n_div > 0 then 'divergente' else 'ok' end;
--
-- Falta o meio: `v_n_ok = 0 and v_n_div = 0 and v_n_prec > 0` — TODAS as
-- seções caíram em pré-condição, NENHUMA foi de fato somada — cai no segundo
-- ramo porque `v_n_div = 0`, e sai `resultado := 'ok'` com o texto "As 0
-- seções deste documento fecham com as próprias linhas. N ficaram sem
-- conferir…". `fn_registrar_reconciliacao` grava `precondicoes_ok = true,
-- resultado = 'ok'` — a linha AFIRMA que conferiu e fechou quando NADA foi
-- conferido. É a regra 7 do CLAUDE.md por outro caminho: um estágio que não
-- rodou (aqui, nem uma soma real aconteceu) fica com a mesma cara, e pior,
-- de um estágio que rodou e achou tudo em ordem.
--
-- A CAUSA MEDIDA: até a 0142 este ramo médio era impossível na prática — só
-- `rotulo_duplicado`/`unidade_mista` produziam pré-condição, e um documento
-- inteiro caindo nos dois ao mesmo tempo era raro. A 0143 (hierarquia
-- achatada: `Supabase/migrations/0143_hierarquia_achatada_nao_e_divergencia.sql`)
-- acrescentou um TERCEIRO motivo de pré-condição — soma ≈ 2× o pai — que é
-- exatamente o que uma extração sem hierarquia produz em TODA seção do
-- documento de uma vez, não seção a seção. Um balanço inteiramente achatado
-- passou, com a 0143, de "divergente" (pego por `fn_reconciliar_ativo_-
-- passivo_pl`? não — pego pela própria árvore, antes da 0143) para "ok" no
-- nível do documento — o oposto do que a 0133 foi escrita para fazer.
--
-- MEDIDO EM PRODUÇÃO (25/09/2026, SOMENTE LEITURA — nenhuma escrita, nenhum
-- apply): 12 linhas de `reconciliacao` com `tipo = 'secao_fecha'`,
-- `resultado = 'ok'` e `fonte_a->>'secoes_conferidas' = '0'`, em 4 casos; e 48
-- documentos ATUAIS (BALANCO/COMBINADO/DRE entre outros) cujo
-- `fn_conferir_arvore` dá 0 seções conferidas e >0 em pré-condição — achados
-- `hierarquia_achatada`, `rotulo_duplicado`, `sem_parcela`. O despachante
-- (`fn_reconciliar_por_documento`, 0152:495) só chama a árvore para
-- BALANCO/BALANCETE/COMBINADO, então os 48 incluem documento fora do gate;
-- os 12 já registrados são os que passaram.
--
-- A CORREÇÃO, e o que ela DELIBERADAMENTE não muda.
--
--   No ramo `v_n_ok + v_n_div = 0` (com `v_n_prec > 0`, o único jeito de
--   chegar aqui depois do primeiro `if`), grava com `p_resultado =
--   'documento_ausente'` — o MESMO valor que a função já usa no ramo "sem
--   árvore", e que o CONTRATO da 0186 (`Supabase/migrations/0186_o_motivo_-
--   que_o_achatamento_engolia.sql:60-130`) documenta como o motivo que
--   `fn_reconciliar_arvore` usa para "sem estrutura verificável" — não prova
--   ausência do documento, só garante NÃO abrir pendência.
--
--   EFEITO na gravação (`fn_registrar_reconciliacao`, corpo vigente 0188:343):
--   `precondicoes_ok = false`, `resultado = 'precondicao_nao_satisfeita'`,
--   `motivo_precondicao = 'documento_ausente'`. A linha para de AFIRMAR que
--   fechou.
--
--   A FILA NÃO MUDA: `v_divergente := p_resultado not in ('ok',
--   'documento_ausente')` trata 'ok' e 'documento_ausente' pelo MESMO ramo —
--   nenhum dos dois abre pendência, e uma pendência aberta antes se resolve
--   nos dois. Isso é DE PROPÓSITO, não uma lacuna desta migration: rótulo
--   duplicado já tem dono (`reconciliacao:duplicidade_de_rotulo`, 0105); a
--   0143 decidiu, com o nome que deu ao achado, NÃO acusar hierarquia
--   achatada como defeito da árvore (é defeito de EXTRAÇÃO, e o remédio é o
--   prompt, não uma pendência de reconciliação — ver o cabeçalho da 0143). O
--   que esta migration corrige é só a MENTIRA no `resultado`: "ok" quando
--   zero seções foram conferidas. Ela não promove hierarquia achatada a
--   achado acionável — isso seria decisão de negócio nova, fora do escopo de
--   um defeito de vocabulário.
--
--   A DESCRIÇÃO do novo ramo diz QUANTAS seções ficaram sem conferir, POR QUÊ
--   (contagem por achado: hierarquia_achatada / rotulo_duplicado /
--   unidade_mista / sem_parcela) e o EFEITO — "nenhuma seção deste documento
--   foi conferida: uma linha perdida dentro de qualquer seção passa sem
--   aviso" — regra 1 do CLAUDE.md: ausência com motivo E efeito, nunca um
--   zero mudo.
--
--   O RAMO 'ok' PARCIAL (`v_n_ok > 0`) NÃO MUDA DE COMPORTAMENTO — ele já
--   declarava corretamente "N seções fecham, M ficaram sem conferir". O TEXTO
--   dele, sim: dizia "rótulo duplicado ou unidade mista", que é falso desde a
--   0143 (hierarquia achatada é a terceira causa possível de pré-condição, e
--   passou a acontecer). Corrigido no mesmo fôlego por ser barato — é a
--   mesma REEMISSÃO, e deixar o texto errado ali seria a mesma família de
--   defeito que esta migration existe para fechar.
--
--   REEMITIDA A FUNÇÃO INTEIRA a partir do corpo vigente (0133) — nunca
--   `replace` de texto (`.claude/memory/nunca-corrigir-funcao-por-replace.md`).
--   Conferido por grep (`create or replace function fn_reconciliar_arvore`
--   em `Supabase/migrations/`) que nenhuma migration entre a 0133 e esta
--   reemitiu o corpo — só a 0133 o define.
--
-- O QUE ESTA MIGRATION NÃO FAZ.
--   • Não roda reconciliação nem recompute em caso nenhum. As 12 linhas já
--     gravadas em produção continuam com `resultado = 'ok'` até a próxima
--     rodada de cada caso — corrigir o já gravado é um backfill à parte, que
--     esta migration não faz e que precisa da mesma medição de alcance que
--     este cabeçalho já fez para não repetir o vício da 0179/0183 (agir sem
--     medir o alcance real em produção antes).
--   • Não muda `fn_conferir_arvore`, o CONTRATO de motivos da 0186, nem a
--     linha que decide pendência.
--   • Não é aplicada em produção por estar escrita. Quem responde é a sonda:
--
--       select chave, migration, tipo, objeto, presente, detalhe, porque
--         from fn_instalacao_conferir() where not presente order by 1;
-- =============================================================================

create or replace function fn_reconciliar_arvore(p_documento_id uuid)
returns jsonb
language plpgsql
as $$
declare
  v_caso_id     uuid;
  v_entidade_id uuid;
  v_periodo_id  uuid;
  v_tipo        text;
  v_versao      uuid;
  v_n_ok        int := 0;
  v_n_div       int := 0;
  v_n_prec      int := 0;
  v_n_achatada  int := 0;
  v_n_rotulo    int := 0;
  v_n_unidade   int := 0;
  v_n_semparc   int := 0;
  v_pior_abs    numeric;
  v_pior_pct    numeric;
  v_pior_pai    text;
  v_partes      text[] := '{}';
  v_causas      text[] := '{}';
  v_resultado   text;
  v_desc        text;
begin
  select caso_id, entidade_id, periodo_id, tipo_taxonomia
    into v_caso_id, v_entidade_id, v_periodo_id, v_tipo
  from documento where id = p_documento_id;

  if v_caso_id is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento não encontrado');
  end if;

  v_versao := fn_versao_atual(p_documento_id);
  if v_versao is null then
    return jsonb_build_object('executado', false, 'motivo', 'documento sem versão');
  end if;

  select count(*) filter (where resultado = 'ok'),
         count(*) filter (where resultado = 'divergente'),
         count(*) filter (where resultado = 'precondicao_nao_satisfeita')
    into v_n_ok, v_n_div, v_n_prec
  from fn_conferir_arvore(v_versao);

  -- Nenhum pai com filho: documento de lista (aging, razão, mapa de dívida) ou
  -- extração sem hierarquia. Não é achado — é ausência de árvore para conferir.
  if v_n_ok + v_n_div + v_n_prec = 0 then
    return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
      'secao_fecha', 'A', p_documento_id, null, null, 'documento_ausente', null, null,
      jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1)'),
      'Este documento não tem seção com filhos — não há árvore a conferir. É o esperado em '
      || 'documento de lista (razão, aging, mapa de dívida), não um achado.');
  end if;

  -- 0190: NENHUMA seção fechou de verdade (nem `ok`, nem `divergente`) — só
  -- pré-condição, em TODAS. Antes desta migration isto caía no ramo `else` de
  -- baixo e saía `resultado := 'ok'` ("As 0 seções deste documento fecham…"),
  -- afirmando que a árvore conferiu e fechou quando nenhuma soma real
  -- aconteceu. Grava com o MESMO motivo do ramo "sem árvore" acima
  -- (`documento_ausente` — CONTRATO na 0186:60-130): não abre pendência (o
  -- achado, quando tem dono, já tem — rótulo duplicado é da 0105; hierarquia
  -- achatada é decisão da própria 0143 de não acusar), mas a linha para de
  -- MENTIR que fechou.
  if v_n_ok + v_n_div = 0 then
    select count(*) filter (where achado = 'hierarquia_achatada'),
           count(*) filter (where achado = 'rotulo_duplicado'),
           count(*) filter (where achado = 'unidade_mista'),
           count(*) filter (where achado = 'sem_parcela')
      into v_n_achatada, v_n_rotulo, v_n_unidade, v_n_semparc
    from fn_conferir_arvore(v_versao)
    where resultado = 'precondicao_nao_satisfeita';

    if v_n_achatada > 0 then
      v_causas := v_causas || format('%s por hierarquia achatada (a extração ainda não separa '
                                     'o subgrupo do grupo — remédio é o prompt, não reconciliação)',
                                     v_n_achatada);
    end if;
    if v_n_rotulo > 0 then
      v_causas := v_causas || format('%s por rótulo duplicado (reconciliacao:duplicidade_de_'
                                     'rotulo, 0105, já cobra)', v_n_rotulo);
    end if;
    if v_n_unidade > 0 then
      v_causas := v_causas || format('%s por unidade mista', v_n_unidade);
    end if;
    if v_n_semparc > 0 then
      v_causas := v_causas || format('%s sem parcela somável', v_n_semparc);
    end if;

    return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
      'secao_fecha', 'A', p_documento_id,
      jsonb_build_object('secoes_conferidas', 0, 'pior_secao', null),
      jsonb_build_object('divergentes', 0, 'sem_conferir', v_n_prec),
      'documento_ausente', null, null,
      jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1) na unidade do documento'),
      format('Nenhuma das %s seção(ões) deste documento foi conferida (%s). Nenhuma soma real '
             'aconteceu: uma linha perdida dentro de qualquer seção passaria sem aviso, porque '
             'não há aqui nenhuma conferência que a pegasse.',
             v_n_prec, array_to_string(v_causas, '; ')));
  end if;

  select a.divergencia_abs,
         case when a.pai_valor <> 0 then a.divergencia_abs / abs(a.pai_valor) end,
         a.pai
    into v_pior_abs, v_pior_pct, v_pior_pai
  from fn_conferir_arvore(v_versao) a
  where a.resultado = 'divergente'
  order by a.divergencia_abs desc
  limit 1;

  select array_agg(
           format('%s%s: informa %s, filhos somam %s (dif. %s)',
                  a.pai,
                  case when coalesce(a.periodo_coluna, '') <> ''
                       then ' [' || a.periodo_coluna || ']' else '' end,
                  a.pai_valor, a.soma_filhos, a.divergencia_abs)
           order by a.divergencia_abs desc)
    into v_partes
  from (select * from fn_conferir_arvore(v_versao)
         where resultado = 'divergente'
         order by divergencia_abs desc limit 5) a;

  v_resultado := case when v_n_div > 0 then 'divergente' else 'ok' end;

  if v_n_div > 0 then
    v_desc := format(
      '%s seção(ões) não fecham com as próprias linhas neste documento (%s conferem). %s. '
      || 'Ou a extração perdeu/errou linha nessas seções, ou o documento não fecha consigo '
      || 'mesmo — as duas exigem olhar o PDF, e a diferença decide entre reextrair e perguntar '
      || 'ao cliente.',
      v_n_div, v_n_ok, array_to_string(v_partes, '; '));
    if v_n_div > 5 then
      v_desc := v_desc || format(' (mostrando as 5 maiores de %s; muitas seções quebrando de uma '
                                 'vez costuma ser escala ou coluna, não linha perdida.)', v_n_div);
    end if;
  else
    -- 0190: o texto dizia só "rótulo duplicado ou unidade mista" — falso desde
    -- a 0143, que acrescentou hierarquia achatada como terceira causa de
    -- pré-condição. Corrigido na mesma reemissão; comportamento deste ramo
    -- (v_n_ok > 0, `resultado := 'ok'`) não muda.
    v_desc := format('As %s seções deste documento fecham com as próprias linhas. %s ficaram sem '
                     'conferir por pré-condição (hierarquia achatada, rótulo duplicado, unidade '
                     'mista ou sem parcela somável).',
                     v_n_ok, v_n_prec);
  end if;

  return fn_registrar_reconciliacao(v_caso_id, v_entidade_id, v_periodo_id,
    'secao_fecha', 'A', p_documento_id,
    jsonb_build_object('secoes_conferidas', v_n_ok + v_n_div, 'pior_secao', v_pior_pai),
    jsonb_build_object('divergentes', v_n_div, 'sem_conferir', v_n_prec),
    v_resultado, v_pior_abs, v_pior_pct,
    jsonb_build_object('tolerancia', 'arredondamento ~0,5*(n+1) na unidade do documento'),
    v_desc);
end;
$$;

comment on function fn_reconciliar_arvore(uuid) is
  'Registra, como reconciliação Classe A, se as seções do documento fecham com as próprias linhas. '
  'UMA pendência por documento (não uma por seção): erro de escala quebra todas as seções de uma '
  'vez, e trinta pendências para um defeito é o oposto do que fazer com o tempo de quem lê a fila. '
  '0190: quando TODAS as seções caem em pré-condição (nenhuma `ok`, nenhuma `divergente`), grava '
  '''documento_ausente'' em vez de ''ok'' — a árvore não conferiu nada, e o resultado deixa de '
  'afirmar o contrário.';

grant execute on function fn_reconciliar_arvore(uuid) to authenticated;

-- -----------------------------------------------------------------------------
-- Catálogo da sonda — o requisito de CORPO que prova que esta correção está
-- instalada (a assinatura de `fn_reconciliar_arvore` não muda: `reconciliar_-
-- arvore`, tipo funcao, migration 0133, continua provando só que a função
-- EXISTE). Marcador é código, não comentário — `sonda_marcador_e_codigo.test.sql`
-- exige isso para todo marcador novo de tipo `corpo`.
--
-- ORDEM 830: a 0189 usa 820-829.
-- -----------------------------------------------------------------------------

insert into instalacao_requisito
  (chave, migration, tipo, objeto, marcador, porque, severidade, ordem) values

  ('reconciliar_arvore_nao_mente_ok', '0190', 'corpo', 'fn_reconciliar_arvore',
   'v_n_ok + v_n_div = 0',
   'Sem este ramo, um documento cuja árvore inteira cai em pré-condição (hierarquia achatada, '
   'rótulo duplicado, unidade mista) grava `resultado = ''ok''` com `precondicoes_ok = true` — '
   'afirma que conferiu e fechou quando NENHUMA seção foi de fato somada. Regressão medida em '
   'produção (25/09/2026, somente leitura): 12 linhas de reconciliacao com secoes_conferidas=0 e '
   'resultado=ok em 4 casos.',
   'importante', 830)

on conflict (chave) do update
  set migration = excluded.migration,
      tipo      = excluded.tipo,
      objeto    = excluded.objeto,
      marcador  = excluded.marcador,
      porque    = excluded.porque,
      severidade = excluded.severidade,
      ordem     = excluded.ordem;

update instalacao_cobertura
   set ate_migration = '0190', revisado_em = current_date,
       observacao = 'A 0190 reemite fn_reconciliar_arvore para fechar o ramo em que TODAS as '
         'seções caem em pré-condição: antes gravava resultado=ok (afirmando que a árvore fechou '
         'quando nada foi conferido); agora grava documento_ausente, mesmo motivo do ramo "sem '
         'árvore", sem mudar o comportamento da fila (documento_ausente já não abre pendência). '
         'Catalogado pelo corpo (reconciliar_arvore_nao_mente_ok) — a assinatura da função não '
         'muda, então só o corpo prova a correção.'
 where id = true;
